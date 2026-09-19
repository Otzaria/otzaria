import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';
import 'package:otzaria/app_report/models/crash_signature.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';

/// סוג דיווח על התוכנה, בערכי החוזה מול השרת.
enum AppReportType {
  bug,
  crash,
  performance,
  suggestion;

  static AppReportType parse(Object? raw) => AppReportType.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => AppReportType.bug,
  );
}

/// מקור הדיווח: ידני, מתוך הצעה אחרי קריסה, או אוטומטי.
enum AppReportTrigger {
  manual('manual'),
  crashPrompt('crash_prompt'),
  autoCrash('auto_crash');

  const AppReportTrigger(this.wireName);

  final String wireName;

  /// רק בדיווח ידני המייל חובה (לפי החוזה).
  bool get requiresEmail => this == AppReportTrigger.manual;

  static AppReportTrigger parse(Object? raw) =>
      AppReportTrigger.values.firstWhere(
        (value) => value.wireName == raw,
        orElse: () => AppReportTrigger.manual,
      );
}

/// דיווח על התוכנה — גוף הבקשה ל-`/api/app-reports` ורשומת התור/ההיסטוריה.
@immutable
class AppReport {
  const AppReport({
    required this.reportId,
    required this.type,
    required this.trigger,
    required this.title,
    required this.appVersion,
    required this.platform,
    required this.createdAt,
    this.description = '',
    this.stepsToReproduce = '',
    this.reporterEmail = '',
    this.osVersion,
    this.arch,
    this.signature,
    this.sentryEventId,
    this.diagnostics,
    this.errorLog,
    this.images = const [],
    this.issueNumber,
    this.issueUrl,
    this.merged = false,
    this.duplicate = false,
    this.issuePending = false,
    this.sentAt,
  });

  static const int schemaVersion = 1;
  static const int maxTitleLength = 200;
  static const int maxDescriptionLength = 10000;
  static const int maxStepsLength = 5000;
  static const int maxAppVersionLength = 50;
  static const int maxOsVersionLength = 200;
  static const int maxArchLength = 20;
  static const int maxSentryEventIdLength = 64;

  /// גבולות בבייטים; מחושבים ב-1000 כדי להישאר מתחת לגבול השרת בכל פירוש.
  static const int maxDiagnosticsBytes = 300 * 1000;
  static const int maxErrorLogBytes = 250 * 1000;
  static const int maxBodyBytes = 700 * 1000;

  /// גבול הבקשה כולה: הטקסט והצרופות, ועוד צילומי המסך בנפרד.
  static const int maxRequestBytes =
      maxBodyBytes + AppReportImage.maxPayloadBytes;

  static const Set<String> platforms = {
    'windows',
    'linux',
    'macos',
    'android',
    'ios',
  };

  final String reportId;
  final AppReportType type;
  final AppReportTrigger trigger;
  final String title;
  final String description;
  final String stepsToReproduce;
  final String reporterEmail;
  final String appVersion;
  final String platform;
  final String? osVersion;
  final String? arch;
  final CrashSignature? signature;
  final String? sentryEventId;
  final DateTime createdAt;
  final Map<String, dynamic>? diagnostics;
  final String? errorLog;

  /// צילומי המסך. לא עוברים הסתרת מידע ונשמרים באתר בלבד, לא ב-GitHub.
  final List<AppReportImage> images;

  // ── שדות הרשומה המקומית, אחרי שליחה ──
  final int? issueNumber;
  final String? issueUrl;
  final bool merged;
  final bool duplicate;
  final bool issuePending;
  final DateTime? sentAt;

  /// מזהה UUID v4 חדש לדיווח.
  static String generateReportId() => PluginReportService.generateReportId();

  /// שם הפלטפורמה בערכי החוזה (`other` לפלטפורמה לא מוכרת).
  static String currentPlatform() {
    if (kIsWeb) return 'other';
    final os = Platform.operatingSystem;
    return platforms.contains(os) ? os : 'other';
  }

