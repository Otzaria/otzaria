import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/core/info/error_log_reader.dart';
import 'package:otzaria/core/info/info_topic.dart';
import 'package:otzaria/core/info/os_version.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

/// הצרופות של דיווח: מפת האבחון וקטע הלוג, כבר אחרי הסתרת מידע אישי.
class AppReportAttachments {
  const AppReportAttachments({
    required this.diagnostics,
    required this.errorLog,
  });

  final Map<String, dynamic> diagnostics;
  final String errorLog;
}

/// אוסף את האבחון ואת קטע הלוג לדיווח על התוכנה. כל מקטע עמיד לכשל:
/// מקטע שנכשל נרשם כ-`{'error': ...}` ואינו מפיל את השאר.
class AppReportCollector {
  AppReportCollector({
    AppReportRedactor? redactor,
    this._appInfoLoader,
    this._pluginsLoader,
    this._openTabCounts,
    this._errorLogPath,
    this._shutdownLogPath,
    DateTime Function()? clock,
  }) : _redactor = redactor ?? AppReportRedactor.fromPlatform(),
       _clock = clock ?? DateTime.now;

  /// טווח הזמן של רשומות הלוג שנכנסות לדיווח.
  static const Duration errorLogWindow = Duration(days: 7);
  static const int maxErrorLogBytes = 200 * 1000;
  static const int maxShutdownLogBytes = 20 * 1000;

  /// נקרא רק סוף הקובץ: לוג של שנים אינו נטען כולו לזיכרון.
  static const int _maxErrorLogReadBytes = 4 * 1000 * 1000;

  final AppReportRedactor _redactor;
  final Future<Map<String, dynamic>> Function()? _appInfoLoader;
  final Future<List<InstalledPlugin>> Function()? _pluginsLoader;
  final Future<Map<String, int>> Function()? _openTabCounts;
  final String? _errorLogPath;
  final String? _shutdownLogPath;
  final DateTime Function() _clock;

  /// אוסף אבחון + לוג במקביל.
  Future<AppReportAttachments> collect() async {
    final results = await Future.wait([
      collectDiagnostics(),
      collectErrorLog(),
    ]);
    return AppReportAttachments(
      diagnostics: results[0] as Map<String, dynamic>,
      errorLog: results[1] as String,
    );
  }

  /// מפת האבחון: מידע התוכנה, מערכת, מצב הרשת, ציר העלייה וספירת כרטיסיות.
  Future<Map<String, dynamic>> collectDiagnostics() async {
    final tabCounts = _openTabCounts;
    final diagnostics = <String, dynamic>{
      'collectedAt': _clock().toUtc().toIso8601String(),
      'appInfo': await _guard('appInfo', _loadAppInfo),
      'system': await _guard('system', () async => systemInfo()),
      'state': await _guard('state', () async => _stateInfo()),
      'startupTimeline': await _guard(
        'startupTimeline',
        () async => {
          'lines': const LineSplitter()
              .convert(StartupTimeline.instance.format())
              .where((line) => line.trim().isNotEmpty)
              .toList(),
        },
      ),
      if (tabCounts != null)
        'openTabs': await _guard(
          'openTabs',
          () async => Map<String, dynamic>.from(await tabCounts()),
        ),
    };
    return _redact(diagnostics);
  }

  /// רשומות errors.txt מהשבוע האחרון (החדשות בגבול הגודל) ולוג הסגירה.
  Future<String> collectErrorLog() async {
    final since = _clock().subtract(errorLogWindow);
    final parts = <String>[];

    try {
      final path = _errorLogPath ?? ErrorLogFile.resolvePath();
      final content = await _readTail(path, _maxErrorLogReadBytes);
      if (content != null && content.isNotEmpty) {
        final excerpt = await _excerptInIsolate(content, since);
        if (excerpt.isNotEmpty) parts.add(excerpt);
      }
    } catch (error) {
      parts.add('[errors.txt unavailable: $error]');
    }

    try {
      final path = _shutdownLogPath ?? _defaultShutdownLogPath();
      if (path != null) {
        final content = await _readTail(path, maxShutdownLogBytes * 4);
        if (content != null) {
          final text = const LineSplitter()
              .convert(content)
              .where((line) {
                final stamp = DateTime.tryParse(line.split(' | ').first.trim());
                return stamp != null && !stamp.isBefore(since);
              })
              .join('\n');
          if (text.isNotEmpty) {
            final bounded = AppReport.keepTailBytes(
              text,
              maxShutdownLogBytes,
            );
            parts.add(
              '=== ${ErrorLogReader.shutdownLogFileName} ===\n$bounded',
            );
          }
        }
      }
    } catch (error) {
      parts.add('[shutdown log unavailable: $error]');
    }

    return _redactor.redactText(parts.join('\n\n'));
  }

