import 'dart:convert';
import 'dart:io';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/printing/print_content_models.dart';

enum NotesImportConflictStrategy {
  merge,
  skip,
  keepBoth,
  overwrite,
}

class NotesImportSummary {
  final int inserted;
  final int updated;
  final int skipped;
  final int duplicated;

  const NotesImportSummary({
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.duplicated,
  });
}

class PersonalNotesImportExportService {
  final PersonalNotesDatabase _database;

  PersonalNotesImportExportService({PersonalNotesDatabase? database})
    : _database = database ?? PersonalNotesDatabase.instance;

  Map<String, dynamic> buildExport({
    required List<PersonalNote> notes,
    String? description,
  }) {
    return {
      'version': '2.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'description': ?description,
      'notes': notes.map(_noteToJson).toList(),
    };
  }

  Future<void> exportToFile({
    required String path,
    required List<PersonalNote> notes,
    String? description,
  }) async {
    final payload = buildExport(notes: notes, description: description);
    final file = File(path);
    await file.writeAsString(jsonEncode(payload));
  }

  /// בונה ייצוא טקסט קריא למשתמש (להבדיל מהגיבוי שהוא JSON גולמי).
  ///
  /// העיצוב הוויזואלי (מודגש/נטוי/קו חוצה וכו') לא נשמר — זו גרסה לקריאה
  /// והעתקה. עם זאת יעדי הקישורים *כן* נשמרים: טקסט מקושר מיוצא בתבנית
  /// `הטקסט (היעד)`, כדי לא לאבד מידע מהותי שאינו עיצוב בלבד.
  String buildPlainTextExport({
    required List<PersonalNote> notes,
    String? description,
  }) {
    const separator =
        '------------------------------------------------------------';
    final buffer = StringBuffer()
      ..writeln('הערות אישיות מאוצריא')
      ..writeln('============================================================');
    if (description != null && description.trim().isNotEmpty) {
      buffer.writeln(description.trim());
    }
    buffer
      ..writeln('תאריך ייצוא: ${_formatDate(DateTime.now())}')
      ..writeln('מספר הערות: ${notes.length}');

    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final title = (note.displayTitle?.trim().isNotEmpty ?? false)
          ? note.displayTitle!.trim()
          : note.bookId;
      final meta = <String>['ספר: ${note.bookId}'];
      if (note.lineNumber != null) meta.add('שורה: ${note.lineNumber}');
      meta.add('עודכן: ${_formatDate(note.updatedAt)}');

      buffer
        ..writeln()
        ..writeln('[${i + 1}] $title')
        ..writeln(meta.join(' | '))
        ..writeln(separator)
        // trimRight בלבד — עקבי עם הנרמול בשמירה, כדי לא למחוק הזחה/שורות
        // פותחות שהמשתמש שמר בכוונה.
        ..writeln(_noteBodyText(note).trimRight());
    }

