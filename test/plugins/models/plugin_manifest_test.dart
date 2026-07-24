import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

void main() {
  group('PluginManifest', () {
    test('parses tool tab icon name', () {
      final manifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'test.plugin.icon',
        'name': 'Icon Plugin',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {
            'title': 'Icon Plugin',
            'iconName': 'calendar_24_filled',
          },
        },
      });

      expect(manifest.toolTabIconName, 'calendar_24_filled');

      final toolTab =
          (manifest.toJson()['contributes'] as Map<String, dynamic>)['toolTab']
              as Map<String, dynamic>;
      expect(toolTab['iconName'], 'calendar_24_filled');
    });

    test('icon name is null when omitted', () {
      final manifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'test.plugin.default.icon',
        'name': 'Default Icon Plugin',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {
            'title': 'Default Icon Plugin',
          },
        },
      });

      expect(manifest.toolTabIconName, isNull);
    });

    test('allowOrderBeforeBuiltIns defaults to false when omitted', () {
      final manifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'test.plugin.default.order.permission',
        'name': 'Default Placement Plugin',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {
            'title': 'Default Placement Plugin',
          },
        },
      });

      expect(manifest.allowOrderBeforeBuiltIns, isFalse);

      final toolTab =
          (manifest.toJson()['contributes'] as Map<String, dynamic>)['toolTab']
              as Map<String, dynamic>;
      expect(toolTab['allowOrderBeforeBuiltIns'], isFalse);
    });

    test('backgroundEntrypoint is null when omitted', () {
      final manifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'test.plugin.no.background',
        'name': 'No Background Plugin',
        'version': '1.0.0',
        'entrypoint': 'index.html',
      });

      expect(manifest.backgroundEntrypoint, isNull);
      final contributes =
          manifest.toJson()['contributes'] as Map<String, dynamic>;
      expect(contributes.containsKey('background'), isFalse);
    });

    test('parses contributes.background.entrypoint and serializes it back', () {
      final manifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'test.plugin.background',
        'name': 'Background Plugin',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'contributes': {
          'background': {'entrypoint': 'dist/background.html'},
        },
      });

      expect(manifest.backgroundEntrypoint, 'dist/background.html');

      final background =
          (manifest.toJson()['contributes']
                  as Map<String, dynamic>)['background']
              as Map<String, dynamic>;
      expect(background['entrypoint'], 'dist/background.html');
    });

    test('parses allowOrderBeforeBuiltIns=true and serializes it back', () {
      final manifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'test.plugin.before.builtins',
        'name': 'Leading Plugin',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {
            'title': 'Leading Plugin',
            'allowOrderBeforeBuiltIns': true,
          },
        },
      });

      expect(manifest.allowOrderBeforeBuiltIns, isTrue);

      final toolTab =
          (manifest.toJson()['contributes'] as Map<String, dynamic>)['toolTab']
              as Map<String, dynamic>;
      expect(toolTab['allowOrderBeforeBuiltIns'], isTrue);
    });
  });
}
