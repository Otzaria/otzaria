import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/view/plugin_linkify_script.dart';

void main() {
  group('buildPluginLinkifyScript', () {
    test('מוזרק לפני קוד הדף', () {
      expect(
        buildPluginLinkifyScript(auto: false).injectionTime,
        UserScriptInjectionTime.AT_DOCUMENT_START,
      );
    });

    test('המצב האוטומטי נגזר מהדגל שהועבר', () {
      expect(
        buildPluginLinkifyScript(auto: true).source,
        contains('window.__otzariaAutoLinkify = true;'),
      );
      expect(
        buildPluginLinkifyScript(auto: false).source,
        contains('window.__otzariaAutoLinkify = false;'),
      );
    });
  });

  group('contributes.autoLinkify', () {
    PluginManifest parse(Map<String, dynamic> contributes) =>
        PluginManifest.fromJson({
          'id': 'demo',
          'name': 'demo',
          'version': '1.0.0',
          'entrypoint': 'index.html',
          'contributes': contributes,
        });

    test('כבוי כברירת מחדל', () {
      expect(parse(const {}).autoLinkify, isFalse);
    });

    test('נדלק ממניפסט ושורד round-trip', () {
      final manifest = parse(const {'autoLinkify': true});
      expect(manifest.autoLinkify, isTrue);
      expect(PluginManifest.fromJson(manifest.toJson()).autoLinkify, isTrue);
    });
  });
}
