import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';

import 'package:otzaria/utils/text/heading_slug.dart';
import 'package:otzaria/utils/text/otzaria_markup.dart';
import 'package:path/path.dart' as p;

/// מחלקה לטיפול בקישורי HTML בתוך הטקסט
class HtmlLinkHandler {
  /// מנסה לפענח URL בצורה בטוחה, תומך בטקסט רגיל ו-URL encoded
  static String _safeDecode(String text) {
    if (text.isEmpty) return text;

    try {
      // אם הטקסט מכיל % זה כנראה מקודד
      if (text.contains('%')) {
        return Uri.decodeComponent(text);
      }
      // אחרת, זה כבר טקסט רגיל
      return text;
    } catch (e) {
      // אם הפענוח נכשל, נחזיר את הטקסט המקורי
      debugPrint('Failed to decode URL component: $text, error: $e');
      return text;
    }
  }

  /// מטפל בקישורים מבוססי תווים (inline links)
  static Future<void> _handleInlineLink(
    BuildContext context,
    String url,
    Function(TextBookTab) openBookCallback,
  ) async {
    try {
      // פענוח ה-URL ולקיחת הפרמטרים
      final uri = Uri.parse(url);
      final path = _safeDecode(uri.queryParameters['path'] ?? '');
      final indexStr = uri.queryParameters['index'] ?? '';
      final ref = _safeDecode(uri.queryParameters['ref'] ?? '');

      if (path.isEmpty) {
        throw Exception('נתיב לא תקין בקישור');
      }

      // המרת האינדקס למספר (index2 מגיע כ-1-based, אבל אנחנו צריכים 0-based)
      final index = int.tryParse(indexStr);
      if (index == null) {
        throw Exception('אינדקס לא תקין בקישור');
      }

      // מציאת הספר על פי הנתיב
      final bookTitle = _getTitleFromPath(path);
      final library = await DataRepository.instance.library;
      final foundBook = resolveBookLinkTarget(library, bookTitle);

      if (foundBook == null) {
        throw Exception('לא נמצא ספר בשם: $bookTitle');
      }

      // פתיחת הספר באינדקס הנכון (המרה ל-0-based)
      final tab = TextBookTab(
        book: foundBook,
        index: index - 1, // המרה מ-1-based ל-0-based
        openLeftPane:
            (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );

      openBookCallback(tab);

      if (context.mounted && ref.isNotEmpty) {
        UiSnack.show(CommonMessages.openedRef(ref));
      }
    } catch (e) {
      debugPrint('שגיאה בטיפול בקישור מבוסס תווים: $e');

      if (context.mounted) {
        UiSnack.show(CommonMessages.cannotOpenLink(e));
      }
    }
  }

  /// מחלץ שם ספר מנתיב קובץ
  static String _getTitleFromPath(String path) {
    // הסרת סיומת קובץ ונתיב
    String title = path.split('/').last.split('\\').last;
    final extension = p.extension(title).toLowerCase();
    if (extension == '.txt' || extension == '.text') {
      title = title.substring(0, title.length - extension.length);
    }
    return title;
  }

  /// מפצל את חלק הכותרות של הקישור לרמות, ומסיר רמות ריקות.
  static List<String> _headerSegments(String raw) => [
    for (final part in raw.split('#')) _safeDecode(part).trim(),
  ]..removeWhere((segment) => segment.isEmpty);

  /// מטפל בלחיצה על קישור HTML
  ///
  /// הפונקציה מפרשת קישורים בפורמטים הבאים:
  /// - book://שם_הספר - פותח ספר בתחילתו
  /// - book://שם_הספר#כותרת - פותח ספר ומנווט לכותרת ספציפית
  /// - book://שם_הספר#כותרת#תת-כותרת#... - נתיב היררכי בעץ תוכן העניינים
  /// - #כותרת (וכן #כותרת#תת-כותרת) - מנווט לכותרת באותו ספר
  /// - otzaria://inline-link?path={path}&index={index}&ref={ref} - קישור מבוסס תווים
  ///
  /// דוגמאות:
  /// - <a href="book://ברכות">ברכות</a>
  /// - <a href="book://ברכות#דף ב">ברכות דף ב</a>
  /// - <a href="book://בית יוסף#אורח חיים#סימן א">בית יוסף או"ח סימן א</a>
  /// - <a href="#דף ג">דף ג</a>
  /// האם [url] מפנה לספר אחר, כך ש"פתח בכרטיסייה חדשה" אפשרי עבורו
  /// (עוגן בתוך אותו ספר אינו כזה).
  static bool opensAnotherBook(String url) =>
      url.startsWith('otzaria://inline-link') || url.startsWith('book://');

  /// יעד חיצוני שמותר לפתוח מחומר שהגיע מתוך מסמך.
  @visibleForTesting
  static Uri? externalUriFor(String url) {
    final safeUrl = safeLinkTarget(url);
    if (safeUrl == null || safeUrl.startsWith('#')) return null;
    final uri = Uri.tryParse(safeUrl);
    if (uri == null ||
        !kAllowedLinkSchemes.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') && !uri.hasAuthority) {
      return null;
    }
    return uri;
  }

  /// פותח את יעד הקישור בכרטיסייה חדשה ברקע, בלי לעזוב את הטאב הנוכחי.
  static Future<void> openLinkInBackground(
    BuildContext context,
    String url,
  ) async {
    if (!opensAnotherBook(url)) return;
    // ה-bloc נשלף לפני ההמתנה: ההקשר עשוי להתפרק עד שהיעד ייפתר.
    final tabsBloc = context.read<TabsBloc>();
    await handleLink(
      context,
      url,
      (tab) => tabsBloc.add(
        AddTab(tab, insertAdjacent: true, inBackground: true),
      ),
    );
  }

  static Future<bool> handleLink(
    BuildContext context,
    String url,
    Function(TextBookTab) openBookCallback,
  ) async {
    try {
      // בדיקה אם זה קישור מבוסס תווים (inline-link)
      if (url.startsWith('otzaria://inline-link')) {
        await _handleInlineLink(context, url, openBookCallback);
        return true;
      }

      // בדיקה אם זה קישור פנימי לכותרת באותו ספר
      if (url.startsWith('#')) {
        // עוגן id (קישורי הערות שוליים כמו #footnote-1) — לפני מסלול הכותרות.
        final fragment = _safeDecode(url.substring(1)).trim();
        if (await _navigateToIdAnchor(context, fragment)) return true;
        if (!context.mounted) return true;
        await _navigateToHeader(context, _headerSegments(url.substring(1)));
        return true;
      }

      // בדיקה אם זה קישור לספר
      if (url.startsWith('book://')) {
        final bookUrl = url.substring(7); // הסרת "book://"
        final separatorIndex = bookUrl.indexOf('#');

        await _openBookWithHeader(
          context,
          _safeDecode(
            separatorIndex < 0 ? bookUrl : bookUrl.substring(0, separatorIndex),
          ),
          separatorIndex < 0
              ? const <String>[]
              : _headerSegments(bookUrl.substring(separatorIndex + 1)),
          openBookCallback,
        );
        return true;
      }

      final externalUri = externalUriFor(url);
      if (externalUri != null) {
        final launched = await launchUrl(
          externalUri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) throw Exception('מערכת ההפעלה לא פתחה את הקישור');
        return true;
      }

      // אם זה לא קישור שאנחנו מטפלים בו, נחזיר false
      return false;
    } catch (e, stackTrace) {
      debugPrint('שגיאה בטיפול בקישור: $e');
      debugPrint('Stack trace: $stackTrace');

      // הצגת הודעת שגיאה למשתמש
      if (context.mounted) {
        UiSnack.show(CommonMessages.linkOpenError(e));
      }

      return false;
    }
  }

  /// מאתר את הספר שקישור `book://` מפנה אליו, כ-TextBook לפתיחה בלשונית.
  ///
  /// ‏`findBookByTitle` משווה `runtimeType` ולא `is`, ולכן ספר-מסמך
  /// (HTML/DOCX/EPUB/ODT) אינו נמצא בחיפוש אחר `TextBook` — אף שהקורא פותח
  /// אותו דרך אותה לשונית בדיוק, בעטיפת `toTextBook()` (ראו
  /// `OpenedTab.fromBook`). בלי ההשלמה כאן כל קישור `book://` אל ספר כזה
  /// מת, ובקובצי HTML זו הדרך המתועדת לקשר בין ספרים.
  static TextBook? resolveBookLinkTarget(Library library, String title) {
    final direct = library.findBookByTitle(title, TextBook);
    if (direct is TextBook) return direct;
    final any = library.findBookByTitle(title, null);
    return any is ConvertibleDocumentBook ? any.toTextBook() : null;
  }

  /// מאתר את השורה שמכילה עוגן `id="[fragment]"` בגוף הספר, או null.
  @visibleForTesting
  static int? findIdAnchorLine(List<String> lines, String fragment) {
    if (fragment.isEmpty || fragment.contains('#')) return null;
    final idPattern = RegExp('\\bid\\s*=\\s*"${RegExp.escape(fragment)}"');
    final index = lines.indexWhere(idPattern.hasMatch);
    return index < 0 ? null : index;
  }

  /// מנווט לעוגן id בספר הנוכחי (הערות שוליים בסגנון #footnote-N ↔ #noteref-N).
  /// מחזיר false כשאין עוגן כזה — והקישור ממשיך למסלול הכותרות.
  static Future<bool> _navigateToIdAnchor(
    BuildContext context,
    String fragment,
  ) async {
    try {
      final state = context.read<TextBookBloc>().state;
      if (state is! TextBookLoaded) return false;
      final index = findIdAnchorLine(state.content, fragment);
      if (index == null) return false;
      final viewportExtent =
          context.size?.height ?? MediaQuery.sizeOf(context).height;
      await scrollToSourceLine(
        scrollController: state.scrollController,
        scrollOffsetController: state.scrollOffsetController,
        positionsListener: state.positionsListener,
        segments: state.readingSegments,
        lineIndex: index,
        viewportExtent: viewportExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.ease,
      );
      return true;
    } catch (e) {
      debugPrint('שגיאה בניווט לעוגן id: $e');
      return false;
    }
  }

  /// מנווט לכותרת באותו ספר הנוכחי
  static Future<void> _navigateToHeader(
    BuildContext context,
    List<String> segments,
  ) async {
    final headerName = segments.join(', ');
    try {
      // נקבל את הספר הנוכחי מה-BLoC
      final textBookBloc = context.read<TextBookBloc>();
      final state = textBookBloc.state;

      if (state is! TextBookLoaded) {
        throw Exception('לא ניתן לנווט - הספר לא נטען');
      }

      // חיפוש הכותרת בתוכן הספציפי
      final viewportExtent =
          context.size?.height ?? MediaQuery.sizeOf(context).height;
      // עוגן בתוכן שהקורא מציג כרגע קודם לפענוח הנתיב: טעינה מחדש של הספר
      // מחזירה אינדקסים של שורות המקור, שאינם באותה מפה כמו ה-HTML המוצג
      // (ספרי Markdown).
      final anchorIndex = segments.length == 1
          ? findAnchorIndex(state.content, segments.single)
          : null;
      final resolved = anchorIndex != null
          ? HeaderPathResult(index: anchorIndex, reachedHeader: segments.single)
          : await _findHeaderPath(state.book, segments);

      if (resolved.index != null) {
        // ניווט לאינדקס שנמצא
        await scrollToSourceLine(
          scrollController: state.scrollController,
          scrollOffsetController: state.scrollOffsetController,
          positionsListener: state.positionsListener,
          segments: state.readingSegments,
          lineIndex: resolved.index!,
          viewportExtent: viewportExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.ease,
        );

        if (context.mounted) {
          UiSnack.show(
            resolved.missingSegment == null
                ? CommonMessages.navigatedToHeader(headerName)
                : CommonMessages.navigatedToPartialHeader(
                    resolved.reachedHeader ?? headerName,
                    resolved.missingSegment!,
                  ),
          );
        }
      } else {
        throw Exception('לא נמצאה הכותרת: ${resolved.missingSegment}');
      }
    } catch (e) {
      debugPrint('שגיאה בניווט לכותרת: $e');

      if (context.mounted) {
        UiSnack.show(CommonMessages.cannotNavigateToHeader(headerName));
      }
    }
  }

  /// פותח ספר ומנווט לנתיב הכותרות שצוין (אם צוין)
  static Future<void> _openBookWithHeader(
    BuildContext context,
    String bookTitle,
    List<String> segments,
    Function(TextBookTab) openBookCallback,
  ) async {
    try {
      // חיפוש הספר בספרייה
      final library = await DataRepository.instance.library;

      // קבלת רשימת כל הספרים לבדיקה
      final allBooks = library.getAllBooks();

      final anyBook = library.findBookByTitle(bookTitle, null);
      final foundBook = resolveBookLinkTarget(library, bookTitle);

      if (foundBook == null) {
        if (anyBook != null) {
          throw Exception(
            'הספר "$bookTitle" נמצא אבל הוא מטיפוס ${anyBook.runtimeType}, לא TextBook',
          );
        }

        // הצגת רשימת ספרים זמינים למשתמש
        final availableBooks = allBooks.take(10).map((b) => b.title).join(', ');
        throw Exception(
          'לא נמצא ספר בשם: "$bookTitle".\nספרים זמינים (דוגמאות): $availableBooks',
        );
      }

      final book = foundBook;
      final resolved = segments.isEmpty
          ? const HeaderPathResult()
          : await _findHeaderPath(book, segments);

      // פתיחת הספר
      final tab = TextBookTab(
        book: book,
        index: resolved.index ?? 0,
        openLeftPane:
            (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );

      openBookCallback(tab);

      if (!context.mounted || segments.isEmpty) return;

      // הודעה אחת בלבד, שמשקפת לאן הקישור הגיע בפועל: הצלחה מלאה, נחיתה על
      // רמה חלקית, או כישלון שפתח את תחילת הספר.
      final headerName = segments.join(', ');
      if (resolved.missingSegment == null) {
        UiSnack.show(CommonMessages.openedBookAtHeader(bookTitle, headerName));
      } else if (resolved.index != null) {
        UiSnack.show(
          CommonMessages.openedBookAtPartialHeader(
            bookTitle,
            resolved.reachedHeader ?? headerName,
            resolved.missingSegment!,
          ),
        );
      } else {
        UiSnack.show(
          CommonMessages.headerNotFoundOpeningStart(
            resolved.missingSegment!,
            bookTitle,
          ),
        );
      }
    } catch (e) {
      debugPrint('שגיאה בפתיחת ספר: $e');

      if (context.mounted) {
        UiSnack.show(CommonMessages.cannotOpenBook(bookTitle));
      }
    }
  }

  /// מפענח נתיב כותרות בספר.
  ///
  /// [segments] - רמות הכותרות לפי הסדר, למשל ['אורח חיים', 'סימן א'].
  /// מחזיר [HeaderPathResult] עם האינדקס העמוק שנמצא והרמה הראשונה שלא נמצאה.
  @visibleForTesting
  static HeaderPathResult resolveHeaderPath(
    List<TocEntry> roots,
    List<String> segments,
  ) => _resolveHeaderPath(roots, segments);

  static Future<HeaderPathResult> _findHeaderPath(
    TextBook book,
    List<String> segments,
  ) async {
    if (segments.isEmpty) return const HeaderPathResult();

    try {
      final tableOfContents = await book.tableOfContents;
      final hierarchical = _resolveHeaderPath(tableOfContents, segments);
      if (hierarchical.missingSegment == null) return hierarchical;

      // תאימות לאחור: קישור בן שתי רמות שנכתב לפני התמיכה בנתיב היררכי התייחס
      // לכותרת אחת שמורכבת משתיהן עם רווח (מבנה "דף ב" + "עמוד א" בגמרא).
      if (segments.length == 2) {
        final joined = segments.join(' ');
        final legacyIndex =
            _findSingleHeader(tableOfContents, joined) ??
            await _findHeaderInContent(book, joined);
        if (legacyIndex != null) {
          return HeaderPathResult(index: legacyIndex, reachedHeader: joined);
        }
      }

      // חיפוש בגוף הספר אינו יכול לשמור על ענף ההורה, ולכן הוא בטוח רק
      // כשבקישור יש כותרת אחת.
      if (segments.length == 1) {
        final fromContent = await _findHeaderInContent(book, segments.single);
        if (fromContent != null) {
          return HeaderPathResult(
            index: fromContent,
            reachedHeader: segments.single,
          );
        }
      }

      return hierarchical;
    } catch (e) {
      debugPrint('שגיאה בחיפוש כותרת: $e');
      return const HeaderPathResult();
    }
  }

  /// הולך במורד עץ תוכן העניינים לפי [segments], רמה אחר רמה.
  static HeaderPathResult _resolveHeaderPath(
    List<TocEntry> roots,
    List<String> segments,
  ) {
    var candidates = roots;
    int? deepestIndex;
    String? reachedHeader;

    for (final segment in segments) {
      final match = _matchInSubtree(candidates, segment);
      if (match == null) {
        return HeaderPathResult(
          index: deepestIndex,
          reachedHeader: reachedHeader,
          missingSegment: segment,
        );
      }
      deepestIndex = match.index;
      reachedHeader = match.text;
      candidates = match.children;
    }

    return HeaderPathResult(index: deepestIndex, reachedHeader: reachedHeader);
  }

  /// מאתר כותרת בין [candidates], ואם אינה שם - בכל תת-העץ שמתחתיהם.
  /// החיפוש בתת-העץ מאפשר לקישור לדלג על רמות ביניים שכותב הקישור לא הכיר,
  /// וההתאמה המדויקת מבטיחה שלא יקפוץ לענף אחר.
  static TocEntry? _matchInSubtree(List<TocEntry> candidates, String segment) {
    for (final entry in candidates) {
      if (isHeaderMatch(entry.text, segment)) return entry;
    }
    for (final entry in flattenToc(candidates)) {
      if (isHeaderMatch(entry.text, segment)) return entry;
    }
    return null;
  }

  /// מחפש כותרת יחידה בכל עץ תוכן העניינים, כולל התאמה לפי מספר דף בלבד.
  static int? _findSingleHeader(List<TocEntry> roots, String headerName) {
    final entries = flattenToc(roots);
    for (final entry in entries) {
      if (isHeaderMatch(entry.text, headerName)) return entry.index;
    }

    // אם לא נמצא, ננסה לחפש רק לפי מספר הדף (בלי עמוד)
    // זה עוזר כשהקישור כולל עמוד שלא קיים בתוכן העניינים
    final pageOnlyMatch = _extractPageNumber(headerName);
    if (pageOnlyMatch == null) return null;
    for (final entry in entries) {
      if (_extractPageNumber(entry.text) == pageOnlyMatch) return entry.index;
    }
    return null;
  }

  /// מחפש כותרת בשורות הספר עצמן, כשאינה מופיעה בתוכן העניינים.
  static Future<int?> _findHeaderInContent(
    TextBook book,
    String headerName,
  ) async {
    final content = await book.text;
    final lines = content.split('\n');
    final tagPattern = RegExp(r'<[^>]*>');

    // יעד עוגן מפורש קודם להתאמת טקסט: כך מסמכי Markdown מסמנים יעדי ניווט
    // שאינם ה-slug של הכותרת.
    final anchorIndex = findAnchorIndex(lines, headerName);
    if (anchorIndex != null) return anchorIndex;

    for (int i = 0; i < lines.length; i++) {
      if (isHeaderMatch(
        lines[i].replaceAll(tagPattern, '').trim(),
        headerName,
      )) {
        return i;
      }
    }

    // חיפוש לפי דף בלבד
    final pageOnlyMatch = _extractPageNumber(headerName);
    if (pageOnlyMatch == null) return null;
    for (int i = 0; i < lines.length; i++) {
      final cleanLine = lines[i].replaceAll(tagPattern, '').trim();
      if (_extractPageNumber(cleanLine) == pageOnlyMatch) return i;
    }
    return null;
  }

  /// מחלץ את מספר הדף מכותרת (למשל "דף כג א" -> "כג")
  static String? _extractPageNumber(String text) {
    // דפוס לזיהוי מספר דף עברי
    final pagePattern = RegExp(r'דף\s+([א-ת]{1,3})');
    final match = pagePattern.firstMatch(text);
    if (match != null) {
      return match.group(1);
    }

    // אם אין "דף", ננסה למצוא מספר עברי בתחילת המחרוזת
    final numberPattern = RegExp(r'^([א-ת]{1,3})(?:\s|$)');
    final numberMatch = numberPattern.firstMatch(text.trim());
    if (numberMatch != null) {
      return numberMatch.group(1);
    }

    return null;
  }

  /// בדיקה אם טקסט תואם לכותרת המבוקשת.
  /// בכוונה אין התאמת substring — כותרת קצרה (כמו "ב") התאימה כמעט לכל
  /// שורה וניווטה למקום שגוי; עדיף "לא נמצא" גלוי עם פתיחת תחילת הספר.
  static bool isHeaderMatch(String text, String headerName) {
    final cleanText = text.trim().replaceAll(RegExp(r'\s+'), '');
    final cleanHeader = headerName.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanText == cleanHeader) return true;
    return headingSlug(text) == headingSlug(headerName);
  }

  /// מחפש יעד עוגן מפורש בשורות המוצגות — `id` על כותרת או `name`/`id` על
  /// `<a>`. כך מסמכי Markdown מסמנים יעדי ניווט שאינם ה-slug של הכותרת.
  @visibleForTesting
  static int? findAnchorIndex(List<String> lines, String anchor) {
    final trimmed = anchor.trim();
    if (trimmed.isEmpty) return null;
    final pattern = RegExp(
      '<(?:h[1-6]|a)\\b[^>]*\\b(?:name|id)\\s*=\\s*(["\\\'])'
      '${RegExp.escape(trimmed)}\\1',
      caseSensitive: false,
    );
    for (var index = 0; index < lines.length; index++) {
      // סינון מוקדם: התאמת regex על כל שורה בספר יקרה מהותית מחיפוש מחרוזת.
      if (!lines[index].contains(trimmed)) continue;
      if (pattern.hasMatch(lines[index])) return index;
    }
    return null;
  }
}

/// תוצאת פענוח נתיב כותרות בקישור.
///
/// [index] - שורת היעד שנמצאה (null כשאף רמה לא נמצאה).
/// [reachedHeader] - טקסט הכותרת העמוקה שאליה הגענו.
/// [missingSegment] - הרמה הראשונה שלא נמצאה; null כשכל הנתיב נמצא.
class HeaderPathResult {
  final int? index;
  final String? reachedHeader;
  final String? missingSegment;

  const HeaderPathResult({this.index, this.reachedHeader, this.missingSegment});
}