  /// מערכת ההפעלה, ארכיטקטורה, שפה ומסכים — בלי להריץ תהליכים חיצוניים.
  @visibleForTesting
  static Map<String, dynamic> systemInfo() {
    final info = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'osVersion': osVersion(),
      'arch': detectArch(),
      'processAbi': Abi.current().toString(),
      'processors': Platform.numberOfProcessors,
      'dartVersion': Platform.version.split(' ').first,
    };
    try {
      final dispatcher = PlatformDispatcher.instance;
      info['locale'] = dispatcher.locale.toLanguageTag();
      info['locales'] = dispatcher.locales
          .map((l) => l.toLanguageTag())
          .toList();
      info['textScaleFactor'] = dispatcher.textScaleFactor;
      info['displays'] = [
        for (final display in dispatcher.displays)
          {
            'width': display.size.width,
            'height': display.size.height,
            'devicePixelRatio': display.devicePixelRatio,
            'refreshRate': display.refreshRate,
          },
      ];
      info['views'] = [
        for (final view in dispatcher.views)
          {
            'physicalWidth': view.physicalSize.width,
            'physicalHeight': view.physicalSize.height,
            'devicePixelRatio': view.devicePixelRatio,
          },
      ];
    } catch (error) {
      info['displayError'] = '$error';
    }
    return info;
  }

  /// [raw] ו-[isWindows] נועדו לבדיקות.
  static String osVersion({String? raw, bool? isWindows}) {
    try {
      return displayOsVersion(raw: raw, isWindows: isWindows);
    } catch (_) {
      return '';
    }
  }

  /// `x64` / `arm64` / … לפי ה-ABI של התהליך. תהליך x64 באמולציה על מעבד ARM
  /// מזוהה לפי `PROCESSOR_IDENTIFIER` ומדווח `x64-on-arm64`.
  static String detectArch({Abi? abi, Map<String, String>? environment}) {
    final current = abi ?? Abi.current();
    final name = current.toString();
    final underscore = name.indexOf('_');
    var arch = underscore < 0 ? name : name.substring(underscore + 1);
    if (arch == 'ia32') arch = 'x86';
    if (current == Abi.windowsX64) {
      final env = environment ?? Platform.environment;
      final identifier = env['PROCESSOR_IDENTIFIER'] ?? '';
      if (identifier.toUpperCase().contains('ARM')) return 'x64-on-arm64';
    }
    return arch;
  }

  Future<Map<String, dynamic>> _loadAppInfo() async {
    final loader = _appInfoLoader;
    if (loader != null) return loader();
    // בלי רשימת קבצים אישיים: שמות קבצים של המשתמש אינם נחוצים לאבחון.
    final report = await AppInfoService.collect(
      InfoTopic.all,
      pluginsLoader: _pluginsLoader,
      fileLimit: 0,
      errorLimit: 0,
    );
    return report.toJson();
  }

  Map<String, dynamic> _stateInfo() {
    return {
      'portable': AppPaths.isPortable,
      if (Settings.isInitialized) ...{
        'offlineMode':
            Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false,
        'crashReportMode':
            Settings.getValue<String>(
              SettingsRepository.keyAppCrashReportMode,
            ) ??
            'ask',
      },
    };
  }

  static Future<Map<String, dynamic>> _guard(
    String name,
    Future<Map<String, dynamic>> Function() body,
  ) async {
    try {
      return await body();
    } catch (error) {
      debugPrint('AppReportCollector: $name failed: $error');
      return {'error': '$error'};
    }
  }

  Map<String, dynamic> _redact(Map<String, dynamic> map) {
    try {
      return Map<String, dynamic>.from(_redactor.redactJson(map) as Map);
    } catch (error) {
      // מפה שאי אפשר להסתיר בה בוודאות לא יוצאת מהמחשב.
      return {'error': 'redaction failed: $error'};
    }
  }

  /// פונקציה סטטית: סגירה בתוך מתודת מופע עלולה ללכוד את `this` שאינו ניתן להעברה.
  static Future<String> _excerptInIsolate(String content, DateTime since) =>
      Isolate.run(
        () => recentErrorLogExcerpt(
          content,
          since: since,
          maxBytes: maxErrorLogBytes,
        ),
      );

  static String? _defaultShutdownLogPath() {
    if (!Platform.isWindows) return null;
    final temp = Platform.environment['TEMP'];
    if (temp == null || temp.isEmpty) return null;
    return p.join(temp, ErrorLogReader.shutdownLogFileName);
  }

  static Future<String?> _readTail(String path, int maxBytes) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final raf = await file.open();
    try {
      final length = await raf.length();
      final start = length > maxBytes ? length - maxBytes : 0;
      await raf.setPosition(start);
      final bytes = await raf.read(length - start);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      await raf.close();
    }
  }
}
