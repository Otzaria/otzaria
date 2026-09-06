import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

/// Tab שמציג מפרשים של ספר PDF בכרטסייה עצמאית.
///
/// בעת פתיחה רגילה (מהספר החי) חולק את ה-state עם [sourceTab] הפעיל.
/// בעת שחזור מהפעלה קודמת נבנה [sourceTab] חדש מתוך הנתונים השמורים
/// (נתיב + עמוד + מפרשים פעילים), והמסך טוען בעצמו את ה-headings/links
/// החסרים. במצב זה הטאב הוא הבעלים של ה-sourceTab ומשחרר אותו ב-dispose.
class PdfCommentatorsTab extends OpenedTab {
  final PdfBookTab sourceTab;
  bool _disposeSourceTabOnDispose;

  PdfCommentatorsTab({
    required this.sourceTab,
    this._disposeSourceTabOnDispose = false,
  }) : super('מפרשים | ${sourceTab.title}');

  /// שחזור מ-JSON — בונה sourceTab חדש מהנתונים השמורים.
  factory PdfCommentatorsTab.fromJson(Map<String, dynamic> json) {
    final rawSourceTab = json['sourceTab'];
    final Map<String, dynamic> sourceJson = rawSourceTab is Map
        ? Map<String, dynamic>.from(rawSourceTab)
        : <String, dynamic>{};

    final sourceTab = PdfBookTab.fromJson(sourceJson);
    final active = (json['activeCommentators'] as List?)?.cast<String>();
    if (active != null) {
      sourceTab.activeCommentators = active.toSet();
    }

    return PdfCommentatorsTab(
      sourceTab: sourceTab,
      disposeSourceTabOnDispose: true,
    )..isPinned = json['isPinned'] ?? false;
  }

  /// המקור והשכפול חייבים לקבל [sourceTab] נפרד: קודם שניהם הצביעו על אותו
  /// [PdfBookTab], ו-[dispose] של האחד שחרר את הבקרים של השני.
  @override
  OpenedTab clone() {
    // `OpenedTab.from` מעביר פרמטרי קונסטרוקטור בלבד. ארבעת השדות הבאים
    // נקבעים אחרי הבנייה, ובלעדיהם הכרטיסייה המשוכפלת נפתחת בלי בחירת
    // המפרשים — רגרסיה שהמשתמש רואה. [fromJson] למעלה עושה בדיוק את אותו
    // דבר עבור activeCommentators.
    final copiedSource = OpenedTab.from(sourceTab) as PdfBookTab;
    copiedSource.activeCommentators = Set<String>.of(
      sourceTab.activeCommentators,
    );
    copiedSource.pdfHeadings = sourceTab.pdfHeadings;
    copiedSource.currentTextLineNumber = sourceTab.currentTextLineNumber;
    copiedSource.currentTextLineNumberEnd = sourceTab.currentTextLineNumberEnd;

    return PdfCommentatorsTab(
      sourceTab: copiedSource,
      // השכפול הוא הבעלים של ה-sourceTab שנוצר כאן; בלי זה הבקרים
      // וה-ValueNotifier-ים שלו לא משוחררים לעולם.
      disposeSourceTabOnDispose: true,
    )..isPinned = isPinned;
  }

  /// יורש את הבעלות על [sourceTab] כשטאב הספר שהחזיק אותו נסגר.
  ///
  /// ⚠️ בלי זה שחרור טאב הספר משאיר את הכרטיסיה הזו מצביעה על
  /// `currentTitle` משוחרר — ורצועת הכרטיסיות עצמה מאזינה לו.
  void assumeSourceTabOwnership() {
    _disposeSourceTabOnDispose = true;
  }

  @override
  void dispose() {
    if (_disposeSourceTabOnDispose) {
      sourceTab.dispose();
    }
    super.dispose();
  }

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'type': 'PdfCommentatorsTab',
    'isPinned': isPinned,
    'sourceTab': sourceTab.toJson(),
    'activeCommentators': sourceTab.activeCommentators.toList(),
  };
}
