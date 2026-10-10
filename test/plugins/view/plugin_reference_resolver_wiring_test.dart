import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// שני המופעים בונים [PluginBridgeDependencies] בחיווט המשותף. הבדיקה מונעת
/// חזרה לקריאה הישירה ל-findRefs בלי הספרים האישיים.
void main() {
  const hosts = {
    'lib/plugins/view/plugin_webview_host.dart': 'מופע התוסף הקדמי ומופע הרקע',
  };

  for (final host in const [
    'lib/plugins/view/plugin_tab_page.dart',
    'lib/plugins/view/plugin_background_host.dart',
  ]) {
    test('$host בונה את ה-bridge בחיווט המשותף', () {
      final source = File(host).readAsStringSync();
      expect(source, contains('initPluginHost('));
      expect(source, isNot(contains('PluginBridgeDependencies(')));
    });
  }

  for (final entry in hosts.entries) {
    test('${entry.value} משתמש ב-resolver המשותף', () {
      final source = File(entry.key).readAsStringSync();

      expect(
        source,
        contains(
          "import 'package:otzaria/plugins/bridge/plugin_reference_resolver.dart';",
        ),
      );
      expect(
        source,
        contains(
          'resolveReference: buildPluginReferenceResolver(findRefRepository),',
        ),
      );
    });
  }
}
