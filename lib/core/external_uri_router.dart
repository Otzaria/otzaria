import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/models/plugin_store_install_request.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';
import 'package:otzaria/search/models/search_configuration.dart'
    show SearchMode;
import 'package:otzaria/settings/view/settings_screen.dart' show SettingsTab;

/// פעולה הנגזרת מקישור `otzaria://...` חיצוני.
sealed class ExternalUriAction {
  const ExternalUriAction();
}

/// פתיחת מסך עליון (ספרייה, הגדרות, חיפוש וכו').
class OpenScreenAction extends ExternalUriAction {
  final Screen screen;
  const OpenScreenAction(this.screen);
}

/// פתיחת לשונית כלי במסך הכלים לפי מזהה (built-in או תוסף).
class OpenToolAction extends ExternalUriAction {
  final String toolId;
  const OpenToolAction(this.toolId);
}

/// פתיחת תוסף ישירות לפי מזהה התוסף — גם אם אינו מוצמד ללשוניות.
///
/// בניגוד ל-[OpenToolAction] (שמטפל בכלים מובנים ובתוספים מוצמדים בלבד),
/// פעולה זו פותחת כל תוסף מותקן, כולל תוסף לא-מוצמד, במצב transient.
class OpenPluginAction extends ExternalUriAction {
  final String pluginId;
  const OpenPluginAction(this.pluginId);
}

/// פתיחת ספר בעיון לפי מזהה הספר ב-DB.
///
/// [index] — אינדקס סעיף התחלתי (אופציונלי). מתעלמים מערכים שליליים.
/// [searchQuery] — מחרוזת חיפוש להדגשה (אופציונלי).
/// [markSection] — כאשר `true`, מדגיש את כל תוכן המקטע ב-[index].
/// [markText] — כאשר מוגדר, מדגיש את הטקסט הספציפי הזה בתוך המקטע.
///
/// סדר עדיפות להדגשה: [markText] > [markSection] > [searchQuery].
class OpenBookAction extends ExternalUriAction {
  final int bookId;
  final int? index;
  final String? searchQuery;
  final bool markSection;
  final String? markText;
  const OpenBookAction(
    this.bookId, {
    this.index,
    this.searchQuery,
    this.markSection = false,
    this.markText,
  });

  /// `true` אם הקישור מציין במפורש מיקום או הדגשה — index, ?mark או ?m=.
  /// משמש להחלטה האם להזיז טאב קיים למיקום הזה (deep-link "חשוף" ללא
  /// מיקום לא אמור להזיז טאב פתוח).
  bool get hasExplicitPosition =>
      index != null || markSection || markText != null;
}

/// פתיחת ספר PDF לפי מזהה משותף עם ה-TextBook ב-DB.
///
/// [page] — מספר עמוד התחלתי (אופציונלי).
class OpenPdfBookAction extends ExternalUriAction {
  final int bookId;
  final int? page;
  const OpenPdfBookAction(this.bookId, {this.page});

  /// `true` אם הקישור מציין במפורש עמוד. ראה [OpenBookAction.hasExplicitPosition].
  bool get hasExplicitPosition => page != null;
}

/// בקשת התקנה של תוסף ממאגר חיצוני.
class InstallPluginAction extends ExternalUriAction {
  final PluginStoreInstallRequest request;
  const InstallPluginAction(this.request);
}

/// בקשת התקנה של תוסף מקובץ מקומי (לחיצה כפולה על קובץ `.otzplugin`).
class InstallLocalPluginAction extends ExternalUriAction {
  final String archivePath;
  const InstallLocalPluginAction(this.archivePath);
}

/// מעבר לטאב פתוח לפי מיקומו ברשימה (0-based). משמש את ה-Jump List של
/// שורת המשימות ב-Windows, שבונה פריט לכל טאב פתוח. אינו פותח טאב חדש —
/// אם המיקום לא קיים, מתעלמים.
class SwitchToTabAction extends ExternalUriAction {
  final int index;
  const SwitchToTabAction(this.index);
}

/// פתיחת דיאלוג ההיסטוריה.
class OpenHistoryAction extends ExternalUriAction {
  const OpenHistoryAction();
}

/// פתיחת דיאלוג הסימניות.
class OpenBookmarksAction extends ExternalUriAction {
  const OpenBookmarksAction();
}

