import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/plugin_install_decision.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

PluginManifest _manifest({
  List<String> permissions = const [],
  bool allowOrderBeforeBuiltIns = false,
}) => PluginManifest(
  schemaVersion: 1,
  id: 'test.plugin',
  name: 'תוסף בדיקה',
  version: '2.0.0',
  description: 'תיאור תוסף',
  author: 'בודק',
  homepage: 'https://test.com',
  entrypoint: 'index.html',
  minAppVersion: '1.0.0',
  sdkVersion: '1.0.0',
  permissions: permissions,
  networkEnabled: false,
  networkAllowlist: const [],
  toolTabTitle: 'Tab',
  toolTabOrder: 0,
  allowOrderBeforeBuiltIns: allowOrderBeforeBuiltIns,
  defaultPinned: true,
  publishedDataTypes: const [],
);

PluginInstallDecision _decide({
  List<String> permissions = const [],
  String? previousVersion = '1.0.0',
  Map<String, bool> previousGranted = const {},
  bool? previousAllowOrder,
  bool allowOrderBeforeBuiltIns = false,
  bool isOfflineMode = false,
  // הבדיקות כאן עוסקות בהכרעת ההרשאות; מי יזם את ההתקנה נבדק בקובץ נפרד.
  bool isUserInitiated = true,
}) => resolvePluginInstallDecision(
  manifest: _manifest(
    permissions: permissions,
    allowOrderBeforeBuiltIns: allowOrderBeforeBuiltIns,
  ),
  previousVersion: previousVersion,
  previousGrantedPermissions: previousGranted,
  previousAllowOrderBeforeBuiltInsGranted: previousAllowOrder,
  isOfflineMode: isOfflineMode,
  isUserInitiated: isUserInitiated,
);

void main() {
  group('עדכון שאינו דורש החלטה (issue #1410)', () {
    test('כל ההרשאות כבר הוענקו — אין מה לשאול', () {
      final decision = _decide(
        permissions: const ['search.fulltext.read'],
        previousGranted: const {'search.fulltext.read': true},
      );

      expect(decision.isPlainUpdate, isTrue);
      expect(decision.requiresUserDecision, isFalse);
      expect(
        decision.permissionToggles,
        const {'search.fulltext.read': true},
        reason: 'ההרשאות שהמשתמש העניק נשלחות כפי שהן',
      );
    });

    test('תוסף בלי הרשאות כלל — אין מה לשאול', () {
      expect(_decide().requiresUserDecision, isFalse);
    });

    test('הרשאה חדשה בגרסה — שואלים', () {
      final decision = _decide(
        permissions: const ['search.fulltext.read', 'history.write'],
        previousGranted: const {'search.fulltext.read': true},
      );

      expect(decision.newPermissions, const ['history.write']);
      expect(decision.requiresUserDecision, isTrue);
    });

    test('הרשאה שהמשתמש כיבה — שואלים', () {
      final decision = _decide(
        permissions: const ['search.fulltext.read'],
        previousGranted: const {'search.fulltext.read': false},
      );

      expect(decision.revokedPermissions, const ['search.fulltext.read']);
      expect(decision.requiresUserDecision, isTrue);
    });

    test('הרשאת רשת שאינה זמינה במצב מנותק — שואלים', () {
      final decision = _decide(
        permissions: [pluginNetworkAccessPermission],
        previousGranted: {pluginNetworkAccessPermission: true},
        isOfflineMode: true,
      );

      expect(
        decision.temporarilyUnavailablePermissions,
        contains(pluginNetworkAccessPermission),
      );
      expect(decision.requiresUserDecision, isTrue);
    });

    test('שאלת ההקדמה שטרם נענתה — שואלים', () {
      final decision = _decide(allowOrderBeforeBuiltIns: true);

      expect(decision.requestsOrderBeforeBuiltIns, isTrue);
      expect(decision.requiresUserDecision, isTrue);
    });

    test('התקנה ראשונה תמיד שואלת', () {
      expect(_decide(previousVersion: null).requiresUserDecision, isTrue);
    });
  });

  group('המארח אינו פותח דיאלוג לעדכון שקט (issue #1410)', () {
    PluginSystemInstallRequiresPermissions state({
      List<String> permissions = const [],
      String? previousVersion = '1.0.0',
      Map<String, bool> previousGranted = const {},
      bool isUserInitiated = true,
    }) => PluginSystemInstallRequiresPermissions(
      manifest: _manifest(permissions: permissions),
      tempDirPath: '/tmp/plugin',
      previousVersion: previousVersion,
      previousGrantedPermissions: previousGranted,
      isUserInitiated: isUserInitiated,
    );

    test('עדכון בלי הרשאות חדשות אינו נפתח לדיאלוג', () {
      final decision = resolvePluginInstallPrompt(
        state(
          permissions: const ['search.fulltext.read'],
          previousGranted: const {'search.fulltext.read': true},
        ),
        isOfflineMode: false,
      );

      expect(decision.requiresUserDecision, isFalse);
    });

    test('אותו עדכון שקט כשתוסף יזם אותו — כן נפתח לדיאלוג', () {
      final decision = resolvePluginInstallPrompt(
        state(
          permissions: const ['search.fulltext.read'],
          previousGranted: const {'search.fulltext.read': true},
          isUserInitiated: false,
        ),
        isOfflineMode: false,
      );

      expect(decision.isPlainUpdate, isTrue);
      expect(decision.requiresUserDecision, isTrue);
    });

    test('עדכון עם הרשאה חדשה כן נפתח לדיאלוג', () {
      final decision = resolvePluginInstallPrompt(
        state(permissions: const ['search.fulltext.read']),
        isOfflineMode: false,
      );

      expect(decision.requiresUserDecision, isTrue);
    });
  });
}
