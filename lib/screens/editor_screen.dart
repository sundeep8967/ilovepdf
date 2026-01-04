import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import '../services/native_pdf_service.dart';
import '../services/debug_logger.dart';
import '../services/pdf_bridge_service.dart';
import '../services/pdf_service.dart';
import '../models/pdf_document.dart' as models;

class EditorScreen extends StatefulWidget {
  final String pdfPath;
  final ReplacementMethod? initialMethod;

  const EditorScreen({
    super.key, 
    required this.pdfPath,
    this.initialMethod,
  });

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
  bool _isDisposed = false;
  
  // Edit history
  final List<models.EditOperation> _editHistory = [];

  // Manual Drag Edit State
  bool _isManualEditing = false;
  Rect? _selectionRect;
  Offset _dragOffset = Offset.zero;
  TextStyleInfo? _editingStyle;
  String _editingText = '';
  double _editingFontSize = 12.0;
  bool _editingBold = false;
  bool _editingItalic = false;
  Offset? _initialDragPos;
  double _editScaleFactor = 1.0;
  Rect? _localSelectionRect;
  final GlobalKey _stackKey = GlobalKey();
  
  // Magnifier State
  bool _isZoomEnabled = true; // Default to ON as requested
  bool _isDragging = false;

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
    
    // Copy file to stable location to prevent file_picker cleanup issues
    try {
      final originalFile = File(_currentPath);
      if (await originalFile.exists()) {
        final directory = await getApplicationDocumentsDirectory();
        final stablePath = '${directory.path}/working_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final stableFile = await originalFile.copy(stablePath);
        _currentPath = stableFile.path;
        DebugLogger.info('Copied to stable path', stablePath);
      }
    } catch (e) {
      DebugLogger.warning('Could not copy file', e.toString());
    }
    
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
    
