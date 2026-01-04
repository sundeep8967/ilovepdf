import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'editor_screen.dart';
import '../services/native_pdf_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickAndOpenPdf(BuildContext context, [ReplacementMethod? method]) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final tempPath = result.files.single.path!;
      
      // CRITICAL: Copy file to stable location IMMEDIATELY
      // file_picker temp files get deleted very quickly
      String stablePath = tempPath;
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          final directory = await getApplicationDocumentsDirectory();
          final fileName = tempPath.split('/').last;
          stablePath = '${directory.path}/$fileName';
          await tempFile.copy(stablePath);
          debugPrint('✅ Copied PDF to stable path: $stablePath');
        }
      } catch (e) {
        debugPrint('⚠️ Could not copy file: $e, using original path');
      }
      
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(
              pdfPath: stablePath,
              initialMethod: method,
            ),
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text(
          'PDF Editor',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF16213E),
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo/Icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF0F3460),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE94560).withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.picture_as_pdf,
                size: 60,
                color: Color(0xFFE94560),
              ),
            ),
            const SizedBox(height: 40),
            
            // Title
            const Text(
              'Edit PDF Text',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // Subtitle
            Text(
              'Select a PDF file to start editing',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 48),
            
            // Open PDF Button
            // Option 1: Current / Recommended (Visual/Strict Dialog)
            ElevatedButton.icon(
              onPressed: () => _pickAndOpenPdf(context, null),
              icon: const Icon(Icons.edit_note),
              label: const Text(
                'Edit PDF (Recommended)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: _buttonStyle(const Color(0xFFE94560)),
            ),
            const SizedBox(height: 16),

            // Option 2: Android Native (Legacy)
            ElevatedButton.icon(
              onPressed: () => _pickAndOpenPdf(context, ReplacementMethod.legacyNative),
              icon: const Icon(Icons.android),
              label: const Text(
                'Edit PDF 2 (Android Native)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: _buttonStyle(const Color(0xFF0F3460)),
            ),
            const SizedBox(height: 16),

            // Option 3: Node.js (Legacy)
            ElevatedButton.icon(
              onPressed: () => _pickAndOpenPdf(context, ReplacementMethod.nodeJs),
              icon: const Icon(Icons.javascript),
              label: const Text(
                'Edit PDF 3 (Node.js)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: _buttonStyle(const Color(0xFF0F3460)),
            ),
          ],
        ),
      ),
    );
  }
  ButtonStyle _buttonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      minimumSize: const Size(280, 56), // Fixed width for alignment
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      shadowColor: color.withOpacity(0.4),
    );
  }
}
