import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/file/page_converter.dart';

/// האם הגדרת פורמט הפתיחה של תלמוד בבלי היא PDF (ברירת המחדל: טקסט).
bool talmudBavliOpensInPdf() =>
    Settings.getValue<String>(SettingsRepository.keyTalmudBavliOpenFormat) ==
    'pdf';

/// האם [book] הוא מסכת תלמוד בבלי (ולא מפרש או ספר עזר).
///
/// מסכתות טקסט יושבות ב'תלמוד בבלי / סדר X'; ה-PDF-ים ישירות בקטגוריית
/// 'תלמוד בבלי'. מפרשים (ראשונים, אחרונים וכו') חיים גם הם תחת השורש
/// 'תלמוד בבלי' אך בתתי-קטגוריות שאינן 'סדר X' — ואינם נחשבים.
bool isTalmudBavliBook(Book book) {
  final rawPath = book.category?.path ?? book.categoryPath ?? book.heCategories;
  if (rawPath != null && rawPath.trim().isNotEmpty) {
    final parts = rawPath
        .split(RegExp(r'\s*[/,]\s*'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty ||
        parts.first != DatabaseConstants.talmudBavliFolderName) {
      return false;
    }
    return parts.length == 1 || parts[1].startsWith('סדר ');
  }
  if (book is FileBook) {
    // PDF ללא קטגוריה: מסכת רק אם הקובץ יושב ישירות בתיקיית 'תלמוד בבלי'.
    // פיצול על שני סוגי הלוכסנים — נתיב Windows חייב להתפרש נכון גם בבדיקות
    // שרצות על Linux (package:path מפרש לפי מערכת ההפעלה הנוכחית בלבד).
    final segments = book.path
        .split(RegExp(r'[/\\]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.length >= 2 &&
        segments[segments.length - 2] ==
            DatabaseConstants.talmudBavliFolderName;
  }
  return false;
}

/// מאתר את מופע הטקסט של [title] בעץ הספרייה בהתאמת [categoryId] מדויקת.
///
/// ללא [categoryId] אין זהות ודאית של ספר היעד (חיפוש לפי כותרת בלבד עלול
/// להחזיר ספר אחר בעל שם זהה) — ולכן מוחזר null והקורא מוותר על ההמרה.
TextBook? findTextBookByExactCategory(
  Category library,
  String title,
  int? categoryId,
) {
  if (categoryId == null) return null;
  for (final book in library.getAllBooks()) {
    if (book is TextBook &&
        book.title == title &&
        book.categoryId == categoryId) {
      return book;
    }
  }
  return null;
}

/// שלב הזיהוי המהיר של המרת בבלי ל-PDF: איתור מופע הטקסט בעץ ומהדורת
/// ה-PDF הנלווית, **ללא** מיפוי העמודים הכבד (פתיחת קובץ ה-PDF).
///
/// מחזיר null כשהיעד אינו מסכת בבלי, ההגדרה אינה PDF, או שאין מהדורת PDF.
Future<({TextBook textBook, PdfBook pdfBook})?> resolveTalmudBavliPdfBook(
  TextBook textBook,
) async {
  if (textBook.isUserBook || !talmudBavliOpensInPdf()) return null;
  try {
    final library = await DataRepository.instance.library;
    // אימות שספר היעד עצמו מסכת בבלי (ולא ספר אחר בעל שם זהה): לפי הנתיב
    // שסופק על [textBook], או לפי מופע הטקסט בעץ בהתאמת categoryId מדויקת.
    final resolvedText = isTalmudBavliBook(textBook)
        ? textBook
        : findTextBookByExactCategory(
            library,
            textBook.title,
            textBook.categoryId,
          );
    if (resolvedText == null || !isTalmudBavliBook(resolvedText)) return null;
    final pdfBook = library.getCompanionBook(resolvedText, PdfBook) as PdfBook?;
    if (pdfBook == null || !isTalmudBavliBook(pdfBook)) return null;
    return (textBook: resolvedText, pdfBook: pdfBook);
  } catch (_) {
    return null;
  }
}

/// יעד PDF חלופי לפתיחת [textBook] במיקום [textIndex], כאשר הגדרת פורמט
/// הפתיחה של הבבלי היא PDF.
///
/// מחזיר null כשהיעד אינו בבלי, אין מהדורת PDF בספרייה, או שאין מיפוי
/// עמודים אמין — ואז הקורא פותח את מהדורת הטקסט כרגיל.
Future<({PdfBook book, int page})?> resolveTalmudBavliPdfTarget(
  TextBook textBook,
  int textIndex,
) async {
  final target = await resolveTalmudBavliPdfBook(textBook);
  if (target == null) return null;
  try {
    final page = await textToPdfPage(
      target.textBook,
      textIndex,
      pdfBook: target.pdfBook,
    );
    if (page == null) return null;
    return (book: target.pdfBook, page: page);
  } catch (_) {
    return null;
  }
}

/// טאב דחוי ליעד בבלי שכבר זוהה ([target]): נפתח מיידית עם מחוון טעינה,
/// מיפוי העמוד רץ בתוכו, ובסיום מוחלף ב-PDF — או בטאב הטקסט אם אין מיפוי.
///
/// מפתח ה-dedupe (קנוני אם לא סופק) מוצמד גם לטאב הדחוי וגם לטאב הסופי,
/// כך שלחיצה חוזרת — בזמן הרזולוציה או אחריה — ממקדת במקום לפתוח כפילות.
ResolvingTab buildTalmudBavliResolvingTab({
  required ({TextBook textBook, PdfBook pdfBook}) target,
  required int textIndex,
  required OpenedTab Function(String? dedupeKey) buildTextTab,
  required PdfBookTab Function(int page, String? dedupeKey) buildPdfTab,
  String? dedupeKey,
}) {
  final key = dedupeKey ?? 'talmud-bavli-pdf:${target.pdfBook.path}|$textIndex';
  return ResolvingTab(
    fallbackTab: buildTextTab(key),
    dedupeKey: key,
    resolve: () async {
      final page = await textToPdfPage(
        target.textBook,
        textIndex,
        pdfBook: target.pdfBook,
      );
      // הטאב החלופי שבבעלות ה-ResolvingTab ייסגר איתו — בונים עותק טרי.
      if (page == null) return buildTextTab(key);
      return buildPdfTab(page, key);
    },
  );
}

/// בונה טאב לפתיחת יעד קישור (תפריט הקשר, עוגן-מילה, מפרשים אחאים).
/// יעד השייך לתלמוד בבלי נפתח מיידית כטאב טעינה שמוחלף ב-PDF בדף הממופה.
Future<OpenedTab> buildLinkTargetTab(Link link) async {
  final textBook = TextBook(
    title: utils.getTitleFromPath(link.path2),
    isUserBook: link.targetIsUserBook,
    categoryId: link.targetCategoryId,
    fileType: link.targetFileType,
  );
  final textIndex = link.index2 - 1;
  TextBookTab buildTextTab(String? dedupeKey) => TextBookTab(
    book: textBook,
    index: textIndex,
    dedupeKey: dedupeKey,
    openLeftPane:
        (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
        (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
  );
  final target = await resolveTalmudBavliPdfBook(textBook);
  if (target == null) return buildTextTab(null);
  return buildTalmudBavliResolvingTab(
    target: target,
    textIndex: textIndex,
    buildTextTab: buildTextTab,
    buildPdfTab: (page, dedupeKey) => PdfBookTab(
      book: target.pdfBook,
      pageNumber: page,
      dedupeKey: dedupeKey,
      requiresStableLayout: true,
    ),
  );
}