    // Avoid setState during build/layout/paint phases (widget tree locked)
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      // If we are disposing or building, we simply ignore the update
      // triggering selection clear during dispose is common in SfPdfViewer
      return; 
    }
    
    if (details.selectedText != null && details.selectedText!.isNotEmpty) {
      DebugLogger.debug('Text selected', '"${details.selectedText}"');
      setState(() {
        _selectedText = details.selectedText;
        _selectionRect = details.globalSelectedRegion;
      });
    } else {
      if (mounted) {
        setState(() {
          _selectedText = null;
        });
      }
    }
  }


  Future<void> _handleManualEdit() async {
    if (_selectedText == null) return;
    
    setState(() => _isLoading = true);
    
    // 1. Inspect Text Style
    final styleInfo = await PdfService().inspectText(
      path: _currentPath,
      searchText: _selectedText!.trim(), // Trim to avoid whitespace issues
      pageNumber: _pdfController.pageNumber - 1,
    );
    
    setState(() => _isLoading = false);
    
    if (!mounted) return;
    
    // 2. Determine initial position & Scale
    Offset initialPos = const Offset(100, 100);
    // Default scale to device pixel ratio (usually ~3.0) to prevent hypersensitivity if width not found
    double scale = MediaQuery.of(context).devicePixelRatio;
    Rect? localRect;
    
    if (_selectionRect != null) {
      if (_selectionRect!.width > 0 && styleInfo.width > 0) {
        scale = _selectionRect!.width / styleInfo.width;
      }
      
      // Convert global to local
      final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox != null) {
        final stackTopLeft = stackBox.localToGlobal(Offset.zero);
        DebugLogger.info('Coordinate Debug', 'SelectionRect Global: ${_selectionRect!.topLeft}, Stack Global: $stackTopLeft');
        
        initialPos = stackBox.globalToLocal(_selectionRect!.topLeft);
        
        // CORRECTION: Small fixed nudge (5px) to account for padding.
        // Full height (30px) and Half height (15px) were too high ("Upper").
        // Zero shift was too low ("Came Down").
        // 5px should bridge the gap caused by internal padding.
        initialPos -= const Offset(0, 5);
        
        DebugLogger.info('Coordinate Debug', 'Calculated InitialPos (Local) Nudged: $initialPos');

        // Calculate local rect for the white cover
        localRect = initialPos & _selectionRect!.size;
      } else {
        initialPos = _selectionRect!.topLeft; 
        localRect = _selectionRect;
        DebugLogger.warning('Coordinate Debug', 'StackBox not found, using raw rect');
      }
    }

    // 3. Enter Manual Edit Mode
    setState(() {
      _isManualEditing = true;
      _editingStyle = styleInfo;
      _editingText = _selectedText!;
      _editingFontSize = styleInfo.fontSize > 0 ? styleInfo.fontSize : 12.0;
      _editingBold = styleInfo.isBold;
      _editingItalic = styleInfo.isItalic;
      _dragOffset = initialPos;
      _initialDragPos = initialPos;
      _editScaleFactor = scale;
      _localSelectionRect = localRect;
    });
  }

  Widget _buildStyleToggle({required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blueAccent : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? Colors.blue : Colors.transparent),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  List<Widget> _buildManualEditOverlay() {
    return [
      // 0. White Cover (Eraser) - Hides original text
      if (_localSelectionRect != null)
        Positioned(
          left: _localSelectionRect!.left,
          top: _localSelectionRect!.top,
          width: _localSelectionRect!.width,
          height: _localSelectionRect!.height,
          child: Container(
            color: Colors.white,
          ),
        ),

      // 1. White Cover for Pink Markers (PRECISE size matching text)
      // Covers ONLY the pink selection circles, not surrounding context.
      if (_localSelectionRect != null)
        Positioned(
          left: _dragOffset.dx,
          top: _dragOffset.dy,
          child: IgnorePointer(
            child: Container(
              width: _localSelectionRect!.width + 10, // Just slightly wider than text
              height: _localSelectionRect!.height + 5, // Match text height
              color: Colors.white,
            ),
          ),
        ),

      // 2. Clean Text Layer (EXACT drag position, NO border)
      // This is what the Magnifier will SEE and magnify.
      // Placed AFTER white cover so text is on top.
      Positioned(
        left: _dragOffset.dx + 4, // Match padding
        top: _dragOffset.dy + 2,  // Match padding
        child: IgnorePointer(
          child: Text(
            _editingText,
            style: TextStyle(
              fontSize: _editingFontSize * _editScaleFactor,
              fontWeight: _editingBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: _editingItalic ? FontStyle.italic : FontStyle.normal,
              color: Colors.black,
              fontFamily: 'Helvetica',
            ),
          ),
        ),
      ),

      // 2. Magnifier (Zoom Effect) - Wide View
      // Now simply magnifies the Clean Text above (which is at exact position).
      if (_isZoomEnabled)
        Positioned(
          left: _dragOffset.dx - 140, // Center wide box
          top: _dragOffset.dy - 120, // Float higher
          child: SizedBox(
            width: 280,
            height: 80,
            child: RawMagnifier(
              size: const Size(280, 80),
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.blueAccent, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                shadows: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
                ],
              ),
              magnificationScale: 1.5,
              focalPointOffset: const Offset(0, 80), 
            ),
          ),
        ),

      // 2. Draggable Text (The UI Control)
      // Visual: HAS Blue Border (User Request).
      // Stack: Above Magnifier (so Magnifier looks "under" it and sees only PDF).
      Positioned(
        left: _dragOffset.dx,
        top: _dragOffset.dy,
        child: GestureDetector(
          onPanDown: (_) => setState(() => _isDragging = true), 
          onPanCancel: () => setState(() => _isDragging = false),
          onPanEnd: (_) => setState(() => _isDragging = false),
          onPanUpdate: (details) {
            setState(() {
              _dragOffset += details.delta;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              boxShadow: const [
                 BoxShadow(
                   color: Colors.black26, 
                   blurRadius: 4,
                   offset: Offset(2, 2),
                 ),
              ],
              border: Border.all(color: Colors.blueAccent, width: 1), // Border visible here!
            ),
            child: Text(
              _editingText,
              style: TextStyle(
                fontSize: _editingFontSize * _editScaleFactor,
                fontWeight: _editingBold ? FontWeight.bold : FontWeight.normal,
                fontStyle: _editingItalic ? FontStyle.italic : FontStyle.normal,
                color: Colors.black,
                fontFamily: 'Helvetica',
              ),
            ),
          ),
        ),
      ),
      
      // 2. Control Panel
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          color: const Color(0xFF1A1A2E),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Text Field
              TextField(
                controller: TextEditingController(text: _editingText)
                  ..selection = TextSelection.collapsed(offset: _editingText.length),
                onChanged: (val) => setState(() => _editingText = val),
                 style: const TextStyle(color: Colors.white),
                 decoration: const InputDecoration(
                   labelText: 'Edit Text',
                   labelStyle: TextStyle(color: Colors.white70),
                   border: OutlineInputBorder(),
                 ),
              ),
              const SizedBox(height: 12),
              
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Style
                  Row(
                    children: [
                      _buildStyleToggle(
                        icon: Icons.format_bold,
                        isActive: _editingBold,
                        onTap: () => setState(() => _editingBold = !_editingBold),
                      ),
                      const SizedBox(width: 8),
                      _buildStyleToggle(
                        icon: Icons.format_italic,
                        isActive: _editingItalic,
                        onTap: () => setState(() => _editingItalic = !_editingItalic),
                      ),
                      const SizedBox(width: 16),
                      // Zoom Toggle
                      _buildStyleToggle(
                        icon: Icons.zoom_in,
                        isActive: _isZoomEnabled, // New state
                        onTap: () => setState(() => _isZoomEnabled = !_isZoomEnabled),
                      ),
                    ],
                  ),
                  
                  // Size
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, color: Colors.white),
                        onPressed: () => setState(() => _editingFontSize = (_editingFontSize - 0.5).clamp(4.0, 72.0)),
                      ),
                      Text(
                        _editingFontSize.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.white),
                        onPressed: () => setState(() => _editingFontSize = (_editingFontSize + 0.5).clamp(4.0, 72.0)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isManualEditing = false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _applyManualEdit,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560)),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _applyManualEdit() async {
    setState(() => _isLoading = true);
    
    // Calculate Delta (Pixels -> PDF Points)
    final pixelDelta = _dragOffset - (_initialDragPos ?? Offset.zero);
    
    // Standard Scale
    double deltaX = pixelDelta.dx / _editScaleFactor;
    double deltaY = pixelDelta.dy / _editScaleFactor;

    // Apply Rotation Correction
    // Visual Up (-Y) usually maps to PDF Up (+Y) in standard (0 deg) files.
    // Normalized Delta: Assume Standard PDF (Bottom-Up)
    
    double pdfDeltaX = 0;
    double pdfDeltaY = 0;
    
    final int rotation = _editingStyle?.rotation ?? 0;
    DebugLogger.info('Applying Edit with Rotation', '$rotation degrees');

    switch (rotation) {
      case 90:
        pdfDeltaX = deltaY;       // Drag Right -> Move Up?
        pdfDeltaY = deltaX;       // Drag Down -> Move Right?
        break;
      case 180:
        pdfDeltaX = -deltaX;      // Drag Right -> Move Left
        pdfDeltaY = deltaY;       // Drag Down (+Y) -> Move Up (+Y in rotated frame)? No.
                                  // 180 means Visual Down aligns with PDF Up.
                                  // So Drag Down (+Y) -> Increase PDF Y.
        break;
      case 270:
        pdfDeltaX = -deltaY;
        pdfDeltaY = -deltaX;
        break;
      case 0:
      default:
        pdfDeltaX = deltaX;
        // Inverted Y Logic: Drag Down (+Y visual) -> Decrease PDF Y (Bottom-Up)
        pdfDeltaY = -deltaY; 
        break;
    }

    DebugLogger.info('Delta Calc', 'Px: $pixelDelta, Scale: $_editScaleFactor -> PDF Delta: ($pdfDeltaX, $pdfDeltaY)');
    
    final newPath = await PdfService().replaceTextAdvanced(
      path: _currentPath,
      searchText: _selectedText!,
      newText: _editingText,
      pageNumber: _pdfController.pageNumber - 1,
      fontSize: _editingFontSize,
      isBold: _editingBold,
      isItalic: _editingItalic,
      xOffset: pdfDeltaX,
      yOffset: pdfDeltaY,
    );
    
    setState(() {
      _isLoading = false;
      _isManualEditing = false; // Exit mode
    });
    
    if (newPath != null) {
      setState(() {
        _currentPath = newPath;
        _hasChanges = true;
        _selectedText = null;
        _selectionRect = null; // Clear selection
      });
      DebugLogger.success('Advanced Edit Applied');
    } else {
      DebugLogger.error('Edit Failed');
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
      
      // If a specific method was chosen at launch, use it immediately
      if (widget.initialMethod != null) {
        if (!mounted) return;
        await _replaceText(_selectedText!, result, currentPage, widget.initialMethod!);
        return;
      }

      // Otherwise ask user for alignment method preference
      if (!mounted) return;
      final method = await showDialog<ReplacementMethod>(
        context: context,
        builder: (context) => SimpleDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Choose Alignment', style: TextStyle(color: Colors.white)),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ReplacementMethod.visual),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Visual Alignment (Recommended)', style: TextStyle(color: Colors.white)),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ReplacementMethod.strict),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Strict Alignment (Native)', style: TextStyle(color: Colors.white70)),
              ),
            ),
            const Divider(color: Colors.white24),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ReplacementMethod.manualMode),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Option 3: Manual Mode', style: TextStyle(color: Colors.lightGreenAccent)),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ReplacementMethod.legacyNative),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Option 2: Android Native (Legacy)', style: TextStyle(color: Colors.amber)),
              ),
            ),
          ],
        ),
      );
      
      if (method != null) {
        await _replaceText(_selectedText!, result, currentPage, method);
      }
    } else {
      DebugLogger.debug('Edit cancelled');
    }
  }

  Future<void> _replaceText(String oldText, String newText, int pageNumber, ReplacementMethod method) async {
    setState(() => _isLoading = true);
    DebugLogger.info('Starting text replacement...');

    String? newPath;

    if (method == ReplacementMethod.manualMode) {
      // Manual Mode: Uses Native backend (style-preserving)
      try {
        newPath = await PdfService().replaceText(
          path: _currentPath,
          searchText: oldText,
          newText: newText,
          pageNumber: pageNumber - 1,
        );
        if (newPath == null) {
          DebugLogger.error('Manual Mode replace failed');
        }
      } catch (e) {
        DebugLogger.error('Manual Mode Error', e.toString());
      }
    } else if (method == ReplacementMethod.legacyNative) {
      // Option 2: Android Native (MethodChannel)
      try {
        newPath = await PdfService().replaceText(
          path: _currentPath,
          searchText: oldText,
          newText: newText,
          pageNumber: pageNumber - 1,
        );
        if (newPath == null) {
          DebugLogger.error('Native Bridge failed', 'Start server or check logs');
        }
      } catch (e) {
        DebugLogger.error('Native Bridge Error', e.toString());
      }
    } else {
      // Option 3: Syncfusion Native (Visual or Strict)
      newPath = await NativePdfService.replaceText(
        pdfPath: _currentPath,
        searchText: oldText,
        newText: newText,
        pageNumber: pageNumber - 1, // 0-indexed
        method: method,
      );
    }

    if (newPath != null) {
      // Add to history
      _editHistory.add(models.EditOperation(
        elementId: 'edit_${_editHistory.length}',
        oldText: oldText,
        newText: newText,
        pageNumber: pageNumber - 1,
      ));

      setState(() {
        _currentPath = newPath!;
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

  Future<void> _handleBackNavigation() async {
    if (_isDisposed) return;
    _isDisposed = true;  // Mark as disposed before navigation
    
    // Clear selection before navigating to avoid render object issues
    try {
      _pdfController.clearSelection();
    } catch (e) {
      // Ignore - widget may already be disposed
    }
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: Scaffold(
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
              key: _stackKey,
              children: [
                SfPdfViewer.file(
                  File(_currentPath),
                  key: ValueKey(_currentPath),
                  controller: _pdfController,
                  canShowTextSelectionMenu: false,  // Disabled - use our Edit Text button instead
                  enableTextSelection: !_isManualEditing, // Disable native selection while dragging
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

                // Manual Edit Overlay (Drag & Controls)
                if (_isManualEditing)
                  ..._buildManualEditOverlay(),
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
      floatingActionButton: (_selectedText != null && !_isManualEditing)
          ? FloatingActionButton.extended(
              onPressed: () {
                if (widget.initialMethod == ReplacementMethod.manualMode) {
                  _handleManualEdit();
                } else {
                  _showEditDialog();
                }
              },
              backgroundColor: const Color(0xFFE94560),
              icon: const Icon(Icons.edit),
              label: const Text('Edit Text'),
            )
          : null,
      ),
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
    _isDisposed = true;
    // Dispose controller safely
    try {
      _pdfController.clearSelection();
      _pdfController.dispose();
    } catch (e) {
      // Ignore dispose error
    }
    super.dispose();
  }
}


