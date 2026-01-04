/// Represents a PDF document with extracted text elements
class PdfDocument {
  final String path;
  final int pageCount;
  final List<PdfPage> pages;

  PdfDocument({
    required this.path,
    required this.pageCount,
    required this.pages,
  });

  factory PdfDocument.fromJson(Map<String, dynamic> json) {
    return PdfDocument(
      path: json['path'] as String,
      pageCount: json['pageCount'] as int,
      pages: (json['pages'] as List)
          .map((p) => PdfPage.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Represents a single page in the PDF
class PdfPage {
  final int pageNumber;
  final double width;
  final double height;
  final List<TextElement> elements;

  PdfPage({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.elements,
  });

  factory PdfPage.fromJson(Map<String, dynamic> json) {
    return PdfPage(
      pageNumber: json['pageNumber'] as int,
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      elements: (json['elements'] as List)
          .map((e) => TextElement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Represents a text element in the PDF
class TextElement {
  final String id;
  final String content;
  final double x;
  final double y;
  final double width;
  final double height;
  final int pageNumber;

  TextElement({
    required this.id,
    required this.content,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pageNumber,
  });

  factory TextElement.fromJson(Map<String, dynamic> json) {
    return TextElement(
      id: json['id'] as String,
      content: json['content'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      pageNumber: json['pageNumber'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'pageNumber': pageNumber,
    };
  }
}

/// Represents an edit operation
class EditOperation {
  final String elementId;
  final String oldText;
  final String newText;
  final int pageNumber;
  final DateTime timestamp;

  EditOperation({
    required this.elementId,
    required this.oldText,
    required this.newText,
    required this.pageNumber,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'elementId': elementId,
      'oldText': oldText,
      'newText': newText,
      'pageNumber': pageNumber,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
