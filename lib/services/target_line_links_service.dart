import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';

/// קישורי שורת היעד, מופרדים לשתי הרשימות שמוצגות כתתי-תפריט נפרדים.
@immutable
class TargetLineLinks {
  /// קישורים תלויי-טקסט — מפרשים על אותו קטע.
  final List<Link> commentaries;

  /// קישורי הפניה/עיון היוצאים מאותו קטע.
  final List<Link> references;

  const TargetLineLinks({
    required this.commentaries,
    required this.references,
  });

  /// קטע שנטען ואין בו לא מפרשים ולא קישורים.
  static const empty = TargetLineLinks(commentaries: [], references: []);
}

/// חתימת פונקציית הטעינה, מוזרקת כדי לאפשר החלפת מימוש ובדיקות.
typedef TargetLineLinksLoader =
    Future<List<Link>> Function(TextBook book, int startIndex, int endIndex);

/// טוען את הקישורים היוצאים מקטע היעד של [Link] — הבסיס לתתי-התפריטים
/// "מפרשים" ו"קישורים" בתפריט ההקשר של מפרש או של קישור.
///
/// כשלוחצים לחיצה ימנית על רש"י בפאנל המפרשים, [Link.path2] הוא ספר רש"י
/// ו-[Link.index2] השורה בו; מכאן נטענים המפרשים והקישורים *על אותה שורה*.
/// שאילתה אחת מספיקה לשתי הרשימות — ההפרדה היא לפי [LinkTypes].
///
/// המטמון גלובלי ומוגבל, ונשמר בין מסכים. הטעינה עצלה ומתרעננת דרך
/// [refreshStream]; [clearCache] נדרש כשהמסד עצמו משתנה.
class TargetLineLinksService {
  /// מספר הקטעים במטמון לפני פינוי הישן ביותר.
  static const int _maxCacheEntries = 256;

  /// תקרת שורות לקישור-טווח, שלא ייטען קטע ענק בגלל מפרש ארוך.
  static const int _maxRangeLines = 10;

  /// השהיית הטעינה בריחוף. תואמת את ההשהיות האחרות בתפריט ההקשר.
  static const Duration hoverPrefetchDelay = Duration(milliseconds: 150);

  final TargetLineLinksLoader _loader;

  /// [loader] מוזרק בבדיקות; בייצור נטען דרך [TextBookRepository].
  TargetLineLinksService({TargetLineLinksLoader? loader})
    : _loader = loader ?? _defaultLoader;

  /// המופע המשותף לכל המסכים — כך המטמון נשמר במעבר בין פאנל, כרטיסייה ו-PDF.
  static TargetLineLinksService instance = TargetLineLinksService();

  @visibleForTesting
  static void resetInstanceForTesting({TargetLineLinksLoader? loader}) {
    instance._dispose();
    instance = TargetLineLinksService(loader: loader);
  }

  void _dispose() {
    _hoverPrefetchTimer?.cancel();
    _refresh.close();
  }

  static Future<List<Link>> _defaultLoader(
    TextBook book,
    int startIndex,
    int endIndex,
  ) {
    return TextBookRepository(
      fileSystem: FileSystemData.instance,
    ).getBookLinksInRange(book, startIndex: startIndex, endIndex: endIndex);
  }

  // ערך null = בטעינה. LinkedHashMap שומר סדר הכנסה, ולכן המפתח הראשון הוא
  // הוותיק ביותר ומפונה כשהמטמון מתמלא.
  final LinkedHashMap<String, TargetLineLinks?> _cache = LinkedHashMap();
  final StreamController<void> _refresh = StreamController<void>.broadcast();

  // ריחוף אחד פעיל בכל רגע, ולכן טיימר יחיד מספיק.
  Timer? _hoverPrefetchTimer;

  // עולה בכל [clearCache]. טעינה שהתחילה לפני הניקוי לא תיגע במטמון שכבר שייך
  // לספרייה אחרת — לא תדרוס ערך חדש ולא תמחק placeholder של טעינה שאחריה.
  int _generation = 0;

  // קטעים שטעינתם נכשלה. הכשל אינו נשמר במטמון (הוא עשוי להיות זמני), אבל
  // בלי הסימון הזה תת-התפריט היה מציג "טוען…" לנצח ויורה שאילתה בכל בנייה.
  final Set<String> _failed = {};

