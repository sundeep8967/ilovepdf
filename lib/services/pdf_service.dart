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

  /// Inspect text to get style and position info
  Future<TextStyleInfo> inspectText({
    required String path,
    required String searchText,
    required int pageNumber,
  }) async {
    try {
      final jsonString = await _channel.invokeMethod<String>('inspectText', {
        'path': path,
        'searchText': searchText,
        'pageNumber': pageNumber,
      });
      
      if (jsonString != null) {
        final Map<String, dynamic> data = jsonDecode(jsonString);
        return TextStyleInfo.fromJson(data);
      }
      return TextStyleInfo(found: false);
    } on PlatformException catch (e) {
      print('Error inspecting text: ${e.message}');
      return TextStyleInfo(found: false);
    }
  }

  /// Advanced Replace with Manual Overrides
  Future<String?> replaceTextAdvanced({
    required String path,
    required String searchText,
    required String newText,
    required int pageNumber,
    required double fontSize,
    required bool isBold,
    required bool isItalic,
    required double xOffset,
    required double yOffset,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('replaceTextAdvanced', {
        'path': path,
        'searchText': searchText,
        'newText': newText,
        'pageNumber': pageNumber,
        'fontSize': fontSize,
        'isBold': isBold,
        'isItalic': isItalic,
        'xOffset': xOffset,
        'yOffset': yOffset,
      });
      return result;
    } on PlatformException catch (e) {
      print('Error replacing text advanced: ${e.message}');
      return null;
    }
  }
}

class TextStyleInfo {
  final bool found;
  final double fontSize;
  final bool isBold;
  final bool isItalic;
  final double x;
  final double y;

  TextStyleInfo({
    this.found = false,
    this.fontSize = 12.0,
    this.isBold = false,
    this.isItalic = false,
    this.x = 0.0,
    this.y = 0.0,
  });

  factory TextStyleInfo.fromJson(Map<String, dynamic> json) {
    if (json['found'] != true) return TextStyleInfo(found: false);
    
    return TextStyleInfo(
      found: true,
      fontSize: (json['fontSize'] as num).toDouble(),
      isBold: json['isBold'] == true,
      isItalic: json['isItalic'] == true,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
}