    return buffer.toString();
  }

  /// מחזיר את גוף ההערה כטקסט קריא, תוך שימור יעדי הקישורים.
  ///
  /// עבור הערות עשירות (Quill Delta) ה-[PersonalNote.contentPlain] שומר רק את
  /// הטקסט הגלוי ומאבד את ה-link attributes. כאן בונים את הטקסט מתוך ה-Delta
  /// עצמו ומשרשרים את היעד אחרי טקסט מקושר בתבנית `טקסט (יעד)`. אם התוכן אינו
  /// Delta תקין — נופלים בחזרה ל-[PersonalNote.contentPlain].
  String _noteBodyText(PersonalNote note) {
    if (note.contentFormat != PersonalNoteContentFormat.quillDelta) {
      return note.contentPlain;
    }
    try {
      final decoded = jsonDecode(note.content) as List<dynamic>;
      final buffer = StringBuffer();
      for (final op in decoded) {
        if (op is! Map<String, dynamic>) continue;
        final insert = op['insert'];
        if (insert is! String) continue;
        final attributes = op['attributes'];
        final link = attributes is Map<String, dynamic>
            ? attributes['link']
            : null;
        if (link is String && link.isNotEmpty && insert.trim().isNotEmpty) {
          buffer.write('$insert ($link)');
        } else {
          buffer.write(insert);
        }
      }
      return buffer.toString();
    } catch (_) {
      return note.contentPlain;
    }
  }

  /// בונה את בלוקי המסמך לייצוא וורד בתבנית חידושי תורה (issue #767):
  /// כותרת לכל ספר, תת-כותרת לכל מיקום (פרק/דף) מתוך [locationRef], ואחריהן
  /// גוף ההערה — בלי מספרי שורה ותאריכים. הערות ללא מיקום מקובצות בסוף הספר.
  List<PrintBlock> buildWordExportBlocks({
    required List<PersonalNote> notes,
    required String? Function(PersonalNote note) locationRef,
  }) {
    final sorted = [...notes]
      ..sort((a, b) {
        final byBook = a.bookId.compareTo(b.bookId);
        if (byBook != 0) return byBook;
        int line(PersonalNote n) =>
            n.hasLocation ? (n.lineNumber ?? 0) : 1 << 30;
        return line(a).compareTo(line(b));
      });

    final blocks = <PrintBlock>[];
    String? currentBook;
    String? currentRef;
    for (final note in sorted) {
      final body = _noteWordBlocks(note);
      if (body.isEmpty) continue;

      if (note.bookId != currentBook) {
        currentBook = note.bookId;
        currentRef = null;
        blocks.add(
          PrintBlock(
            kind: PrintBlockKind.heading,
            headingLevel: 1,
            text: _escapeHtml(parsePersonalNotesBookKey(note.bookId).title),
          ),
        );
      }

      final ref = note.hasLocation ? locationRef(note)?.trim() : null;
      final refLabel = (ref?.isNotEmpty ?? false)
          ? ref
          : (note.hasLocation ? null : 'הערות ללא מיקום');
      if (refLabel != null && refLabel != currentRef) {
        currentRef = refLabel;
        blocks.add(
          PrintBlock(
            kind: PrintBlockKind.heading,
            headingLevel: 2,
            text: _escapeHtml(refLabel),
          ),
        );
      }

      blocks.addAll(body);
    }
    return blocks;
  }

  /// גוף הערה אחת כבלוקי טקסט, כשהדיבור-המתחיל (הטקסט שסומן) מודגש בראשה.
  List<PrintBlock> _noteWordBlocks(PersonalNote note) {
    final paragraphs = _noteHtmlParagraphs(note);
    while (paragraphs.isNotEmpty && paragraphs.last.trim().isEmpty) {
      paragraphs.removeLast();
    }
    if (paragraphs.isEmpty) return const [];

    final dibur = note.anchorText?.trim() ?? '';
    if (dibur.isNotEmpty) {
      final needsPeriod = !RegExp(r'[.:,;!?]$').hasMatch(dibur);
      final suffix = needsPeriod ? '.' : '';
      paragraphs[0] = '<b>${_escapeHtml(dibur)}$suffix</b> ${paragraphs[0]}';
    }

    return [
      for (final paragraph in paragraphs)
        PrintBlock(kind: PrintBlockKind.text, text: paragraph),
    ];
  }

  /// ממיר את תוכן ההערה לפסקאות HTML פנים-שורתי (מודגש/נטוי/קו תחתי וכו')
  /// שמנוע הוורד יודע לפרש. יעדי קישורים חיצוניים (http) נשמרים כטקסט;
  /// קישורים פנימיים של האפליקציה מושמטים — הם חסרי משמעות במסמך מודפס.
  List<String> _noteHtmlParagraphs(PersonalNote note) {
    List<String> fromPlain() =>
        note.contentPlain.trimRight().split('\n').map(_escapeHtml).toList();

    if (note.contentFormat != PersonalNoteContentFormat.quillDelta) {
      return fromPlain();
    }
    try {
      final decoded = jsonDecode(note.content) as List<dynamic>;
      final paragraphs = <String>[];
      final current = StringBuffer();
      for (final op in decoded) {
        if (op is! Map<String, dynamic>) continue;
        final insert = op['insert'];
        if (insert is! String) continue;
        final rawAttributes = op['attributes'];
        final attributes = rawAttributes is Map<String, dynamic>
            ? rawAttributes
            : null;
        final parts = insert.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            current.write(_styledHtml(parts[i], attributes));
          }
          if (i < parts.length - 1) {
            paragraphs.add(current.toString());
            current.clear();
          }
        }
      }
      if (current.isNotEmpty) paragraphs.add(current.toString());
      return paragraphs;
    } catch (_) {
      return fromPlain();
    }
  }

  String _styledHtml(String text, Map<String, dynamic>? attributes) {
    var html = _escapeHtml(text);
    final link = attributes?['link'];
    if (link is String && link.startsWith('http') && text.trim().isNotEmpty) {
      html = '$html (${_escapeHtml(link)})';
    }
    if (attributes?['bold'] == true) html = '<b>$html</b>';
    if (attributes?['italic'] == true) html = '<i>$html</i>';
    if (attributes?['underline'] == true) html = '<u>$html</u>';
    if (attributes?['strike'] == true) html = '<s>$html</s>';
    final script = attributes?['script'];
    if (script == 'super') html = '<sup>$html</sup>';
    if (script == 'sub') html = '<sub>$html</sub>';
    return html;
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// מייצא את ההערות לקובץ טקסט קריא (.txt).
  Future<void> exportToTextFile({
    required String path,
    required List<PersonalNote> notes,
    String? description,
  }) async {
    final text = buildPlainTextExport(notes: notes, description: description);
    final file = File(path);
    await file.writeAsString(text);
  }

  String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  Future<NotesImportSummary> importFromFile({
    required String path,
    required NotesImportConflictStrategy strategy,
  }) async {
    final file = File(path);
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final version = decoded['version'] as String? ?? '1.0';
    if (!version.startsWith('2')) {
      throw Exception('גרסת ייצוא לא נתמכת: $version');
    }

    final notesJson = decoded['notes'] as List<dynamic>? ?? const [];
    int inserted = 0;
    int updated = 0;
    int skipped = 0;
    int duplicated = 0;

    for (final item in notesJson) {
      if (item is! Map<String, dynamic>) continue;
      final note = _noteFromJson(item);
      final existing = await _database.getNote(note.id);

      if (existing == null) {
        await _database.insertNote(note);
        inserted++;
        continue;
      }

      switch (strategy) {
        case NotesImportConflictStrategy.skip:
          skipped++;
          break;
        case NotesImportConflictStrategy.overwrite:
          await _database.updateNote(note);
          updated++;
          break;
        case NotesImportConflictStrategy.merge:
          if (note.updatedAt.isAfter(existing.updatedAt)) {
            await _database.updateNote(note);
            updated++;
          } else {
            skipped++;
          }
          break;
        case NotesImportConflictStrategy.keepBoth:
          final duplicatedNote = note.copyWith(
            content: note.content,
            contentPlain: note.contentPlain,
            contentFormat: note.contentFormat,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          );
          final withNewId = duplicatedNote.copyWith(
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          );
          await _database.insertNote(
            PersonalNote(
              id: _generateId(),
              bookId: withNewId.bookId,
              lineNumber: withNewId.lineNumber,
              displayTitle: withNewId.displayTitle,
              anchorText: withNewId.anchorText,
              anchorPrefix: withNewId.anchorPrefix,
              anchorSuffix: withNewId.anchorSuffix,
              anchorStart: withNewId.anchorStart,
              anchorEnd: withNewId.anchorEnd,
              lastKnownLineNumber: withNewId.lastKnownLineNumber,
              status: withNewId.status,
              content: withNewId.content,
              contentPlain: withNewId.contentPlain,
              contentFormat: withNewId.contentFormat,
              createdAt: withNewId.createdAt,
              updatedAt: withNewId.updatedAt,
            ),
          );
          duplicated++;
          break;
      }
    }

    return NotesImportSummary(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      duplicated: duplicated,
    );
  }

  Map<String, dynamic> _noteToJson(PersonalNote note) {
    return {
      'id': note.id,
      'bookId': note.bookId,
      'lineNumber': note.lineNumber,
      'displayTitle': note.displayTitle,
      'anchorText': note.anchorText,
      'anchorPrefix': note.anchorPrefix,
      'anchorSuffix': note.anchorSuffix,
      'anchorStart': note.anchorStart,
      'anchorEnd': note.anchorEnd,
      'lastKnownLineNumber': note.lastKnownLineNumber,
      'status': note.status.name,
      'content': note.content,
      'contentPlain': note.contentPlain,
      'contentFormat': note.contentFormat.name,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
    };
  }

  PersonalNote _noteFromJson(Map<String, dynamic> json) {
    return PersonalNote(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      lineNumber: json['lineNumber'] as int?,
      displayTitle: json['displayTitle'] as String?,
      anchorText: json['anchorText'] as String?,
      anchorPrefix: json['anchorPrefix'] as String?,
      anchorSuffix: json['anchorSuffix'] as String?,
      anchorStart: json['anchorStart'] as int?,
      anchorEnd: json['anchorEnd'] as int?,
      lastKnownLineNumber: json['lastKnownLineNumber'] as int?,
      status: PersonalNoteStatus.values.byName(json['status'] as String),
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

  String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = timestamp.toRadixString(16).padLeft(8, '0');
    return 'pn_${timestamp}_$randomPart';
  }
}
