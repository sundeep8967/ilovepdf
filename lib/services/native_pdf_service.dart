// Native PDF Editor Service
// Uses Syncfusion Flutter PDF for offline PDF editing on Android
// No server required - runs entirely on device!

import 'dart:io';
import 'dart:ui' show Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'debug_logger.dart';
import '../models/pdf_document.dart' as models;

/// Font information extracted from the original text
class FontInfo {
  final String fontName;
  final double fontSize;
  final bool isBold;
  final bool isItalic;
  
  FontInfo({
    required this.fontName,
    required this.fontSize,
    required this.isBold,
    required this.isItalic,
  });
  
  @override
  String toString() => 'FontInfo(name=$fontName, size=$fontSize, bold=$isBold, italic=$isItalic)';
}

class NativePdfService {
  
  /// Extract all text elements from a PDF with their positions
  static Future<models.PdfDocument?> extractTextElements(String pdfPath) async {
    try {
      DebugLogger.info('Loading PDF for extraction', pdfPath);
      
      final file = File(pdfPath);
      if (!await file.exists()) {
        DebugLogger.error('PDF file not found', pdfPath);
        return null;
      }
      
      final bytes = await file.readAsBytes();
      DebugLogger.debug('PDF loaded', '${bytes.length} bytes');
      
      // Load PDF document
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      DebugLogger.info('PDF opened', '${document.pages.count} pages');
      
      final pages = <models.PdfPage>[];
      int elementId = 0;
      
      // Extract text from each page
      for (int i = 0; i < document.pages.count; i++) {
        final page = document.pages[i];
        final pageSize = page.size;
        DebugLogger.debug('Processing page ${i + 1}', '${pageSize.width}x${pageSize.height}');
        
        // Extract text with layout
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        final List<TextLine> textLines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
        
        DebugLogger.debug('Page ${i + 1} text lines', '${textLines.length} lines found');
        
        final elements = <models.TextElement>[];
        
        for (final textLine in textLines) {
          final bounds = textLine.bounds;
          final text = textLine.text;
          
          if (text.trim().isNotEmpty) {
            // Get font info from word elements if available
            double fontSize = bounds.height * 0.85;
            if (textLine.wordCollection.isNotEmpty) {
              final firstWord = textLine.wordCollection[0];
              fontSize = firstWord.fontSize > 0 ? firstWord.fontSize : fontSize;
            }
            
            elements.add(models.TextElement(
              id: 'text_$elementId',
              content: text,
              x: bounds.left,
              y: bounds.top,
              width: bounds.width,
              height: bounds.height,
              pageNumber: i,
            ));
            elementId++;
            
            DebugLogger.debug('Found text', '"${text.length > 30 ? '${text.substring(0, 30)}...' : text}" fontSize=$fontSize');
          }
        }
        
        pages.add(models.PdfPage(
          pageNumber: i,
          width: pageSize.width,
          height: pageSize.height,
          elements: elements,
        ));
      }
      
      document.dispose();
      
      DebugLogger.success('Text extraction complete', '$elementId elements from ${pages.length} pages');
      
      return models.PdfDocument(
        path: pdfPath,
        pageCount: pages.length,
        pages: pages,
      );
      
    } catch (e, stackTrace) {
      DebugLogger.error('Failed to extract text', '$e\n$stackTrace');
      return null;
    }
  }

