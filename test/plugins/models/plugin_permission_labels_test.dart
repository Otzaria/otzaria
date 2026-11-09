import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_labels.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

PluginManifest _manifest({Map<String, dynamic>? startup}) =>
    PluginManifest.fromJson({
      'schemaVersion': 1,
      'id': 'test.permissions',
      'name': 'Test',
      'version': '1.0.0',
      'entrypoint': 'index.html',
      'permissions': const <String>[],
      'contributes': {'startup': ?startup},
    });

PluginManifest _networkManifest({
  required bool networkEnabled,
  List<String> allowlist = const [],
}) => PluginManifest.fromJson({
  'schemaVersion': 1,
  'id': 'test.geo',
  'name': 'Test',
  'version': '1.0.0',
  'entrypoint': 'index.html',
  'permissions': const [pluginGeolocationPermission],
  'network': {'enabled': networkEnabled, 'allowlist': allowlist},
});

const _bannedJargon = [
  'sqlite',
  'localhost',
  'webview',
  'blob',
  'legacy',
  'faces',
  'face ',
  'ollama',
  'loopback',
  'api',
  'json',
  'http',
  'isolate',
  'runtime',
  'מנוע',
];

void main() {
  final shownPermissions = [
    ...pluginValidPermissions,
    pluginNewTabPagePermission,
  ];

  test('תיאורי ההרשאות כתובים בעברית פשוטה, בלי מונחים טכניים', () {
    for (final permission in shownPermissions) {
      final info = getPermissionInfo(permission);
      final text = '${info.label} ${info.description}'.toLowerCase();
      expect(info.description.trim(), isNotEmpty, reason: permission);
      expect(RegExp(r'[א-ת]').hasMatch(info.description), isTrue);
      for (final word in _bannedJargon) {
        expect(text, isNot(contains(word)), reason: '$permission: $word');
      }
    }
  });

  test('תיאור ההפעלה ברקע לפי המניפסט אינו טכני', () {
    for (final manifest in [
      _manifest(),
      _manifest(
        startup: {
          'contextMenuItems': [
            {'id': 'lookup', 'title': 'Lookup'},
          ],
          'activationEvents': ['app.startup'],
        },
      ),
      _manifest(
        startup: {
          'publishedData': [
            {'type': 'calendar.event', 'key': 'static', 'payload': {}},
          ],
        },
      ),
    ]) {
      final text = getPermissionInfo(
        pluginRunOnStartupPermission,
        manifest: manifest,
      ).description.toLowerCase();
      for (final word in _bannedJargon) {
        expect(text, isNot(contains(word)), reason: word);
      }
    }
  });

  test('לכל הרשאה (פרט לאירועים) אייקון משלה', () {
    final byIcon = <IconData, List<String>>{};
    for (final permission in shownPermissions) {
      if (permission.startsWith('events.subscribe:')) continue;
      byIcon
          .putIfAbsent(getPermissionInfo(permission).icon, () => [])
          .add(permission);
    }
    final duplicates = byIcon.values.where((list) => list.length > 1);
    expect(duplicates, isEmpty, reason: 'אייקון משותף להרשאות שונות');
  });

  test('ההרשאות החדשות מסבירות את מה שהן מאפשרות', () {
    final fieldActions = getPermissionInfo(pluginSearchFieldActionsPermission);
    expect(fieldActions.description, contains('הטקסט שבשדה'));
    expect(fieldActions.description, contains('הקטגוריה'));
    expect(fieldActions.description, contains('ספרי התוסף'));
    final dialog = getPermissionInfo('search.dialog');
    expect(dialog.description, contains('מילות החיפוש'));
    expect(dialog.description, contains('נשמר'));
    expect(
      getPermissionInfo(pluginLibraryBooksProvidePermission).description,
      contains('ספרים משלו'),
    );
  });

  test('לכל הרשאה תקפה יש תווית עברית — לא נופלת ל-fallback', () {
    final missing = pluginValidPermissions.where((permission) {
      final info = getPermissionInfo(permission);
      return info.label == permission ||
          info.description.startsWith('גישה לפונקציונליות');
    }).toList();

    expect(missing, isEmpty, reason: 'הרשאות ללא תווית ב-_permissionLabels');
  });

  test('הרשאות הסימניות וכלי העזר מסבירות את ההשלכה בפועל', () {
    expect(getPermissionInfo('bookmarks.read').label, contains('סימניות'));
    final write = getPermissionInfo(pluginBookmarksWritePermission);
    expect(write.description, contains('מחיקה'));
    expect(
      getPermissionInfo(pluginToolsReadPermission).label,
      isNot('tools.read'),
    );
  });

  test('כתיבה לנתוני המשתמש מתחילה מאושרת — עקבי עם notes.write', () {
    for (final permission in [
      'notes.write',
      'history.write',
      pluginBookmarksWritePermission,
      pluginToolsReadPermission,
      pluginBookmarksReadPermission,
    ]) {
      expect(
        pluginPermissionDefaultGrant(permission, isOfflineMode: false),
        isTrue,
        reason: permission,
      );
    }
  });

  test('sensitive startup permissions are off by default', () {
    expect(
      pluginPermissionDefaultGrant(
        pluginStartupContributionsPermission,
        isOfflineMode: false,
      ),
      isFalse,
    );
    expect(
      pluginPermissionDefaultGrant(
        pluginRunOnStartupPermission,
        isOfflineMode: false,
      ),
      isFalse,
    );
    expect(
      pluginPermissionDefaultGrant(
        pluginBackgroundKeepAlivePermission,
        isOfflineMode: false,
      ),
      isFalse,
    );
    expect(
      pluginPermissionDefaultGrant('notes.read', isOfflineMode: false),
      isTrue,
    );
  });

  test('startup permissions are first and preserve their priority', () {
    expect(
      orderedPluginPermissions(
        const [
          'notes.read',
          pluginBackgroundKeepAlivePermission,
          pluginStartupContributionsPermission,
          'ui.feedback',
          pluginRunOnStartupPermission,
        ],
        isOfflineMode: false,
      ),
      const [
        pluginRunOnStartupPermission,
        pluginStartupContributionsPermission,
        pluginBackgroundKeepAlivePermission,
        'notes.read',
        'ui.feedback',
      ],
    );
  });

  test('מיקום כבוי כברירת מחדל, וממוקם מיד אחרי לוח ההעתקה', () {
    expect(
      pluginPermissionDefaultGrant(
        pluginGeolocationPermission,
        isOfflineMode: false,
      ),
      isFalse,
    );
    expect(
      orderedPluginPermissions(
        const [
          'notes.read',
          pluginGeolocationPermission,
          pluginClipboardReadPermission,
        ],
        isOfflineMode: false,
      ),
      const [
        pluginClipboardReadPermission,
        pluginGeolocationPermission,
        'notes.read',
      ],
    );
  });

  test('מיקום: תוסף עם רשת מקבל אזהרה שמונה את השרתים שאליהם יוכל לשלוח', () {
    final info = getPermissionInfo(
      pluginGeolocationPermission,
      manifest: _networkManifest(
        networkEnabled: true,
        allowlist: const [
          'https://nominatim.openstreetmap.org/reverse',
          'https://nominatim.openstreetmap.org/search',
          'https://get.geojs.io/v1/ip/geo.json',
        ],
      ),
    );
    expect(info.description, contains('לשלוח את המיקום'));
    expect(info.description, contains('nominatim.openstreetmap.org'));
    expect(info.description, contains('get.geojs.io'));
    // כל שרת מופיע פעם אחת, גם כשיש לו כמה כתובות.
    expect(
      'nominatim.openstreetmap.org'.allMatches(info.description),
      hasLength(1),
    );
  });

  test('מיקום: תוסף בלי רשת — אין אזהרת שליחה', () {
    final plain = getPermissionInfo(pluginGeolocationPermission).description;
    for (final manifest in [
      _networkManifest(networkEnabled: false),
      _networkManifest(
        networkEnabled: false,
        allowlist: const ['https://example.com'],
      ),
    ]) {
      expect(
        getPermissionInfo(
          pluginGeolocationPermission,
          manifest: manifest,
        ).description,
        plain,
      );
    }
    expect(plain, isNot(contains('לשלוח')));
  });

  test('מיקום: רשת בלי שרת בר-הצגה — האזהרה נשארת, בלי רשימה', () {
    // כתובות מקומיות לא יוצאות מהמחשב; כתובת ללא סכימה אינה נפרסת לשרת.
    for (final allowlist in [
      const <String>[],
      const ['http://localhost:11434', 'http://127.0.0.1:1234'],
      const ['example.com'],
    ]) {
      final description = getPermissionInfo(
        pluginGeolocationPermission,
        manifest: _networkManifest(networkEnabled: true, allowlist: allowlist),
      ).description;
      expect(description, contains('לשלוח את המיקום לשרתים באינטרנט'));
      expect(description, isNot(contains('localhost')));
      expect(description, isNot(contains('127.0.0.1')));
    }
  });

  test('מיקום: רשימת השרתים מוגבלת, והשאר נספרים', () {
    final description = getPermissionInfo(
      pluginGeolocationPermission,
      manifest: _networkManifest(
        networkEnabled: true,
        allowlist: [for (var i = 1; i <= 7; i++) 'https://s$i.example.com'],
      ),
    ).description;
    expect(description, contains('s1.example.com'));
    expect(description, contains('s4.example.com'));
    expect(description, isNot(contains('s5.example.com')));
    expect(description, contains('ועוד 3'));
  });

  test('host contributions wording also covers actions without WebView', () {
    final info = getPermissionInfo(pluginStartupContributionsPermission);

    expect(info.label, 'הוספת רכיבים לתוכנה');
    expect(info.description, contains('בלי לפתוח את דף התוסף'));
    expect(info.description, isNot(contains('לחיצה על פקד תפתח')));
  });

  test('declarative background text lists actual activation reasons', () {
    final manifest = _manifest(
      startup: {
        'contextMenuItems': [
          {'id': 'lookup', 'title': 'Lookup'},
        ],
        'activationEvents': [
          'app.startup',
          'reader.sectionContentChanged',
        ],
      },
    );

    final reasons = pluginBackgroundActivationReasons(manifest);
    expect(reasons, contains('לחיצה על פריט בתפריט הטקסט'));
    expect(reasons, contains('עליית אוצריא'));
    expect(reasons, contains('אירועי שינוי תוכן בקורא'));

    final info = getPermissionInfo(
      pluginRunOnStartupPermission,
      manifest: manifest,
    );
    expect(info.label, 'הפעלה ברקע לפי אירוע');
    expect(info.description, contains('3 דקות'));
  });

  test('legacy plugin retains the compatibility wording', () {
    final info = getPermissionInfo(
      pluginRunOnStartupPermission,
      manifest: _manifest(),
    );

    expect(info.label, 'טעינה אוטומטית ברקע');
    expect(info.description, contains('מדור קודם'));
  });

  test(
    'foreground-only contributions are not listed as background reasons',
    () {
      final manifest = _manifest(
        startup: {
          'toolbarItems': [
            {'id': 'open', 'title': 'Open', 'openPlugin': true},
          ],
          'contextMenuItems': [
            {'id': 'separator', 'type': 'separator'},
            {'id': 'open', 'title': 'Open', 'openPlugin': true},
          ],
          'activationEvents': ['app.startup'],
        },
      );

      expect(pluginBackgroundActivationReasons(manifest), ['עליית אוצריא']);
    },
  );

  test('ספק ספרים לחיפוש הספרייה מוסבר כסיבה להפעלה ברקע', () {
    final manifest = _manifest(
      startup: {
        'libraryBooks': [
          {'id': 'books', 'provider': 'mylib', 'title': 'ספרייה'},
        ],
      },
    );

    expect(pluginBackgroundActivationReasons(manifest), [
      'בחירת ספר של התוסף במסך הספרייה',
    ]);
  });

  test('static-only contribution says the background grant is unused', () {
    final manifest = _manifest(
      startup: {
        'publishedData': [
          {'type': 'calendar.event', 'key': 'static', 'payload': {}},
        ],
      },
    );

    expect(pluginBackgroundActivationReasons(manifest), isEmpty);
    final info = getPermissionInfo(
      pluginRunOnStartupPermission,
      manifest: manifest,
    );
    expect(info.description, contains('אינה בשימוש'));
    expect(info.description, isNot(contains('פעולה שהתוסף הגדיר')));
  });
}
