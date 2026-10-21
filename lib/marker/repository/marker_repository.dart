import 'dart:convert';
import 'dart:math';

import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/storage/marker_changes.dart';
import 'package:otzaria/marker/storage/marker_database.dart';

/// סימון חדש לפני שמירה: מה שנבחר בספר.
class MarkerDraft {
  final String bookTitle;
  final String? bookUid;
  final List<MarkerSegment> segments;
  final String text;
  final String? ref;

  /// טיוטה מספר PDF; [segments] לפי מספר עמוד.
  final bool pdf;

  const MarkerDraft({
    required this.bookTitle,
    this.bookUid,
    required this.segments,
    required this.text,
    this.ref,
    this.pdf = false,
  });
}

enum MarkerCreateOutcome {
  created,

  /// אותו טווח כבר סומן — הצבע שלו הוחלף במקום ליצור כפילות.
  recolored,

  /// סימון שעוגנו אבד סומן מחדש באותו מקום, והעוגן שלו הוחלף.
  repaired,

  /// אותו טווח כבר סומן באותו צבע.
  unchanged,
}

/// הסימון השתנה בחלון אחר מאז שנטען לעריכה.
class MarkerConflictException implements Exception {
  final MarkerHighlight current;

  const MarkerConflictException(this.current);
}

/// עמוד ברשימת המרקר, עם הספירות והמסננים שלצדו.
typedef MarkerPage = ({
  List<MarkerHighlight> items,
  MarkerCounts counts,
  List<MarkerBookCount> books,
  List<({String tag, int count})> tags,
});

/// כל מה שהגיבוי שומר מהמסד.
typedef MarkerBackupRows = ({
  List<Map<String, dynamic>> highlights,
  List<MarkerLegacyRef> importedLegacy,
});

class MarkerImportSummary {
  final int added;
  final int skipped;

  const MarkerImportSummary({required this.added, required this.skipped});
}

class MarkerRepository {
  MarkerRepository({
    MarkerDatabase? database,
    MarkerChanges? changes,
    DateTime Function()? clock,
  }) : _db = database ?? MarkerDatabase.instance,
       _changes = changes ?? MarkerChanges.instance,
       _clock = clock ?? DateTime.now;

  final MarkerDatabase _db;
  final MarkerChanges _changes;
  final DateTime Function() _clock;
  static final Random _random = Random.secure();

  static String newId(DateTime now) {
    final micros = now.microsecondsSinceEpoch.toRadixString(36);
    final random = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return 'mk-$micros-$random';
  }

  /// במילישניות, כמו שהמסד שומר — אחרת רשומה שנשמרה אינה שווה לזו שנקראת.
  DateTime get _now => DateTime.fromMillisecondsSinceEpoch(
    _clock().millisecondsSinceEpoch,
    isUtc: true,
  );

  // ===== קריאה =====

  /// קריאה מהמסד אם הוא קיים; כשאין עדיין מסד התוצאה היא [empty].
  Future<T> _read<T>(T Function(Database db) body, T empty) async {
    final db = await _db.existingDatabase;
    return db == null ? empty : body(db);
  }

  /// מעל זה ספר נקרא ב-isolate: אלפי סימונים בספר אחד עוצרים את פתיחתו.
  static const int _backgroundBookRows = 500;

  /// [pdf] — הסימונים של ספר ה-PDF בשם הזה, ולא של ספר הטקסט.
  Future<List<MarkerHighlight>> loadBook({
    required String bookTitle,
    String? bookUid,
    bool pdf = false,
  }) async {
    final db = await _db.existingDatabase;
    if (db == null) return const [];
    final book = (title: bookTitle, uid: bookUid, pdf: pdf);
    if (_db.countBook(db, bookTitle: bookTitle, bookUid: bookUid, pdf: pdf) <=
        _backgroundBookRows) {
      return _readBook(_db, db, book);
    }
    return await _db.readInBackground(_readBook, book) ?? const [];
  }

  Future<MarkerHighlight?> get(String id) =>
      _read((db) => _db.get(db, id), null);

  Future<List<MarkerHighlight>> getMany(Iterable<String> ids) =>
      _read((db) => _db.getMany(db, ids), const []);

  /// עמוד של הרשימה, ב-isolate (ייצוא קורא את כל ההתאמות).
  Future<List<MarkerHighlight>> query(
    MarkerQuery query, {
    required int offset,
    required int limit,
    List<String> colorOrder = const [],
  }) async =>
      await _db.readInBackground(_readQuery, (
        query: query,
        offset: offset,
        limit: limit,
        colorOrder: colorOrder,
      )) ??
      const [];

