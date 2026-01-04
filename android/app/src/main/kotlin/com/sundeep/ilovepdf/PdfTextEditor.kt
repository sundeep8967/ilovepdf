package com.sundeep.ilovepdf

import android.content.Context
import android.graphics.Color
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.OutputStreamWriter
import java.util.Collections
import kotlin.math.max
import kotlin.math.min

class PdfTextEditor(private val context: Context) {
    
    /**
     * Replace text in PDF using Overlay Strategy:
     * 1. Find text coordinates
     * 2. Draw white rectangle over old text
     * 3. Draw new text over it
     */
    fun replaceText(inputPath: String, searchText: String, newText: String, pageNumber: Int): String {
        android.util.Log.d("PdfTextEditor", "Overlay Replace: '$searchText' -> '$newText' on page $pageNumber")
        
        val inputFile = File(inputPath)
        val document = PDDocument.load(inputFile)
        
        try {
            val page = document.getPage(pageNumber)
            
            // 1. Find the text coordinates
            val stripper = PositionTextStripper(searchText)
            stripper.sortByPosition = true
            stripper.startPage = pageNumber + 1
            stripper.endPage = pageNumber + 1
            
            // We need to run the stripper on the document to populate hits
            val dummyOutput = OutputStreamWriter(ByteArrayOutputStream())
            stripper.writeText(document, dummyOutput)
            
            val hits = stripper.hits
            android.util.Log.d("PdfTextEditor", "Found ${hits.size} occurrences")
            
            if (hits.isNotEmpty()) {
                val hit = hits[0]
                
                // 2. Overlay implementation
                val contentStream = PDPageContentStream(document, page, PDPageContentStream.AppendMode.APPEND, true, true)
                
                // Calculate cover width
                val font = PDType1Font.HELVETICA
                // If fontSize is tiny (e.g. 6.5), it might be scaled. 
                // Let's rely on the visual width from the hit for the box, but ensure we cover new text
                // For drawing new text, we must match the size. 
                // If hit.fontSize is 6.5, drawing at 6.5 might be too small if 6.5 was "scaled up" by the viewer but we draw unscaled?
                // TextMatrix usually handles scale. We are only setting font size.
                // Let's just use 12 as a safe fallback if invisible, or rely on hit.fontSize but log it.
                
                var fontSize = hit.fontSize
                if (fontSize < 6) fontSize = 10f // Heuristic: suspicious small font
                
                val newTextWidth = font.getStringWidth(newText) / 1000 * fontSize
                val coverWidth = max(hit.width, newTextWidth) + 4 // Padding
                
                // Coordinate Calculations
                // We know hit.baselineY is the correct PDF baseline coordinate (verified by text placement)
                // Existing text sits ON this baseline and extends UP by approx fontSize.
                // Descenders go DOWN by approx 20% of fontSize.
                
                // So we want the rect to start slightly below baseline and go up.
                val rectY = hit.baselineY - 3
                // Height needs to cover fontSize + padding
                val rectH = fontSize + 6 
                
                android.util.Log.d("PdfTextEditor", "Redact Rect: y=$rectY, h=$rectH (Baseline=${hit.baselineY}, FontSz=$fontSize)")
                
                // Draw White Rectangle (Redaction)
                contentStream.setNonStrokingColor(255, 255, 255)
                contentStream.addRect(hit.x - 2, rectY, coverWidth, rectH)
                contentStream.fill()
                
                // Draw New Text
                contentStream.setNonStrokingColor(0, 0, 0)
                contentStream.beginText()
                contentStream.setFont(font, fontSize)
                
                // Use the Raw Baseline Y from the matrix if available, else derive
                android.util.Log.d("PdfTextEditor", "Drawing Text at Baseline: ${hit.baselineY}")
                contentStream.newLineAtOffset(hit.x, hit.baselineY) 
                contentStream.showText(newText)
                contentStream.endText()
                
                contentStream.close()
            } else {
                android.util.Log.e("PdfTextEditor", "Text not found: $searchText")
            }
            
            // Generate output path
            val outputFile = File(context.cacheDir, "edited_${System.currentTimeMillis()}.pdf")
            document.save(outputFile)
            
            return outputFile.absolutePath
        } finally {
            document.close()
        }
    }

    // Helper class to find text coordinates
    private class PositionTextStripper(private val targetString: String) : PDFTextStripper() {
        val hits = mutableListOf<TextHit>()
        
        override fun writeString(text: String, textPositions: List<TextPosition>) {
            var searchIndex = 0
            while (true) {
                val foundIndex = text.indexOf(targetString, searchIndex)
                if (foundIndex == -1) break
                
                if (foundIndex + targetString.length <= textPositions.size) {
                    val firstChar = textPositions[foundIndex]
                    val lastChar = textPositions[foundIndex + targetString.length - 1]
                    
                    val x = firstChar.xDirAdj
                    
                    // yDirAdj is Y from top (Java coords)
                    val yFromTop = firstChar.yDirAdj
                    val height = firstChar.heightDir
                    val width = lastChar.xDirAdj + lastChar.widthDirAdj - firstChar.xDirAdj
                    
                    // Get Raw Baseline from Text Matrix (translateY is index 5 or 2,1)
                    val baselineY = firstChar.textMatrix.translateY
                    
                    hits.add(TextHit(x, yFromTop, width, height, firstChar.fontSizeInPt, baselineY))
                }
                searchIndex = foundIndex + 1
            }
            super.writeString(text, textPositions)
        }
    }
    
    data class TextHit(
        val x: Float, 
        val y: Float, // From Top
        val width: Float, 
        val height: Float, 
        val fontSize: Float,
        val baselineY: Float // Raw PDF Baseline
    )
}