/// פתיחת מסך ההגדרות בלשונית מסוימת.
///
/// [tab] — הלשונית הרצויה. אם null, נפתח מסך ההגדרות בלשונית הנוכחית/ראשונה.
class OpenSettingsTabAction extends ExternalUriAction {
  final SettingsTab? tab;
  const OpenSettingsTabAction({this.tab});
}

/// פתיחת חיפוש כללי בלשונית חדשה והפעלת החיפוש מיידית עם ברירות המחדל
/// (כל הקטגוריות).
///
/// [mode] — מצב החיפוש מהפרמטר `mode=` (מתקדם/מדויק/מקורב). כאשר null
/// (ללא פרמטר או ערך לא מוכר) החיפוש רץ במצב ברירת המחדל (מתקדם).
class RunSearchAction extends ExternalUriAction {
  final String query;
  final SearchMode? mode;
  const RunSearchAction(this.query, {this.mode});
}

/// פתיחת דיאלוג איתור מקורות (FindRefDialog) עם טקסט מילוי-מראש.
///
/// [query] — הטקסט שייכתב בשדה החיפוש של הדיאלוג ויפעיל חיפוש מיידית.
/// כאשר [query] ריק (כתובת ללא `q=`), נפתח הדיאלוג ריק.
class RunDetectionAction extends ExternalUriAction {
  final String query;
  const RunDetectionAction(this.query);
}

/// פתיחת מסך העיון בספר האחרון שנפתח.
class OpenInspectionAction extends ExternalUriAction {
  const OpenInspectionAction();
}

/// פתיחת מסך ניהול התוספים (הגדרות ← כלים).
class OpenSdkAction extends ExternalUriAction {
  const OpenSdkAction();
}

/// פתיחת פאנל הכלים (רשת הקוביות) — הכלים עצמם נפתחים ככרטיסיות בעיון.
class OpenToolsLauncherAction extends ExternalUriAction {
  const OpenToolsLauncherAction();
}

/// פתיחת הדף היומי — פותח את ספר ה-PDF של התלמוד הבבלי בדף הנכון ליום.
class OpenDailyPageAction extends ExternalUriAction {
  const OpenDailyPageAction();
}

