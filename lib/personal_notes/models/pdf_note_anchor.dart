import 'package:equatable/equatable.dart';

/// נקודה יחסית בדף PDF לא מסובב; ראשית הצירים בפינה השמאלית התחתונה.
class PdfNoteAnchor extends Equatable {
  final int pageNumber;
  final double x;
  final double y;

  /// מזהה מהדורת ה-PDF בתוך מקור הספר; אינו משנה את מפתח ההערות הוותיק.
  final String? documentId;

  const PdfNoteAnchor({
    required this.pageNumber,
    required this.x,
    required this.y,
    this.documentId,
  }) : assert(pageNumber > 0),
       assert(x >= 0 && x <= 1),
       assert(y >= 0 && y <= 1),
       assert(documentId == null || documentId.length > 0);

  factory PdfNoteAnchor.fromJson(Map<String, dynamic> json) {
    final page = json['pageNumber'];
    final x = json['x'];
    final y = json['y'];
    final documentId = json['documentId'];
    if (page is! int ||
        page < 1 ||
        x is! num ||
        y is! num ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        (documentId != null && (documentId is! String || documentId.isEmpty))) {
      throw const FormatException('Invalid PDF note anchor');
    }
    return PdfNoteAnchor(
      pageNumber: page,
      x: x.toDouble(),
      y: y.toDouble(),
      documentId: documentId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'pageNumber': pageNumber,
    'x': x,
    'y': y,
    if (documentId != null) 'documentId': documentId,
  };

  @override
  List<Object?> get props => [pageNumber, x, y, documentId];
}
