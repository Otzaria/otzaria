import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// בדיקות פורמט עבור `docs/plugin-sdk/API_REFERENCE.md`.
///
/// אתר התוספים (`C:\Otzaria_Website\src\lib\pluginValidation.js`) מורד את
/// הקובץ הזה מ-GitHub ומפענח ממנו את רשימת ההרשאות, ה-APIs והאירועים
/// התקפים, ולפיהם בודק את כל התוספים שמועלים לחנות. אם הפורמט של הקובץ
/// משתנה והפענוח קורס — האתר חוזר ל-fallback מקובע שמתעדכן רק ידנית,
/// וכל תוסף שמשתמש ב-API חדש שלא הופיע ב-fallback יקבל אזהרת שווא.
///
/// הטסטים הללו משחזרים את לוגיקת הפענוח של ה-website (בדיוק אותם regex)
/// ומוודאים שהקובץ נשאר ניתן לפענוח: מעל לסף המינימלי שהוא דורש, וכולל
/// אבני-יסוד שצריכות להיות מתועדות. כל שינוי במבנה הכותרות, ב-fences של
/// קוד או בשמות ההרשאות שיקרוס את הפענוח — ישבור את הטסטים האלה כאן.
///
/// אם הטסט נכשל: בדקו שהקובץ עדיין כולל את התבניות הבאות:
///   * כותרות שיטה: ``` ### \`namespace.method\` ```
///   * כותרות אירוע: ``` ### Event: \`event.name\` ``` — לא בתבנית של שיטה
///   * דוגמאות קריאה: `Otzaria.call('namespace.method', …)`
///   * רישום אירוע: `Otzaria.on('event.name', …)`
///   * הרשאות ב-inline-code (backticked) כמו `` `library.books.read` ``
///   * הרשאות אירוע בפורמט `events.subscribe:event.name`
void main() {
  group(
    'API_REFERENCE.md format (consumed by Otzaria_Website pluginValidation.js)',
    () {
      late String md;

      setUpAll(() {
        final file = File('docs/plugin-sdk/API_REFERENCE.md');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'docs/plugin-sdk/API_REFERENCE.md חייב להתקיים — האתר '
              'מסתמך עליו לוולידציה של כל תוסף. אם הקובץ הועבר/שונה שמו, '
              'יש לעדכן גם את pluginValidation.js (API_REFERENCE_URL).',
        );
        md = file.readAsStringSync();
      });

      test('יש לפחות 5 הרשאות שניתנות לפענוח (סף הקריסה של ה-website)', () {
        final permissions = _parsePermissions(md);
        expect(
          permissions.length,
          greaterThanOrEqualTo(5),
          reason:
              'pluginValidation.js זורק "Parsed API reference looked malformed" '
              'כאשר נמצאות פחות מ-5 הרשאות. נמצאו: ${permissions.length}. '
              'ודאו שהרשאות מצוטטות ב-inline code (backtick) בפורמט snake_case '
              'מנוקד כמו `library.books.read`.',
        );
      });

      test('יש לפחות 10 שיטות API שניתנות לפענוח (סף הקריסה של ה-website)', () {
        final methods = _parseApiMethods(md);
        expect(
          methods.length,
          greaterThanOrEqualTo(10),
          reason:
              'pluginValidation.js זורק "Parsed API reference looked malformed" '
              'כאשר נמצאות פחות מ-10 שיטות. נמצאו: ${methods.length}. '
              'ודאו ששיטות מתועדות בכותרת `### `namespace.method`` או '
              'בדוגמה Otzaria.call(...).',
        );
      });

      test('הרשאות יסוד שהאתר מצפה להן מתועדות בפורמט תקין', () {
        final permissions = _parsePermissions(md);
        const expectedCore = <String>[
          'app.info.read',
          'library.books.read',
          'library.content.read',
          'reader.open',
          'notes.read',
          'notes.write',
          'plugin.storage.read',
          'plugin.storage.write',
          'ui.feedback',
        ];
        final missing = expectedCore
            .where((p) => !permissions.contains(p))
            .toList();
        expect(
          missing,
          isEmpty,
          reason:
              'הרשאות יסוד חסרות מהפענוח: $missing. ודאו שכל אחת מהן מופיעה '
              'לפחות פעם אחת מצוטטת ב-inline code (backtick). למשל: '
              '"`library.books.read`".',
        );
      });

      test('שיטות API מרכזיות מתועדות בכותרת או בדוגמת Otzaria.call', () {
        final methods = _parseApiMethods(md);
        const expectedCore = <String>[
          'app.getInfo',
          'library.findBooks',
          'library.getBookContent',
          'search.fullText',
          'reader.openBook',
          'reader.getCurrentRef',
          'notes.list',
          'notes.add',
          'ui.showMessage',
          'storage.get',
          'storage.set',
        ];
        final missing = expectedCore
            .where((m) => !methods.contains(m))
            .toList();
        expect(
          missing,
          isEmpty,
          reason:
              'שיטות API מרכזיות חסרות מהפענוח: $missing. ודאו שכל שיטה '
              'מופיעה לפחות בכותרת ``### `namespace.method`'
              '`` או בדוגמת ``Otzaria.call(\'namespace.method\', …)``.',
        );
      });

      test('הרשאות events.subscribe נמצאות וכל אחת מהן מייצרת event מקביל', () {
        final permissions = _parsePermissions(md);
        final events = _parseEvents(md, permissions);
        final subscribePerms = permissions
            .where((p) => p.startsWith('events.subscribe:'))
            .toList();

        expect(
          subscribePerms,
          isNotEmpty,
          reason:
              'לא נמצאו הרשאות events.subscribe:* במסמך. הרשאות אלה הן '
              'מקור חיוני לרשימת האירועים שה-website מאשר.',
        );

        for (final perm in subscribePerms) {
          final eventName = perm.substring('events.subscribe:'.length);
          expect(
            events,
            contains(eventName),
            reason:
                'ההרשאה $perm קיימת אבל ה-event $eventName לא נכלל ברשימת '
                'האירועים שנפענחה — מצב לא עקבי.',
          );
        }
      });

      test('אירועי lifecycle plugin.boot / plugin.ready מתועדים במסמך', () {
        expect(
          md.contains('plugin.boot'),
          isTrue,
          reason: 'plugin.boot חייב להופיע במסמך כדי שייכלל ברשימת האירועים.',
        );
        expect(
          md.contains('plugin.ready'),
          isTrue,
          reason: 'plugin.ready חייב להופיע במסמך כדי שייכלל ברשימת האירועים.',
        );
      });

      test('אירועים אינם נכנסים לרשימת ה-methods', () {
        final methods = _parseApiMethods(md);
        final events = _parseEvents(md, _parsePermissions(md));
        final leaked = events.where(methods.contains).toList()..sort();
        expect(
          leaked,
          isEmpty,
          reason:
              'אירועים שנפענחו גם כ-methods: $leaked. כותרת אירוע חייבת '
              'להיות ``### Event: `event.name``` — התבנית '
              '``### `event.name``` מסמנת method, וה-website יכריז על '
              'האירוע כ-API תקף לקריאה.',
        );
      });

      test('כותרות השיטה אינן מקבלות placeholder גנרי namespace.method', () {
        final methods = _parseApiMethods(md);
        expect(
          methods,
          isNot(contains('namespace.method')),
          reason:
              'pluginValidation.js מסנן placeholder "namespace.method" מתוך '
              'Otzaria.call, אבל אם הוא הוכנס לכותרת ``### `namespace.method``` '
              'הוא ייכנס לרשימה והאתר יכריז עליו כשיטה תקפה.',
        );
      });
    },
  );
}

