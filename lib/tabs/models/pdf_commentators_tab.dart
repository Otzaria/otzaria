import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

/// Tab שמציג מפרשים של ספר PDF בכרטסייה עצמאית.
///
/// [PdfCommentatorsTab.of] נותן לכרטיסייה עותק משלה של מצב הספר, כמו כרטיסיית
/// הטקסט: מיקום ובחירת מפרשים משלה, והיא לא נגררת אחרי הדפדוף בספר.
class PdfCommentatorsTab extends OpenedTab {
  final PdfBookTab sourceTab;
  bool applyBookSelection;
  SourceTabOwnership? _sourceTabOwnership;

  PdfCommentatorsTab({
    required this.sourceTab,
    bool disposeSourceTabOnDispose = false,
    this.applyBookSelection = false,
  }) : super('מפרשים | ${sourceTab.title}') {
    if (disposeSourceTabOnDispose) {
      _sourceTabOwnership = SourceTabOwnership(sourceTab)..retain();
    }
  }

  /// כרטיסייה חדשה מתוך ספר פתוח. בלי העותק היא חלקה עם הספר את המפרשים
  /// הפעילים ואת רשימת הקישורים, ושדרוג הרשימה המלאה שלה כיבה את חלון הקישורים.
  factory PdfCommentatorsTab.of(
    PdfBookTab book, {
    bool applyBookSelection = true,
  }) {
    final copiedSource = OpenedTab.from(book) as PdfBookTab;
    copiedSource.activeCommentators = Set<String>.of(book.activeCommentators);
    copiedSource.pdfHeadings = book.pdfHeadings;
    copiedSource.currentTextLineNumber = book.currentTextLineNumber;
    copiedSource.currentTextLineNumberEnd = book.currentTextLineNumberEnd;
    copiedSource.currentTitle.value = book.currentTitle.value;
    return PdfCommentatorsTab(
      sourceTab: copiedSource,
      applyBookSelection: applyBookSelection,
      disposeSourceTabOnDispose: true,
    );
  }

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
    if (json['currentTitle'] case final String title) {
      sourceTab.currentTitle.value = title;
    }

    return PdfCommentatorsTab(
      sourceTab: sourceTab,
      applyBookSelection:
          active == null && sourceTab.activeCommentators.isEmpty,
      disposeSourceTabOnDispose: true,
    )..isPinned = json['isPinned'] ?? false;
  }

  /// לכל שכפול [sourceTab] משלו: [dispose] של אחד משחרר את הבקרים שלו.
  @override
  OpenedTab clone() =>
      PdfCommentatorsTab.of(sourceTab, applyBookSelection: false)
        ..isPinned = isPinned;

  /// יורש את הבעלות על [sourceTab] כשטאב הספר שהחזיק אותו נסגר.
  ///
  /// ⚠️ בלי זה שחרור טאב הספר משאיר את הכרטיסיה הזו מצביעה על
  /// `currentTitle` משוחרר — ורצועת הכרטיסיות עצמה מאזינה לו.
  void assumeSourceTabOwnership(SourceTabOwnership ownership) {
    assert(identical(ownership.sourceTab, sourceTab));
    _sourceTabOwnership = ownership..retain();
  }

  @override
  void dispose() {
    _sourceTabOwnership?.release();
    _sourceTabOwnership = null;
    super.dispose();
  }

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'type': 'PdfCommentatorsTab',
    'isPinned': isPinned,
    'sourceTab': sourceTab.toJson(),
    // הכותרת שאליה נווט בכרטיסייה; ה-sourceTab שומר רק את העמוד.
    'currentTitle': sourceTab.currentTitle.value,
    'activeCommentators': sourceTab.activeCommentators.toList(),
  };
}
