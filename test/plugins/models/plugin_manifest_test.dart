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

      final toolTab = (manifest.toJson()['contributes']
          as Map<String, dynamic>)['toolTab'] as Map<String, dynamic>;
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
  });
}
