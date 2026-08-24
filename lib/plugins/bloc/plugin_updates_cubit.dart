import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/services/plugin_update_check_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// מצב עדכוני התוספים הזמינים: מפה `pluginId -> עדכון`, אחרי סינון תוספים
/// שהמשתמש סגר להם את הצ'יפ בריצה הנוכחית.
@immutable
class PluginUpdatesState {
  final Map<String, PluginUpdateInfo> updates;

  const PluginUpdatesState(this.updates);

  PluginUpdateInfo? updateFor(String pluginId) => updates[pluginId];
}

/// מחזיק את תוצאות בדיקת העדכונים עבור ה-UI.
///
/// בכוונה נפרד מ-`PluginSystemBloc`: הוא עובר דרך מצבי ביניים בזמן התקנה
/// וטעינה מחדש, וכל state נוסף שם מסכן את יציבות טאבי התוספים (ה-WebView
/// נהרס כשהטאב נעקר מהעץ).
class PluginUpdatesCubit extends Cubit<PluginUpdatesState> {
  /// כמה זמן תוצאת בדיקה (מוצלחת) תקפה לפני שפתיחת טאב תגרור בדיקה חדשה.
  static const Duration checkTtl = Duration(hours: 6);

  /// המתנה לניסיון חוזר אחרי כשל — קצרה מה-TTL כדי שכשל רגעי בפתיחת הטאב
  /// הראשון לא ישבית את הבדיקה לשעות.
  static const Duration retryTtl = Duration(minutes: 30);

  final PluginUpdateCheckService _service;
  final Future<String> Function() _appVersionLoader;
  final DateTime Function() _clock;

  final Set<String> _dismissed = {};
  Map<String, PluginUpdateInfo> _fetched = const {};
  DateTime? _nextCheckAt;
  bool _checkInFlight = false;

  PluginUpdatesCubit({
    PluginUpdateCheckService? service,
    Future<String> Function()? appVersionLoader,
    DateTime Function()? clock,
  }) : _service = service ?? PluginUpdateCheckService(),
       _appVersionLoader = appVersionLoader ?? _loadAppVersion,
       _clock = clock ?? DateTime.now,
       super(const PluginUpdatesState({}));

  static Future<String> _loadAppVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// מפעילה בדיקת עדכונים אם עבר ה-TTL. בטוחה לקריאה בכל פתיחת טאב תוסף:
  /// בדיקות מקבילות מתלכדות, ובתוך חלון ה-TTL הקריאה היא no-op.
  Future<void> ensureChecked(List<InstalledPlugin> plugins) async {
    if (_checkInFlight) return;
    final now = _clock();
    final nextCheckAt = _nextCheckAt;
    if (nextCheckAt != null && now.isBefore(nextCheckAt)) return;

    _checkInFlight = true;
    try {
      final appVersion = await _appVersionLoader();
      final updates = await _service.fetchUpdates(
        plugins,
        appVersion: appVersion,
      );
      if (isClosed) return;
      if (updates == null) {
        _nextCheckAt = _clock().add(retryTtl);
        return;
      }
      _nextCheckAt = _clock().add(checkTtl);
      _fetched = updates;
      _emitFiltered();
    } finally {
      _checkInFlight = false;
    }
  }

  /// הסתרת הצ'יפ של תוסף עד סוף הריצה הנוכחית.
  void dismiss(String pluginId) {
    _dismissed.add(pluginId);
    _emitFiltered();
  }

  void _emitFiltered() {
    emit(
      PluginUpdatesState(
        Map.unmodifiable({
          for (final entry in _fetched.entries)
            if (!_dismissed.contains(entry.key)) entry.key: entry.value,
        }),
      ),
    );
  }
}
