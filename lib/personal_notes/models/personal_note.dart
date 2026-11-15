import 'package:equatable/equatable.dart';
import 'package:otzaria/personal_notes/models/pdf_note_anchor.dart';

export 'pdf_note_anchor.dart';

/// Indicates whether a personal note currently has a valid location in the book.
enum PersonalNoteStatus {
  /// The note is anchored to a specific line in the book.
  located,

  /// The note lost its anchor and awaits manual reposition.
  missing,

  /// הערה על הספר כולו, בלי מיקום. נשמרת כ-missing עם `scope: 'book'`, כדי
  /// שגרסה ישנה תציג אותה כחסרת מיקום ולא תיכשל בקריאתה.
  book,
}

/// על מה הערה חלה.
enum PersonalNoteScope { book, lines, words }

/// Supported formats for note content.
enum PersonalNoteContentFormat {
  /// Plain text content.
  plain,

  /// Quill Delta JSON content.
  quillDelta,
}

/// Represents a stored personal note.
class PersonalNote extends Equatable {
  /// Unique note identifier.
  final String id;

  /// Title of the book the note belongs to.
  final String bookId;

  /// Line number in the book (1-based). `null` when [status] is [PersonalNoteStatus.missing].
  final int? lineNumber;

  /// השורה האחרונה (1-based) בהערה על כמה שורות; null בהערה על שורה אחת.
  final int? endLineNumber;

  /// Display title for the note - the text from the beginning of the line.
  /// Used for display and for matching when the book content changes.
  final String? displayTitle;

  /// הטקסט המדויק שנבחר בעת יצירת ההערה (בלי ניקוד/טעמים).
  /// `null` מציין הערה שהוגדרה על השורה כולה (לא נבחרו מילים ספציפיות),
  /// ואז הסימון נפרס על כל השורה. כאשר קיים — הסימון נפרס רק על מילים אלו.
  final String? anchorText;

  /// הקשר מנורמל לפני הביטוי שנבחר — לזיהוי המופע הנכון כשהטקסט חוזר בשורה.
  final String? anchorPrefix;

  /// הקשר מנורמל אחרי הביטוי שנבחר — לזיהוי המופע הנכון כשהטקסט חוזר בשורה.
  final String? anchorSuffix;

  /// מיקום תווי (offset) של תחילת הביטוי בשורה הגולמית — רמז/fast-path.
  /// מאומת מחדש בעת הרינדור; אם אינו תקף נעשה איתור מחדש לפי [anchorText].
  final int? anchorStart;

  /// מיקום תווי (offset) של סוף הביטוי בשורה הגולמית — רמז/fast-path.
  final int? anchorEnd;

  /// מיקום פיזי ב-PDF, שאינו תלוי במיפוי לשורות של מהדורת הטקסט.
  final PdfNoteAnchor? pdfAnchor;

  /// If the note lost its anchor, we keep the previous line number for UI hints.
  final int? lastKnownLineNumber;

  /// Current status of the note.
  final PersonalNoteStatus status;

  /// Full user supplied note content (trimmed, can span multiple lines).
  /// For [PersonalNoteContentFormat.plain] this is plain text.
  /// For [PersonalNoteContentFormat.quillDelta] this is Delta JSON.
  final String content;

  /// Plain-text representation for search and previews.
  final String contentPlain;

  /// Content format.
  final PersonalNoteContentFormat contentFormat;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last update timestamp.
  final DateTime updatedAt;

  const PersonalNote({
    required this.id,
    required this.bookId,
    required this.lineNumber,
    this.endLineNumber,
    this.displayTitle,
    this.anchorText,
    this.anchorPrefix,
    this.anchorSuffix,
    this.anchorStart,
    this.anchorEnd,
    this.pdfAnchor,
    required this.lastKnownLineNumber,
    required this.status,
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
    required this.createdAt,
    required this.updatedAt,
  });

