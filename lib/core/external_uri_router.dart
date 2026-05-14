import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/models/plugin_store_install_request.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';

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

/// פתיחת ספר בעיון לפי מזהה הספר ב-DB.
///
/// [index] — אינדקס סעיף התחלתי (אופציונלי). מתעלמים מערכים שליליים.
/// [searchQuery] — מחרוזת חיפוש להדגשה בכל הספר (אופציונלי). פותח גם את חלונית
/// החיפוש בספר. מתאים ל"חיפוש בכל הספר".
/// [pinpointHighlight] — תת-מחרוזת להדגשה ממוקדת **רק בתוך הסעיף שצוין ב-[index]**,
/// בלי לפתוח חלונית חיפוש. כל מופעי המחרוזת באותו סעיף יודגשו. מתאים לקישור ישיר
/// לטקסט מסוים בתוך מקטע. מתעלמים אם [index] לא צוין.
class OpenBookAction extends ExternalUriAction {
  final int bookId;
  final int? index;
  final String? searchQuery;
  final String? pinpointHighlight;
  const OpenBookAction(
    this.bookId, {
    this.index,
    this.searchQuery,
    this.pinpointHighlight,
  });
}

/// פתיחת ספר PDF לפי מזהה משותף עם ה-TextBook ב-DB.
///
/// [page] — מספר עמוד התחלתי (אופציונלי).
class OpenPdfBookAction extends ExternalUriAction {
  final int bookId;
  final int? page;
  const OpenPdfBookAction(this.bookId, {this.page});
}

/// בקשת התקנה של תוסף ממאגר חיצוני.
class InstallPluginAction extends ExternalUriAction {
  final PluginStoreInstallRequest request;
  const InstallPluginAction(this.request);
}

/// פתיחת חיפוש כללי בלשונית חדשה והפעלת החיפוש מיידית עם ברירות המחדל
/// (כל הקטגוריות, מצב מתקדם).
class RunSearchAction extends ExternalUriAction {
  final String query;
  const RunSearchAction(this.query);
}

/// מפענח קישורי `otzaria://...` לפעולה דומיין.
///
/// סכמות וכתובות נתמכות:
/// * `otzaria://open/calendar`              – לוח שנה
/// * `otzaria://open/gematria`              – גימטריה
/// * `otzaria://open/notes`                 – הערות אישיות
/// * `otzaria://open/library`               – ספרייה
/// * `otzaria://open/search`                – פותח את מסך החיפוש (ללא הפעלת חיפוש)
/// * `otzaria://open/search?q=<text>`        – פותח לשונית חיפוש חדשה ומפעיל חיפוש
/// * `otzaria://open/settings`              – הגדרות
/// * `otzaria://open/tools`                 – מסך הכלים
/// * `otzaria://open/tool/<tool-id>`        – לשונית כלי לפי מזהה מלא
/// * `otzaria://open/book/<id>`             – פתיחת ספר טקסט בעיון לפי מזהה DB
///   - `?index=<n>` קפיצה לסעיף התחלתי (n >= 0)
///   - `?q=<text>`  מחרוזת חיפוש להדגשה בכל הספר (פותח גם חלונית חיפוש)
///   - `?highlight=<text>` הדגשה ממוקדת לכל המופעים של `<text>` **רק בסעיף `index`**,
///     בלי לפתוח חלונית חיפוש. דורש `index=<n>` במקביל; אחרת מתעלמים.
///     אם גם `q=` וגם `highlight=` סופקו — `highlight=` גובר.
/// * `otzaria://open/pdf/<id>`              – פתיחת ספר PDF לפי מזהה DB (משותף עם TextBook)
///   - `?index=<n>` קפיצה לעמוד התחלתי (n >= 0)
/// * `otzaria://plugin/install?url=<download>` – התקנת תוסף
///   - `&overwrite=true|false` דריסת תוסף קיים
///
/// הסכמה, ה-host והתת-נתיב הראשון אינם רגישים לאותיות גדולות/קטנות.
class ExternalUriRouter {
  static const Map<String, String> _toolAliases = {
    'calendar': 'builtin.calendar',
    'gematria': 'builtin.gematria',
    'notes': 'builtin.notes',
  };

  static const Map<String, Screen> _screenAliases = {
    'library': Screen.library,
    'search': Screen.search,
    'settings': Screen.settings,
    'tools': Screen.more,
  };

  static ExternalUriAction? parseUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'otzaria') {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host == 'open') {
      return _parseOpen(uri);
    }
    if (host == 'plugin') {
      final request = PluginStoreLinkParser.parseUri(uri);
      if (request == null) return null;
      return InstallPluginAction(request);
    }
    return null;
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
          return RunSearchAction(rawQuery);
        }
      }

      final toolId = _toolAliases[firstLower];
      if (toolId != null) {
        return OpenToolAction(toolId);
      }
      final screen = _screenAliases[firstLower];
      if (screen != null) {
        return OpenScreenAction(screen);
      }
      return null;
    }

    if (segments.length == 2 && firstLower == 'tool') {
      final rawId = segments[1].trim();
      if (rawId.isEmpty) {
        return null;
      }
      return OpenToolAction(rawId);
    }

    if (segments.length == 2 && firstLower == 'book') {
      final bookId = int.tryParse(segments[1].trim());
      if (bookId == null || bookId <= 0) {
        return null;
      }

      final indexParam = uri.queryParameters['index']?.trim();
      final parsedIndex =
          indexParam == null || indexParam.isEmpty ? null : int.tryParse(indexParam);
      final index = (parsedIndex != null && parsedIndex >= 0) ? parsedIndex : null;

      final rawHighlight = uri.queryParameters['highlight']?.trim();
      // הדגשה ממוקדת לסעיף דורשת אינדקס; בלעדיו אין משמעות ל"איזה סעיף".
      final pinpointHighlight = (rawHighlight == null ||
              rawHighlight.isEmpty ||
              index == null)
          ? null
          : rawHighlight;

      // אם נבחרה הדגשה ממוקדת — היא גוברת על q= הכללי, כדי לא לפתוח חלונית
      // חיפוש בנוסף להדגשה הממוקדת.
      final rawQuery = uri.queryParameters['q']?.trim();
      final searchQuery = (pinpointHighlight != null ||
              rawQuery == null ||
              rawQuery.isEmpty)
          ? null
          : rawQuery;

      return OpenBookAction(
        bookId,
        index: index,
        searchQuery: searchQuery,
        pinpointHighlight: pinpointHighlight,
      );
    }

    if (segments.length == 2 && firstLower == 'pdf') {
      final bookId = int.tryParse(segments[1].trim());
      if (bookId == null || bookId <= 0) {
        return null;
      }

      final indexParam = uri.queryParameters['index']?.trim();
      final parsedIndex = int.tryParse(indexParam ?? '');
      final page = (parsedIndex != null && parsedIndex >= 1) ? parsedIndex : null;

      return OpenPdfBookAction(bookId, page: page);
    }

    return null;
  }
}
