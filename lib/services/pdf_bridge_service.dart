// PDF Bridge Service
// Communicates with the Node.js PDF processing server
// 
// For development: connects to local server on computer
// For production: will use embedded JavaScript engine

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'debug_logger.dart';
import '../models/pdf_document.dart';

class PdfBridgeService {
  // Server URL - change this based on where the server is running
  // For Android emulator: use 10.0.2.2 instead of localhost
  // For real device: use your computer's local IP
  static String serverUrl = 'http://10.0.2.2:3456';
  
  /// Check if server is reachable
  static Future<bool> checkHealth() async {
    try {
      DebugLogger.info('Checking server health...', serverUrl);
      final response = await http.get(
        Uri.parse('$serverUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        DebugLogger.success('Server is healthy');
        return true;
      }
      DebugLogger.error('Server unhealthy', 'Status: ${response.statusCode}');
      return false;
    } catch (e) {
      DebugLogger.error('Server unreachable', e);
      return false;
    }
  }

  /// Convert PDF file to JSON structure
  static Future<PdfConversionResult> convertPdfToJson(String pdfPath) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      DebugLogger.info('Starting PDF conversion', pdfPath);
      
      // Read file and convert to base64
      final file = File(pdfPath);
      if (!await file.exists()) {
        throw Exception('PDF file not found: $pdfPath');
      }
      
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);
      DebugLogger.debug('PDF read', '${bytes.length} bytes');
      
      // Send to server
      DebugLogger.info('Sending to server...');
      final response = await http.post(
        Uri.parse('$serverUrl/convert'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pdfBase64': base64}),
      ).timeout(const Duration(seconds: 30));
      
      stopwatch.stop();
      DebugLogger.debug('Server responded', '${response.statusCode} in ${stopwatch.elapsedMilliseconds}ms');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Add server logs
        if (data['logs'] != null) {
          DebugLogger.addServerLogs(data['logs'] as List);
        }
        
        if (data['success'] == true) {
          final doc = PdfDocument.fromJson(data['data']);
          DebugLogger.success('PDF converted', '${doc.pageCount} pages');
          
          return PdfConversionResult(
            success: true,
            document: doc,
            duration: stopwatch.elapsedMilliseconds,
          );
        }
      }
      
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
      
    } catch (e) {
      stopwatch.stop();
      DebugLogger.error('Conversion failed', e);
      
      return PdfConversionResult(
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Replace text in PDF
  static Future<PdfEditResult> replaceText({
    required String pdfPath,
    required String searchText,
    required String newText,
    required int pageNumber,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      DebugLogger.info('Starting text replacement');
      DebugLogger.debug('Search text', searchText);
      DebugLogger.debug('New text', newText);
      DebugLogger.debug('Page', pageNumber.toString());
      
      // Read file
      final file = File(pdfPath);
      final bytes = await file.readAsBytes();
      final base64Input = base64Encode(bytes);
      
      // Send to server
      DebugLogger.info('Sending replace request to server...');
      final response = await http.post(
        Uri.parse('$serverUrl/replace'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pdfBase64': base64Input,
          'searchText': searchText,
          'newText': newText,
          'pageNumber': pageNumber,
        }),
      ).timeout(const Duration(seconds: 30));
      
      stopwatch.stop();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Add server logs
        if (data['logs'] != null) {
          DebugLogger.addServerLogs(data['logs'] as List);
        }
        
        if (data['success'] == true && data['outputBase64'] != null) {
          // Save the modified PDF to a temp file
          final outputBytes = base64Decode(data['outputBase64']);
          final tempDir = Directory.systemTemp;
          final outputPath = '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
          await File(outputPath).writeAsBytes(outputBytes);
          
          DebugLogger.success('Text replaced', outputPath);
          
          return PdfEditResult(
            success: true,
            outputPath: outputPath,
            duration: stopwatch.elapsedMilliseconds,
          );
        }
      }
      
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
      
    } catch (e) {
      stopwatch.stop();
      DebugLogger.error('Replace failed', e);
      
      return PdfEditResult(
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Apply multiple edits to PDF
  static Future<PdfEditResult> applyEdits({
    required String pdfPath,
    required List<Map<String, dynamic>> edits,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      DebugLogger.info('Applying ${edits.length} edit(s)');
      
      final file = File(pdfPath);
      final bytes = await file.readAsBytes();
      final base64Input = base64Encode(bytes);
      
      final response = await http.post(
        Uri.parse('$serverUrl/apply-edits'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pdfBase64': base64Input,
          'edits': edits,
        }),
      ).timeout(const Duration(seconds: 60));
      
      stopwatch.stop();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['logs'] != null) {
          DebugLogger.addServerLogs(data['logs'] as List);
        }
        
        if (data['success'] == true && data['outputBase64'] != null) {
          final outputBytes = base64Decode(data['outputBase64']);
          final tempDir = Directory.systemTemp;
          final outputPath = '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
          await File(outputPath).writeAsBytes(outputBytes);
          
          DebugLogger.success('Edits applied', outputPath);
          
          return PdfEditResult(
            success: true,
            outputPath: outputPath,
            duration: stopwatch.elapsedMilliseconds,
          );
        }
      }
      
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
      
    } catch (e) {
      stopwatch.stop();
      DebugLogger.error('Apply edits failed', e);
      
      return PdfEditResult(
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsedMilliseconds,
      );
    }
  }
}

/// Result of PDF conversion
class PdfConversionResult {
  final bool success;
  final PdfDocument? document;
  final String? error;
  final int duration;

  PdfConversionResult({
    required this.success,
    this.document,
    this.error,
    required this.duration,
  });
}

/// Result of PDF edit operation
class PdfEditResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final int duration;

  PdfEditResult({
    required this.success,
    this.outputPath,
    this.error,
    required this.duration,
  });
}
