import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/app_report/services/app_hang_report.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/error_log_file.dart';

/// מחבר את מנוע Flutter לגלאי התקיעות שרץ ברמת התהליך באנדרואיד.
class AndroidHangMonitor {
  AndroidHangMonitor({
    MethodChannel? channel,
    bool? isAndroid,
  }) : _channel = channel ?? defaultChannel,
       _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid);

  static const MethodChannel defaultChannel = MethodChannel(
    'otzaria/hang_monitor',
  );

  final MethodChannel _channel;
  final bool _isAndroid;

  Future<void> start() async {
    if (!_isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'appHangRecovered') {
        unawaited(
          AppHangReport.onRecovered(
            call.arguments,
            detect: (duration) async =>
                candidateForRecovery(call.arguments, duration),
          ),
        );
      }
      return null;
    });
    await _channel.invokeMethod<void>('start', {
      'logPath': ErrorLogFile.resolvePath(),
      'version': ErrorLogFile.appVersion,
    });
  }

  @visibleForTesting
  static CrashCandidate? candidateForRecovery(
    Object? arguments,
    Duration duration,
  ) {
    if (arguments case {
      'hangId': final String id,
      'record': final String text,
    } when id.isNotEmpty) {
      final blocks = parseErrorLogBlocks(text);
      if (blocks.length != 1) return null;
      final block = blocks.single;
      if (!block.isAppHang ||
          block.timestamp == null ||
          !block.text.contains('\nHang ID: $id\n')) {
        return null;
      }
      return CrashCandidate.hang(
        signature: block.signature,
        hangDuration: duration,
        details: block.text,
        entries: [block],
      );
    }
    return null;
  }
}