  /// נפלט בכל פעם שטעינה הסתיימה — תתי-התפריטים נבנים מחדש מהמטמון.
  Stream<void> get refreshStream => _refresh.stream;

  @visibleForTesting
  int get cacheSize => _cache.length;

  /// ספר היעד של הקישור — הספר שעליו נפתח תפריט ההקשר.
  static TextBook targetBookOf(Link link) => TextBook(
    title: utils.getTitleFromPath(link.path2),
    categoryId: link.targetCategoryId,
    fileType: link.targetFileType,
    isUserBook: link.targetIsUserBook,
  );

  /// זהות היעד כוללת אישי/רשמי וסוג קובץ: מזהי הקטגוריה של user_books.db הם
  /// מרחב נפרד, ובלעדיהם שני ספרים שונים באותה כותרת היו חולקים ערך במטמון.
  static String _cacheKey(Link link) {
    final title = utils.getTitleFromPath(link.path2);
    final target =
        '${link.targetIsUserBook ? 'u' : 'o'}_${link.targetCategoryId ?? ''}'
        '_${link.targetFileType ?? ''}';
    return '$title|$target|${link.index2}|${link.index2End}';
  }

  static (int start, int end) _rangeOf(Link link) {
    final start = (link.index2 - 1).clamp(0, 1 << 30);
    final rawEnd = ((link.index2End ?? link.index2) - 1).clamp(start, 1 << 30);
    return (start, rawEnd.clamp(start, start + _maxRangeLines));
  }

  /// מחזיר את מה שכבר במטמון, או null כשהקטע עדיין לא נטען.
  TargetLineLinks? cached(Link link) {
    final key = _cacheKey(link);
    if (!_cache.containsKey(key)) return null;
    // remove+reinsert מזיז את המפתח לסוף — בלעדיו הפינוי היה FIFO, והקטע
    // שחוזרים אליו הכי הרבה היה מפונה לפני קטע שנטען פעם אחת ונשכח.
    final value = _cache.remove(key);
    _cache[key] = value;
    return value;
  }

  /// האם לקישור יש קטע יעד שאפשר לטעון עליו. קישור בלי יעד תקין לא ייטען
  /// לעולם, ולכן תת-התפריט שלו חייב להיות אפור ולא תקוע ב"טוען…".
  static bool _hasLoadableTarget(Link link) =>
      link.path2.isNotEmpty && link.index2 > 0;

  /// מתחיל טעינה אם טרם התחילה. בטוח לקריאה חוזרת.
  void prefetch(Link link) {
    if (!_hasLoadableTarget(link)) return;
    final key = _cacheKey(link);
    if (_cache.containsKey(key)) return;
    // ריחוף או לחיצה ימנית חדשים = ניסיון חוזר מפורש אחרי כשל.
    _failed.remove(key);
    _cache[key] = null;
    _evictIfNeeded();
    unawaited(_load(key, link));
  }

  /// טעינה מקדימה בריחוף, בהשהיה קצרה — בלעדיה סמן שחולף מעל רשימת מפרשים
  /// היה פותח שאילתה (ו-Isolate) לכל פריט בדרך. ריחוף חדש מבטל את הקודם.
  void prefetchOnHover(Link link) {
    _hoverPrefetchTimer?.cancel();
    if (_cache.containsKey(_cacheKey(link))) return;
    _hoverPrefetchTimer = Timer(hoverPrefetchDelay, () => prefetch(link));
  }

  /// מפנה את הוותיק ביותר, ולעולם לא קטע שנמצא כרגע בטעינה — פינוי כזה היה
  /// מבטל את אירוע הרענון שלו ומשאיר תת-תפריט פתוח תקוע ב"טוען…".
  void _evictIfNeeded() {
    if (_cache.length <= _maxCacheEntries) return;
    for (final key in _cache.keys.toList()) {
      if (_cache.length <= _maxCacheEntries) return;
      if (_cache[key] == null) continue;
      _cache.remove(key);
    }
  }

