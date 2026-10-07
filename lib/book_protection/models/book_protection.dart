import 'package:equatable/equatable.dart';

/// הגבלות המו"ל על ספר ובאנר הקרדיט שלו, מהטבלאות `book_protection` ו-`book_banner`.
///
/// [level] 0 = אין הגבלה. רמה לא מוכרת מעל [maxKnownLevel] נחשבת לרמה המחמירה ביותר.
class BookProtection extends Equatable {
  const BookProtection({this.level = 0, this.bannerText});

  static const BookProtection none = BookProtection();

  /// הרמה המחמירה ביותר שהאפליקציה מכירה.
  static const int maxKnownLevel = 2;

  /// מספר השורות המרבי בפעולת העתקה אחת בספר מוגן.
  static const int copySegmentLimit = 5;

  /// מספר השורות המרבי בעבודת הדפסה אחת ברמה 2.
  static const int printSegmentLimit = 15;

  final int level;
  final String? bannerText;

  int get effectiveLevel => level <= 0
      ? 0
      : level > maxKnownLevel
      ? maxKnownLevel
      : level;

  bool get isProtected => effectiveLevel > 0;

  bool get hasBanner => bannerText != null && bannerText!.trim().isNotEmpty;

  /// ייצוא ל-Word/טקסט — פורמט שקל לערוך.
  bool get allowsEditableExport => effectiveLevel < 1;

  /// "שמירה כ-PDF" במסך ההדפסה.
  bool get allowsPdfExport => effectiveLevel < 2;

  /// null = ללא הגבלה.
  int? get maxCopySegments => effectiveLevel >= 1 ? copySegmentLimit : null;

  /// null = ללא הגבלה.
  int? get maxPrintSegments => effectiveLevel >= 2 ? printSegmentLimit : null;

  bool allowsCopyOf(int segmentCount) {
    final max = maxCopySegments;
    return max == null || segmentCount <= max;
  }

  /// סוף טווח הדפסה (בלעדי) [start]..[end] אחרי מגבלת ההדפסה.
  int limitPrintEnd(int start, int end) {
    final max = maxPrintSegments;
    return max == null || end - start <= max ? end : start + max;
  }

  /// המחמירה מבין שתי ההגבלות (לפלט שמשלב כמה ספרים); הבאנר נשמר מ-this.
  BookProtection strictest(BookProtection other) =>
      other.effectiveLevel > effectiveLevel
      ? BookProtection(level: other.level, bannerText: bannerText)
      : this;

  @override
  List<Object?> get props => [level, bannerText];
}