  /// העמוד הראשון של הרשימה עם הספירות, ב-isolate: עם אלפי סימונים
  /// הספירות לוקחות עשרות מילישניות.
  Future<MarkerPage> loadPage(
    MarkerQuery query, {
    required int limit,
    List<String> colorOrder = const [],
  }) async =>
      await _db.readInBackground(_readPage, (
        query: query,
        limit: limit,
        colorOrder: colorOrder,
      )) ??
      (
        items: const <MarkerHighlight>[],
        counts: const MarkerCounts(),
        books: const <MarkerBookCount>[],
        tags: const <({String tag, int count})>[],
      );

  /// כל הסימונים כקובץ גיבוי מקודד, ב-isolate: עם עשרות אלפי סימונים
  /// הקידוד לבדו עוצר את החלונות. [envelope] — שאר שדות הקובץ.
  Future<String> backupJson(
    Map<String, Object?> envelope, {
    bool indent = false,
  }) async =>
      await _db.readInBackground(_backupJson, (
        envelope: envelope,
        indent: indent,
      )) ??
      _encodeBackupJson(envelope, (
        highlights: const [],
        importedLegacy: const [],
      ), indent);

  Future<MarkerCounts> counts(MarkerQuery query) =>
      _read((db) => _db.counts(db, query), const MarkerCounts());

  Future<List<MarkerBookCount>> books() => _read(_db.books, const []);

  Future<List<({String tag, int count})>> tags() => _read(_db.tags, const []);

  Future<int> countAll() => _read(_db.countAll, 0);

  Future<List<MarkerHighlight>> all() => _read(_db.all, const []);

  // ===== כתיבה =====

  /// שומר סימון בצבע [color]. טווח שכבר סומן בדיוק מקבל את הצבע החדש ושומר
  /// על ההערה והתגיות שלו, במקום להיווצר פעמיים.
  Future<({MarkerHighlight highlight, MarkerCreateOutcome outcome})> create(
    MarkerDraft draft,
    MarkerColor color,
  ) async {
    if (draft.segments.isEmpty) {
      throw ArgumentError.value(draft, 'draft', 'no segments');
    }
    final segments = [...draft.segments]
      ..sort((a, b) => a.sectionIndex.compareTo(b.sectionIndex));
    final now = _now;
    final result = await _db.transaction((db) {
      final existing = _sameRange(db, draft, segments);
      if (existing != null && !_anchorsMatch(existing.segments, segments)) {
        final repaired = existing.copyWith(
          segments: [
            for (var i = 0; i < segments.length; i++)
              MarkerSegment(
                sectionIndex: segments[i].sectionIndex,
                range: segments[i].range,
                legacyId: existing.segments[i].legacyId,
              ),
          ],
          text: draft.text,
          colorId: color.id,
          colorHex: color.hex,
          updatedAt: now,
          version: existing.version + 1,
        );
        _db.upsert(db, repaired);
        return (highlight: repaired, outcome: MarkerCreateOutcome.repaired);
      }
      if (existing != null) {
        if (existing.colorId == color.id) {
          return (highlight: existing, outcome: MarkerCreateOutcome.unchanged);
        }
        final updated = existing.copyWith(
          colorId: color.id,
          colorHex: color.hex,
          updatedAt: now,
          version: existing.version + 1,
        );
        _db.upsert(db, updated);
        return (highlight: updated, outcome: MarkerCreateOutcome.recolored);
      }
      final highlight = MarkerHighlight(
        id: newId(now),
        bookTitle: draft.bookTitle,
        bookUid: draft.bookUid,
        segments: segments,
        pdf: draft.pdf,
        text: draft.text,
        ref: draft.ref,
        colorId: color.id,
        colorHex: color.hex,
        createdAt: now,
        updatedAt: now,
      );
      _db.upsert(db, highlight);
      return (highlight: highlight, outcome: MarkerCreateOutcome.created);
    });
    if (result.outcome != MarkerCreateOutcome.unchanged) {
      _changes.notify(MarkerChange.saved([result.highlight]));
    }
    return result;
  }

