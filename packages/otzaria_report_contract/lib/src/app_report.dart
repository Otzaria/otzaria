import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'app_report_image.dart';
import 'app_report_minidump.dart';
import 'app_report_redactor.dart';
import 'crash_signature.dart';
import 'report_id.dart';
import 'reports_queue_format.dart';

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
    this.schema = schemaVersion,
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
    this.minidump,
    this.issueNumber,
    this.issueUrl,
    this.merged = false,
    this.duplicate = false,
    this.issuePending = false,
    this.sentAt,
    this.carriedBy,
    this.carriedAt,
  });

  static const int schemaVersion = 2;
  static const int maxTitleLength = 200;
  static const int maxDescriptionLength = 10000;
  static const int maxStepsLength = 5000;
  static const int maxAppVersionLength = 50;
  static const int maxOsVersionLength = 200;
  static const int maxArchLength = 20;
  static const int maxSentryEventIdLength = 64;

  /// Schema 2 counts all attachments in binary MiB, without truncating them.
  static const int maxDiagnosticsBytes = 10 * 1024 * 1024;
  static const int maxErrorLogBytes = 10 * 1024 * 1024;
  static const int legacyMaxDiagnosticsBytes = 300 * 1000;
  static const int legacyMaxErrorLogBytes = 250 * 1000;
  static const int maxBodyBytes = 700 * 1000;

  /// Includes worst-case JSON escaping (six bytes per control character),
  /// base64, gzip overhead and metadata. Attachment validation runs first.
  static const int maxRequestBytes = 128 * 1024 * 1024;

  static const Set<String> platforms = {
    'windows',
    'linux',
    'macos',
    'android',
    'ios',
  };

  final String reportId;

  /// נשמר בתור כדי ששחזור, ניסיון חוזר וייצוא לא ישנו את מדיניות הצרופות.
  final int schema;
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

  /// minidump של קריסה נייטיבית. נשמר באתר בלבד, לא ב-GitHub.
  final AppReportMinidump? minidump;

  // ── שדות הרשומה המקומית, אחרי שליחה ──
  final int? issueNumber;
  final String? issueUrl;
  final bool merged;
  final bool duplicate;
  final bool issuePending;
  final DateTime? sentAt;

  /// מי לקח את הדיווח לשליחה במקום אוצריא, ומתי.
  final String? carriedBy;
  final DateTime? carriedAt;

  bool get isCarriedByOfflineUpdate => carriedBy == kCarriedByOfflineUpdate;

  /// מזהה UUID v4 חדש לדיווח.
  static String generateReportId() => generateReportUuid();

  /// שם הפלטפורמה בערכי החוזה (`other` לפלטפורמה לא מוכרת).
  static String currentPlatform() {
    if (_isWeb) return 'other';
    final os = Platform.operatingSystem;
    return platforms.contains(os) ? os : 'other';
  }

  static const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

  static bool isValidEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());

  /// שם השדה הראשון שהשרת ידחה (422), או null כשהדיווח תקין לשליחה.
  String? validate() {
    if (schema != 1 && schema != schemaVersion) return 'schema';
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
    final imageLimit = schema == 1
        ? AppReportImage.legacyMaxBytes
        : AppReportImage.maxBytes;
    if (images.length > AppReportImage.maxCount ||
        images.any((image) => image.bytes.length > imageLimit)) {
      return 'attachments.images';
    }
    final imageBytes = images.fold<int>(
      0,
      (sum, image) => sum + image.bytes.length,
    );
    if (schema == 1) {
      if (imageBytes > AppReportImage.legacyMaxTotalBytes) {
        return 'attachments.images';
      }
      // תורים ישנים עשויים להכיל dump בלי מידע אמין על גודלו המקורי.
      if (minidump != null &&
          minidump!.gzipBytes.length >
              AppReportMinidump.legacyMaxRawBytes +
                  AppReportMinidump.compressionAllowance) {
        return 'attachments.minidump';
      }
    } else {
      if (diagnostics != null &&
          _utf8Length(jsonEncode(diagnostics)) > maxDiagnosticsBytes) {
        return 'attachments.diagnostics';
      }
      if (errorLog != null && _utf8Length(errorLog!) > maxErrorLogBytes) {
        return 'attachments.errorLog';
      }
      final dump = minidump;
      if (dump != null &&
          (dump.rawByteLength == null ||
              dump.rawByteLength! > AppReportMinidump.maxRawBytes ||
              dump.gzipBytes.length >
                  AppReportMinidump.maxRawBytes +
                      AppReportMinidump.compressionAllowance)) {
        return 'attachments.minidump';
      }
      if (imageBytes + otherAttachmentBytes > AppReportImage.maxTotalBytes) {
        return 'attachments';
      }
    }
    return null;
  }

  /// נפח האבחון, הלוג וה-dump שנבחרו לפני base64; קיצוץ נשמר רק ב-schema 1.
  /// כך בדיקת התקציב אינה מקודדת תמונות כבדות בכל שינוי בטופס.
  int get otherAttachmentBytes {
    final attachments = _textPayload()['attachments'] as Map<String, dynamic>?;
    final diag = attachments?['diagnostics'];
    final log = attachments?['errorLog'];
    return (diag == null ? 0 : _utf8Length(jsonEncode(diag))) +
        (log is String ? _utf8Length(log) : 0) +
        (minidump?.rawByteLength ?? 0);
  }

  /// גוף הבקשה לשרת; חיתוך צרופות נשמר רק לתאימות schema 1.
  Map<String, dynamic> toApiPayload() => _addImages(_textPayload());

  /// מקדם עריכה לחוזה החדש, ושומר דיווח ישן תקין שאינו עומד במכסות החדשות.
  AppReport forEditedTransport() {
    final current = copyWith(schema: schemaVersion);
    return schema == 1 && validate() == null && current.validate() != null
        ? this
        : current;
  }

  /// משתמש בחוזה הישן רק כשהמקודד שלו שומר את כל תוכן הדיווח.
  AppReport forCompatibleTransport() {
    if (schema != schemaVersion || validate() != null) return this;
    final legacy = copyWith(schema: 1);
    if (legacy.validate() != null) return this;
    final completeText = _textPayload()..remove('schema');
    final legacyText = legacy._textPayload()..remove('schema');
    return jsonEncode(completeText) == jsonEncode(legacyText) ? legacy : this;
  }

  Map<String, dynamic> _textPayload() {
    final payload = _basePayload();
    final attachments = <String, dynamic>{};
    final diag = diagnostics;
    if (diag != null) {
      attachments['diagnostics'] =
          schema != 1 ||
              _utf8Length(jsonEncode(diag)) <= legacyMaxDiagnosticsBytes
          ? diag
          : {'truncated': true, 'reason': 'diagnostics exceeded size limit'};
    }
    final log = errorLog;
    if (log != null && log.isNotEmpty) {
      attachments['errorLog'] = schema == 1
          ? keepTailBytes(log, legacyMaxErrorLogBytes)
          : log;
    }
    if (attachments.isEmpty) return payload;
    payload['attachments'] = attachments;
    if (schema != 1) return payload;

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
    return payload;
  }

  /// מקודד את הבתים רק בבניית הבקשה עצמה.
  Map<String, dynamic> _addImages(Map<String, dynamic> payload) {
    final attachments =
        (payload['attachments'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    if (images.isNotEmpty) {
      attachments['images'] = [for (final image in images) image.toJson()];
    }
    final dump = minidump;
    if (dump != null) attachments['minidump'] = dump.toJson();
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
      'schema': schema,
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
    'schema': schema,
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
    if (minidump != null) 'minidump': minidump!.toJson(),
    if (issueNumber != null) 'issueNumber': issueNumber,
    if (issueUrl != null) 'issueUrl': issueUrl,
    'merged': merged,
    'duplicate': duplicate,
    'issuePending': issuePending,
    if (sentAt != null) 'sentAt': sentAt!.toUtc().toIso8601String(),
    if (carriedBy != null) 'carriedBy': carriedBy,
    if (carriedAt != null) 'carriedAt': carriedAt!.toUtc().toIso8601String(),
  };

  factory AppReport.fromJson(Map<String, dynamic> json) {
    final diagnostics = json['diagnostics'];
    return AppReport(
      schema: json['schema'] is int ? json['schema'] as int : 1,
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
      minidump: AppReportMinidump.fromJson(json['minidump']),
      issueNumber: json['issueNumber'] is int
          ? json['issueNumber'] as int
          : null,
      issueUrl: json['issueUrl'] as String?,
      merged: json['merged'] == true,
      duplicate: json['duplicate'] == true,
      issuePending: json['issuePending'] == true,
      sentAt: DateTime.tryParse(_string(json['sentAt'])),
      carriedBy: switch (json['carriedBy']) {
        final String value => value,
        _ => null,
      },
      carriedAt: DateTime.tryParse(_string(json['carriedAt'])),
    );
  }

  static const Object _unset = Object();

  AppReport copyWith({
    int? schema,
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
    Object? minidump = _unset,
    Object? issueNumber = _unset,
    Object? issueUrl = _unset,
    bool? merged,
    bool? duplicate,
    bool? issuePending,
    Object? sentAt = _unset,
  }) {
    return AppReport(
      schema: schema ?? this.schema,
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
      minidump: identical(minidump, _unset)
          ? this.minidump
          : minidump as AppReportMinidump?,
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
      carriedBy: carriedBy,
      carriedAt: carriedAt,
    );
  }

  /// רשומת היסטוריה: בלי הצרופות הכבדות, כדי שמאה דיווחים לא ינפחו את המסד.
  AppReport withoutAttachments() => copyWith(
    diagnostics: null,
    errorLog: null,
    images: const [],
    minidump: null,
  );

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
