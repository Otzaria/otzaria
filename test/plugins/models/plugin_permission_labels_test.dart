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

void main() {
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