  /// מנקה את המטמון — בהחלפת ספרייה או אחרי ייבוא קישורי-משתמש, שבהם המיפוי
  /// (ספר, שורה) ← קישורים משתנה במסד.
  void clearCache() {
    _generation++;
    _hoverPrefetchTimer?.cancel();
    _cache.clear();
    _failed.clear();
    if (!_refresh.isClosed) _refresh.add(null);
  }

  Future<void> _load(String key, Link link) async {
    final generation = _generation;
    TargetLineLinks result;
    try {
      final (start, end) = _rangeOf(link);
      final links = await _loader(targetBookOf(link), start, end);
      result = _partition(links);
    } catch (_) {
      // כשל זמני (DB נעול, החלפת ספרייה) — מסירים את המפתח כדי שפתיחה הבאה של
      // התפריט תנסה שוב, במקום לקבע רשימה ריקה עד הפעלה מחדש. במכוון בלי
      // פליטה לזרם: היא הייתה בונה מחדש את תת-התפריט, שקורא ל-prefetch, ותחת
      // כשל קבוע נוצרת לולאת שאילתות. תת-תפריט פתוח נשאר ב"טוען…" עד שייסגר.
      if (generation == _generation) {
        _cache.remove(key);
        _failed.add(key);
      }
      return;
    }
    _failed.remove(key);
    await _preloadEras(result);
    if (generation != _generation) return;
    // המפתח פונה מהמטמון בזמן הטעינה — אין טעם להחזירו ולפנות ערך חי אחר.
    if (!_cache.containsKey(key)) return;
    // remove+reinsert: הצבה על מפתח קיים אינה מזיזה אותו לסוף, והקטע שהרגע
    // נטען היה נחשב הוותיק ביותר ומפונה מיד בגל טעינות מקבילות.
    _cache.remove(key);
    _cache[key] = result;
    _evictIfNeeded();
    if (!_refresh.isClosed) _refresh.add(null);
  }

  /// טוען את דורות ספרי היעד למטמון של [CommentaryService], שממנו קורא המיון
  /// הסינכרוני בזמן ההצגה. נעשה *לפני* הפליטה לזרם, אחרת הרשימה הייתה מוצגת
  /// אלפביתית ואז מסתדרת מחדש מול העיניים. כישלון אינו פוסל את הקישורים.
  static Future<void> _preloadEras(TargetLineLinks data) async {
    try {
      await CommentaryService.preloadEras([
        for (final link in [...data.commentaries, ...data.references])
          utils.getTitleFromPath(link.path2),
      ]);
    } catch (_) {
      return;
    }
  }

  /// מפצל לשתי הרשימות ומסיר כפילויות. הדדופ נעשה בתוך כל רשימה בנפרד ואחרי
  /// הסיווג — אחרת קישור שנזרק (למשל הפניה inline) היה תופס את המשבצת של
  /// קישור לגיטימי לאותו יעד. המיון לפי דורות נעשה בזמן ההצגה, כדי שלא ייקבע
  /// סדר שגוי אם טבלת הדורות עדיין לא נטענה.
  static TargetLineLinks _partition(List<Link> links) {
    final commentaries = <Link>[];
    final references = <Link>[];
    final seenCommentaries = <String>{};
    final seenReferences = <String>{};

    for (final link in links) {
      if (link.path2.isEmpty || link.index2 <= 0) continue;
      if (LinkTypes.isVirtualSource(link.connectionType)) continue;
      final targetKey =
          '${link.path2}|${link.index2}|${link.targetIsUserBook ? 'u' : 'o'}';

      if (LinkTypes.isDependentTextLink(link.connectionType)) {
        if (seenCommentaries.add(targetKey)) commentaries.add(link);
      } else if (link.start == null && link.end == null) {
        // קישורי-טווח inline מסומנים בטקסט עצמו ואינם פריט תפריט.
        if (seenReferences.add(targetKey)) references.add(link);
      }
    }

    if (commentaries.isEmpty && references.isEmpty) {
      return TargetLineLinks.empty;
    }
    return TargetLineLinks(
      commentaries: commentaries,
      references: references,
    );
  }

