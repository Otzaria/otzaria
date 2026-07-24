import 'package:equatable/equatable.dart';

enum DirectErrorReportQueueType {
  manual,
  automaticRetry,
}

/// מודל אחיד לדיווח טעות שנשלח ישירות לצוות אוצריא.
class DirectErrorReport extends Equatable {
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
  });

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
  }) {
    return DirectErrorReport(
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
      createdAt: createdAt,
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
  };

  factory DirectErrorReport.fromJson(Map<String, dynamic> json) {
    return DirectErrorReport(
      id: json['id'] as String,
      senderEmail: json['senderEmail'] as String,
      subject: json['subject'] as String,
      bookTitle: json['bookTitle'] as String,
      currentRef: json['currentRef'] as String,
      lineNumber: json['lineNumber'] as int,
      selectedText: (json['selectedText'] as String?) ?? '',
      errorDetails: (json['errorDetails'] as String?) ?? '',
      contextText: (json['contextText'] as String?) ?? '',
      filePath: (json['filePath'] as String?) ?? '',
      sourceFolder: (json['sourceFolder'] as String?) ?? '',
      libraryVersion: (json['libraryVersion'] as String?) ?? 'unknown',
      queueType: _queueTypeFromJson(json['queueType']),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  static DirectErrorReportQueueType _queueTypeFromJson(dynamic value) {
    return DirectErrorReportQueueType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => DirectErrorReportQueueType.manual,
    );
  }

  Map<String, dynamic> toApiPayload() => {
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
  ];
}
