import 'dart:io';

import 'package:test/test.dart';

/// ה-WebView אינו זמין בטסט, ולכן בודקים שהשער המשותף לכרטיסיה ולמופע הרקע
/// משתמש בהחלטה המאושרת לנתיב `/w/` של התוסף.
void main() {
  const gates = {
    'lib/plugins/view/plugin_webview_host.dart': 'שער הכרטיסיה ומופע הרקע',
  };

  // שני המופעים חייבים לעבור בשער המשותף ולא לממש שער משלהם.
  for (final host in const [
    'lib/plugins/view/plugin_tab_page.dart',
    'lib/plugins/view/plugin_background_host.dart',
  ]) {
    test('$host עובר בשער המשותף', () {
      final source = File(host).readAsStringSync();
      expect(source, contains('with PluginWebViewHost'));
      expect(source, contains('pluginNavigationPolicy('));
      expect(source, contains('interceptPluginRequest('));
      expect(source, isNot(contains('PluginFileServer.instance.isServerUri')));
    });
  }

  gates.forEach((path, name) {
    group(name, () {
      final source = File(path).readAsStringSync();

      test('שני השערים משתמשים בהחלטת נתיב ההעלאה', () {
        expect(
          RegExp(r'_isOwnFileServerRequest\(uri\)').allMatches(source),
          hasLength(2),
        );
        expect(source, contains('isUploadUriForPlugin'));
      });

      test('חסימות נרשמות לכל היותר פעם בדקה', () {
        expect(
          RegExp(r'_logFileServerDenial\(uri\)').allMatches(source),
          hasLength(2),
        );
        expect(source, contains('_fileServerDenialLogInterval'));
        expect(
          source,
          contains(
            'now.difference(lastLogAt) < _fileServerDenialLogInterval',
          ),
        );
      });
    });
  });
}