/// מפענח קישורי `otzaria://...` לפעולה דומיין.
///
/// סכמות וכתובות נתמכות:
/// * `otzaria://open/calendar`              – לוח שנה
/// * `otzaria://open/gematria`              – גימטריה
/// * `otzaria://open/notes`                 – הערות אישיות
/// * `otzaria://open/shamor_zachor`         – שמור וזכור
/// * `otzaria://open/measurements`          – מדות ושיעורים
/// * `otzaria://open/aramaic_dictionary`    – מילון ארמי-עברי
/// * `otzaria://open/acronyms_dictionary`   – ראשי תיבות
/// * `otzaria://open/library`               – ספרייה
/// * `otzaria://open/search`                – פותח את מסך החיפוש (ללא הפעלת חיפוש)
/// * `otzaria://open/search?q=<text>`        – פותח לשונית חיפוש חדשה ומפעיל חיפוש
///   - `&mode=advanced|exact|fuzzy` מצב החיפוש (מתקדם/מדויק/מקורב); ערך לא
///     מוכר או חסר — מצב ברירת המחדל (מתקדם)
/// * `otzaria://open/settings`              – הגדרות (הלשונית הנוכחית)
/// * `otzaria://open/settings/design`       – הגדרות › מראה
/// * `otzaria://open/settings/text`         – הגדרות › כתב
/// * `otzaria://open/settings/library`      – הגדרות › ספרייה
/// * `otzaria://open/settings/tools`        – הגדרות › כלים
/// * `otzaria://open/settings/shortcuts`    – הגדרות › קיצורים
/// * `otzaria://open/settings/system`       – הגדרות › מערכת
/// * `otzaria://open/settings/about`        – הגדרות › אודות
/// * `otzaria://open/tools`                 – פותח את פאנל הכלים
/// * `otzaria://open/history`               – פותח את דיאלוג ההיסטוריה
/// * `otzaria://open/bookmarks`             – פותח את דיאלוג הסימניות
/// * `otzaria://open/detection`             – פותח דיאלוג איתור מקורות ריק
/// * `otzaria://open/detection?q=<text>`    – פותח דיאלוג איתור מקורות עם טקסט מילוי-מראש
/// * `otzaria://open/inspection`            – פותח מסך עיון בספר האחרון שנפתח
/// * `otzaria://open/sdk`                   – פותח הגדרות ← כלים (ניהול תוספים)
/// * `otzaria://open/daily_page`            – פותח את הדף היומי (PDF תלמוד בבלי בדף הנכון)
/// * `otzaria://open/tool/<tool-id>`        – כרטיסיית כלי בעיון לפי מזהה מלא
/// * `otzaria://open/plugin/<plugin-id>`    – פתיחת תוסף ישירות לפי מזהה (גם לא-מוצמד)
/// * `otzaria://open/tab/<index>`           – מעבר לטאב פתוח לפי מיקומו (0-based; Jump List)
/// * `otzaria://open/book/<id>`             – פתיחת ספר טקסט בעיון לפי מזהה DB
///   - `?index=<n>` קפיצה לסעיף התחלתי (n >= 0)
///   - `?q=<text>`  מחרוזת חיפוש להדגשה
///   - `?mark`      הדגשת כל תוכן המקטע ב-index (דגל ללא ערך)
///   - `?m=<text>`  הדגשת טקסט ספציפי בתוך המקטע (URL-encoded)
///   - סדר עדיפות להדגשה: m > mark > q
/// * `otzaria://open/pdf/<id>`              – פתיחת ספר PDF לפי מזהה DB (משותף עם TextBook)
///   - `?index=<n>` קפיצה לעמוד התחלתי (n >= 0)
/// * `otzaria://plugin/install?url=<download>` – התקנת תוסף
///   - `&overwrite=true|false` דריסת תוסף קיים
///   - `&token=<t>&callback=<url>` דיווח תוצאת ההתקנה חזרה לאתר החנות
///     (ה-callback חייב להיות באותו origin של כתובת ההורדה)
/// * `otzaria://plugin/install-local?path=<abs-path>` – התקנת תוסף מקובץ מקומי
///   (משמש לשיוך קובץ `.otzplugin` במערכת ההפעלה). הנתיב חייב להיות מוחלט,
///   להסתיים ב-`.otzplugin`, ואינו נתיב UNC/התקן (ראה `_isSafeLocalPluginPath`).
///
/// הסכמה, ה-host והתת-נתיב הראשון אינם רגישים לאותיות גדולות/קטנות.
class ExternalUriRouter {
  static const Map<String, String> _toolAliases = {
    'calendar': 'builtin.calendar',
    'gematria': 'builtin.gematria',
    'notes': 'builtin.notes',
    'shamor_zachor': 'builtin.shamor_zachor',
    'measurements': 'builtin.measurements',
    'aramaic_dictionary': 'builtin.aramaic_dictionary',
    'acronyms_dictionary': 'builtin.acronyms_dictionary',
  };

  static const Map<String, Screen> _screenAliases = {
    'library': Screen.library,
    'search': Screen.search,
  };

  /// מיפוי הפרמטר `mode=` של `open/search` ל-[SearchMode].
  static const Map<String, SearchMode> _searchModeAliases = {
    'advanced': SearchMode.advanced,
    'exact': SearchMode.exact,
    'fuzzy': SearchMode.fuzzy,
  };

  /// מיפוי מחרוזת לשונית (מנתיב URL) ל-[SettingsTab].
  static const Map<String, SettingsTab> _settingsTabAliases = {
    'design': SettingsTab.design,
    'text': SettingsTab.text,
    'library': SettingsTab.library,
    'tools': SettingsTab.tools,
    'shortcuts': SettingsTab.shortcuts,
    'system': SettingsTab.system,
    'about': SettingsTab.about,
  };

  /// ממיר קישור `zayit://` לפורמט `otzaria://` המקביל.
  /// מחזיר את ה-Uri המקורי אם הוא כבר `otzaria://`, ו-null אם הסכמה לא מוכרת.
  ///
  /// נתמך:
  ///   `zayit://book/{id}`              → `otzaria://open/book/{id}`
  ///   `zayit://book/{id}/line/{index}` → `otzaria://open/book/{id}?index={index}`
  static Uri? normalizeUri(Uri uri) {
    if (uri.scheme.toLowerCase() == 'otzaria') return uri;
    if (uri.scheme.toLowerCase() != 'zayit') return null;

    if (uri.host.toLowerCase() == 'book') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return null;
      final bookId = int.tryParse(segments[0]);
      if (bookId == null || bookId <= 0) return null;

      int? lineIndex;
      if (segments.length >= 3 && segments[1].toLowerCase() == 'line') {
        lineIndex = int.tryParse(segments[2]);
      }

      final queryParams = <String, String>{};
      if (lineIndex != null && lineIndex >= 0) {
        queryParams['index'] = lineIndex.toString();
      }

      return Uri(
        scheme: 'otzaria',
        host: 'open',
        pathSegments: ['book', bookId.toString()],
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
    }
    return null;
  }