  /// סימון קיים באותו טווח בדיוק, באותו ספר — כפי שהקורא מציג אותו.
  MarkerHighlight? _sameRange(
    Database db,
    MarkerDraft draft,
    List<MarkerSegment> segments,
  ) {
    for (final candidate in _db.loadBook(
      db,
      bookTitle: draft.bookTitle,
      bookUid: draft.bookUid,
      span: (
        first: segments.first.sectionIndex,
        last: segments.last.sectionIndex,
      ),
      pdf: draft.pdf,
    )) {
      // ספר אחר באותה כותרת (שני מזהים יציבים) אינו נוגע בסימון הזה.
      if (markerOtherBook(candidate.bookUid, draft.bookUid)) continue;
      if (!candidate.sameRangeAs(segments)) continue;
      // מזהה שנגזר מנתיב משתנה כשהספרייה עוברת מקום: זה אותו ספר, והסימון
      // שמוצג בו מתעדכן במקום להיווצר פעמיים. עותק אחר של הקובץ שהטקסט בו
      // שונה אינו מקבל את הסימון — רק טקסט זהה הוא אותו מקום.
      final uid = candidate.bookUid;
      if (uid != null &&
          draft.bookUid != null &&
          uid != draft.bookUid &&
          !_sameText(candidate.segments, segments)) {
        continue;
      }
      return candidate;
    }
    return null;
  }

  /// אותו טקסט בכל המקטעים.
  static bool _sameText(List<MarkerSegment> stored, List<MarkerSegment> fresh) {
    for (var i = 0; i < stored.length; i++) {
      if (stored[i].range.exactText != fresh[i].range.exactText) return false;
    }
    return true;
  }

  /// אותם גבולות עם עוגן תקין ואותו טקסט. אחרת הטקסט שבמקום השתנה, והסימון
  /// החדש מתקן את הישן במקום להיחשב לכפילות שלו.
  static bool _anchorsMatch(
    List<MarkerSegment> stored,
    List<MarkerSegment> fresh,
  ) {
    for (var i = 0; i < stored.length; i++) {
      if (stored[i].status.needsRepair ||
          stored[i].range.exactText != fresh[i].range.exactText) {
        return false;
      }
    }
    return true;
  }

  Future<List<MarkerHighlight>> setColor(
    Iterable<String> ids,
    MarkerColor color,
  ) => _updateMany(
    ids,
    (highlight) => highlight.colorId == color.id
        ? null
        : highlight.copyWith(colorId: color.id, colorHex: color.hex),
  );

  Future<List<MarkerHighlight>> setFavorite(
    Iterable<String> ids,
    bool favorite,
  ) => _updateMany(
    ids,
    (highlight) => highlight.favorite == favorite
        ? null
        : highlight.copyWith(favorite: favorite),
  );

  Future<List<MarkerHighlight>> setTags(String id, List<String> tags) =>
      _updateMany([id], (highlight) {
        final normalized = MarkerHighlight.normalizeTags(tags);
        return _sameList(normalized, highlight.tags)
            ? null
            : highlight.copyWith(tags: normalized);
      });

  Future<List<MarkerHighlight>> addTags(
    Iterable<String> ids,
    List<String> tags,
  ) => _updateMany(ids, (highlight) {
    final merged = MarkerHighlight.normalizeTags([...highlight.tags, ...tags]);
    return _sameList(merged, highlight.tags)
        ? null
        : highlight.copyWith(tags: merged);
  });

  /// [expectedVersion] — הגרסה שנפתחה לעריכה. גרסה אחרת פירושה שהסימון
  /// השתנה בחלון אחר, ואז נזרק [MarkerConflictException] בלי לשמור.
  Future<MarkerHighlight?> setNote(
    String id,
    MarkerNote? note, {
    int? expectedVersion,
  }) async {
    final updated = await _updateMany([id], (highlight) {
      if (expectedVersion != null && highlight.version != expectedVersion) {
        throw MarkerConflictException(highlight);
      }
      final empty = note == null || note.plain.trim().isEmpty;
      if (empty && highlight.note == null) return null;
      return empty
          ? highlight.copyWith(clearNote: true)
          : highlight.copyWith(note: note);
    });
    return updated.isEmpty ? await get(id) : updated.single;
  }

  /// מחליף את גבולות הסימון. [expectedVersion] כמו ב-[setNote].
  /// [moveTo] — מראה המקום החדש, כשהסימון עובר למקום אחר (גם null).
  Future<MarkerHighlight?> setRange(
    String id,
    List<MarkerSegment> segments,
    String text, {
    required int expectedVersion,
    ({String? ref})? moveTo,
  }) async {
    final updated = await _updateMany([id], (highlight) {
      if (highlight.version != expectedVersion) {
        throw MarkerConflictException(highlight);
      }
      return highlight.copyWith(
        segments: List.unmodifiable(segments),
        text: text,
        ref: moveTo?.ref,
        clearRef: moveTo != null && moveTo.ref == null,
      );
    });
    return updated.isEmpty ? null : updated.single;
  }

