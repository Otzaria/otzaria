import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

Map<String, dynamic> _manifestJson({Map<String, dynamic>? toolTab}) => {
  'id': 'com.example.multi',
  'name': 'multi',
  'version': '1.0.0',
  'entrypoint': 'index.html',
  if (toolTab != null) 'contributes': {'toolTab': toolTab},
};

void main() {
  group('contributes.toolTab.allowMultipleInstances', () {
    test('ברירת מחדל: מופע יחיד', () {
      expect(
        PluginManifest.fromJson(_manifestJson()).allowMultipleInstances,
        isFalse,
      );
    });

    test('הדגל נקרא מהמניפסט ושורד סבב toJson/fromJson', () {
      final manifest = PluginManifest.fromJson(
        _manifestJson(toolTab: {'allowMultipleInstances': true}),
      );
      expect(manifest.allowMultipleInstances, isTrue);
      expect(
        PluginManifest.fromJson(manifest.toJson()).allowMultipleInstances,
        isTrue,
      );
    });

    test('toJson לא כותב את המפתח כשהדגל כבוי', () {
      final contributes =
          PluginManifest.fromJson(_manifestJson()).toJson()['contributes']
              as Map<String, dynamic>;
      final toolTab = contributes['toolTab'] as Map<String, dynamic>;
      expect(toolTab.containsKey('allowMultipleInstances'), isFalse);
    });

    for (final value in <Object?>['true', 1, 'yes', null, <String>[]]) {
      test('ערך שאינו בוליאני ($value) אינו זורק ונחשב כבוי', () {
        final manifest = PluginManifest.fromJson(
          _manifestJson(toolTab: {'allowMultipleInstances': value}),
        );
        expect(manifest.allowMultipleInstances, isFalse);
      });
    }
  });
}