  static ExternalUriAction? parseUri(Uri uri) {
    final normalized = normalizeUri(uri);
    if (normalized == null) return null;
    if (normalized != uri) return parseUri(normalized);
    if (uri.scheme.toLowerCase() != 'otzaria') {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host == 'open') {
      return _parseOpen(uri);
    }
    if (host == 'plugin') {
      final localPath = _parseLocalInstall(uri);
      if (localPath != null) {
        return InstallLocalPluginAction(localPath);
      }
      final request = PluginStoreLinkParser.parseUri(uri);
      if (request == null) return null;
      return InstallPluginAction(request);
    }
    return null;
  }

  static String? _parseLocalInstall(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.toLowerCase())
        .toList();
    final isLocalInstall =
        segments.length == 1 && segments.first == 'install-local';
    if (!isLocalInstall) return null;

    final rawPath = uri.queryParameters['path']?.trim();
    if (rawPath == null || rawPath.isEmpty) return null;
    if (!_isSafeLocalPluginPath(rawPath)) return null;

    return rawPath;
  }

  /// הקשר הנתיבים לאימות `install-local` — סמנטיקת הפלטפורמה הנוכחית.
  /// ניתן להחלפה בבדיקות כדי לאמת התנהגות Windows/POSIX מכל פלטפורמה.
  @visibleForTesting
  static p.Context pathContext = p.context;

  /// בודקת שנתיב מקומי בטוח להתקנת תוסף. קישור `otzaria://` ניתן להפעלה
  /// מדף אינטרנט, ולכן הנתיב אינו מהימן:
  /// - נתיב UNC/התקן (`\\server\share`, `\\.\`, `\\?\`, `//host`) נדחה —
  ///   עצם קריאתו גורמת ל-Windows לפתוח חיבור SMB ולדלוף אישורי NTLM לתוקף.
  /// - חובה נתיב מוחלט בסמנטיקת הפלטפורמה הנוכחית (החוזה הוא `<abs-path>`);
  ///   נתיב יחסי נפתר מול תיקיית העבודה ולכן אינו מהימן מקישור חיצוני.
  /// - חובה סיומת `.otzplugin` כדי לא לקרוא קובץ שרירותי מהדיסק.
  static bool _isSafeLocalPluginPath(String path) {
    if (path.startsWith(r'\\') || path.startsWith('//')) return false;
    if (!pathContext.isAbsolute(path)) return false;
    // ב-Windows נתיב כמו `\foo` נחשב rooted אך יחסי-לכונן הנוכחי — נדרש
    // כונן מפורש כדי שהנתיב יהיה מוחלט באמת.
    if (pathContext.style == p.Style.windows &&
        !RegExp(r'^[A-Za-z]:').hasMatch(path)) {
      return false;
    }
    return path.toLowerCase().endsWith('.otzplugin');
  }

  static ExternalUriAction? _parseOpen(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return null;
    }

    final firstLower = segments.first.toLowerCase();

    if (segments.length == 1) {
      // search?q=<text> מקבל טיפול מיוחד — יוצר לשונית ומפעיל חיפוש.
      if (firstLower == 'search') {
        final rawQuery = uri.queryParameters['q']?.trim();
        if (rawQuery != null && rawQuery.isNotEmpty) {
          final rawMode = uri.queryParameters['mode']?.trim().toLowerCase();
          return RunSearchAction(rawQuery, mode: _searchModeAliases[rawMode]);
        }
      }

      // detection?q=<text> — פותח דיאלוג איתור מקורות עם טקסט מילוי-מראש.
      // ללא q — פותח דיאלוג איתור ריק.
      if (firstLower == 'detection') {
        final rawQuery = uri.queryParameters['q']?.trim() ?? '';
        return RunDetectionAction(rawQuery);
      }

      // inspection — פותח מסך עיון בספר האחרון.
      if (firstLower == 'inspection') {
        return const OpenInspectionAction();
      }

      // sdk — פותח דיאלוג ניהול תוספים.
      if (firstLower == 'sdk') {
        return const OpenSdkAction();
      }

      // daily_page — פותח את ספר ה-PDF של התלמוד בדף הנכון ליום.
      if (firstLower == 'daily_page') {
        return const OpenDailyPageAction();
      }

      // settings בלי sub-tab — פותח הגדרות ללא ניווט לטאב ספציפי.
      if (firstLower == 'settings') {
        return const OpenSettingsTabAction();
      }

      // history — פותח דיאלוג היסטוריה.
      if (firstLower == 'history') {
        return const OpenHistoryAction();
      }

      // bookmarks — פותח דיאלוג סימניות.
      if (firstLower == 'bookmarks') {
        return const OpenBookmarksAction();
      }

      final toolId = _toolAliases[firstLower];
      if (toolId != null) {
        return OpenToolAction(toolId);
      }
      if (firstLower == 'tools') {
        return const OpenToolsLauncherAction();
      }
      final screen = _screenAliases[firstLower];
      if (screen != null) {
        return OpenScreenAction(screen);
      }
      return null;
    }

    // settings/<tab> — פותח הגדרות ומנווט ללשונית הרצויה.
    if (segments.length == 2 && firstLower == 'settings') {
      final tabKey = segments[1].toLowerCase();
      final tab = _settingsTabAliases[tabKey];
      // לשונית לא מוכרת — מתעלמים (מחזירים null, לא OpenSettingsTabAction ריק)
      if (tab == null) return null;
      return OpenSettingsTabAction(tab: tab);
    }

    if (segments.length == 2 && firstLower == 'tool') {
      final rawId = segments[1].trim();
      if (rawId.isEmpty) {
        return null;
      }
      return OpenToolAction(rawId);
    }

    if (segments.length == 2 && firstLower == 'plugin') {
      final rawId = segments[1].trim();
      if (rawId.isEmpty) {
        return null;
      }
      return OpenPluginAction(rawId);
    }

    // tab/<index> — מעבר לטאב פתוח לפי מיקומו (0-based). נבנה ע"י ה-Jump List.
    if (segments.length == 2 && firstLower == 'tab') {
      final index = int.tryParse(segments[1].trim());
      if (index == null || index < 0) {
        return null;
      }
      return SwitchToTabAction(index);
    }

    if (segments.length == 2 && firstLower == 'book') {
      final bookId = int.tryParse(segments[1].trim());
      if (bookId == null || bookId <= 0) {
        return null;
      }

      final indexParam = uri.queryParameters['index']?.trim();
      final parsedIndex = indexParam == null || indexParam.isEmpty
          ? null
          : int.tryParse(indexParam);
      final index = (parsedIndex != null && parsedIndex >= 0)
          ? parsedIndex
          : null;

      final rawQuery = uri.queryParameters['q']?.trim();
      final rawSearchQuery = (rawQuery == null || rawQuery.isEmpty)
          ? null
          : rawQuery;

      // mark — דגל בוליאני: קיים ב-queryParameters גם ללא ערך (?mark) וגם עם ערך ריק (?mark=)
      final markSection = uri.queryParameters.containsKey('mark');

      // m — טקסט ספציפי לסימון; מתעלמים מערך ריק או רווחים בלבד
      final rawMark = uri.queryParameters['m']?.trim();
      final markText = (rawMark == null || rawMark.isEmpty) ? null : rawMark;

      // אכיפת עדיפות m > mark > q: אם יש סימון מקומי (m או mark), q מתעלם
      // לחלוטין כדי שלא תיפתח לשונית חיפוש כללית במקביל. כך הקישור מתנהג
      // כפי שמתואר בתיעוד והקריאה ל-API חד-משמעית.
      final searchQuery = (markText != null || markSection)
          ? null
          : rawSearchQuery;

      return OpenBookAction(
        bookId,
        index: index,
        searchQuery: searchQuery,
        markSection: markSection,
        markText: markText,
      );
    }

    if (segments.length == 2 && firstLower == 'pdf') {
      final bookId = int.tryParse(segments[1].trim());
      if (bookId == null || bookId <= 0) {
        return null;
      }

      final indexParam = uri.queryParameters['index']?.trim();
      final parsedIndex = int.tryParse(indexParam ?? '');
      final page = (parsedIndex != null && parsedIndex >= 1)
          ? parsedIndex
          : null;

      return OpenPdfBookAction(bookId, page: page);
    }

    return null;
  }
}
