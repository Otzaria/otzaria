import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
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
  final Random _random;
  final DateTime Function() _now;

  PersonalNotesImportExportService({
    PersonalNotesDatabase? database,
    Random? random,
    DateTime Function()? now,
  }) : _database = database ?? PersonalNotesDatabase.instance,
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  Map<String, dynamic> buildExport({
    required List<PersonalNote> notes,
    String? description,
  }) {
    return {
      'version': '2.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'description': ?description,
      'notes': notes.map((note) => note.toJson()).toList(),
    };
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

  /// בונה כותרות ספר ומיקום וגופי הערות ל-Word; הערות ללא מיקום בסוף הספר.
  List<PrintBlock> buildWordExportBlocks({
    required List<PersonalNote> notes,
    required String? Function(PersonalNote note) locationRef,
    String? Function(PersonalNote note)? sourceLink,
  }) {
    final sorted = [...notes]
      ..sort((a, b) {
        final byBook = a.bookId.compareTo(b.bookId);
        if (byBook != 0) return byBook;
        int line(PersonalNote n) =>
            n.hasLocation ? (n.lineNumber ?? 0) : 1 << 30;
        final byLine = line(a).compareTo(line(b));
        if (byLine != 0) return byLine;
        final byTime = a.hasLocation
            ? a.createdAt.compareTo(b.createdAt)
            : b.updatedAt.compareTo(a.updatedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    final blocks = <PrintBlock>[];
    String? currentBook;
    String? currentRef;
    String? currentSourceLink;
    for (final note in sorted) {
      final body = _noteWordBlocks(note);
      if (body.isEmpty) continue;

      if (note.bookId != currentBook) {
        currentBook = note.bookId;
        currentRef = null;
        currentSourceLink = null;
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
      final link = note.hasLocation ? sourceLink?.call(note) : null;
      if (refLabel != null &&
          (refLabel != currentRef || link != currentSourceLink)) {
        currentRef = refLabel;
        currentSourceLink = link;
        blocks.add(
          PrintBlock(
            kind: PrintBlockKind.heading,
            headingLevel: 2,
            text: _escapeHtml(refLabel),
            sourceLink: link,
          ),
        );
      }

      blocks.addAll(body);
    }
    return blocks;
  }

  /// גוף הערה כבלוקי טקסט, כשהטקסט שסומן או כותרת ההערה מודגשים בראשה.
  List<PrintBlock> _noteWordBlocks(PersonalNote note) {
    final paragraphs = _noteHtmlParagraphs(note);
    while (paragraphs.isNotEmpty && paragraphs.last.trim().isEmpty) {
      paragraphs.removeLast();
    }
    if (paragraphs.isEmpty) return const [];

    var dibur = note.anchorText?.trim() ?? '';
    final displayTitle = note.displayTitle?.trim() ?? '';
    // טקסט העוגן מנורמל לצורך חיפוש ועלול לאבד גרש וגרשיים. כשהכותרת
    // משקפת את אותה בחירה, מייצאים את הטקסט כפי שהמשתמש בחר אותו.
    // בהערות ישנות עם כותרת שונה מעדיפים את העוגן המדויק.
    if (dibur.isNotEmpty && displayTitle.isNotEmpty) {
      final normalizedAnchor = normalizeAnchorText(dibur);
      if (normalizedAnchor.isNotEmpty &&
          normalizeAnchorText(displayTitle) == normalizedAnchor) {
        dibur = displayTitle;
      }
    }
    if (dibur.isEmpty) dibur = displayTitle;
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
    // קובץ גיבוי של האפליקציה (includes, 1.0 או 2.0) מקבץ הערות לפי ספר;
    // קובץ ייצוא 1.0 שייך למערכת ההערות הקודמת.
    if (!version.startsWith('2') && decoded['includes'] == null) {
      throw Exception('גרסת ייצוא לא נתמכת: $version');
    }

    final notes = [
      for (final item in decoded['notes'] as List<dynamic>? ?? const [])
        if (item is Map<String, dynamic>)
          for (final json in item['notes'] as List<dynamic>? ?? [item])
            (
              PersonalNote.fromJson(json as Map<String, dynamic>),
              json.containsKey('anchorText'),
              json.containsKey('pdfAnchor'),
            ),
    ];
    return _database.batchNotifications((batch) async {
      int inserted = 0;
      int updated = 0;
      int skipped = 0;
      int duplicated = 0;

      for (final (note, hasAnchorText, hasPdfAnchor) in notes) {
        final existing = await _database.getNote(note.id);

        if (existing == null) {
          await batch.insertNote(note);
          inserted++;
          continue;
        }

        switch (strategy) {
          case NotesImportConflictStrategy.skip:
            skipped++;
            break;
          case NotesImportConflictStrategy.overwrite:
          case NotesImportConflictStrategy.merge:
            if (strategy == NotesImportConflictStrategy.merge &&
                !note.updatedAt.isAfter(existing.updatedAt)) {
              skipped++;
              break;
            }
            // שדה חסר בגיבוי ישן אינו מבטל עוגן מקומי; null מפורש כן.
            // שומרים עוגן רק כשהספר, המיקום והקשר המקור עדיין תואמים.
            final preserveAnchor =
                !hasAnchorText &&
                existing.isWordAnchored &&
                note.bookId == existing.bookId &&
                note.lineNumber == existing.lineNumber &&
                note.status == existing.status &&
                note.displayTitle == existing.displayTitle &&
                (note.hasLocation ||
                    note.lastKnownLineNumber == existing.lastKnownLineNumber);
            var updatedNote = preserveAnchor
                ? note
                      .copyWith(clearAnchor: true)
                      .copyWith(
                        anchorText: existing.anchorText,
                        anchorPrefix: existing.anchorPrefix,
                        anchorSuffix: existing.anchorSuffix,
                        anchorStart: existing.anchorStart,
                        anchorEnd: existing.anchorEnd,
                      )
                : note;
            if (!hasPdfAnchor &&
                existing.pdfAnchor != null &&
                note.bookId == existing.bookId &&
                note.lineNumber == existing.lineNumber &&
                note.displayTitle == existing.displayTitle &&
                note.status == existing.status &&
                (note.hasLocation ||
                    note.lastKnownLineNumber == existing.lastKnownLineNumber)) {
              updatedNote = updatedNote.copyWith(pdfAnchor: existing.pdfAnchor);
            }
            await batch.updateNote(updatedNote);
            updated++;
            break;
          case NotesImportConflictStrategy.keepBoth:
            await batch.insertNote(note.copyWith(id: _generateId()));
            duplicated++;
            break;
        }
      }

      // קובץ מגרסה ישנה מחזיק הערות של ספר אישי תחת הכותרת בלבד.
      if (inserted + updated + duplicated > 0) {
        await _database.setUserBookKeysPending(true);
      }
      return NotesImportSummary(
        inserted: inserted,
        updated: updated,
        skipped: skipped,
        duplicated: duplicated,
      );
    });
  }

  String _generateId() {
    final timestamp = _now().microsecondsSinceEpoch;
    // Imports can create several copies within the same clock tick.
    final randomPart = List.generate(
      4,
      (_) => _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
    return 'pn_${timestamp}_$randomPart';
  }
}
