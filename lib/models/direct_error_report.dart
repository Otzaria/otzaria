import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:otzaria/utils/canonical_json.dart';

enum DirectErrorReportQueueType {
  manual,
  automaticRetry,
}

/// סוג הדיווח לפי חוזה תיקוני הטקסט (§1.3).
enum DirectErrorReportKind {
  freeText('free_text'),
  textCorrection('text_correction');

  const DirectErrorReportKind(this.apiName);

  final String apiName;

  static DirectErrorReportKind fromApiName(Object? value) =>
      DirectErrorReportKind.values.firstWhere(
        (kind) => kind.apiName == value,
        orElse: () => DirectErrorReportKind.freeText,
      );
}

/// הצעת תיקון מובנית; שדות הטקסט מדויקים (בלי trim/נרמול). בחירה null = השורה
/// כולה; [proposedText] null = ללא הצעה, "" = הצעת מחיקה.
class TextCorrection extends Equatable {
  /// תקרת אורך (יחידות UTF-16) של השורה ושל ההצעה, לפי החוזה (§2.2).
  static const int maxTextLength = 20000;

  final String originalLine;
  final String? originalSelection;
  final int? selectionStart;
  final int? selectionEnd;
  final String? proposedText;

  const TextCorrection._({
    required this.originalLine,
    required this.originalSelection,
    required this.selectionStart,
    required this.selectionEnd,
    required this.proposedText,
  });

  /// הצעה על השורה כולה (הבחירה לא אותרה חד-משמעית בשורה הגולמית).
  const TextCorrection.wholeLine({
    required String originalLine,
    String? proposedText,
  }) : this._(
         originalLine: originalLine,
         originalSelection: null,
         selectionStart: null,
         selectionEnd: null,
         proposedText: proposedText,
       );

  /// הצעה על תת-מחרוזת [start, end) של [originalLine] (offsets ב-UTF-16).
  factory TextCorrection.selection({
    required String originalLine,
    required int start,
    required int end,
    String? proposedText,
  }) {
    RangeError.checkValidRange(start, end, originalLine.length);
    if (start == end) {
      throw ArgumentError.value(end, 'end', 'Empty selection');
    }
    return TextCorrection._(
      originalLine: originalLine,
      originalSelection: originalLine.substring(start, end),
      selectionStart: start,
      selectionEnd: end,
      proposedText: proposedText,
    );
  }

  bool get hasSelection => originalSelection != null;

  /// הטקסט שההצעה מחליפה.
  String get target => originalSelection ?? originalLine;

  String get contextBefore =>
      hasSelection ? originalLine.substring(0, selectionStart) : '';

  String get contextAfter =>
      hasSelection ? originalLine.substring(selectionEnd!) : '';

  TextCorrection withProposedText(String? proposedText) => TextCorrection._(
    originalLine: originalLine,
    originalSelection: originalSelection,
    selectionStart: selectionStart,
    selectionEnd: selectionEnd,
    proposedText: proposedText,
  );

  Map<String, dynamic>? get _apiSelectionOffset => hasSelection
      ? {
          'unit': 'utf16_code_units',
          'start': selectionStart,
          'end': selectionEnd,
        }
      : null;

  Map<String, dynamic> toJson() => {
    'originalLine': originalLine,
    'originalSelection': originalSelection,
    'selectionStart': selectionStart,
    'selectionEnd': selectionEnd,
    'proposedText': proposedText,
  };