  static bool isValidEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());

  /// שם השדה הראשון שהשרת ידחה (422), או null כשהדיווח תקין לשליחה.
  String? validate() {
    if (reportId.isEmpty || reportId.length > 100) return 'reportId';
    if (title.trim().isEmpty) return 'title';
    final email = reporterEmail.trim();
    if (trigger.requiresEmail) {
      if (description.trim().isEmpty) return 'description';
      if (!isValidEmail(email)) return 'reporterEmail';
    } else if (email.isNotEmpty && !isValidEmail(email)) {
      return 'reporterEmail';
    }
    if (appVersion.trim().isEmpty) return 'appVersion';
    return null;
  }

  /// גוף הבקשה לשרת, חתוך לגבולות החוזה ולגבול הגוף הכולל.
  Map<String, dynamic> toApiPayload() {
    final payload = _basePayload();
    final attachments = <String, dynamic>{};
    final diag = diagnostics;
    if (diag != null) {
      attachments['diagnostics'] =
          _utf8Length(jsonEncode(diag)) <= maxDiagnosticsBytes
          ? diag
          : {'truncated': true, 'reason': 'diagnostics exceeded size limit'};
    }
    final log = errorLog;
    if (log != null && log.isNotEmpty) {
      attachments['errorLog'] = keepTailBytes(log, maxErrorLogBytes);
    }
    if (attachments.isEmpty) return _addImages(payload);
    payload['attachments'] = attachments;

    // מעבר לגבול הכולל — מקצרים קודם את הלוג (מהישן), ורק אז מוותרים על האבחון.
    var overflow = _utf8Length(jsonEncode(payload)) - maxBodyBytes;
    if (overflow > 0 && attachments['errorLog'] is String) {
      final current = attachments['errorLog'] as String;
      final target = _utf8Length(current) - overflow - 1024;
      if (target > 0) {
        attachments['errorLog'] = keepTailBytes(current, target);
      } else {
        attachments.remove('errorLog');
      }
      overflow = _utf8Length(jsonEncode(payload)) - maxBodyBytes;
    }
    if (overflow > 0) attachments.remove('diagnostics');
    _addImages(payload);
    return payload;
  }

  /// התמונות מתווספות אחרי הקיצוץ: יש להן תקציב משלהן ב-[maxRequestBytes].
  Map<String, dynamic> _addImages(Map<String, dynamic> payload) {
    final attachments =
        (payload['attachments'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    if (images.isNotEmpty) {
      attachments['images'] = [for (final image in images) image.toJson()];
    }
    if (attachments.isEmpty) {
      payload.remove('attachments');
    } else {
      payload['attachments'] = attachments;
    }
    return payload;
  }

  Map<String, dynamic> _basePayload() {
    final email = reporterEmail.trim();
    return {
      'schema': schemaVersion,
      'reportId': reportId,
      'type': type.name,
      'trigger': trigger.wireName,
      'title': _clamp(title.trim(), maxTitleLength),
      'description': _clamp(description.trim(), maxDescriptionLength),
      if (stepsToReproduce.trim().isNotEmpty)
        'stepsToReproduce': _clamp(stepsToReproduce.trim(), maxStepsLength),
      if (email.isNotEmpty) 'reporterEmail': email,
      'appVersion': _clamp(appVersion.trim(), maxAppVersionLength),
      'platform': platforms.contains(platform) ? platform : 'other',
      if (osVersion != null && osVersion!.isNotEmpty)
        'osVersion': _clamp(osVersion!, maxOsVersionLength),
      if (arch != null && arch!.isNotEmpty)
        'arch': _clamp(arch!, maxArchLength),
      // ההסתרה עלולה להאריך פריים מעבר לגבול (`<user>` ארוך משם קצר).
      if (signature != null && signature!.exceptionType.trim().isNotEmpty)
        'signature': {
          'exceptionType': _clamp(
            signature!.exceptionType.trim(),
            CrashSignature.maxExceptionTypeLength,
          ),
          'frames': [
            for (final frame in signature!.frames.take(
              CrashSignature.maxFrames,
            ))
              _clamp(frame, CrashSignature.maxFrameLength),
          ],
        },
      if (sentryEventId != null && sentryEventId!.isNotEmpty)
        'sentryEventId': _clamp(sentryEventId!, maxSentryEventIdLength),
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  /// הרשומה המלאה לתור המקומי, כולל שדות התוצאה.
  Map<String, dynamic> toJson() => {
    'reportId': reportId,
    'type': type.name,
    'trigger': trigger.wireName,
    'title': title,
    'description': description,
    'stepsToReproduce': stepsToReproduce,
    'reporterEmail': reporterEmail,
    'appVersion': appVersion,
    'platform': platform,
    if (osVersion != null) 'osVersion': osVersion,
    if (arch != null) 'arch': arch,
    if (signature != null) 'signature': signature!.toJson(),
    if (sentryEventId != null) 'sentryEventId': sentryEventId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (diagnostics != null) 'diagnostics': diagnostics,
    if (errorLog != null) 'errorLog': errorLog,
    if (images.isNotEmpty)
      'images': [for (final image in images) image.toJson()],
    if (issueNumber != null) 'issueNumber': issueNumber,
    if (issueUrl != null) 'issueUrl': issueUrl,
    'merged': merged,
    'duplicate': duplicate,
    'issuePending': issuePending,
    if (sentAt != null) 'sentAt': sentAt!.toUtc().toIso8601String(),
  };

  factory AppReport.fromJson(Map<String, dynamic> json) {
    final diagnostics = json['diagnostics'];
    return AppReport(
      reportId: '${json['reportId'] ?? ''}',
      type: AppReportType.parse(json['type']),
      trigger: AppReportTrigger.parse(json['trigger']),
      title: _string(json['title']),
      description: _string(json['description']),
      stepsToReproduce: _string(json['stepsToReproduce']),
      reporterEmail: _string(json['reporterEmail']),
      appVersion: _string(json['appVersion']),
      platform: _string(json['platform']),
      osVersion: json['osVersion'] as String?,
      arch: json['arch'] as String?,
      signature: CrashSignature.fromJson(json['signature']),
      sentryEventId: json['sentryEventId'] as String?,
      createdAt:
          DateTime.tryParse(_string(json['createdAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      diagnostics: diagnostics is Map
          ? Map<String, dynamic>.from(diagnostics)
          : null,
      errorLog: json['errorLog'] as String?,
      images: [
        if (json['images'] case final List<dynamic> images)
          for (final image in images.map(AppReportImage.fromJson)) ?image,
      ],
      issueNumber: json['issueNumber'] is int
          ? json['issueNumber'] as int
          : null,
      issueUrl: json['issueUrl'] as String?,
      merged: json['merged'] == true,
      duplicate: json['duplicate'] == true,
      issuePending: json['issuePending'] == true,
      sentAt: DateTime.tryParse(_string(json['sentAt'])),
    );
  }

  static const Object _unset = Object();

  AppReport copyWith({
    String? reportId,
    AppReportType? type,
    String? title,
    String? description,
    String? stepsToReproduce,
    String? reporterEmail,
    Object? signature = _unset,
    Object? diagnostics = _unset,
    Object? errorLog = _unset,
    List<AppReportImage>? images,
    Object? issueNumber = _unset,
    Object? issueUrl = _unset,
    bool? merged,
    bool? duplicate,
    bool? issuePending,
    Object? sentAt = _unset,
  }) {
    return AppReport(
      reportId: reportId ?? this.reportId,
      type: type ?? this.type,
      trigger: trigger,
      title: title ?? this.title,
      description: description ?? this.description,
      stepsToReproduce: stepsToReproduce ?? this.stepsToReproduce,
      reporterEmail: reporterEmail ?? this.reporterEmail,
      appVersion: appVersion,
      platform: platform,
      osVersion: osVersion,
      arch: arch,
      signature: identical(signature, _unset)
          ? this.signature
          : signature as CrashSignature?,
      sentryEventId: sentryEventId,
      createdAt: createdAt,
      diagnostics: identical(diagnostics, _unset)
          ? this.diagnostics
          : diagnostics as Map<String, dynamic>?,
      errorLog: identical(errorLog, _unset)
          ? this.errorLog
          : errorLog as String?,
      images: images ?? this.images,
      issueNumber: identical(issueNumber, _unset)
          ? this.issueNumber
          : issueNumber as int?,
      issueUrl: identical(issueUrl, _unset)
          ? this.issueUrl
          : issueUrl as String?,
      merged: merged ?? this.merged,
      duplicate: duplicate ?? this.duplicate,
      issuePending: issuePending ?? this.issuePending,
      sentAt: identical(sentAt, _unset) ? this.sentAt : sentAt as DateTime?,
    );
  }

  /// רשומת היסטוריה: בלי הצרופות הכבדות, כדי שמאה דיווחים לא ינפחו את המסד.
  AppReport withoutAttachments() =>
      copyWith(diagnostics: null, errorLog: null, images: const []);

  /// מסתיר מידע אישי בכל הטקסטים שנשלחים, מלבד שדה המייל של המדווח.
  AppReport redactedWith(AppReportRedactor redactor) {
    final sig = signature;
    final diag = diagnostics;
    return copyWith(
      title: redactor.redactText(title),
      description: redactor.redactText(description),
      stepsToReproduce: redactor.redactText(stepsToReproduce),
      signature: sig == null
          ? null
          : CrashSignature(
              exceptionType: redactor.redactText(sig.exceptionType),
              frames: sig.frames.map(redactor.redactText).toList(),
            ),
      diagnostics: diag == null
          ? null
          : Map<String, dynamic>.from(redactor.redactJson(diag) as Map),
      errorLog: errorLog == null ? null : redactor.redactText(errorLog!),
      images: [
        for (final image in images)
          image.withFileName(redactor.redactText(image.fileName)),
      ],
    );
  }

  /// שומר את סוף הטקסט (החדש ביותר בלוג) בגבול [maxBytes] של UTF-8.
  static String keepTailBytes(String text, int maxBytes) {
    final bytes = utf8.encode(text);
    if (bytes.length <= maxBytes) return text;
    var start = bytes.length - maxBytes;
    // לא מתחילים באמצע תו מרובה-בייטים.
    while (start < bytes.length && (bytes[start] & 0xC0) == 0x80) {
      start++;
    }
    return utf8.decode(bytes.sublist(start), allowMalformed: true);
  }

  static int _utf8Length(String value) => utf8.encode(value).length;

  static String _string(Object? value) => value is String ? value : '';

  static String _clamp(String value, int max) {
    if (value.length <= max) return value;
    var end = max;
    // לא חותכים בין שני חצאי surrogate.
    final unit = value.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    return value.substring(0, end);
  }
}
