import 'dart:convert';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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

  const PersonalNoteDraft({
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
    required this.updatedAt,
    this.lineNumber,
    this.noteId,
    this.referenceText,
  });

  Map<String, dynamic> toJson() => {
    'content': content,
    'contentPlain': contentPlain,
    'contentFormat': contentFormat.name,
    'updatedAt': updatedAt.toIso8601String(),
    'lineNumber': lineNumber,
    'noteId': noteId,
    'referenceText': referenceText,
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
    );
  }
}

class PersonalNoteDraftService {
  static const _prefix = 'personal_note_draft:';

  String _key(
    String bookId, {
    int? categoryId,
    int? lineNumber,
    String? noteId,
  }) {
    assert((lineNumber == null) != (noteId == null));
    final bookSegment = categoryId != null ? '$bookId@$categoryId' : bookId;
    if (noteId != null) {
      return '$_prefix$bookSegment:note:$noteId';
    }
    return '$_prefix$bookSegment:$lineNumber';
  }

  String _bookPrefix(String bookId, {int? categoryId}) {
    final bookSegment = categoryId != null ? '$bookId@$categoryId' : bookId;
    return '$_prefix$bookSegment:';
  }

  Future<PersonalNoteDraft?> loadDraft({
    required String bookId,
    int? categoryId,
    int? lineNumber,
    String? noteId,
  }) async {
    final key = _key(
      bookId,
      categoryId: categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
    );
    final raw = Settings.getValue<String>(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PersonalNoteDraft.fromJson(decoded);
    } catch (e) {
      return null;
    }
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
    );
    final normalizedDraft = PersonalNoteDraft(
      content: draft.content,
      contentPlain: draft.contentPlain,
      contentFormat: draft.contentFormat,
      updatedAt: draft.updatedAt,
      lineNumber: lineNumber ?? draft.lineNumber,
      noteId: noteId ?? draft.noteId,
      referenceText: draft.referenceText,
    );
    await Settings.setValue<String>(key, jsonEncode(normalizedDraft.toJson()));
  }

  Future<void> clearDraft({
    required String bookId,
    int? categoryId,
    int? lineNumber,
    String? noteId,
  }) async {
    final key = _key(
      bookId,
      categoryId: categoryId,
      lineNumber: lineNumber,
      noteId: noteId,
    );
    await Settings.setValue<String?>(key, null);
  }

  Future<PersonalNoteDraft?> loadLatestNewNoteDraft({
    required String bookId,
    int? categoryId,
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

      final raw = Settings.getValue<String>(key);
      if (raw == null) continue;

      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final draft = PersonalNoteDraft.fromJson(decoded);
        if (draft.lineNumber == null) continue;
        if (latestDraft == null ||
            draft.updatedAt.isAfter(latestDraft.updatedAt)) {
          latestDraft = draft;
        }
      } catch (_) {
        continue;
      }
    }

    return latestDraft;
  }
}