  /// Replace text in a PDF using overlay method
  /// ONLY replaces the FIRST occurrence to avoid accidental edits
  /// Preserves the original font style
  static Future<String?> replaceText({
    required String pdfPath,
    required String searchText,
    required String newText,
    required int pageNumber,
  }) async {
    try {
      DebugLogger.info('=== TEXT REPLACEMENT START ===');
      DebugLogger.info('Search text', '"$searchText"');
      DebugLogger.info('New text', '"$newText"');
      DebugLogger.info('Page number', '$pageNumber (0-indexed)');
      
      // Load the PDF
      final file = File(pdfPath);
      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      DebugLogger.debug('PDF loaded', '${document.pages.count} pages');
      
      if (pageNumber < 0 || pageNumber >= document.pages.count) {
        DebugLogger.error('Invalid page', 'Page $pageNumber out of range (0-${document.pages.count - 1})');
        document.dispose();
        return null;
      }
      
      final page = document.pages[pageNumber];
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      
      // First, try to find the exact text
      DebugLogger.debug('Searching for exact match...');
      final List<MatchedItem> matches = extractor.findText(
        [searchText], 
        startPageIndex: pageNumber, 
        endPageIndex: pageNumber,
      );
      
      DebugLogger.info('Exact matches found', '${matches.length}');
      
      if (matches.isNotEmpty) {
        // ONLY replace the FIRST match to avoid accidental edits
        final match = matches.first;
        final bounds = match.bounds;
        
        DebugLogger.info('Replacing FIRST match only');
        DebugLogger.debug('Match position', 'x=${bounds.left.toStringAsFixed(1)}, y=${bounds.top.toStringAsFixed(1)}');
        DebugLogger.debug('Match size', 'w=${bounds.width.toStringAsFixed(1)}, h=${bounds.height.toStringAsFixed(1)}');
        
        // Get font info from the matching text
        final fontInfo = _extractFontInfo(extractor, pageNumber, bounds, searchText);
        DebugLogger.info('Detected font', fontInfo.toString());
        
        _drawTextOverlay(page, bounds, newText, fontInfo);
        DebugLogger.success('Text replaced at first match');
        
      } else {
        // Try to find as part of a line
        DebugLogger.warning('No exact match, searching in text lines...');
        
        final textLines = extractor.extractTextLines(
          startPageIndex: pageNumber, 
          endPageIndex: pageNumber,
        );
        
        DebugLogger.debug('Found ${textLines.length} text lines on page');
        
        TextLine? matchingLine;
        int matchStart = -1;
        
        for (final line in textLines) {
          final lineText = line.text;
          final idx = lineText.indexOf(searchText);
          if (idx != -1) {
            matchingLine = line;
            matchStart = idx;
            DebugLogger.debug('Found in line', '"$lineText"');
            DebugLogger.debug('Match starts at index', '$matchStart');
            break;
          }
        }
        
        if (matchingLine != null) {
          // Calculate bounds for just the matching portion
          final lineBounds = matchingLine.bounds;
          
          // Estimate the width of the matching text portion
          final lineText = matchingLine.text;
          final charWidth = lineBounds.width / lineText.length;
          final matchX = lineBounds.left + (matchStart * charWidth);
          final matchWidth = searchText.length * charWidth;
          
          final matchBounds = Rect.fromLTWH(
            matchX,
            lineBounds.top,
            matchWidth,
            lineBounds.height,
          );
          
          DebugLogger.debug('Calculated match bounds', 
            'x=${matchBounds.left.toStringAsFixed(1)}, w=${matchBounds.width.toStringAsFixed(1)}');
          
          // Extract font info from the matching line
          final fontInfo = _extractFontInfoFromLine(matchingLine, matchStart);
          DebugLogger.info('Detected font from line', fontInfo.toString());
          
          _drawTextOverlay(page, matchBounds, newText, fontInfo);
          DebugLogger.success('Text replaced via line match');
          
        } else {
          DebugLogger.error('Text not found anywhere on page $pageNumber');
          DebugLogger.error('Search text was', '"$searchText"');
          document.dispose();
          return null;
        }
      }
      
      // Save modified PDF
      final outputPath = await _saveModifiedPdf(document);
      document.dispose();
      
      DebugLogger.success('=== REPLACEMENT COMPLETE ===', outputPath);
      return outputPath;
      
    } catch (e, stackTrace) {
      DebugLogger.error('Replace text failed', '$e');
      DebugLogger.debug('Stack trace', '$stackTrace');
      return null;
    }
  }

