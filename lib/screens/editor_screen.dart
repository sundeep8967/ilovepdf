import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import '../services/native_pdf_service.dart';
import '../services/debug_logger.dart';
import '../models/pdf_document.dart' as models;

class EditorScreen extends StatefulWidget {
  final String pdfPath;

  const EditorScreen({super.key, required this.pdfPath});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  
  String _currentPath = '';
  models.PdfDocument? _document;
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _selectedText;
  bool _showDebugPanel = false;
  
  // Edit history
  final List<models.EditOperation> _editHistory = [];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.pdfPath;
    DebugLogger.clear();
    DebugLogger.info('EditorScreen initialized', _currentPath);
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    setState(() => _isLoading = true);
    
    DebugLogger.info('Loading PDF document...');
    final doc = await NativePdfService.extractTextElements(_currentPath);
    
    if (mounted) {
      setState(() {
        _document = doc;
        _isLoading = false;
      });
      
      if (doc != null) {
        DebugLogger.success('Document loaded', '${doc.pageCount} pages, ${doc.pages.fold<int>(0, (sum, p) => sum + p.elements.length)} elements');
      } else {
        DebugLogger.error('Failed to load document');
      }
    }
  }

  void _onTextSelectionChanged(PdfTextSelectionChangedDetails details) {
    // IMPORTANT: Check mounted to prevent setState errors during disposal
    if (!mounted) return;
    
    if (details.selectedText != null && details.selectedText!.isNotEmpty) {
      DebugLogger.debug('Text selected', '"${details.selectedText}"');
      setState(() {
        _selectedText = details.selectedText;
      });
    } else {
      if (mounted) {
        setState(() {
          _selectedText = null;
        });
      }
    }
  }

  Future<void> _showEditDialog() async {
    if (_selectedText == null) return;

    DebugLogger.info('Opening edit dialog', 'Selected: "$_selectedText"');
    
    final controller = TextEditingController(text: _selectedText);
    final currentPage = _pdfController.pageNumber;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Edit Text',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Original: "$_selectedText"',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter new text',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: const Color(0xFF0F3460),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE94560)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Replace'),
          ),
        ],
      ),
    );

    if (result != null && result != _selectedText) {
      DebugLogger.info('User confirmed edit', '"$_selectedText" → "$result"');
      await _replaceText(_selectedText!, result, currentPage);
    } else {
      DebugLogger.debug('Edit cancelled');
    }
  }

  Future<void> _replaceText(String oldText, String newText, int pageNumber) async {
    setState(() => _isLoading = true);
    DebugLogger.info('Starting text replacement...');

    final newPath = await NativePdfService.replaceText(
      pdfPath: _currentPath,
      searchText: oldText,
      newText: newText,
      pageNumber: pageNumber - 1, // 0-indexed
    );

    if (newPath != null) {
      // Add to history
      _editHistory.add(models.EditOperation(
        elementId: 'edit_${_editHistory.length}',
        oldText: oldText,
        newText: newText,
        pageNumber: pageNumber - 1,
      ));

      setState(() {
        _currentPath = newPath;
        _hasChanges = true;
        _selectedText = null;
        _isLoading = false;
      });

      DebugLogger.success('Text replaced successfully!');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Text replaced successfully!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } else {
      setState(() => _isLoading = false);
      
      DebugLogger.error('Failed to replace text');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to replace text. Check debug logs.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View Logs',
              textColor: Colors.white,
              onPressed: () => setState(() => _showDebugPanel = true),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveDocument() async {
    DebugLogger.info('Saving document...');
    
    final directory = await getExternalStorageDirectory();
    if (directory == null) {
      DebugLogger.error('Could not access storage');
      return;
    }

    final fileName = 'edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outputPath = '${directory.path}/$fileName';

    final success = await NativePdfService.saveDocument(
      inputPath: _currentPath,
      outputPath: outputPath,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success 
              ? 'Saved to: $fileName' 
              : 'Failed to save document',
          ),
          backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _copyLogs() {
    final logsText = DebugLogger.getLogsAsText();
    Clipboard.setData(ClipboardData(text: logsText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text(
          'Edit PDF',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF16213E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Debug toggle
          IconButton(
            icon: Icon(
              _showDebugPanel ? Icons.bug_report : Icons.bug_report_outlined,
              color: _showDebugPanel ? const Color(0xFFE94560) : Colors.white,
            ),
            tooltip: 'Toggle Debug Panel',
            onPressed: () => setState(() => _showDebugPanel = !_showDebugPanel),
          ),
          if (_hasChanges)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save PDF',
              onPressed: _saveDocument,
            ),
        ],
      ),
      body: Column(
        children: [
          // PDF Viewer
          Expanded(
            flex: _showDebugPanel ? 2 : 1,
            child: Stack(
              children: [
                SfPdfViewer.file(
                  File(_currentPath),
                  key: ValueKey(_currentPath),
                  controller: _pdfController,
                  canShowTextSelectionMenu: false,  // Disabled - use our Edit Text button instead
                  enableTextSelection: true,
                  onTextSelectionChanged: _onTextSelectionChanged,
                ),
                
                // Loading Overlay
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Color(0xFFE94560),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Processing PDF...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Debug Panel
          if (_showDebugPanel)
            Expanded(
              flex: 1,
              child: Container(
                color: const Color(0xFF0D0D1A),
                child: Column(
                  children: [
                    // Debug header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: const Color(0xFF16213E),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'Debug Logs',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            color: Colors.white70,
                            onPressed: _copyLogs,
                            tooltip: 'Copy Logs',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            color: Colors.white70,
                            onPressed: () {
                              DebugLogger.clear();
                              setState(() {});
                            },
                            tooltip: 'Clear Logs',
                          ),
                        ],
                      ),
                    ),
                    // Log list
                    Expanded(
                      child: ValueListenableBuilder<List<LogEntry>>(
                        valueListenable: DebugLogger.logsNotifier,
                        builder: (context, logs, _) {
                          return ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final log = logs[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  log.formatted,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: _getLogColor(log.level),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      
      // Edit FAB
      floatingActionButton: _selectedText != null
          ? FloatingActionButton.extended(
              onPressed: _showEditDialog,
              backgroundColor: const Color(0xFFE94560),
              icon: const Icon(Icons.edit),
              label: const Text('Edit Text'),
            )
          : null,
    );
  }

  Color _getLogColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.yellow.shade300;
      case LogLevel.info:
        return Colors.blue.shade300;
      case LogLevel.success:
        return Colors.green.shade300;
      case LogLevel.warning:
        return Colors.orange.shade300;
      case LogLevel.error:
        return Colors.red.shade300;
    }
  }

  @override
  void dispose() {
    // Dispose controller safely
    try {
      _pdfController.dispose();
    } catch (e) {
      DebugLogger.debug('Controller dispose error (expected)', '$e');
    }
    super.dispose();
  }
}
