import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/generated_links/models/generated_links_processing_status.dart';
import 'package:otzaria/generated_links/models/processed_range.dart';

/// מבנה ה-cache המקומי של קישורים שנוצרו לספר אחד.
class GeneratedLinksCache {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;

  /// גרסת מנוע הכללים שייצר את הקישורים.
  final String rulesVersion;

  final String? appVersion;

  final int sourceBookId;

  /// טביעת אצבע של הספר בזמן היצירה; אם השתנה — ה-cache לא תקף.
  final String sourceFingerprint;

  final GeneratedLinksProcessingStatus status;

  /// טווחי שורות שעובדו ונשמרו.
  final List<ProcessedRange> processedRanges;

  final List<GeneratedInlineLink> links;

  final DateTime updatedAt;

  /// זמן הכשל האחרון; רלוונטי רק כאשר [status] הוא [GeneratedLinksProcessingStatus.failed].
  final DateTime? failedAt;

  const GeneratedLinksCache({
    required this.schemaVersion,
    required this.rulesVersion,
    required this.sourceBookId,
    required this.sourceFingerprint,
    required this.status,
    required this.processedRanges,
    required this.links,
    required this.updatedAt,
    this.appVersion,
    this.failedAt,
  });

  /// מחזיר האם ה-cache תקף ומלא לשימוש ב-scheduler.
  ///
  /// `processing` נדחה במכוון: cache שהופסק באמצע עיבוד אינו נחשב
  /// "תקף" גם אם ה-fingerprint תואם — ה-scheduler חייב להמשיך לעבד אותו.
  bool isValidFor(String fingerprint, String expectedRulesVersion) {
    if (sourceFingerprint != fingerprint) return false;
    if (rulesVersion != expectedRulesVersion) return false;
    if (status == GeneratedLinksProcessingStatus.stale) return false;
    if (status == GeneratedLinksProcessingStatus.failed) return false;
    if (status == GeneratedLinksProcessingStatus.processing) return false;
    return true;
  }

  /// מחזיר האם יש קישורים שניתן להציג כבר (partial/complete/processing).
  ///
  /// cache חלקי ו-processing כן ניתנים להצגה; stale ו-failed — לא.
  bool get hasDisplayableLinks =>
      links.isNotEmpty &&
      status != GeneratedLinksProcessingStatus.stale &&
      status != GeneratedLinksProcessingStatus.failed;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'rulesVersion': rulesVersion,
        if (appVersion != null) 'appVersion': appVersion,
        'sourceBookId': sourceBookId,
        'sourceFingerprint': sourceFingerprint,
        'status': status.toJson(),
        'processedRanges': processedRanges.map((r) => r.toJson()).toList(),
        'links': links.map((l) => l.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        if (failedAt != null) 'failedAt': failedAt!.toIso8601String(),
      };

  factory GeneratedLinksCache.fromJson(Map<String, dynamic> json) =>
      GeneratedLinksCache(
        schemaVersion:
            json['schemaVersion'] as int? ?? currentSchemaVersion,
        rulesVersion: json['rulesVersion'] as String,
        appVersion: json['appVersion'] as String?,
        sourceBookId: json['sourceBookId'] as int,
        sourceFingerprint: json['sourceFingerprint'] as String,
        status: GeneratedLinksProcessingStatus.fromJson(
            json['status'] as String),
        processedRanges: (json['processedRanges'] as List<dynamic>)
            .map((e) =>
                ProcessedRange.fromJson(e as Map<String, dynamic>))
            .toList(),
        links: (json['links'] as List<dynamic>)
            .map((e) =>
                GeneratedInlineLink.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        failedAt: json['failedAt'] != null
            ? DateTime.parse(json['failedAt'] as String)
            : null,
      );

  /// מחזיר עותק של ה-cache עם שדות מעודכנים.
  GeneratedLinksCache copyWith({
    GeneratedLinksProcessingStatus? status,
    List<ProcessedRange>? processedRanges,
    List<GeneratedInlineLink>? links,
    DateTime? updatedAt,
    DateTime? failedAt,
    String? rulesVersion,
  }) =>
      GeneratedLinksCache(
        schemaVersion: schemaVersion,
        rulesVersion: rulesVersion ?? this.rulesVersion,
        appVersion: appVersion,
        sourceBookId: sourceBookId,
        sourceFingerprint: sourceFingerprint,
        status: status ?? this.status,
        processedRanges: processedRanges ?? this.processedRanges,
        links: links ?? this.links,
        updatedAt: updatedAt ?? this.updatedAt,
        failedAt: failedAt ?? this.failedAt,
      );
}
