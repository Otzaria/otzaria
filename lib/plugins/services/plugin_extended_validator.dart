import 'dart:convert';
import 'dart:io';

import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:path/path.dart' as p;

/// תוצאת ולידציה מורחבת לתוסף.
///
/// `errors` — חסומה (האריזה לא תושלם).
/// `warnings` — מציגה הודעה אך מאפשרת אריזה.
/// `design` — תאימות עיצוב (לפי `DESIGN_GUIDE.md` של Otzaria).
class PluginValidationReport {
  final List<String> errors;
  final List<String> warnings;
  final DesignComplianceReport design;

  const PluginValidationReport({
    required this.errors,
    required this.warnings,
    required this.design,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

class DesignComplianceReport {
  final bool compliant;
  final List<String> violations;

  const DesignComplianceReport({
    required this.compliant,
    required this.violations,
  });
}

/// רשימת ה-API methods המוכרים. תואם FALLBACK_API_METHODS ב-pluginValidation.js.
const Set<String> _knownApiMethods = {
  'app.getInfo',
  'app.getTheme',
  'app.getLocale',
  'app.getUserEmail',
  'app.getGrantedPermissions',
  'library.findBooks',
  'library.getBookMetadata',
  'library.listRecentBooks',
  'library.getBookContent',
  'library.getBookToc',
  'search.fullText',
  'reader.openBook',
  'reader.openBookAtRef',
  'reader.getCurrentState',
  'reader.getCurrentRef',
  'reader.getSelection',
  'reader.addContextMenuItem',
  'reader.removeContextMenuItem',
  'reader.setHighlight',
  'reader.getHighlights',
  'reader.clearHighlight',
  'reader.clearAllHighlights',
  'navigation.goTo',
  'notes.list',
  'notes.getBookNotesSummary',
  'notes.add',
  'notes.update',
  'notes.delete',
  'ui.showMessage',
  'ui.showSuccess',
  'ui.showError',
  'ui.showConfirm',
  'ui.showWarning',
  'feedback.sendEmail',
  'history.list',
  'history.listSearches',
  'history.clear',
  'history.remove',
  'notifications.showInApp',
  'notifications.sendSystem',
  'notifications.scheduleSystem',
  'notifications.cancel',
  'notifications.cancelAll',
  'notifications.checkPermissions',
  'notifications.requestPermissions',
  'storage.get',
  'storage.set',
  'storage.remove',
  'storage.list',
  'settings.get',
  'settings.getMany',
  'calendar.getSelectedDate',
  'calendar.getDailyTimes',
  'calendar.getHalachicTimes',
  'calendar.getJewishDate',
  'calendar.getEvents',
  'publishedData.upsert',
  'publishedData.remove',
  'publishedData.listOwn',
  'database.listSources',
  'database.describeSource',
  'database.query',
  'database.batchQuery',
  'network.fetch',
  'network.download',
  'shortcut.create',
};

/// APIs קיימות בתוספים אך אינן מתועדות פומבית — לא נאזהיר עליהן.
const Set<String> _knownUndocumentedMethods = {
  'plugin.listInstalled',
  'plugin.requestInstall',
  'plugin.uninstall',
};

/// אירועי lifecycle ו-events נתמכים.
const Set<String> _knownEvents = {
  'plugin.boot',
  'plugin.ready',
  'theme.changed',
  'navigation.changed',
  'reader.current_book_changed',
  'reader.current_ref_changed',
  'reader.selection_changed',
  'reader.context_menu_item_clicked',
  'calendar.date_changed',
  'workspace.changed',
  'settings.changed',
  'plugin.permissions_changed',
};

/// מיפוי `method -> permission` נדרשת (תואם METHOD_REQUIRED_PERMISSION ב-JS).
const Map<String, String> _methodRequiredPermission = {
  'app.getInfo': 'app.info.read',
  'app.getTheme': 'app.info.read',
  'app.getLocale': 'app.info.read',
  'app.getGrantedPermissions': 'app.info.read',
  'app.getUserEmail': 'app.user_email.read',
  'library.findBooks': 'library.books.read',
  'library.getBookMetadata': 'library.books.read',
  'library.listRecentBooks': 'library.books.read',
  'library.getBookContent': 'library.content.read',
  'library.getBookToc': 'library.content.read',
  'search.fullText': 'search.fulltext.read',
  'reader.openBook': 'reader.open',
  'reader.openBookAtRef': 'reader.open',
  'reader.getCurrentState': 'reader.open',
  'reader.getCurrentRef': 'reader.open',
  'reader.getSelection': 'reader.open',
  'reader.addContextMenuItem': 'reader.context_menu',
  'reader.removeContextMenuItem': 'reader.context_menu',
  'reader.setHighlight': 'reader.highlight',
  'reader.getHighlights': 'reader.highlight',
  'reader.clearHighlight': 'reader.highlight',
  'reader.clearAllHighlights': 'reader.highlight',
  'navigation.goTo': 'navigation.write',
  'notes.list': 'notes.read',
  'notes.getBookNotesSummary': 'notes.read',
  'notes.add': 'notes.write',
  'notes.update': 'notes.write',
  'notes.delete': 'notes.write',
  'ui.showMessage': 'ui.feedback',
  'ui.showSuccess': 'ui.feedback',
  'ui.showError': 'ui.feedback',
  'ui.showConfirm': 'ui.feedback',
  'ui.showWarning': 'ui.feedback',
  'feedback.sendEmail': 'feedback.send_email',
  'history.list': 'history.read',
  'history.listSearches': 'history.read',
  'history.clear': 'history.write',
  'history.remove': 'history.write',
  'notifications.showInApp': 'notifications.send',
  'notifications.sendSystem': 'notifications.system',
  'notifications.scheduleSystem': 'notifications.system',
  'notifications.cancel': 'notifications.system',
  'notifications.cancelAll': 'notifications.system',
  'notifications.checkPermissions': 'notifications.system',
  'notifications.requestPermissions': 'notifications.system',
  'storage.get': 'plugin.storage.read',
  'storage.set': 'plugin.storage.write',
  'storage.remove': 'plugin.storage.write',
  'storage.list': 'plugin.storage.read',
  'settings.get': 'settings.read',
  'settings.getMany': 'settings.read',
  'calendar.getSelectedDate': 'calendar.read',
  'calendar.getDailyTimes': 'calendar.read',
  'calendar.getHalachicTimes': 'calendar.read',
  'calendar.getJewishDate': 'calendar.read',
  'calendar.getEvents': 'calendar.read',
  'publishedData.upsert': 'published_data.write',
  'publishedData.remove': 'published_data.write',
  'publishedData.listOwn': 'published_data.write',
  'database.listSources': 'database.read',
  'database.describeSource': 'database.read',
  'database.query': 'database.read',
  'database.batchQuery': 'database.read',
  'network.fetch': 'network.access',
  'network.download': 'network.access',
  'shortcut.create': 'ui.create_shortcut',
};

/// שדות שמורים שאינם API methods (כדי שלא ייתפסו ב-shorthand scanner).
const Set<String> _reservedHolderFields = {
  'call',
  'on',
  'off',
  'emit',
  'once',
  'use',
  'init',
  'setup',
  'ready',
};

class PluginExtendedValidator {
  /// מבצע ולידציה מורחבת על תיקיית התוסף.
  ///
  /// תואם ללוגיקה ב-`C:\Otzaria_Website\src\lib\pluginValidation.js`.
  /// [manifest] חייב להיות תקני (`PluginManifest.fromJson` עבר בהצלחה).
  static PluginValidationReport validate({
    required PluginManifest manifest,
    required Map<String, dynamic> manifestJson,
    required String directoryPath,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    final declaredPermissions = manifest.permissions.toSet();

    _validateNetwork(manifestJson, declaredPermissions, errors, warnings);
    _checkNameVsToolTabTitle(manifestJson, warnings);

    final files = _collectScannableFiles(directoryPath);
    final apiUsage = <String, Set<String>>{};
    final eventUsage = <String, Set<String>>{};

    for (final entry in files.entries) {
      final relName = entry.key;
      if (!_isCodeLikeFile(relName)) continue;
      String text;
      try {
        text = entry.value.readAsStringSync();
      } catch (_) {
        continue;
      }
      final scan = _scanCodeForApiUsage(text);
      for (final method in scan.methods) {
        apiUsage.putIfAbsent(method, () => <String>{}).add(relName);
      }
      for (final ev in scan.events) {
        eventUsage.putIfAbsent(ev, () => <String>{}).add(relName);
      }
    }

    for (final entry in apiUsage.entries) {
      final method = entry.key;
      if (_knownApiMethods.contains(method) ||
          _knownUndocumentedMethods.contains(method)) {
        continue;
      }
      warnings.add(
          'קריאה ל-API לא מוכר: $method (קבצים: ${entry.value.join(', ')})');
    }

    for (final entry in eventUsage.entries) {
      final ev = entry.key;
      if (_knownEvents.contains(ev)) continue;
      warnings
          .add('רישום ל-event לא מוכר: $ev (קבצים: ${entry.value.join(', ')})');
    }

    // Cross-check: method משומש אך ההרשאה לא הוכרזה.
    for (final method in apiUsage.keys) {
      final required = _methodRequiredPermission[method];
      if (required == null) continue;
      if (!declaredPermissions.contains(required)) {
        warnings.add(
            'התוסף משתמש ב-$method אך לא ביקש את ההרשאה "$required" ב-manifest');
      }
    }

    // Cross-check: event subscription דורש הרשאת events.subscribe:X.
    for (final ev in eventUsage.keys) {
      final eventPerm = 'events.subscribe:$ev';
      if (!pluginValidPermissions.contains(eventPerm)) continue;
      if (!declaredPermissions.contains(eventPerm)) {
        warnings.add(
            'רישום ל-event "$ev" דורש את ההרשאה "$eventPerm" שלא הוכרזה ב-manifest');
      }
    }

    final design = _checkDesignCompliance(files);

    return PluginValidationReport(
      errors: errors,
      warnings: warnings,
      design: design,
    );
  }

  // ===== Manifest checks =====

  /// בדיקות network — כל הליקויים כאן מסווגים כ-warnings, כי לפי התיעוד
  /// הרשמי `network.allowlist` הוא "שדה הצהרתי בלבד" (ברירת מחדל `[]`)
  /// וההרשאה בפועל מנוהלת ע"י אוצריא בקוד. אריזה לא תיחסם, אך נציין למפתח
  /// שאם הוא מצהיר על שימוש ברשת — כדאי להצהיר במפורש לאן.
  static void _validateNetwork(
    Map<String, dynamic> manifestJson,
    Set<String> declaredPermissions,
    List<String> errors,
    List<String> warnings,
  ) {
    final network = manifestJson['network'];
    final networkEnabled = network is Map && network['enabled'] == true;
    final networkRequested =
        networkEnabled || declaredPermissions.contains('network.access');
    if (!networkRequested) return;

    final allowlistRaw = network is Map ? network['allowlist'] : null;
    if (allowlistRaw is! List || allowlistRaw.isEmpty) {
      warnings.add(
          'התוסף מבקש network.access או network.enabled אך network.allowlist ריק. השדה הוא הצהרתי בלבד (התיעוד בפועל מוגדר באוצריא), אך מומלץ לפרט את הכתובות שבהן התוסף עושה שימוש לטובת שקיפות מול המשתמש');
      return;
    }
    final urlPattern = RegExp(r'^https?://', caseSensitive: false);
    for (final raw in allowlistRaw) {
      if (raw is! String || !urlPattern.hasMatch(raw)) {
        warnings.add(
            'כתובת לא תקינה ב-network.allowlist: ${jsonEncode(raw)} (מומלץ http(s) URL מלא)');
      } else if (raw.contains('*')) {
        warnings.add('network.allowlist אינו תומך ב-wildcard: $raw');
      }
    }
  }

  /// `contributes.toolTab.title` הוא שדה אופציונלי שברירת המחדל שלו היא
  /// שם התוסף; הדוגמה הרשמית עצמה משתמשת בשמות שונים. לכן אי-התאמה אינה
  /// שגיאה — לכל היותר אזהרה אינפורמטיבית, וגם זאת רק כשהמפתח **התעלם**
  /// מההמלצה (כלומר הגדיר title שזהה לגמרי לשם, מה שמיותר). למעשה אין כאן
  /// מה לאסור — אם בעתיד יוחלט להוסיף אזהרה, להוסיף כאן.
  static void _checkNameVsToolTabTitle(
    Map<String, dynamic> manifestJson,
    List<String> warnings,
  ) {
    // לפי התיעוד הרשמי, השדות עצמאיים. אין ולידציה נוספת כרגע.
    // הפונקציה נשמרת כ-hook עתידי.
    return;
  }

  // ===== File collection =====

  /// אוסף קבצים נסרקים: manifest.json + קוד (js/mjs/cjs/html/vue/svelte) + סגנון (css/html).
  static Map<String, File> _collectScannableFiles(String directoryPath) {
    final out = <String, File>{};
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return out;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: directoryPath);
      // נורמליזציה ל-forward slashes כמו ב-zip entries
      final relNorm = rel.replaceAll('\\', '/');
      if (relNorm == 'manifest.json' ||
          _isCodeLikeFile(relNorm) ||
          _isStyleLikeFile(relNorm)) {
        out[relNorm] = entity;
      }
    }
    return out;
  }

  static final RegExp _codeFileRe =
      RegExp(r'\.(?:js|mjs|cjs|html?|vue|svelte)$', caseSensitive: false);
  static final RegExp _styleFileRe =
      RegExp(r'\.(?:css|html?)$', caseSensitive: false);

  static bool _isCodeLikeFile(String name) => _codeFileRe.hasMatch(name);
  static bool _isStyleLikeFile(String name) => _styleFileRe.hasMatch(name);

  // ===== Code scanning =====

  static final RegExp _callRe =
      RegExp(r'''Otzaria\s*\.\s*call\s*\(\s*['"]([a-zA-Z][\w.]*)['"]''');
  static final RegExp _onRe =
      RegExp(r'''Otzaria\s*\.\s*on\s*\(\s*['"]([a-zA-Z][\w.]*)['"]''');
  static final RegExp _offRe =
      RegExp(r'''Otzaria\s*\.\s*off\s*\(\s*['"]([a-zA-Z][\w.]*)['"]''');
  static final RegExp _shorthandRe = RegExp(
      r'''Otzaria\s*\.\s*([a-z][a-zA-Z0-9_]*)\s*\.\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(''');

  static _ApiUsage _scanCodeForApiUsage(String text) {
    final cleaned = _stripCommentsForScan(text);
    final methods = <String>{};
    final events = <String>{};

    for (final m in _callRe.allMatches(cleaned)) {
      methods.add(m.group(1)!);
    }
    for (final m in _shorthandRe.allMatches(cleaned)) {
      final holder = m.group(1)!;
      final method = m.group(2)!;
      if (_reservedHolderFields.contains(holder)) continue;
      methods.add('$holder.$method');
    }
    for (final m in _onRe.allMatches(cleaned)) {
      events.add(m.group(1)!);
    }
    for (final m in _offRe.allMatches(cleaned)) {
      events.add(m.group(1)!);
    }
    return _ApiUsage(methods: methods, events: events);
  }

  /// מסיר הערות HTML/JS לפני סריקת קריאות API. סדר הפעולות:
  ///
  ///   1. הערות בלוקיות (HTML `<!-- -->` ו-JS `/* */`) מוסרות.
  ///   2. **string literals** (single/double/backtick) מוחלפים זמנית
  ///      ב-placeholders — כך ש-`//` בתוך URL לא ייחתך.
  ///   3. **regex literals** (`/.../flags` אחרי הקשר מתאים) מוחלפים גם
  ///      הם — כך ש-`//` בתוך regex כמו `/https?:\/\/example/` לא יחתוך
  ///      את שאר השורה ויבליע קריאה אמיתית ל-Otzaria.call שאחריה.
  ///   4. הערות שורה (`//`) מוסרות — בתחילת שורה וגם inline.
  ///   5. ה-placeholders מוחזרים לקדמותם.
  ///
  /// זיהוי regex ב-JS הוא קלאסית חצי-החלטה (`/` יכול להיות חלוקה).
  /// אנחנו לא בונים lexer מלא; אנחנו מזהים regex רק כשהוא מופיע אחרי
  /// תווי הקשר ש**לא** יכולים להיות אופרנד שמאלי של חלוקה (כמו `=`,
  /// `(`, `,`, `;`, `return`, `=>`).
  static String _stripCommentsForScan(String text) {
    var stripped = text
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

    // מחליפים מחרוזות בערך תפסן כדי שהריגקס של `//` לא יחתוך URL/regex.
    // הריגקסים תופסים מחרוזות single/double/backtick, ומתעלמים מתווי escape
    // (`\'`, `\"`, ``\` ``) כדי לא לסגור מוקדם.
    final placeholders = <String>[];
    String replaceLiteral(Match m) {
      final idx = placeholders.length;
      placeholders.add(m.group(0)!);
      return ' STR$idx ';
    }

    // (2) string literals — single/double/backtick. `\\.` תופס escape
    // sequences כדי שמרכאות בורחות לא יסגרו את הספירה מוקדם.
    stripped = stripped.replaceAllMapped(
      RegExp(
        r"'(?:\\.|[^'\\])*'"
        r'|"(?:\\.|[^"\\])*"'
        r'|`(?:\\.|[^`\\])*`',
      ),
      replaceLiteral,
    );

    // (3) regex literals — רק אחרי "הקשר רגקס" (תו או מילת מפתח שמרמזים
    // שהבא הוא ביטוי, לא חלוקה). שומרים את ההקשר ב-group(1) וב-group(2),
    // ואת ה-regex עצמו (group(3)) מחליפים ב-placeholder. ה-character-class
    // ‎`\[…\]` בתוך הregex מאפשר `/` בלתי בורח בתוך class (למשל `/[a-z\/]/`).
    stripped = stripped.replaceAllMapped(
      RegExp(
        r'(^|[=(,;:!?~&|+\-*/%<>{}\[\]]|=>|\breturn\b|\bthrow\b|\bin\b|\bof\b|\btypeof\b|\bdelete\b|\bvoid\b|\binstanceof\b|\bnew\b)'
        r'(\s*)'
        r'(/(?:\\.|\[(?:\\.|[^\]\\\n\r])*\]|[^/\\\n\r])+?/[gimsuyd]*)',
      ),
      (m) {
        final idx = placeholders.length;
        placeholders.add(m.group(3)!);
        return '${m.group(1)}${m.group(2)} STR$idx ';
      },
    );

    // (4) line comments — בטוח להסיר כעת, כי strings ו-regex כבר
    // הוחלפו ב-placeholders.
    stripped = stripped.replaceAll(RegExp(r'//[^\n\r]*'), '');

    // מחזירים את המחרוזות לקדמותן.
    stripped = stripped.replaceAllMapped(
      RegExp(r' STR(\d+) '),
      (m) => placeholders[int.parse(m.group(1)!)],
    );

    return stripped;
  }

  // ===== Design compliance =====

  static const Set<String> _allowedColorKeywords = {
    'inherit',
    'initial',
    'unset',
    'revert',
    'currentcolor',
    'transparent',
    'none',
  };

  static final RegExp _namedColorRe = RegExp(
      r'\b(black|white|red|green|blue|yellow|gray|grey|purple|orange|pink|brown|cyan|magenta|silver|gold|maroon|navy|teal|olive|aqua|fuchsia|lime|violet|indigo|coral|crimson|salmon|khaki|beige|ivory|wheat|tan|chocolate|tomato|turquoise|orchid)\b',
      caseSensitive: false);
  static final RegExp _hexColorRe = RegExp(r'#[0-9a-fA-F]{3,8}\b');
  static final RegExp _rgbHslRe =
      RegExp(r'\b(?:rgb|rgba|hsl|hsla)\s*\(', caseSensitive: false);
  static final RegExp _colorPropRe = RegExp(
      r'(?:^|[\s;{])(color|background(?:-color)?|border(?:-(?:top|right|bottom|left))?(?:-color)?|outline(?:-color)?|fill|stroke)\s*:\s*([^;}]+)',
      caseSensitive: false);

  static DesignComplianceReport _checkDesignCompliance(
      Map<String, File> files) {
    final violations = <String>[];
    final cssChunks = <_CssChunk>[];
    var sawAnyHtml = false;
    var sawAnyCss = false;

    for (final entry in files.entries) {
      final name = entry.key;
      final file = entry.value;

      if (RegExp(r'\.css$', caseSensitive: false).hasMatch(name)) {
        sawAnyCss = true;
        try {
          cssChunks.add(_CssChunk(name, file.readAsStringSync()));
        } catch (_) {}
      } else if (RegExp(r'\.html?$', caseSensitive: false).hasMatch(name)) {
        sawAnyHtml = true;
        String html;
        try {
          html = file.readAsStringSync();
        } catch (_) {
          continue;
        }

        final rootMatch =
            RegExp(r'<html\b([^>]*)>', caseSensitive: false).firstMatch(html);
        if (rootMatch != null) {
          final attrs = rootMatch.group(1) ?? '';
          if (!RegExp(r'''\bdir\s*=\s*['"]\s*rtl\s*['"]''',
                  caseSensitive: false)
              .hasMatch(attrs)) {
            violations.add('$name: תג <html> חייב לכלול dir="rtl"');
          }
          if (!RegExp(r'''\blang\s*=\s*['"]\s*he\s*['"]''',
                  caseSensitive: false)
              .hasMatch(attrs)) {
            violations.add('$name: תג <html> חייב לכלול lang="he"');
          }
        }

        final styleRe =
            RegExp(r'<style[^>]*>([\s\S]*?)</style>', caseSensitive: false);
        for (final m in styleRe.allMatches(html)) {
          cssChunks.add(_CssChunk('$name (<style>)', m.group(1) ?? ''));
        }
      }
    }

    if (!sawAnyHtml && !sawAnyCss) {
      return const DesignComplianceReport(
        compliant: false,
        violations: [
          'לא נמצאו קבצי HTML/CSS שניתן לבדוק את תאימות העיצוב שלהם'
        ],
      );
    }

    for (final chunk in cssChunks) {
      var stripped = _stripCssComments(chunk.css);
      // הגדרות של CSS custom properties (`--color-foo: #xxx;`,
      // `--font-size-base: 18px;`, וכד') מותרות במפורש לפי DESIGN_GUIDE —
      // הן ברירות מחדל לפני applyTheme. מוציאים אותן מהמחרוזת לפני סריקה
      // כדי שלא יזוהו כהפרה.
      stripped =
          stripped.replaceAll(RegExp(r'--[a-zA-Z_][\w-]*\s*:\s*[^;}]+;?'), '');
      final seen = <String>{};
      void addOnce(String type, String message) {
        if (!seen.add(type)) return;
        violations.add(message);
      }

      // 1. צבעי hex
      final hexMatches =
          _hexColorRe.allMatches(stripped).map((m) => m.group(0)!).toList();
      if (hexMatches.isNotEmpty) {
        final sample = hexMatches.toSet().take(3).join(', ');
        addOnce('hex',
            '${chunk.name}: צבעי hex מקודדים ($sample). חובה var(--color-*)');
      }

      // 2. rgb/hsl
      if (_rgbHslRe.hasMatch(stripped)) {
        addOnce('rgb',
            '${chunk.name}: ערכי rgb()/rgba()/hsl()/hsla() מקודדים. חובה var(--color-*)');
      }

      // 3. שמות צבעים באנגלית בערכי color/background/border/outline/fill/stroke
      for (final propMatch in _colorPropRe.allMatches(stripped)) {
        final value = (propMatch.group(2) ?? '').trim();
        if (RegExp(r'var\s*\(').hasMatch(value)) continue;
        final firstToken = value.split(RegExp(r'[\s,]'))[0].toLowerCase();
        if (_allowedColorKeywords.contains(firstToken)) continue;
        if (RegExp(r'^[\d.]+(px|em|rem|%)?$').hasMatch(firstToken)) continue;
        if (_namedColorRe.hasMatch(value)) {
          final preview = value.length > 40 ? value.substring(0, 40) : value;
          addOnce('named',
              '${chunk.name}: שם צבע באנגלית בערך CSS ("$preview"). חובה var(--color-*)');
          break;
        }
      }

      // 4. font-family שאינו var(--font-*)
      for (final m
          in RegExp(r'font-family\s*:\s*([^;}]+)', caseSensitive: false)
              .allMatches(stripped)) {
        final value = (m.group(1) ?? '').trim();
        if (!RegExp(r'var\s*\(\s*--font', caseSensitive: false)
            .hasMatch(value)) {
          final preview = value.length > 50 ? value.substring(0, 50) : value;
          addOnce('font-family',
              '${chunk.name}: font-family מקודד ("$preview"). חובה var(--font-main)');
          break;
        }
      }

      // 5. font-size ב-px קבוע
      for (final m in RegExp(r'font-size\s*:\s*([^;}]+)', caseSensitive: false)
          .allMatches(stripped)) {
        final value = (m.group(1) ?? '').trim();
        if (RegExp(r'var\s*\(').hasMatch(value)) continue;
        if (RegExp(r'^\d+(?:\.\d+)?\s*(?:em|rem|%)$', caseSensitive: false)
            .hasMatch(value)) {
          continue;
        }
        if (RegExp(r'^0(?:px)?$').hasMatch(value)) continue;
        if (RegExp(r'\d+\s*px', caseSensitive: false).hasMatch(value)) {
          final preview = value.length > 30 ? value.substring(0, 30) : value;
          addOnce('font-size-px',
              '${chunk.name}: font-size ב-px קבוע ("$preview"). חובה em/rem או var(--font-size-base)');
          break;
        }
      }

      // 6. border-radius ב-px ארביטררי
      for (final m
          in RegExp(r'border-radius\s*:\s*([^;}]+)', caseSensitive: false)
              .allMatches(stripped)) {
        final value = (m.group(1) ?? '').trim();
        if (RegExp(r'var\s*\(').hasMatch(value)) continue;
        if (RegExp(r'^0(?:px)?(?:\s+0(?:px)?)*$').hasMatch(value)) continue;
        if (RegExp(r'^\d+(?:\.\d+)?\s*%$').hasMatch(value)) continue;
        if (RegExp(r'\d+\s*px', caseSensitive: false).hasMatch(value)) {
          final preview = value.length > 30 ? value.substring(0, 30) : value;
          addOnce('radius-px',
              '${chunk.name}: border-radius ב-px קבוע ("$preview"). חובה var(--radius-sm/md/lg/pill)');
          break;
        }
      }
    }

    // נדרש שימוש כלשהו ב-var(--color-*)
    final usesColorVar = cssChunks.any((c) =>
        RegExp(r'var\s*\(\s*--color-', caseSensitive: false).hasMatch(c.css));
    if (cssChunks.isNotEmpty && !usesColorVar) {
      violations.add(
          'לא נמצא שימוש כלשהו ב-var(--color-*) — חובה להזין צבעים מ-API לפי תיעוד העיצוב');
    }

    return DesignComplianceReport(
      compliant: violations.isEmpty,
      violations: violations,
    );
  }

  static String _stripCssComments(String css) =>
      css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
}

class _ApiUsage {
  final Set<String> methods;
  final Set<String> events;
  _ApiUsage({required this.methods, required this.events});
}

class _CssChunk {
  final String name;
  final String css;
  _CssChunk(this.name, this.css);
}
