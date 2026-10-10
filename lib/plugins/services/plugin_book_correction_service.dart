import 'dart:convert';

import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/utils/canonical_json.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

class PluginBookReportSource {
  final String rawText;
  final String? heRef;

  const PluginBookReportSource(this.rawText, {this.heRef});
}

class PluginBookReportMetadata {
  final int bookId;
  final String title;
  final String sourceFolder;
  final String filePath;
  final String libraryVersion;
  final ReportClientInfo client;

  const PluginBookReportMetadata({
    required this.bookId,
    required this.title,
    required this.sourceFolder,
    required this.filePath,
    required this.libraryVersion,
    required this.client,
  });
}

class PluginBookCorrectionService {
  final String Function() senderEmail;
  final Future<DirectReportDeliveryResult> Function(
    DirectErrorReport, {
    required bool allowQueue,
  })
  deliver;
  final DateTime Function() now;

  PluginBookCorrectionService({
    required this.senderEmail,
    required this.deliver,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<Map<String, dynamic>> submit({
    required String pluginId,
    required Map<String, dynamic> args,
    required PluginBookReportMetadata metadata,
    required Future<PluginBookReportSource> Function(int) loadSource,
  }) async {
    final id = args['reportId'];
    final first = args['sectionIndex'];
    final last = args['endSectionIndex'] ?? first;
    final original = args['original'];
    final proposed = args['proposed'];
    final snapshots = args['snapshots'];
    final details = args['details'] ?? '';
    final allowQueue = args['allowQueue'] ?? true;
    final forceFreeText = args['forceFreeText'] ?? false;
    final start = args['sourceStart'];
    final end = args['sourceEnd'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(id) ||
        first is! int ||
        first < 0 ||
        last is! int ||
        last < first ||
        last - first >= 32 ||
        original is! String ||
        proposed is! String ||
        details is! String ||
        allowQueue is! bool ||
        forceFreeText is! bool ||
        original == proposed ||
        original.length > TextCorrection.maxTextLength ||
        proposed.length > TextCorrection.maxTextLength ||
        details.length > 20000 ||
        snapshots is! List ||
        snapshots.length != last - first + 1 ||
        ((start == null) != (end == null)) ||
        (start != null && (start is! int || end is! int || last != first))) {
      throw Exception('error.invalid_params: נתוני התיקון אינם תקינים.');
    }
    if (utf8.encode(jsonEncode(args)).length >
        DirectErrorReport.maxApiBodyBytes) {
      throw Exception('error.invalid_params: בקשת התיקון גדולה מדי.');
    }
    final email = senderEmail().trim();
    if (!DirectErrorReportService.isValidSenderEmail(email)) {
      throw Exception(
        'error.report_email_required: יש להגדיר כתובת מייל בהגדרות דיווח השגיאות באוצריא.',
      );
    }
    final sources = <PluginBookReportSource>[];
    final plainLines = <String>[];
    for (var index = first; index <= last; index++) {
      final snapshot = snapshots[index - first];
      if (snapshot is! Map ||
          snapshot['index'] != index ||
          snapshot['text'] is! String) {
        throw Exception('error.invalid_params: חסרה תמונת מקור רציפה.');
      }
      final source = await loadSource(index);
      final plain = TextRendererService.stripHtml(source.rawText);
      if (plain != snapshot['text']) {
        throw Exception(
          'error.source_changed: מקור הספר השתנה מאז פתיחת העורך.',
        );
      }
      sources.add(source);
      plainLines.add(plain);
    }
    final plain = plainLines.join('\n');
    int? selectionStart;
    if (start is int && end is int) {
      if (start < 0 ||
          end < start ||
          end > plain.length ||
          plain.substring(start, end) != original) {
        throw Exception('error.invalid_params: הטווח אינו תואם לטקסט המקורי.');
      }
      selectionStart = start;
    } else if (original.isNotEmpty) {
      final index = plain.indexOf(original);
      if (index < 0) {
        throw Exception('error.invalid_params: התיקון אינו נמצא בתמונת המקור.');
      }
      if (plain.lastIndexOf(original) == index) selectionStart = index;
    }
    TextCorrection? correction;
    final raw = sources.first.rawText;
    if (!forceFreeText &&
        first == last &&
        raw.length <= TextCorrection.maxTextLength) {
      if (raw == plain && original == plain && selectionStart == 0) {
        correction = TextCorrection.wholeLine(
          originalLine: raw,
          proposedText: proposed,
        );
      } else if (original.isNotEmpty && selectionStart != null) {
        final rawStart = raw == plain ? selectionStart : raw.indexOf(original);
        final rawEnd = rawStart + original.length;
        if (rawStart >= 0 &&
            (raw == plain || raw.lastIndexOf(original) == rawStart) &&
            (raw == plain ||
                raw.lastIndexOf('<', rawStart) <=
                    raw.lastIndexOf('>', rawStart)) &&
            TextRendererService.stripHtml(raw.substring(0, rawStart)) ==
                plain.substring(0, selectionStart) &&
            TextRendererService.stripHtml(raw.substring(rawEnd)) ==
                plain.substring(selectionStart + original.length)) {
          correction = TextCorrection.selection(
            originalLine: raw,
            start: rawStart,
            end: rawEnd,
            proposedText: proposed,
          );
        }
      } else if (original.isEmpty && raw == plain && start is int) {
        final replacement =
            raw.substring(0, start) + proposed + raw.substring(start);
        if (replacement.length <= TextCorrection.maxTextLength) {
          correction = TextCorrection.wholeLine(
            originalLine: raw,
            proposedText: replacement,
          );
        }
      }
    }
    final fallback =
        '--- הצעת תיקון ---\nמקור: $original\nמוצע: ${proposed.isEmpty ? '(מחיקה)' : proposed}';
    final note = [
      'תיקון מתוך תוסף $pluginId. פסקה ${first + 1}${last == first ? '' : ' עד ${last + 1}'}.',
      if (correction == null && start is int)
        'טווח מקור UTF-16: [$start, $end)',
      if (details.isNotEmpty) details,
    ].join('\n');
    const fit = DirectErrorReport.fitDisplayField;
    final report = DirectErrorReport(
      id: '$pluginId:$id',
      senderEmail: email,
      schemaVersion: DirectErrorReport.currentSchemaVersion,
      reportKind: correction == null
          ? DirectErrorReportKind.freeText
          : DirectErrorReportKind.textCorrection,
      correction: correction,
      subject: fit(
        'הצעת תיקון: ${metadata.title}',
        DirectErrorReport.maxSubjectLength,
      ),
      bookTitle: fit(metadata.title, DirectErrorReport.maxTitleOrRefLength),
      currentRef: fit(
        sources.first.heRef ?? '',
        DirectErrorReport.maxTitleOrRefLength,
      ),
      lineNumber: first + 1,
      selectedText: fit(original, DirectErrorReport.maxSelectedTextLength),
      errorDetails: correction == null ? '$note\n\n$fallback' : note,
      contextText: fit(
        sources.map((s) => s.rawText).join('\n'),
        DirectErrorReport.maxContextTextLength,
      ),
      filePath: metadata.filePath,
      sourceFolder: metadata.sourceFolder,
      libraryVersion: metadata.libraryVersion,
      location: ReportLocation(
        lineIndex: first,
        bookId: metadata.bookId,
        libraryBuildId: metadata.libraryVersion == 'unknown'
            ? null
            : metadata.libraryVersion,
        heRef: sources.first.heRef,
      ),
      client: metadata.client,
      createdAt: now().toUtc(),
    );
    try {
      canonicalJsonEncode(report.toApiPayload());
    } on ArgumentError {
      throw Exception('error.invalid_params: התיקון מכיל תו טקסט פגום.');
    }
    if (report.exceedsApiBodyLimit) {
      throw Exception('error.invalid_params: הדיווח גדול מדי לשליחה.');
    }
    final result = await deliver(report, allowQueue: allowQueue);
    if (result.status == DirectReportDeliveryStatus.failed) {
      final code = result.isIdConflict
          ? 'error.report_id_conflict'
          : 'error.report_failed';
      throw Exception('$code: ${result.message}');
    }
    return {
      'status': result.status.name,
      'reportId': id,
      'nativeReportId': report.id,
      'message': result.message,
      'duplicate': result.isDuplicate,
      'correctionSupported': result.isSent
          ? correction != null && !result.correctionNotSupported
          : null,
    };
  }
}
