import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_drop_guard_script.dart';

void main() {
  group('buildPluginDropGuardScript', () {
    test('מוזרק לפני קוד הדף וגם ל-iframes', () {
      final script = buildPluginDropGuardScript();
      expect(
        script.injectionTime,
        UserScriptInjectionTime.AT_DOCUMENT_START,
      );
      expect(script.forMainFrameOnly, isFalse);
    });

    test('חוסם את ברירת המחדל של גרירת קובץ (dragover + drop)', () {
      final source = buildPluginDropGuardScript().source;
      expect(source, contains("addEventListener('dragover'"));
      expect(source, contains("addEventListener('drop'"));
      expect(source, contains('preventDefault'));
    });

    test('חוסם רק גרירת קבצים, בשלב capture', () {
      final source = buildPluginDropGuardScript().source;
      expect(source, contains("'Files'"));
      expect(source, contains('}, true);'));
    });
  });
}