  /// מוחק ומחזיר את הרשומות שנמחקו, לביטול.
  Future<List<MarkerHighlight>> delete(Iterable<String> ids) async {
    final removed = await _db.transaction((db) {
      final found = _db.getMany(db, ids);
      _db.delete(db, found.map((highlight) => highlight.id));
      return found;
    });
    if (removed.isNotEmpty) {
      _changes.notify(MarkerChange.removed(removed));
    }
    return removed;
  }

  /// מחזיר רשומות שנמחקו, עם אותם מזהים.
  Future<void> restore(List<MarkerHighlight> highlights) async {
    if (highlights.isEmpty) return;
    await _db.transaction((db) {
      for (final highlight in highlights) {
        _db.upsert(db, highlight);
      }
    });
    _changes.notify(MarkerChange.saved(highlights));
  }

  /// שומר עוגנים שחושבו מחדש, בלי הודעה (כל חלון מעגן בעצמו). [versions] —
  /// הגרסה שעוגנה; עריכה שנשמרה בינתיים בחלון אחר אינה נדרסת.
  Future<void> saveAnchors(
    Map<String, List<MarkerSegment>> segmentsById, {
    Map<String, int> versions = const {},
  }) async {
    if (segmentsById.isEmpty) return;
    // כתיבה ארוכה בחלון אחר: מוותרים, והעיגון יחושב שוב בציור הבא.
    await _db.tryTransaction((db) {
      for (final entry in segmentsById.entries) {
        _db.updateSegments(
          db,
          entry.key,
          entry.value,
          MarkerHighlight.statusOf(entry.value),
          version: versions[entry.key],
        );
      }
    });
  }

  /// מחליף את [from] ב-[to] בכל הסימונים. [to] ריק מוחק את התגית.
  Future<int> replaceTag(String from, String? to) async {
    final key = MarkerHighlight.tagKey(from);
    final changed = await _db.transaction((db) {
      final ids = _db.idsWithTag(db, key);
      final now = _now;
      final changed = <MarkerHighlight>[];
      for (final highlight in _db.getMany(db, ids)) {
        final tags = MarkerHighlight.normalizeTags([
          for (final tag in highlight.tags)
            if (MarkerHighlight.tagKey(tag) == key) ?to else tag,
        ]);
        final updated = highlight.copyWith(
          tags: tags,
          updatedAt: now,
          version: highlight.version + 1,
        );
        _db.upsert(db, updated);
        changed.add(updated);
      }
      return changed;
    });
    if (changed.isNotEmpty) {
      _changes.notify(MarkerChange.saved(changed));
    }
    return changed.length;
  }

  /// מוסיף רשומות מיובאות בטרנזקציה אחת. מזהה שכבר קיים מדולג, ולכן הרצה
  /// חוזרת של אותו ייבוא אינה יוצרת כפילויות.
  Future<MarkerImportSummary> importHighlights(
    List<MarkerHighlight> highlights, {
    List<MarkerLegacyRef> importedLegacy = const [],
  }) async {
    final added = await _db.writeInBackground(_importRows, (
      highlights: highlights,
      importedLegacy: importedLegacy,
    ));
    // גם מזהי התוסף שנרשמו בלבד משנים את מה שהקורא מסתיר.
    if (added > 0 || importedLegacy.isNotEmpty) {
      _changes.notify(const MarkerChange.all());
    }
    return MarkerImportSummary(
      added: added,
      skipped: highlights.length - added,
    );
  }

  /// שחזור מגיבוי של התוכנה: רשומה מהגיבוי מחליפה את המקומית, אלא אם
  /// [keepNewerLocal] והמקומית נערכה אחריה. סימון שאינו בגיבוי אינו נמחק.
  Future<int> restoreBackup(
    List<MarkerHighlight> highlights, {
    required bool keepNewerLocal,
    List<MarkerLegacyRef> importedLegacy = const [],
  }) async {
    final written = await _db.writeInBackground(_restoreRows, (
      highlights: highlights,
      importedLegacy: importedLegacy,
      keepNewerLocal: keepNewerLocal,
    ));
    if (written > 0 || importedLegacy.isNotEmpty) {
      _changes.notify(const MarkerChange.all());
    }
    return written;
  }

  /// כל ההדגשות של התוסף הישן שיובאו אי פעם, בכל הספרים.
  Future<Set<String>> allImportedLegacyIds() => _read(
    (db) => {for (final ref in _db.allImportedLegacy(db)) ref.id},
    <String>{},
  );