  /// פריט "מפרשים" — המפרשים על קטע היעד של [link].
  AppContextMenuEntry buildCommentariesEntry({
    required Link link,
    required void Function(Link link) onNavigate,
    bool? removeNikud,
    bool? removePunctuation,
  }) {
    return _buildEntry(
      link: link,
      onNavigate: onNavigate,
      removeNikud: removeNikud,
      removePunctuation: removePunctuation,
      label: 'מפרשים',
      icon: FluentIcons.book_24_regular,
      emptyLabel: 'אין מפרשים על קטע זה',
      select: (data) => data.commentaries,
      groupByEra: true,
    );
  }

  /// פריט "קישורים" — ההפניות היוצאות מקטע היעד של [link].
  AppContextMenuEntry buildLinksEntry({
    required Link link,
    required void Function(Link link) onNavigate,
    bool? removeNikud,
    bool? removePunctuation,
  }) {
    return _buildEntry(
      link: link,
      onNavigate: onNavigate,
      removeNikud: removeNikud,
      removePunctuation: removePunctuation,
      label: 'קישורים',
      icon: FluentIcons.link_24_regular,
      emptyLabel: 'אין קישורים על קטע זה',
      select: (data) => data.references,
      groupByEra: false,
    );
  }

  AppContextMenuEntry _buildEntry({
    required Link link,
    required void Function(Link link) onNavigate,
    required bool? removeNikud,
    required bool? removePunctuation,
    required String label,
    required IconData icon,
    required String emptyLabel,
    required List<Link> Function(TargetLineLinks) select,
    required bool groupByEra,
  }) {
    // ה-enabled נקבע פעם אחת בבניית התפריט ואינו מתרענן עם הזרם. כשהמטמון כבר
    // מלא (ריחוף מקדים) הוא מדויק; אחרת אופטימי, כדי שלא ייצבע אפור בטעות.
    final data = cached(link);
    return AppContextMenuEntry(
      label: label,
      icon: icon,
      enabled:
          _hasLoadableTarget(link) && (data == null || select(data).isNotEmpty),
      childrenBuilder: () => _buildChildren(
        link: link,
        onNavigate: onNavigate,
        removeNikud: removeNikud,
        removePunctuation: removePunctuation,
        emptyLabel: emptyLabel,
        select: select,
        groupByEra: groupByEra,
      ),
      childrenRefreshStream: refreshStream,
    );
  }

  List<AppContextMenuEntry> _buildChildren({
    required Link link,
    required void Function(Link link) onNavigate,
    required bool? removeNikud,
    required bool? removePunctuation,
    required String emptyLabel,
    required List<Link> Function(TargetLineLinks) select,
    required bool groupByEra,
  }) {
    if (!_hasLoadableTarget(link)) {
      return [AppContextMenuEntry(label: emptyLabel, enabled: false)];
    }
    // לא קוראים ל-prefetch על קטע שנכשל: כל בנייה מחדש הייתה יורה שאילתה
    // כושלת נוספת. ריחוף או לחיצה ימנית חדשים ינסו שוב.
    if (_failed.contains(_cacheKey(link))) {
      return const [
        AppContextMenuEntry(label: 'שגיאה בטעינה', enabled: false),
      ];
    }
    prefetch(link);
    final data = cached(link);
    if (data == null) {
      return const [AppContextMenuEntry(label: 'טוען…', enabled: false)];
    }

    // המיון כאן ולא בטעינה: מטמון הדורות מתמלא אסינכרונית, ומיון מוקדם היה
    // מקבע סדר אלפביתי שגוי שגם המפרידים שנגזרים ממנו לא היו תואמים לו.
    final items = CommentaryService.sortLinksByEraSync(select(data));
    if (items.isEmpty) {
      return [AppContextMenuEntry(label: emptyLabel, enabled: false)];
    }

    final presentTitles = {
      for (final item in items) utils.getTitleFromPath(item.path2),
    };
    final entries = <AppContextMenuEntry>[];
    CommentaryEra? lastEra;
    for (final item in items) {
      if (groupByEra) {
        final era = CommentaryService.sortingEraForLink(item, presentTitles);
        if (lastEra != null && era != lastEra) {
          entries.add(const AppContextMenuEntry.divider());
        }
        lastEra = era;
      }
      entries.add(
        buildLinkContextMenuEntry(
          link: item,
          removeNikud: removeNikud,
          removePunctuation: removePunctuation,
          onTap: () => onNavigate(item),
        ),
      );
    }
    return entries;
  }
}