  /// פורמט ה-JSON המשותף לייצוא הערות ולגיבוי.
  factory PersonalNote.fromJson(Map<String, dynamic> json) {
    return PersonalNote(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      lineNumber: json['lineNumber'] as int?,
      endLineNumber: json['endLineNumber'] as int?,
      displayTitle: json['displayTitle'] as String?,
      anchorText: json['anchorText'] as String?,
      anchorPrefix: json['anchorPrefix'] as String?,
      anchorSuffix: json['anchorSuffix'] as String?,
      anchorStart: json['anchorStart'] as int?,
      anchorEnd: json['anchorEnd'] as int?,
      pdfAnchor: json['pdfAnchor'] == null
          ? null
          : PdfNoteAnchor.fromJson(
              Map<String, dynamic>.from(json['pdfAnchor'] as Map),
            ),
      lastKnownLineNumber: json['lastKnownLineNumber'] as int?,
      status: storedStatus(json['status'] as String, json['scope']),
      content: json['content'] as String,
      contentPlain:
          (json['contentPlain'] as String?) ?? (json['content'] as String),
      contentFormat: PersonalNoteContentFormat.values.byName(
        json['contentFormat'] as String? ??
            PersonalNoteContentFormat.plain.name,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'lineNumber': lineNumber,
      if (endLineNumber != null) 'endLineNumber': endLineNumber,
      'displayTitle': displayTitle,
      'anchorText': anchorText,
      'anchorPrefix': anchorPrefix,
      'anchorSuffix': anchorSuffix,
      'anchorStart': anchorStart,
      'anchorEnd': anchorEnd,
      'pdfAnchor': pdfAnchor?.toJson(),
      'lastKnownLineNumber': lastKnownLineNumber,
      'status': storedStatusName,
      if (isBookNote) 'scope': PersonalNoteScope.book.name,
      'content': content,
      'contentPlain': contentPlain,
      'contentFormat': contentFormat.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// `true` כאשר ההערה מעוגנת למילים ספציפיות בשורה (ולא לשורה כולה).
  bool get isWordAnchored => anchorText != null && anchorText!.isNotEmpty;

  bool get isBookNote => status == PersonalNoteStatus.book;

  PersonalNoteScope get scope => isBookNote
      ? PersonalNoteScope.book
      : isWordAnchored
      ? PersonalNoteScope.words
      : PersonalNoteScope.lines;

  /// השורה האחרונה שההערה חלה עליה (1-based), או null כשאין לה מיקום.
  int? get lastLineNumber => hasLocation ? (endLineNumber ?? lineNumber) : null;

  /// האם ההערה חלה על השורה [line] (1-based).
  bool coversLine(int line) =>
      hasLocation && line >= lineNumber! && line <= lastLineNumber!;

  /// הסטטוס כפי שהוא נשמר: הערת ספר נשמרת כ-missing (ראו [PersonalNoteStatus.book]).
  String get storedStatusName =>
      isBookNote ? PersonalNoteStatus.missing.name : status.name;

  /// הסטטוס מהשמירה, לפי [storedStatusName] ו-`scope`.
  static PersonalNoteStatus storedStatus(String name, Object? scope) =>
      scope == PersonalNoteScope.book.name
      ? PersonalNoteStatus.book
      : PersonalNoteStatus.values.byName(name);

  bool get hasLocation =>
      status == PersonalNoteStatus.located && lineNumber != null;

  /// Get the title to display
  /// להערה על הספר אין מילים בספר, ולכן כותרתה היא תחילת התוכן.
  String get title {
    if (displayTitle case final title?) return title;
    if (!isBookNote) return '';
    final line = contentPlain.trimLeft().split('\n').first.trim();
    return line.length > 60 ? '${line.substring(0, 60)}…' : line;
  }

  PersonalNote copyWith({
    String? id,
    int? lineNumber,
    bool clearLineNumber = false,
    int? endLineNumber,
    bool clearEndLineNumber = false,
    String? displayTitle,
    bool clearDisplayTitle = false,
    String? anchorText,
    String? anchorPrefix,
    String? anchorSuffix,
    int? anchorStart,
    int? anchorEnd,
    bool clearAnchor = false,
    PdfNoteAnchor? pdfAnchor,
    bool clearPdfAnchor = false,
    int? lastKnownLineNumber,
    bool clearLastKnownLineNumber = false,
    PersonalNoteStatus? status,
    String? content,
    String? contentPlain,
    PersonalNoteContentFormat? contentFormat,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PersonalNote(
      id: id ?? this.id,
      bookId: bookId,
      lineNumber: clearLineNumber ? null : (lineNumber ?? this.lineNumber),
      endLineNumber: clearEndLineNumber
          ? null
          : (endLineNumber ?? this.endLineNumber),
      displayTitle: clearDisplayTitle
          ? null
          : (displayTitle ?? this.displayTitle),
      anchorText: clearAnchor ? null : (anchorText ?? this.anchorText),
      anchorPrefix: clearAnchor ? null : (anchorPrefix ?? this.anchorPrefix),
      anchorSuffix: clearAnchor ? null : (anchorSuffix ?? this.anchorSuffix),
      anchorStart: clearAnchor ? null : (anchorStart ?? this.anchorStart),
      anchorEnd: clearAnchor ? null : (anchorEnd ?? this.anchorEnd),
      pdfAnchor: clearPdfAnchor ? null : (pdfAnchor ?? this.pdfAnchor),
      lastKnownLineNumber: clearLastKnownLineNumber
          ? null
          : (lastKnownLineNumber ?? this.lastKnownLineNumber),
      status: status ?? this.status,
      content: content ?? this.content,
      contentPlain: contentPlain ?? this.contentPlain,
      contentFormat: contentFormat ?? this.contentFormat,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    bookId,
    lineNumber,
    endLineNumber,
    displayTitle,
    anchorText,
    anchorPrefix,
    anchorSuffix,
    anchorStart,
    anchorEnd,
    pdfAnchor,
    lastKnownLineNumber,
    status,
    content,
    contentPlain,
    contentFormat,
    createdAt,
    updatedAt,
  ];
}