  Future<Set<String>> existingIds(Iterable<String> ids) =>
      _read((db) => _db.existingIds(db, ids), <String>{});

  Future<List<MarkerHighlight>> _updateMany(
    Iterable<String> ids,
    MarkerHighlight? Function(MarkerHighlight highlight) transform,
  ) async {
    final now = _now;
    final updated = await _db.transaction((db) {
      final result = <MarkerHighlight>[];
      for (final highlight in _db.getMany(db, ids)) {
        final next = transform(highlight);
        if (next == null) continue;
        final stamped = next.copyWith(
          updatedAt: now,
          version: highlight.version + 1,
        );
        _db.upsert(db, stamped);
        result.add(stamped);
      }
      return result;
    });
    if (updated.isNotEmpty) {
      _changes.notify(MarkerChange.saved(updated));
    }
    return updated;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

List<MarkerHighlight> _readQuery(
  MarkerDatabase reader,
  Database db,
  ({MarkerQuery query, int offset, int limit, List<String> colorOrder}) arg,
) => reader.query(
  db,
  arg.query,
  offset: arg.offset,
  limit: arg.limit,
  colorOrder: arg.colorOrder,
);

int _importRows(
  MarkerDatabase writer,
  Database db,
  ({
    List<MarkerHighlight> highlights,
    List<MarkerLegacyRef> importedLegacy,
  })
  arg,
) {
  writer.recordLegacyIds(db, arg.importedLegacy);
  final existing = writer.existingIds(db, arg.highlights.map((h) => h.id));
  var added = 0;
  for (final highlight in arg.highlights) {
    writer.recordImportedLegacy(db, highlight);
    if (existing.contains(highlight.id)) continue;
    writer.upsert(db, highlight);
    existing.add(highlight.id);
    added++;
  }
  return added;
}

int _restoreRows(
  MarkerDatabase writer,
  Database db,
  ({
    List<MarkerHighlight> highlights,
    List<MarkerLegacyRef> importedLegacy,
    bool keepNewerLocal,
  })
  arg,
) {
  writer.recordLegacyIds(db, arg.importedLegacy);
  final local = {
    for (final highlight in writer.getMany(
      db,
      arg.highlights.map((h) => h.id),
    ))
      highlight.id: highlight,
  };
  var written = 0;
  for (final highlight in arg.highlights) {
    final existing = local[highlight.id];
    if (arg.keepNewerLocal &&
        existing != null &&
        !highlight.updatedAt.isAfter(existing.updatedAt)) {
      continue;
    }
    writer.recordImportedLegacy(db, highlight);
    // גרסה חדשה, כדי שעורך שנפתח לפני השחזור יזהה שהרשומה הוחלפה.
    writer.upsert(
      db,
      existing == null
          ? highlight
          : highlight.copyWith(
              version: max(existing.version, highlight.version) + 1,
            ),
    );
    written++;
  }
  return written;
}

List<MarkerHighlight> _readBook(
  MarkerDatabase reader,
  Database db,
  ({String title, String? uid, bool pdf}) book,
) => reader.loadBook(
  db,
  bookTitle: book.title,
  bookUid: book.uid,
  pdf: book.pdf,
);

MarkerPage _readPage(
  MarkerDatabase reader,
  Database db,
  ({MarkerQuery query, int limit, List<String> colorOrder}) arg,
) => (
  items: reader.query(
    db,
    arg.query,
    offset: 0,
    limit: arg.limit,
    colorOrder: arg.colorOrder,
  ),
  counts: reader.counts(db, arg.query),
  books: reader.books(db),
  tags: reader.tags(db),
);

String _backupJson(
  MarkerDatabase reader,
  Database db,
  ({Map<String, Object?> envelope, bool indent}) arg,
) => _encodeBackupJson(arg.envelope, _readBackup(reader, db, null), arg.indent);

String _encodeBackupJson(
  Map<String, Object?> envelope,
  MarkerBackupRows rows,
  bool indent,
) => (indent ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
    .convert({
      ...envelope,
      'highlights': rows.highlights,
      if (rows.importedLegacy.isNotEmpty)
        'importedLegacy': [
          for (final ref in rows.importedLegacy)
            {'id': ref.id, 'book': ref.book},
        ],
    });

MarkerBackupRows _readBackup(MarkerDatabase reader, Database db, void _) => (
  highlights: [for (final highlight in reader.all(db)) highlight.toJson()],
  importedLegacy: reader.allImportedLegacy(db),
);
