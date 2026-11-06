import 'dart:convert';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNoteDraft {
  final String content;
  final String contentPlain;
  final PersonalNoteContentFormat contentFormat;
  final DateTime updatedAt;
  final int? lineNumber;
  final String? noteId;
  final String? referenceText;
  final PdfNoteAnchor? pdfAnchor;

  const PersonalNoteDraft({
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
    required this.updatedAt,
    this.lineNumber,
    this.noteId,
    this.referenceText,
    this.pdfAnchor,
  });

  Map<String, dynamic> toJson() => {
    'content': content,
    'contentPlain': contentPlain,
    'contentFormat': contentFormat.name,
    'updatedAt': updatedAt.toIso8601String(),
    'lineNumber': lineNumber,
    'noteId': noteId,
    'referenceText': referenceText,
    if (pdfAnchor != null) 'pdfAnchor': pdfAnchor!.toJson(),
  };

  factory PersonalNoteDraft.fromJson(Map<String, dynamic> json) {
    return PersonalNoteDraft(
      content: json['content'] as String,
      contentPlain:
          json['contentPlain'] as String? ?? (json['content'] as String),
      contentFormat: PersonalNoteContentFormat.values.byName(
        json['contentFormat'] as String? ??
            PersonalNoteContentFormat.plain.name,
      ),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lineNumber: json['lineNumber'] as int?,
      noteId: json['noteId'] as String?,
      referenceText: json['referenceText'] as String?,
      pdfAnchor: json['pdfAnchor'] == null
          ? null
          : PdfNoteAnchor.fromJson(
              Map<String, dynamic>.from(json['pdfAnchor'] as Map),
            ),
    );
  }
}

class PersonalNoteDraftService {
  /// קידומת מפתחות הטיוטות ב-Hive box של ההגדרות. חשופה כדי שגיבוי
  /// ההגדרות יחריג אותה — טיוטה היא תוכן הערה אישית, לא הגדרה.
  static const keyPrefix = 'personal_note_draft:';

  // גרסה לתחרות בין פעולות אסינכרוניות באותו תהליך; אינה חלק מהקובץ.
  // מופעי שירות שונים חולקים מפתחות טיוטה, ולכן חולקים גם את הגרסאות.
  static final _versions = <String, Object>{};
  static const _anyVersion = Object();

  Object? draftVersion({
    required String bookId,
    int? categoryId,
    int? lineNumber,
    String? noteId,
    PdfNoteAnchor? pdfAnchor,
  }) =>
      _versions[_key(
        bookId,
        categoryId: categoryId,
        lineNumber: lineNumber,
        noteId: noteId,
        pdfAnchor: pdfAnchor,
      )];

  String _key(
    String bookId, {
    int? categoryId,
    int? lineNumber,
    String? noteId,
    PdfNoteAnchor? pdfAnchor,
  }) {
    assert((lineNumber == null) != (noteId == null));
    final prefix = _bookPrefix(bookId, categoryId: categoryId);
    if (noteId != null) return '${prefix}note:$noteId';
    if (pdfAnchor != null) {
      final document = pdfAnchor.documentId == null
          ? ''
          : '${Uri.encodeComponent(pdfAnchor.documentId!)}:';
      return '${prefix}pdf:$document${pdfAnchor.pageNumber}:${pdfAnchor.x}:${pdfAnchor.y}';
    }
    return '$prefix$lineNumber';
  }

  String _bookPrefix(String bookId, {int? categoryId}) {
    final bookSegment = categoryId != null ? '$bookId@$categoryId' : bookId;
    return '$keyPrefix$bookSegment:';
  }

  PersonalNoteDraft? _readDraft(String key) {
    final raw = Settings.getValue<String>(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PersonalNoteDraft.fromJson(decoded);
    } catch (e) {
      return null;
    }
  }

  Future<PersonalNoteDraft?> loadDraft({
    required String bookId,
    int? categoryId,
    int? lineNumber,
    String? noteId,
    PdfNoteAnchor? pdfAnchor,
  }) async {
    final key = _key(
      bookId,
      categoryId: categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
      pdfAnchor: pdfAnchor,
    );
    final draft = _readDraft(key);
    if (noteId != null) return draft;
    if (draft != null && draft.pdfAnchor == pdfAnchor) return draft;
    if (pdfAnchor == null) return null;

    // טיוטה שנשמרה במפתח הישן של מספר השורה שייכת רק לנקודה שלה.
    final legacyDraft = _readDraft(
      _key(bookId, categoryId: categoryId, lineNumber: lineNumber),
    );
    return legacyDraft?.pdfAnchor == pdfAnchor ? legacyDraft : null;
  }