// ---------------------------------------------------------------------------
// פענוח שמחקה את `parseApiReferenceMarkdown` ב-pluginValidation.js (1:1
// regex). אל תפשטו את ההיגיון — המטרה היא לוודא שהקובץ נשאר תואם בדיוק
// לפענוח של ה-website.
// ---------------------------------------------------------------------------

Set<String> _parsePermissions(String md) {
  final permissions = <String>{};

  // 1. הרשאות events.subscribe נראות ישירות במחרוזת.
  final subRe = RegExp(r'events\.subscribe:[a-z][a-zA-Z0-9_.]+');
  for (final m in subRe.allMatches(md)) {
    permissions.add(m.group(0)!);
  }

  // 2. הרשאות סטנדרטיות מופיעות כ-inline code (backticked).
  final inlineRe = RegExp(r'`([a-z][a-zA-Z0-9_.:]+)`');
  for (final m in inlineRe.allMatches(md)) {
    final token = m.group(1)!;
    if (_looksLikePermission(token)) permissions.add(token);
  }

  return permissions;
}

Set<String> _parseApiMethods(String md) {
  final methods = <String>{};

  // headings: ### `namespace.method`
  final headingRe = RegExp(
    r'^###\s+`([a-z][a-zA-Z0-9_]*\.[a-zA-Z0-9_]+)`',
    multiLine: true,
  );
  for (final m in headingRe.allMatches(md)) {
    methods.add(m.group(1)!);
  }

  // Otzaria.call('namespace.method', …)
  final callRe = RegExp(
    '''Otzaria\\.call\\(['"]([a-z][a-zA-Z0-9_]*\\.[a-zA-Z0-9_]+)['"]''',
  );
  for (final m in callRe.allMatches(md)) {
    final method = m.group(1)!;
    if (method == 'namespace.method') continue; // placeholder מכוון
    methods.add(method);
  }

  return methods;
}

Set<String> _parseEvents(String md, Set<String> permissions) {
  final events = <String>{};

  // Otzaria.on('event.name', …)
  final onRe = RegExp(
    '''Otzaria\\.on\\(['"]([a-z][a-zA-Z0-9_]*\\.[a-zA-Z0-9_]+)['"]''',
  );
  for (final m in onRe.allMatches(md)) {
    final ev = m.group(1)!;
    if (ev == 'event.name') continue; // placeholder
    events.add(ev);
  }

  // כל events.subscribe:X מרמז על אירוע X
  for (final perm in permissions) {
    if (perm.startsWith('events.subscribe:')) {
      events.add(perm.substring('events.subscribe:'.length));
    }
  }

  // lifecycle
  for (final lifecycle in const ['plugin.boot', 'plugin.ready']) {
    if (md.contains(lifecycle)) events.add(lifecycle);
  }

  return events;
}

bool _looksLikePermission(String token) {
  // events.subscribe:X — בודקים את הזנב
  if (token.startsWith('events.subscribe:')) {
    final tail = token.substring('events.subscribe:'.length);
    return RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+$').hasMatch(tail);
  }

  if (!RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+$').hasMatch(token)) {
    return false;
  }
  if (RegExp(r'[A-Z]').hasMatch(token)) return false;

  // סינון placeholders
  if (RegExp(r'^(event|namespace|plugin)\.(name|method|id)$').hasMatch(token)) {
    return false;
  }
  return true;
}
