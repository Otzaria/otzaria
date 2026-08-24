import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// עדכון זמין לתוסף מותקן, כפי שהוחזר מבדיקת ה-batch מול החנות.
@immutable
class PluginUpdateInfo {
  final String pluginId;
  final String version;

  /// כתובת הורדה מוחלטת, מוצמדת לגרסה — מה שהוצג הוא מה שיותקן.
  final String downloadUrl;

  const PluginUpdateInfo({
    required this.pluginId,
    required this.version,
    required this.downloadUrl,
  });
}

/// בדיקת עדכוני תוספים מול חנות התוספים — כולה בצד התוכנה, בלי שום מעורבות
/// או מוּדעות של התוסף עצמו.
///
/// קריאת batch אחת מכסה את כל התוספים המותקנים מארכיון (`packaged`); תוספי
/// פיתוח מוחרגים. כל כשל — רשת מסוננת, שרת לא זמין, timeout — נבלע בשקט:
/// אין UiSnack ואין לוג למשתמש, הצ'יפ פשוט לא יופיע.
class PluginUpdateCheckService {
  static const String storeBaseUrl = 'https://otzaria.org';
  static const Duration requestTimeout = Duration(seconds: 8);

  final http.Client _client;
  final bool Function() _updatesAllowedReader;

  PluginUpdateCheckService({
    http.Client? client,
    bool Function()? updatesAllowedReader,
  }) : _client = client ?? http.Client(),
       _updatesAllowedReader = updatesAllowedReader ?? updatesAllowed {
    if (client == null) {
      HttpClientRegistry.register(_client.close);
    }
  }

  /// האם מותר לבדוק עדכונים: לא במצב מנותק, ועדכוני תוכנה וספרים לא כובו.
  static bool updatesAllowed() {
    try {
      final isOfflineMode =
          Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;
      final updatesEnabled =
          Settings.getValue<bool>(
            SettingsRepository.keySoftwareAndBookUpdatesEnabled,
          ) ??
          true;
      return !isOfflineMode && updatesEnabled;
    } catch (_) {
      // Settings לא אותחל (בדיקות/עלייה חלקית) — לא יוצאים לרשת.
      return false;
    }
  }

  /// בודקת עדכונים לכל התוספים הנתונים בקריאה אחת.
  ///
  /// מחזירה מפה `pluginId -> עדכון` רק עבור תוספים שיש להם גרסה תואמת חדשה
  /// מהמותקנת; `null` = הבדיקה לא רצה או נכשלה (והכשל שקוף למשתמש).
  Future<Map<String, PluginUpdateInfo>?> fetchUpdates(
    List<InstalledPlugin> plugins, {
    required String appVersion,
  }) async {
    if (!_updatesAllowedReader()) return null;

    final eligible = eligiblePlugins(plugins);
    if (eligible.isEmpty) return const {};

    try {
      final response = await _client
          .get(buildUpdatesUri(eligible, appVersion: appVersion))
          .timeout(requestTimeout);
      if (response.statusCode != 200) return null;
      return parseUpdatesResponse(response.body);
    } catch (_) {
      return null;
    }
  }

  /// התוספים שנבדקים מול החנות: הותקנו מארכיון (לא תוספי פיתוח). ההתאמה
  /// לחנות נעשית לפי מזהה המניפסט — גם תוסף חנות שהותקן ידנית מקובץ מכוסה.
  @visibleForTesting
  static List<InstalledPlugin> eligiblePlugins(List<InstalledPlugin> plugins) =>
      plugins.where((p) => p.sourceType == 'packaged').toList();

  @visibleForTesting
  static Uri buildUpdatesUri(
    List<InstalledPlugin> plugins, {
    required String appVersion,
  }) {
    final entries = plugins.map((p) => '${p.pluginId}@${p.version}').join(',');
    return Uri.parse('$storeBaseUrl/api/plugins/updates').replace(
      queryParameters: {'appVersion': appVersion, 'plugins': entries},
    );
  }

  /// מפרסרת את תשובת ה-batch ומחזירה רק תוספים עם עדכון בפועל.
  /// תשובה שאינה במבנה הצפוי → `null` (כשל שקט), רשומה בודדת פגומה מדולגת.
  @visibleForTesting
  static Map<String, PluginUpdateInfo>? parseUpdatesResponse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final updates = decoded['updates'];
    if (updates is! List) return null;

    final result = <String, PluginUpdateInfo>{};
    for (final entry in updates) {
      if (entry is! Map) continue;
      if (entry['hasUpdate'] != true) continue;
      final uid = entry['uid'];
      final version = entry['version'];
      final downloadUrl = entry['downloadUrl'];
      if (uid is! String || uid.isEmpty) continue;
      if (version is! String || version.isEmpty) continue;
      if (downloadUrl is! String || !downloadUrl.startsWith('/')) continue;
      result[uid] = PluginUpdateInfo(
        pluginId: uid,
        version: version,
        downloadUrl: '$storeBaseUrl$downloadUrl',
      );
    }
    return result;
  }
}
