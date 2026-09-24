import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_install_decision.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

/// דילוג על דיאלוג ההרשאות מותנה בכך שהמשתמש הוא שיזם את העדכון (issue #1410).
PluginManifest _manifest() => PluginManifest(
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
  permissions: const ['search.fulltext.read'],
  networkEnabled: false,
  networkAllowlist: const [],
  toolTabTitle: 'Tab',
  toolTabOrder: 0,
  allowOrderBeforeBuiltIns: false,
  defaultPinned: true,
  publishedDataTypes: const [],
);

PluginInstallDecision _decide({required bool isUserInitiated}) =>
    resolvePluginInstallDecision(
      manifest: _manifest(),
      previousVersion: '1.0.0',
      previousGrantedPermissions: const {'search.fulltext.read': true},
      previousAllowOrderBeforeBuiltInsGranted: null,
      isOfflineMode: false,
      isUserInitiated: isUserInitiated,
    );

void main() {
  test('עדכון שהמשתמש יזם ואין בו החלטה — בלי דיאלוג (issue #1410)', () {
    final decision = _decide(isUserInitiated: true);

    expect(decision.isPlainUpdate, isTrue);
    expect(decision.requiresUserDecision, isFalse);
  });

  test('אותו עדכון בדיוק כשתוסף יזם אותו — עם דיאלוג (issue #1410)', () {
    final decision = _decide(isUserInitiated: false);

    expect(
      decision.isPlainUpdate,
      isTrue,
      reason: 'ההרשאות לא השתנו — זו עדיין אותה הכרעה על ההרשאות',
    );
    expect(
      decision.requiresUserDecision,
      isTrue,
      reason: 'תוסף יכול לפרסם גרסה חדשה של עצמו ולהתקין אותה בשקט',
    );
  });
}