  /// מחזיר null כשהנתונים אינם עקביים — עדיף לאבד את המבנה מלשלוח שבור.
  static TextCorrection? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final line = raw['originalLine'];
    final proposed = raw['proposedText'];
    if (line is! String || (proposed != null && proposed is! String)) {
      return null;
    }
    final start = raw['selectionStart'];
    final end = raw['selectionEnd'];
    final isWholeLine =
        start == null && end == null && raw['originalSelection'] == null;
    if (isWholeLine) {
      return TextCorrection.wholeLine(
        originalLine: line,
        proposedText: proposed as String?,
      );
    }
    if (start is int && end is int) {
      try {
        final correction = TextCorrection.selection(
          originalLine: line,
          start: start,
          end: end,
          proposedText: proposed as String?,
        );
        final storedSelection = raw['originalSelection'];
        if (storedSelection != null &&
            storedSelection != correction.originalSelection) {
          return null;
        }
        return correction;
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// מצרף הצעה מרשומה פגומה כטקסט ל-[details], בלי להחיל אותה על טווח.
  static String salvageMalformedInto(String details, Map raw) {
    final target = raw['originalSelection'] ?? raw['originalLine'];
    final proposed = raw['proposedText'];
    if (target is! String || (proposed != null && proposed is! String)) {
      return details;
    }
    return TextCorrection.wholeLine(
      originalLine: target,
      proposedText: proposed as String?,
    ).appendFallbackTo(details);
  }

  Map<String, dynamic> toApiPayload() => {
    'original_line': originalLine,
    'original_selection': originalSelection,
    'selection_offset': _apiSelectionOffset,
    'proposed_text': proposedText,
    'context_before': contextBefore,
    'context_after': contextAfter,
  };

  Map<String, dynamic> toDigestMap() => {
    'original_line': originalLine,
    'original_selection': originalSelection,
    'proposed_text': proposedText,
    'selection_offset': _apiSelectionOffset,
  };

  /// בלוק ה-fallback לאתר ישן שמתעלם מ-`correction` (חוזה §2.5).
  String get fallbackBlock {
    final proposed = switch (proposedText) {
      null => '(ללא הצעה)',
      '' => '(מחיקה)',
      final text => text,
    };
    return '--- הצעת תיקון ---\nמקור: $target\nמוצע: $proposed';
  }

  /// הסבר המשתמש ובסופו [fallbackBlock].
  String appendFallbackTo(String details) =>
      details.isEmpty ? fallbackBlock : '$details\n\n$fallbackBlock';

  @override
  List<Object?> get props => [
    originalLine,
    originalSelection,
    selectionStart,
    selectionEnd,
    proposedText,
  ];
}

/// מיקום הקטע בספר כפי שהתוכנה מכירה אותו מ-seforim.db (חוזה §1.1).
class ReportLocation extends Equatable {
  /// `line.lineIndex`, 0-based.
  final int? lineIndex;
  final int? bookId;

  /// `schema_meta.db_version`.
  final String? libraryBuildId;
  final String? heRef;

  const ReportLocation({
    this.lineIndex,
    this.bookId,
    this.libraryBuildId,
    this.heRef,
  });

  Map<String, dynamic> toJson() => {
    'lineIndex': lineIndex,
    'bookId': bookId,
    'libraryBuildId': libraryBuildId,
    'heRef': heRef,
  };

  static ReportLocation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return ReportLocation(
      lineIndex: raw['lineIndex'] as int?,
      bookId: raw['bookId'] as int?,
      libraryBuildId: raw['libraryBuildId'] as String?,
      heRef: raw['heRef'] as String?,
    );
  }

  Map<String, dynamic> toApiPayload() => {
    'line_index': lineIndex,
    'book_id': bookId,
    'library_build_id': libraryBuildId,
    'he_ref': heRef,
  };

  @override
  List<Object?> get props => [lineIndex, bookId, libraryBuildId, heRef];
}

/// פרטי התוכנה השולחת.
class ReportClientInfo extends Equatable {
  final String appVersion;
  final String platform;

  const ReportClientInfo({required this.appVersion, required this.platform});

  Map<String, dynamic> toJson() => {
    'appVersion': appVersion,
    'platform': platform,
  };