  /// Extract font information from the text at given bounds
  static FontInfo _extractFontInfo(PdfTextExtractor extractor, int pageNumber, Rect bounds, String searchText) {
    try {
      final textLines = extractor.extractTextLines(
        startPageIndex: pageNumber, 
        endPageIndex: pageNumber,
      );
      
      for (final line in textLines) {
        // Find line that overlaps with our bounds
        if (_rectsOverlap(line.bounds, bounds)) {
          // Search through words to find matching font info
          for (final word in line.wordCollection) {
            // Check if this word overlaps with our search bounds
            if (_rectsOverlap(word.bounds, bounds)) {
              final fontName = word.fontName;
              final fontSize = word.fontSize > 0 ? word.fontSize : bounds.height * 0.75;
              final fontStyle = word.fontStyle;
              
              // Detect bold/italic from font style
              final isBold = fontStyle.contains(PdfFontStyle.bold) || 
                            fontName.toLowerCase().contains('bold');
              final isItalic = fontStyle.contains(PdfFontStyle.italic) || 
                              fontName.toLowerCase().contains('italic') ||
                              fontName.toLowerCase().contains('oblique');
              
              DebugLogger.debug('Word font details', 
                'fontName="$fontName", fontSize=$fontSize, style=$fontStyle');
              
              return FontInfo(
                fontName: fontName,
                fontSize: fontSize,
                isBold: isBold,
                isItalic: isItalic,
              );
            }
          }
        }
      }
    } catch (e) {
      DebugLogger.debug('Font extraction failed', '$e');
    }
    
    // Default fallback
    return FontInfo(
      fontName: 'Helvetica',
      fontSize: (bounds.height * 0.75).clamp(8.0, 48.0),
      isBold: false,
      isItalic: false,
    );
  }

  /// Extract font info from a text line at specific character position
  static FontInfo _extractFontInfoFromLine(TextLine line, int charIndex) {
    try {
      // Find which word contains the character at charIndex
      int charCount = 0;
      for (final word in line.wordCollection) {
        final wordEnd = charCount + word.text.length;
        if (charIndex >= charCount && charIndex < wordEnd) {
          final fontName = word.fontName;
          final fontSize = word.fontSize > 0 ? word.fontSize : line.bounds.height * 0.75;
          final fontStyle = word.fontStyle;
          
          final isBold = fontStyle.contains(PdfFontStyle.bold) || 
                        fontName.toLowerCase().contains('bold');
          final isItalic = fontStyle.contains(PdfFontStyle.italic) || 
                          fontName.toLowerCase().contains('italic');
          
          return FontInfo(
            fontName: fontName,
            fontSize: fontSize,
            isBold: isBold,
            isItalic: isItalic,
          );
        }
        charCount = wordEnd + 1; // +1 for space between words
      }
      
      // Fallback to first word's font
      if (line.wordCollection.isNotEmpty) {
        final firstWord = line.wordCollection.first;
        final fontStyle = firstWord.fontStyle;
        
        return FontInfo(
          fontName: firstWord.fontName,
          fontSize: firstWord.fontSize > 0 ? firstWord.fontSize : line.bounds.height * 0.75,
          isBold: fontStyle.contains(PdfFontStyle.bold) || 
                 firstWord.fontName.toLowerCase().contains('bold'),
          isItalic: fontStyle.contains(PdfFontStyle.italic),
        );
      }
    } catch (e) {
      DebugLogger.debug('Font extraction from line failed', '$e');
    }
    
    return FontInfo(
      fontName: 'Helvetica',
      fontSize: line.bounds.height * 0.75,
      isBold: false,
      isItalic: false,
    );
  }

  /// Check if two rectangles overlap
  static bool _rectsOverlap(Rect a, Rect b) {
    return !(a.right < b.left || 
             a.left > b.right || 
             a.bottom < b.top || 
             a.top > b.bottom);
  }

