package com.sundeep.ilovepdf

import android.content.Context
import com.tom_roush.pdfbox.cos.COSArray
import com.tom_roush.pdfbox.cos.COSBase
import com.tom_roush.pdfbox.cos.COSString
import com.tom_roush.pdfbox.pdfparser.PDFStreamParser
import com.tom_roush.pdfbox.pdfwriter.ContentStreamWriter
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.common.PDStream
import com.tom_roush.pdfbox.contentstream.PDContentStream
import java.io.File

class PdfTextEditor(private val context: Context) {
    
    /**
     * Replace text in PDF and save to a new file
     */
    fun replaceText(inputPath: String, searchText: String, newText: String, pageNumber: Int): String {
        val inputFile = File(inputPath)
        val document = PDDocument.load(inputFile)
        
        try {
            val page = document.getPage(pageNumber)
            replaceTextInPage(document, page, searchText, newText)
            
            // Generate output path
            val outputFile = File(context.cacheDir, "edited_${System.currentTimeMillis()}.pdf")
            document.save(outputFile)
            
            return outputFile.absolutePath
        } finally {
            document.close()
        }
    }
    
    private fun replaceTextInPage(document: PDDocument, page: PDPage, searchText: String, newText: String) {
        // Use PDPage as PDContentStream for the parser
        val parser = PDFStreamParser(page as PDContentStream)
        parser.parse()
        
        val tokens = mutableListOf<Any>()
        var token: Any? = parser.parseNextToken()
        while (token != null) {
            tokens.add(token)
            token = parser.parseNextToken()
        }
        
        var modified = false
        
        for (i in 0 until tokens.size) {
            val t = tokens[i]
            
            when (t) {
                is COSString -> {
                    val text = t.string
                    if (text.contains(searchText)) {
                        val newContent = text.replace(searchText, newText)
                        tokens[i] = COSString(newContent.toByteArray())
                        modified = true
                    }
                }
                is COSArray -> {
                    // Handle TJ operator (array of strings)
                    for (j in 0 until t.size()) {
                        val element = t.get(j)
                        if (element is COSString) {
                            val text = element.string
                            if (text.contains(searchText)) {
                                val newContent = text.replace(searchText, newText)
                                t.set(j, COSString(newContent.toByteArray()))
                                modified = true
                            }
                        }
                    }
                }
            }
        }
        
        if (modified) {
            // Write modified content back
            val newStream = PDStream(document)
            val out = newStream.createOutputStream()
            val writer = ContentStreamWriter(out)
            writer.writeTokens(tokens)
            out.close()
            
            page.setContents(newStream)
        }
    }
    
    /**
     * Save document to specified path
     */
    fun saveToPath(document: PDDocument, outputPath: String): Boolean {
        return try {
            val outputFile = File(outputPath)
            document.save(outputFile)
            true
        } catch (e: Exception) {
            false
        }
    }
}
