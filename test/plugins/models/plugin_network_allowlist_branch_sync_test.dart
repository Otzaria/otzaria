import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';

/// בדיקת סנכרון מול GitHub (דורשת רשת): הרשימה המקומפלת היא עותק חלקי של
/// מקור האמת — הקובץ בענף `plugin-network-allowlist`. כתובת שקיימת רק כאן
/// תיחסם אצל משתמשים ותיצור פער מבלבל, לכן כל ערך מקומפל חייב להופיע בענף.
void main() {
  test('כל כתובת ברשימה המקומפלת מופיעה גם בקובץ שבענף הייעודי ב-GitHub',
      () async {
    final response =
        await http.get(PluginNetworkAccessResolver.officialAllowlistUri);
    expect(
      response.statusCode,
      200,
      reason:
          'לא ניתן למשוך את ${PluginNetworkAccessResolver.officialAllowlistUri} '
          '— ודאו שהענף plugin-network-allowlist קיים ושיש חיבור לרשת',
    );

    final branchAllowlist =
        parsePluginNetworkAllowlistText(utf8.decode(response.bodyBytes));
    final missing = pluginNetworkAllowlist
        .where((entry) => !branchAllowlist.contains(entry))
        .toList();

    expect(
      missing,
      isEmpty,
      reason: 'כתובות שקיימות ברשימה המקומפלת אך חסרות בקובץ '
          'plugin_network_allowlist.txt בענף plugin-network-allowlist: $missing',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));
}