  /// Draw text overlay using the SAME font style as original
  static void _drawTextOverlay(PdfPage page, Rect bounds, String newText, FontInfo fontInfo) {
    final graphics = page.graphics;
    
    // Draw white rectangle to cover old text (with padding)
    final padding = 2.0;
    graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(255, 255, 255)), // White
      bounds: Rect.fromLTWH(
        bounds.left - padding,
        bounds.top - padding,
        bounds.width + (padding * 4), // Extra width for new text
        bounds.height + (padding * 2),
      ),
    );
    
    // Clamp font size to reasonable range
    final clampedFontSize = fontInfo.fontSize.clamp(6.0, 72.0);
    
    // Determine the font style
    PdfFontStyle style = PdfFontStyle.regular;
    if (fontInfo.isBold && fontInfo.isItalic) {
      style = PdfFontStyle.bold; // Combine would need bitwise OR
    } else if (fontInfo.isBold) {
      style = PdfFontStyle.bold;
    } else if (fontInfo.isItalic) {
      style = PdfFontStyle.italic;
    }
    
    // Choose the closest matching standard font family
    PdfFontFamily fontFamily = _matchFontFamily(fontInfo.fontName);
    
    // Create font with detected properties
    final font = PdfStandardFont(fontFamily, clampedFontSize, style: style);
    
    // Draw new text with BASELINE-CORRECTED alignment
    // Standard PDF drawing often adds top padding (ascent overlap).
    // Moving UP by ~15% of font size usually aligns the baseline with the original text.
    final textSize = font.measureString(newText);
    final verticalOffset = textSize.height * 0.15;
    final yPosition = bounds.top - verticalOffset;
    
    graphics.drawString(
      newText,
      font,
      brush: PdfSolidBrush(PdfColor(0, 0, 0)), // Black
      bounds: Rect.fromLTWH(
        bounds.left, 
        yPosition,
        0, 
        0,
      ),
    );
    
    DebugLogger.debug('Overlay drawn', 
      'font=${fontFamily.name} size=$clampedFontSize bold=${fontInfo.isBold} y=$yPosition (top-0.15h) textH=${textSize.height.toStringAsFixed(1)} boundsH=${bounds.height.toStringAsFixed(1)}');
  }

  /// Match font name to closest PdfFontFamily
  static PdfFontFamily _matchFontFamily(String fontName) {
    final name = fontName.toLowerCase();
    
    DebugLogger.debug('Matching font family', 'Original: "$fontName"');
    
    // Times / Times New Roman / Serif fonts
    if (name.contains('times') || 
        name.contains('serif') || 
        name.contains('georgia') ||
        name.contains('cambria')) {
      return PdfFontFamily.timesRoman;
    }
    
    // Courier / Monospace fonts
    if (name.contains('courier') || 
        name.contains('mono') || 
        name.contains('consolas') ||
        name.contains('code')) {
      return PdfFontFamily.courier;
    }
    
    // Symbol fonts
    if (name.contains('symbol')) {
      return PdfFontFamily.symbol;
    }
    
    // Zapf Dingbats
    if (name.contains('dingbat') || name.contains('zapf')) {
      return PdfFontFamily.zapfDingbats;
    }
    
    // Default to Helvetica (Arial-like sans-serif)
    // This covers: Arial, Helvetica, Calibri, Verdana, etc.
    return PdfFontFamily.helvetica;
  }

  /// Save modified PDF to temp directory
  static Future<String> _saveModifiedPdf(PdfDocument document) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
    
    DebugLogger.debug('Saving to', outputPath);
    
    final List<int> bytes = await document.save();
    await File(outputPath).writeAsBytes(bytes);
    
    return outputPath;
  }

  /// Save document to a specific location
  static Future<bool> saveDocument({
    required String inputPath,
    required String outputPath,
  }) async {
    try {
      DebugLogger.info('Saving document', 'From: $inputPath\nTo: $outputPath');
      
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        DebugLogger.error('Input file not found');
        return false;
      }
      
      await inputFile.copy(outputPath);
      DebugLogger.success('Document saved', outputPath);
      return true;
      
    } catch (e) {
      DebugLogger.error('Save failed', e);
      return false;
    }
  }

  /// Add text annotation to PDF (for cases where replacement fails)
  static Future<String?> addTextAnnotation({
    required String pdfPath,
    required String text,
    required int pageNumber,
    required double x,
    required double y,
    double fontSize = 12,
  }) async {
    try {
      DebugLogger.info('Adding text annotation');
      
      final file = File(pdfPath);
      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      if (pageNumber >= document.pages.count) {
        document.dispose();
        return null;
      }
      
      final page = document.pages[pageNumber];
      
      // Draw the text
      page.graphics.drawString(
        text,
        PdfStandardFont(PdfFontFamily.helvetica, fontSize),
        brush: PdfSolidBrush(PdfColor(0, 0, 0)),
        bounds: Rect.fromLTWH(x, y, 0, 0),
      );
      
      final outputPath = await _saveModifiedPdf(document);
      document.dispose();
      
      DebugLogger.success('Text annotation added', outputPath);
      return outputPath;
      
    } catch (e) {
      DebugLogger.error('Add annotation failed', e);
      return null;
    }
  }
}
