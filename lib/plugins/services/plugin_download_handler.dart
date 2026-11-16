import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/utils/plugin_executable_files.dart';

/// מטפל בהורדות WebView2 בלי להציג את חלונית ההורדות המובנית.
abstract final class PluginDownloadHandler {
  static bool get isSupported => Platform.isWindows;

  /// מודיע שההורדה התחילה ומסתיר את חלונית WebView2 בלי לבטל את ההורדה.
  /// הורדה של קובץ הרצה מבוטלת.
  static Future<DownloadStartResponse?> onDownloadStarting(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    if (isExecutableDownload(request)) {
      UiSnack.showError(PluginMessages.executableDownloadBlocked);
      return DownloadStartResponse(
        handled: true,
        action: DownloadStartResponseAction.CANCEL,
      );
    }
    final response = responseFor(isWindows: Platform.isWindows);
    if (response != null) {
      UiSnack.show(PluginMessages.fileDownloadStarted);
    }
    return response;
  }

  /// בונה את תשובת WebView2; בפלטפורמות אחרות אין לשנות את מסלול ההורדה.
  @visibleForTesting
  static DownloadStartResponse? responseFor({required bool isWindows}) {
    return isWindows ? DownloadStartResponse(handled: true) : null;
  }

  /// האם אחד משמות הקובץ שההורדה חושפת הוא קובץ הרצה.
  @visibleForTesting
  static bool isExecutableDownload(DownloadStartRequest request) {
    final names = [
      ?request.suggestedFilename,
      ..._contentDispositionFileNames(request.contentDisposition ?? ''),
      if (request.url.pathSegments.isNotEmpty) request.url.pathSegments.last,
    ];
    return names.any(isPluginBlockedExecutable);
  }

  /// גם `filename` וגם `filename*` — הדפדפן בוחר ביניהם, ולכן נבדקים שניהם.
  static Iterable<String> _contentDispositionFileNames(String header) sync* {
    final pattern = RegExp(
      r"""filename\*?\s*=\s*(?:[\w-]+'[\w-]*')?"?([^";]+)""",
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(header)) {
      final raw = match.group(1)!.trim();
      yield raw;
      final decoded = _tryDecode(raw);
      if (decoded != null) yield decoded;
    }
  }

  // קידוד שבור בכותרת אינו סיבה להפיל את ההחלטה; השם הגולמי כבר נבדק.
  static String? _tryDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }
}