  static ReportClientInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return ReportClientInfo(
      appVersion: (raw['appVersion'] as String?) ?? '',
      platform: (raw['platform'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toApiPayload() => {
    'app_version': appVersion,
    'platform': platform,
  };

  @override
  List<Object?> get props => [appVersion, platform];
}

/// דיווח טעות שנשלח ישירות לצוות אוצריא. [schemaVersion] 1 = דיווח מגרסה ישנה
/// (נשלח כפי שנשלח אז); 2 = חוזה תיקוני הטקסט (docs/text-corrections באתר).
class DirectErrorReport extends Equatable {
  static const int currentSchemaVersion = 2;

  /// תקרת גוף הבקשה לפי החוזה (§2.2): 256KB = 256×1024 בתים של UTF-8.
  static const int maxApiBodyBytes = 256 * 1024;

  /// תקרות שדות התצוגה (UTF-16) שהאתר אוכף ב-v2 בדחייה (payload.js).
  static const int maxSubjectLength = 500;
  static const int maxTitleOrRefLength = 300;
  static const int maxSelectedTextLength = 10000;
  static const int maxContextTextLength = 20000;

  /// מקצר שדה תצוגה לתקרה, עם '…' בסופו. לא חוצה זוג surrogate.
  /// לעולם לא לשדות המדויקים של [TextCorrection].
  static String fitDisplayField(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    var end = maxLength - 1;
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return '${value.substring(0, end)}…';
  }

  final String id;
  final String senderEmail;
  final String subject;
  final String bookTitle;
  final String currentRef;
  final int lineNumber;
  final String selectedText;
  final String errorDetails;
  final String contextText;
  final String filePath;
  final String sourceFolder;
  final String libraryVersion;
  final DirectErrorReportQueueType queueType;
  final DateTime createdAt;
  final int schemaVersion;
  final DirectErrorReportKind reportKind;
  final ReportLocation? location;
  final ReportClientInfo? client;
  final TextCorrection? correction;

  /// בהיסטוריית הנשלחים: false = אתר ישן קלט את ההצעה כטקסט חופשי בלבד.
  final bool? serverAcceptedCorrection;

  /// בהיסטוריה: סיבת כשל קבוע — הדיווח לא נקלט ונשמר כאן כדי שההצעה לא תאבד.
  final String? rejectionReason;

  const DirectErrorReport({
    required this.id,
    required this.senderEmail,
    required this.subject,
    required this.bookTitle,
    required this.currentRef,
    required this.lineNumber,
    this.selectedText = '',
    this.errorDetails = '',
    this.contextText = '',
    this.filePath = '',
    this.sourceFolder = '',
    this.libraryVersion = 'unknown',
    this.queueType = DirectErrorReportQueueType.manual,
    required this.createdAt,
    this.schemaVersion = 1,
    this.reportKind = DirectErrorReportKind.freeText,
    this.location,
    this.client,
    this.correction,
    this.serverAcceptedCorrection,
    this.rejectionReason,
  }) : assert(
         (correction == null) == (reportKind == DirectErrorReportKind.freeText),
         'correction must be set exactly for text_correction reports',
       );

  /// מזהה חדש ויציב לדיווח (`report_id` בחוזה).
  static String generateId(String seed) =>
      '${DateTime.now().microsecondsSinceEpoch}-${seed.hashCode.abs()}';

  bool get isTextCorrection =>
      reportKind == DirectErrorReportKind.textCorrection;

  DirectErrorReport copyWith({
    String? senderEmail,
    String? subject,
    String? bookTitle,
    String? currentRef,
    int? lineNumber,
    String? selectedText,
    String? errorDetails,
    String? contextText,
    String? filePath,
    String? sourceFolder,
    String? libraryVersion,
    DirectErrorReportQueueType? queueType,
    TextCorrection? correction,
    bool? serverAcceptedCorrection,
    String? rejectionReason,
  }) {
    return _copy(
      id: id,
      senderEmail: senderEmail ?? this.senderEmail,
      subject: subject ?? this.subject,
      bookTitle: bookTitle ?? this.bookTitle,
      currentRef: currentRef ?? this.currentRef,
      lineNumber: lineNumber ?? this.lineNumber,
      selectedText: selectedText ?? this.selectedText,
      errorDetails: errorDetails ?? this.errorDetails,
      contextText: contextText ?? this.contextText,
      filePath: filePath ?? this.filePath,
      sourceFolder: sourceFolder ?? this.sourceFolder,
      libraryVersion: libraryVersion ?? this.libraryVersion,
      queueType: queueType ?? this.queueType,
      correction: correction ?? this.correction,
      serverAcceptedCorrection:
          serverAcceptedCorrection ?? this.serverAcceptedCorrection,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  /// עותק זהה עם `report_id` אחר — לתוכן ששונה אחרי שכבר נשלח (409).
  DirectErrorReport withId(String newId) => _copy(
    id: newId,
    senderEmail: senderEmail,
    subject: subject,
    bookTitle: bookTitle,
    currentRef: currentRef,
    lineNumber: lineNumber,
    selectedText: selectedText,
    errorDetails: errorDetails,
    contextText: contextText,
    filePath: filePath,
    sourceFolder: sourceFolder,
    libraryVersion: libraryVersion,
    queueType: queueType,
    correction: correction,
    serverAcceptedCorrection: serverAcceptedCorrection,
    rejectionReason: rejectionReason,
  );

  DirectErrorReport _copy({
    required String id,
    required String senderEmail,
    required String subject,
    required String bookTitle,
    required String currentRef,
    required int lineNumber,
    required String selectedText,
    required String errorDetails,
    required String contextText,
    required String filePath,
    required String sourceFolder,
    required String libraryVersion,
    required DirectErrorReportQueueType queueType,
    required TextCorrection? correction,
    required bool? serverAcceptedCorrection,
    required String? rejectionReason,
  }) {
    return DirectErrorReport(
      id: id,
      senderEmail: senderEmail,
      subject: subject,
      bookTitle: bookTitle,
      currentRef: currentRef,
      lineNumber: lineNumber,
      selectedText: selectedText,
      errorDetails: errorDetails,
      contextText: contextText,
      filePath: filePath,
      sourceFolder: sourceFolder,
      libraryVersion: libraryVersion,
      queueType: queueType,
      createdAt: createdAt,
      schemaVersion: schemaVersion,
      reportKind: reportKind,
      location: location,
      client: client,
      correction: correction,
      serverAcceptedCorrection: serverAcceptedCorrection,
      rejectionReason: rejectionReason,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderEmail': senderEmail,
    'subject': subject,
    'bookTitle': bookTitle,
    'currentRef': currentRef,
    'lineNumber': lineNumber,
    'selectedText': selectedText,
    'errorDetails': errorDetails,
    'contextText': contextText,
    'filePath': filePath,
    'sourceFolder': sourceFolder,
    'libraryVersion': libraryVersion,
    'queueType': queueType.name,
    'createdAt': createdAt.toIso8601String(),
    'schemaVersion': schemaVersion,
    'reportKind': reportKind.apiName,
    'location': location?.toJson(),
    'client': client?.toJson(),
    'correction': correction?.toJson(),
    'serverAcceptedCorrection': serverAcceptedCorrection,
    'rejectionReason': rejectionReason,
  };

  factory DirectErrorReport.fromJson(Map<String, dynamic> json) {
    final rawCorrection = json['correction'];
    final correction = TextCorrection.fromJson(rawCorrection);
    final kind = correction == null
        ? DirectErrorReportKind.freeText
        : DirectErrorReportKind.fromApiName(json['reportKind']);
    var errorDetails = (json['errorDetails'] as String?) ?? '';
    if (correction == null && rawCorrection is Map) {
      errorDetails = TextCorrection.salvageMalformedInto(
        errorDetails,
        rawCorrection,
      );
    }
    return DirectErrorReport(
      id: json['id'] as String,
      senderEmail: json['senderEmail'] as String,
      subject: json['subject'] as String,
      bookTitle: json['bookTitle'] as String,
      currentRef: json['currentRef'] as String,
      lineNumber: json['lineNumber'] as int,
      selectedText: (json['selectedText'] as String?) ?? '',
      errorDetails: errorDetails,
      contextText: (json['contextText'] as String?) ?? '',
      filePath: (json['filePath'] as String?) ?? '',
      sourceFolder: (json['sourceFolder'] as String?) ?? '',
      libraryVersion: (json['libraryVersion'] as String?) ?? 'unknown',
      queueType: _queueTypeFromJson(json['queueType']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
      reportKind: kind,
      location: ReportLocation.fromJson(json['location']),
      client: ReportClientInfo.fromJson(json['client']),
      correction: kind == DirectErrorReportKind.textCorrection
          ? correction
          : null,
      serverAcceptedCorrection: json['serverAcceptedCorrection'] as bool?,
      rejectionReason: json['rejectionReason'] as String?,
    );
  }

  static DirectErrorReportQueueType _queueTypeFromJson(dynamic value) {
    return DirectErrorReportQueueType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => DirectErrorReportQueueType.manual,
    );
  }

  /// `error_details` כפי שנשלח: הסבר המשתמש ובסופו בלוק ה-fallback (§2.5).
  String get apiErrorDetails =>
      correction?.appendFallbackTo(errorDetails) ?? errorDetails;

  /// `content_digest` לפי חוזה §4.2, מחושב על הערכים שנשלחים בפועל.
  String get contentDigest => canonicalJsonSha256({
    'v': 1,
    'report_kind': reportKind.apiName,
    'book_title': bookTitle,
    'current_ref': currentRef,
    'line_index': location?.lineIndex,
    'selected_text': selectedText,
    'error_details': apiErrorDetails,
    'context_text': contextText,
    'source_folder': sourceFolder,
    'file_path': filePath,
    'library_version': libraryVersion,
    'correction': correction?.toDigestMap(),
  });

  /// גוף הבקשה בדיוק כפי שנשלח.
  String get apiBody => jsonEncode(toApiPayload());

  bool get exceedsApiBodyLimit => utf8.encode(apiBody).length > maxApiBodyBytes;

  Map<String, dynamic> toApiPayload() {
    final payload = <String, dynamic>{
      'report_id': id,
      'sender_email': senderEmail,
      'subject': subject,
      'book_title': bookTitle,
      'current_ref': currentRef,
      'line_number': lineNumber,
      'selected_text': selectedText,
      'error_details': errorDetails,
      'context_text': contextText,
      'file_path': filePath,
      'source_folder': sourceFolder,
      'library_version': libraryVersion,
      'created_at': createdAt.toIso8601String(),
    };
    if (schemaVersion < 2) {
      return payload;
    }

    payload
      ..['error_details'] = apiErrorDetails
      ..['schema_version'] = currentSchemaVersion
      ..['report_kind'] = reportKind.apiName
      ..['content_digest'] = contentDigest
      ..['location'] = (location ?? const ReportLocation()).toApiPayload()
      ..['source_hint'] = {
        'source_folder': sourceFolder,
        'library_relative_path': filePath,
        'repo_path': null,
      }
      ..['client'] = client?.toApiPayload();
    final correction = this.correction;
    if (correction != null) {
      payload['correction'] = correction.toApiPayload();
    }
    return payload;
  }

  @override
  List<Object?> get props => [
    id,
    senderEmail,
    subject,
    bookTitle,
    currentRef,
    lineNumber,
    selectedText,
    errorDetails,
    contextText,
    filePath,
    sourceFolder,
    libraryVersion,
    queueType,
    createdAt,
    schemaVersion,
    reportKind,
    location,
    client,
    correction,
    serverAcceptedCorrection,
    rejectionReason,
  ];
}
