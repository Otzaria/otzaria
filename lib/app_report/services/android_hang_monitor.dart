import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/app_report/services/app_hang_report.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:path/path.dart' as p;

/// גלאי התקיעות של אנדרואיד (`HangMonitorChannel.kt`): הנייטיב כותב `App hang`
/// ל-errors.txt, ותקיעה שהשתחררה מדווחת כמו ב-Windows.
class AndroidHangMonitor {
  AndroidHangMonitor({
    MethodChannel? channel,
    String? stateFilePath,
    this._detector,
    DateTime Function()? processStartedAt,
    bool? isAndroid,
  }) : _channel = channel ?? defaultChannel,
       _customStatePath = stateFilePath,
       _processStartedAt = processStartedAt ?? _timelineStart,
       _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  static const MethodChannel defaultChannel = MethodChannel(
    'otzaria/hang_monitor',
  );
  static const String stateFileName = 'android_hang_state.json';

  final MethodChannel _channel;
  final String? _customStatePath;
  final UncleanExitDetector? _detector;
  final DateTime Function() _processStartedAt;
  final bool _isAndroid;

  String get stateFilePath =>
      _customStatePath ??
      p.join(p.dirname(ErrorLogFile.resolvePath()), stateFileName);

  /// פעם אחת לתהליך, אחרי חשיפת החלון.
  Future<void> start() async {
    if (!_isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'appHangRecovered') {
        unawaited(AppHangReport.onRecovered(call.arguments));
      }
      return null;
    });
    await _channel.invokeMethod<void>('start', {
      'logPath': ErrorLogFile.resolvePath(),
      'version': ErrorLogFile.appVersion,
    });
  }

  /// תקיעה מהפעלה קודמת שלא השתחררה: האפליקציה נסגרה כשהיא תקועה. כל תקיעה
  /// מוחזרת פעם אחת; בהרצה הראשונה רק נשמר סימן-המים.
  Future<CrashCandidate?> takeUnrecoveredHang() async {
    if (!_isAndroid) return null;
    try {
      final processStartedAt = _processStartedAt();
      final watermark = await _readWatermark();
      // נשמר לפני הבדיקה, כדי שקריסה בזמן הדיווח לא תחזיר את אותה תקיעה.
      await _writeWatermark(processStartedAt);
      if (watermark == null) return null;
      final detector =
          _detector ?? UncleanExitDetector(processStartedAt: processStartedAt);
      return await detector.detectUnrecoveredHang(since: watermark);
    } catch (error) {
      debugPrint('AndroidHangMonitor: $error');
      return null;
    }
  }

  static DateTime _timelineStart() =>
      StartupTimeline.instance.startedAt ?? DateTime.now();

  Future<DateTime?> _readWatermark() async {
    final file = File(stateFilePath);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      final ms = json is Map ? json['lastCheckedMs'] : null;
      return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeWatermark(DateTime at) async {
    final file = File(stateFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'lastCheckedMs': at.millisecondsSinceEpoch}),
      flush: true,
    );
  }
}
