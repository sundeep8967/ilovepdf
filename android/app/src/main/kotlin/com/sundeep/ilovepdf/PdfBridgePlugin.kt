package com.sundeep.ilovepdf

import android.content.Context
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class PdfBridgePlugin(private val context: Context) {
    
    /**
     * Extract text elements from PDF with their positions
     */
    fun extractTextElements(path: String): String {
        val file = File(path)
        val document = PDDocument.load(file)
        
        try {
            val result = JSONObject()
            val pagesArray = JSONArray()
            
            val stripper = PositionTextStripper()
            
            for (pageIndex in 0 until document.numberOfPages) {
                stripper.setStartPage(pageIndex + 1)
                stripper.setEndPage(pageIndex + 1)
                stripper.currentPageIndex = pageIndex
                stripper.textElements.clear()
                
                // This triggers text extraction
                stripper.getText(document)
                
                val page = document.getPage(pageIndex)
                val pageJson = JSONObject().apply {
                    put("pageNumber", pageIndex)
                    put("width", page.mediaBox.width)
                    put("height", page.mediaBox.height)
                    put("elements", JSONArray(stripper.textElements.map { it.toJson() }))
                }
                pagesArray.put(pageJson)
            }
            
            result.put("path", path)
            result.put("pageCount", document.numberOfPages)
            result.put("pages", pagesArray)
            
            return result.toString()
        } finally {
            document.close()
        }
    }
    
    /**
     * Replace text in PDF and return path to modified file
     */
    fun replaceText(path: String, searchText: String, newText: String, pageNumber: Int): String {
        val editor = PdfTextEditor(context)
        return editor.replaceText(path, searchText, newText, pageNumber)
    }

    fun inspectText(path: String, searchText: String, pageNumber: Int): String {
        val editor = PdfTextEditor(context)
        return editor.inspectText(path, searchText, pageNumber)
    }

    fun replaceTextAdvanced(
        path: String, searchText: String, newText: String, pageNumber: Int,
        fontSize: Float, isBold: Boolean, isItalic: Boolean, xOffset: Float, yOffset: Float,
        isAbsolutePositioning: Boolean = false
    ): String {
        val editor = PdfTextEditor(context)
        return editor.replaceTextAdvanced(
            path, searchText, newText, pageNumber, 
            fontSize, isBold, isItalic, xOffset, yOffset, isAbsolutePositioning
        )
    }
    
    /**
     * Save document to new location
     */
    fun saveDocument(inputPath: String, outputPath: String): Boolean {
        val inputFile = File(inputPath)
        val outputFile = File(outputPath)
        
        inputFile.copyTo(outputFile, overwrite = true)
        return outputFile.exists()
    }
}

/**
 * Custom text stripper that captures text positions
 */
class PositionTextStripper : PDFTextStripper() {
    val textElements = mutableListOf<TextElement>()
    var currentPageIndex = 0
    private var elementIdCounter = 0
    
    private val currentLine = StringBuilder()
    private var lineStartX = 0f
    private var lineStartY = 0f
    private var lineEndX = 0f
    private var lineHeight = 0f
    private var lastY = -1f
    
    override fun writeString(text: String, textPositions: MutableList<TextPosition>) {
        if (textPositions.isEmpty()) return
        
        val firstPos = textPositions.first()
        val lastPos = textPositions.last()
        
        // Check if this is a new line
        if (lastY != -1f && Math.abs(firstPos.y - lastY) > firstPos.height * 0.5) {
            // Save previous line
            flushLine()
        }
        
        // Start new line if needed
        if (currentLine.isEmpty()) {
            lineStartX = firstPos.x
            lineStartY = firstPos.y
            lineHeight = firstPos.height
        }
        
        currentLine.append(text)
        lineEndX = lastPos.x + lastPos.width
        lastY = firstPos.y
        lineHeight = maxOf(lineHeight, firstPos.height)
    }
    
    override fun endPage(page: com.tom_roush.pdfbox.pdmodel.PDPage?) {
        flushLine()
        lastY = -1f
        super.endPage(page)
    }
    
    private fun flushLine() {
        if (currentLine.isNotEmpty()) {
            val text = currentLine.toString().trim()
            if (text.isNotEmpty()) {
                textElements.add(TextElement(
                    id = "text_${currentPageIndex}_${elementIdCounter++}",
                    content = text,
                    x = lineStartX,
                    y = lineStartY,
                    width = lineEndX - lineStartX,
                    height = lineHeight,
                    pageNumber = currentPageIndex
                ))
            }
            currentLine.clear()
        }
    }
}

/**
 * Represents a text element in the PDF
 */
data class TextElement(
    val id: String,
    val content: String,
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
    val pageNumber: Int
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("id", id)
            put("content", content)
            put("x", x.toDouble())
            put("y", y.toDouble())
            put("width", width.toDouble())
            put("height", height.toDouble())
            put("pageNumber", pageNumber)
        }
    }
}
