/// יעד של קישור inline שנוצר מקומית.
///
/// שדה [targetBookId] מוזן על-ידי ה-resolver בשלב 3; בזמן הזיהוי (שלב 2)
/// הוא null. ה-cache שומר אותו לאחר פתרון כדי שפתיחת הקישור לא תצריך
/// חיפוש מחדש בקטלוג.
class GeneratedLinkTarget {
  /// מזהה יציב של ספר היעד בקטלוג (מוזן על-ידי resolver).
  ///
  /// null עד שה-resolver מפתר את הספר.
  final int? targetBookId;

  /// שם הספר היעד כפי שמופיע בספרייה.
  final String bookTitle;

  /// מזהה הקטגוריה של ספר היעד, אם ידוע.
  final int? categoryId;

  /// סוג הקובץ של ספר היעד, בדרך כלל 'txt'.
  final String fileType;

  /// שורת היעד (0-based). null עד שה-resolver מפתר את הפסוק/דף.
  final int? targetIndex;

  /// טקסט תצוגה של המראה מקום, למשל "ברכות דף ב עמוד א".
  final String displayRef;

  const GeneratedLinkTarget({
    required this.bookTitle,
    required this.displayRef,
    this.targetBookId,
    this.categoryId,
    this.fileType = 'txt',
    this.targetIndex,
  });

  /// מחזיר האם היעד פתור במלואו (בוצע resolve).
  bool get isResolved => targetBookId != null && targetIndex != null;

  Map<String, dynamic> toJson() => {
        'bookTitle': bookTitle,
        if (targetBookId != null) 'targetBookId': targetBookId,
        if (categoryId != null) 'categoryId': categoryId,
        'fileType': fileType,
        if (targetIndex != null) 'targetIndex': targetIndex,
        'displayRef': displayRef,
      };

  factory GeneratedLinkTarget.fromJson(Map<String, dynamic> json) =>
      GeneratedLinkTarget(
        bookTitle: json['bookTitle'] as String,
        targetBookId: json['targetBookId'] as int?,
        categoryId: json['categoryId'] as int?,
        fileType: json['fileType'] as String? ?? 'txt',
        targetIndex: json['targetIndex'] as int?,
        displayRef: json['displayRef'] as String,
      );

  GeneratedLinkTarget copyWith({
    int? targetBookId,
    String? bookTitle,
    int? categoryId,
    String? fileType,
    int? targetIndex,
    String? displayRef,
  }) =>
      GeneratedLinkTarget(
        targetBookId: targetBookId ?? this.targetBookId,
        bookTitle: bookTitle ?? this.bookTitle,
        categoryId: categoryId ?? this.categoryId,
        fileType: fileType ?? this.fileType,
        targetIndex: targetIndex ?? this.targetIndex,
        displayRef: displayRef ?? this.displayRef,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedLinkTarget &&
          targetBookId == other.targetBookId &&
          bookTitle == other.bookTitle &&
          categoryId == other.categoryId &&
          fileType == other.fileType &&
          targetIndex == other.targetIndex &&
          displayRef == other.displayRef;

  @override
  int get hashCode => Object.hash(
      targetBookId, bookTitle, categoryId, fileType, targetIndex, displayRef);
}