  Future<void> saveDraft({
    required String bookId,
    int? categoryId,
    int? lineNumber,
    String? noteId,
    required PersonalNoteDraft draft,
  }) async {
    final key = _key(
      bookId,
      categoryId: categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
      pdfAnchor: draft.pdfAnchor,
    );
    final version = _versions[key] = Object();
    final normalizedDraft = PersonalNoteDraft(
      content: draft.content,
      contentPlain: draft.contentPlain,
      contentFormat: draft.contentFormat,
      updatedAt: draft.updatedAt,
      lineNumber: lineNumber ?? draft.lineNumber,
      noteId: noteId ?? draft.noteId,
      referenceText: draft.referenceText,
      pdfAnchor: draft.pdfAnchor,
    );
    if (noteId == null) {
      // מפתח שורה ישן עשוי להכיל טיוטת נקודה. מעבירים אותה לפני כתיבת
      // טיוטה חדשה לאותה שורה, כדי שגם טיוטת טקסט לא תדרוס אותה.
      final legacyKey = _key(
        bookId,
        categoryId: categoryId,
        lineNumber: lineNumber,
      );
      final legacyVersion = _versions[legacyKey];
      final legacyRaw = Settings.getValue<String>(legacyKey);
      final legacyDraft = _readDraft(legacyKey);
      if (legacyDraft?.pdfAnchor != null) {
        final pointKey = _key(
          bookId,
          categoryId: categoryId,
          lineNumber: lineNumber,
          pdfAnchor: legacyDraft!.pdfAnchor,
        );
        if (_readDraft(pointKey) == null) {
          await Settings.setValue<String>(
            pointKey,
            jsonEncode(legacyDraft.toJson()),
          );
        }
        if (identical(_versions[legacyKey], legacyVersion) &&
            Settings.getValue<String>(legacyKey) == legacyRaw) {
          await Settings.setValue<String?>(legacyKey, null);
        }
      }
    }
    // העברה ממפתח PDF ישן עשויה להמתין. כתיבה/ניקוי חדשים גוברים עליה.
    if (identical(_versions[key], version)) {
      await Settings.setValue<String>(
        key,
        jsonEncode(normalizedDraft.toJson()),
      );
    }
  }

  Future<void> clearDraft({
    required String bookId,
    int? categoryId,
    int? lineNumber,
    String? noteId,
    PdfNoteAnchor? pdfAnchor,
    Object? expectedVersion = _anyVersion,
  }) async {
    final key = _key(
      bookId,
      categoryId: categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
      pdfAnchor: pdfAnchor,
    );
    if (!identical(expectedVersion, _anyVersion) &&
        !identical(_versions[key], expectedVersion)) {
      return;
    }
    final version = _versions[key];
    final clearingVersion = _versions[key] = Object();
    if (noteId == null &&
        pdfAnchor == null &&
        _readDraft(key)?.pdfAnchor != null) {
      // ביטול כתיבת טקסט שממתינה להעברת PDF אינו מוחק את ה-PDF הישן.
      _versions.remove(key);
      return;
    }
    final legacyKey = noteId == null && pdfAnchor != null
        ? _key(bookId, categoryId: categoryId, lineNumber: lineNumber)
        : null;
    try {
      // שתי המחיקות מתחילות לפני ההמתנה. כך writer חדש אינו פוגש
      // PDF שכבר נוקה בנקודה אבל עדיין ממתין למחיקת המפתח הישן שלו.
      await Future.wait([
        Settings.setValue<String?>(key, null),
        if (legacyKey != null && _readDraft(legacyKey)?.pdfAnchor == pdfAnchor)
          Settings.setValue<String?>(legacyKey, null),
      ]);
      // עורך שנפתח בזמן הניקוי מזהה שהצילום שלו כבר אינו טיוטה פעילה.
      if (identical(_versions[key], clearingVersion)) _versions.remove(key);
    } catch (_) {
      // כשל מחיקה מאפשר ניסיון חוזר, בלי להחליף גרסה שנכתבה בינתיים.
      if (identical(_versions[key], clearingVersion)) {
        if (version == null) {
          _versions.remove(key);
        } else {
          _versions[key] = version;
        }
      }
      rethrow;
    }
  }

  Future<PersonalNoteDraft?> loadLatestNewNoteDraft({
    required String bookId,
    int? categoryId,
    bool includePdfAnchors = true,
    String? pdfDocumentId,
    Set<String> pdfDocumentIds = const {},
    bool includeUnidentifiedPdfAnchors = true,
  }) async {
    final prefix = _bookPrefix(bookId, categoryId: categoryId);
    if (!Hive.isBoxOpen(HiveCache.keyName)) return null;
    final box = Hive.box<dynamic>(HiveCache.keyName);
    final matchingKeys =
        box.keys
            .map((k) => k.toString())
            .where((key) => key.startsWith(prefix))
            .toList()
          ..sort();

    PersonalNoteDraft? latestDraft;
    for (final key in matchingKeys) {
      if (key.contains(':note:')) continue;

      final draft = _readDraft(key);
      if (draft == null || draft.lineNumber == null) continue;
      final anchor = draft.pdfAnchor;
      if (anchor != null) {
        if (!includePdfAnchors) continue;
        if (anchor.documentId == null) {
          if (!includeUnidentifiedPdfAnchors) continue;
        } else if (anchor.documentId != pdfDocumentId &&
            !pdfDocumentIds.contains(anchor.documentId)) {
          continue;
        }
      }
      if (latestDraft == null ||
          draft.updatedAt.isAfter(latestDraft.updatedAt)) {
        latestDraft = draft;
      }
    }

    return latestDraft;
  }
}
