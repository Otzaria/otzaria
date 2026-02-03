import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNoteDraft {
  final String content;
  final String contentPlain;
  final PersonalNoteContentFormat contentFormat;
  final DateTime updatedAt;

  const PersonalNoteDraft({
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'content': content,
        'contentPlain': contentPlain,
        'contentFormat': contentFormat.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PersonalNoteDraft.fromJson(Map<String, dynamic> json) {
    return PersonalNoteDraft(
      content: json['content'] as String,
      contentPlain: json['contentPlain'] as String? ??
          (json['content'] as String),
      contentFormat: PersonalNoteContentFormat.values.byName(
        json['contentFormat'] as String? ??
        PersonalNoteContentFormat.plain.name,
      ),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class PersonalNoteDraftService {
  static const _prefix = 'personal_note_draft:';

  String _key(String bookId, int lineNumber) =>
      '$_prefix$bookId:$lineNumber';

  Future<PersonalNoteDraft?> loadDraft({
    required String bookId,
    required int lineNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(bookId, lineNumber));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PersonalNoteDraft.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft({
    required String bookId,
    required int lineNumber,
    required PersonalNoteDraft draft,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(bookId, lineNumber), jsonEncode(draft.toJson()));
  }

  Future<void> clearDraft({
    required String bookId,
    required int lineNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(bookId, lineNumber));
  }
}
