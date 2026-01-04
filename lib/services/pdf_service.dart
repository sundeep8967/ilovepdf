import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/pdf_document.dart';

/// Service to communicate with native PDF bridge
class PdfService {
  static const _channel = MethodChannel('com.sundeep.ilovepdf/pdf_bridge');

  /// Extract text elements from a PDF file
  Future<PdfDocument?> extractTextElements(String path) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'extractTextElements',
        {'path': path},
      );
      
      if (result != null) {
        final json = jsonDecode(result) as Map<String, dynamic>;
        return PdfDocument.fromJson(json);
      }
      return null;
    } on PlatformException catch (e) {
      print('Failed to extract text: ${e.message}');
      return null;
    }
  }

  /// Replace text in PDF and get path to modified file
  Future<String?> replaceText({
    required String path,
    required String searchText,
    required String newText,
    required int pageNumber,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'replaceText',
        {
          'path': path,
          'searchText': searchText,
          'newText': newText,
          'pageNumber': pageNumber,
        },
      );
      return result;
    } on PlatformException catch (e) {
      print('Failed to replace text: ${e.message}');
      return null;
    }
  }

  /// Save document to a new location
  Future<bool> saveDocument({
    required String inputPath,
    required String outputPath,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'saveDocument',
        {
          'inputPath': inputPath,
          'outputPath': outputPath,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to save document: ${e.message}');
      return false;
    }
  }
}
