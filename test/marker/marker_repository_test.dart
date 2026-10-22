import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/storage/marker_changes.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/marker/storage/marker_search_text.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

import 'marker_test_helpers.dart';

const _line = 'בראשית ברא אלהים את השמים ואת הארץ';
const _line2 = 'והארץ היתה תהו ובהו וחשך על פני תהום';

void main() {
  late MarkerDatabase db;
  late MarkerRepository repository;
  late List<MarkerChange> changes;

  setUp(() {
    final store = openTestMarkerStore();
    db = store.db;
    repository = store.repository;
    changes = [];
    store.changes.stream.listen(changes.add);
  });

  tearDown(() => db.close());

  group('schema', () {
    test('a new database is created at the current schema version', () async {
      final raw = await db.database;
      expect(
        raw.select('PRAGMA user_version').first.values.first,
        MarkerDatabase.schemaVersion,
      );
    });

    test(
      'a version 1 database keeps its marks and gets the new indexes',
      () async {
        await repository.importHighlights([
          highlightFor('a', [segmentFor(0, _line, 'את')]),
        ]);
        final raw = await db.database;
        raw
          ..execute('DROP INDEX idx_marker_uid_section')
          ..execute('DROP INDEX idx_marker_created_id')
          ..execute(
            'CREATE INDEX idx_marker_book_uid ON marker_highlights(book_uid) '
            'WHERE book_uid IS NOT NULL',
          )
          ..execute(
            'CREATE INDEX idx_marker_created ON marker_highlights(created_at)',
          )
          ..execute('PRAGMA user_version = 1');
        final migrated = MarkerRepository(
          database: MarkerDatabase.withDatabase(raw),
          changes: MarkerChanges(),
        );
        expect(raw.select('PRAGMA user_version').first.values.first, 2);
        final indexes = {
          for (final row in raw.select(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'idx_marker%'",
          ))
            row['name'] as String,
        };
        expect(indexes, contains('idx_marker_uid_section'));
        expect(indexes, contains('idx_marker_created_id'));
        expect(indexes, isNot(contains('idx_marker_book_uid')));
        expect(indexes, isNot(contains('idx_marker_created')));
        expect((await migrated.get('a'))?.text, 'טקסט');
      },
    );

    test('a newer schema is left untouched', () {
      final raw = sqlite3.openInMemory()..execute('PRAGMA user_version = 9');
      MarkerDatabase.withDatabase(raw);
      expect(
        raw.select("SELECT name FROM sqlite_master WHERE type = 'table'"),
        isEmpty,
      );
      raw.close();
    });

    test('a database missing a table at the current version is completed', () {
      final raw = sqlite3.openInMemory()..execute('PRAGMA user_version = 1');
      MarkerDatabase.withDatabase(raw);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name = 'marker_imported_legacy'",
        ),
        hasLength(1),
      );
      raw.close();
    });

    test('a library move in another window refuses writes', () async {
      final raw = sqlite3.openInMemory();
      final moving = MarkerDatabase.withDatabase(raw);
      final locked = MarkerRepository(
        database: moving,
        changes: MarkerChanges(),
      );
      moving.lockForStorageMove('move-1');
      await expectLater(
        locked.importHighlights([
          highlightFor('x', [segmentFor(0, _line, 'את')]),
        ]),
        throwsA(isA<MarkerStorageMovingException>()),
      );
    });

    test('a newer schema refuses writes', () async {
      final raw = sqlite3.openInMemory()..execute('PRAGMA user_version = 9');
      final newer = MarkerRepository(
        database: MarkerDatabase.withDatabase(raw),
        changes: MarkerChanges(),
      );
      await expectLater(
        newer.importHighlights([
          highlightFor('x', [segmentFor(0, _line, 'את')]),
        ]),
        throwsA(isA<MarkerNewerSchemaException>()),
      );
      raw.close();
    });
  });

  group('create', () {
    test('stores a mark with its anchor and notifies the book', () async {
      final result = await repository.create(
        draftFor([segmentFor(0, _line, 'ברא אלהים')], text: 'ברא אלהים'),
        colorOf('green'),
      );
      expect(result.outcome, MarkerCreateOutcome.created);
      final loaded = await repository.loadBook(
        bookTitle: 'בראשית',
        bookUid: 'id:1',
      );
      expect(loaded, hasLength(1));
      expect(loaded.single.segments.single.range.exactText, 'ברא אלהים');
      expect(loaded.single.colorId, 'green');
      expect(changes.single.affects('בראשית', null), isTrue);
    });

    test(
      'the same text after a library move recolours the mark, not a copy',
      () async {
        const before = 'בראשית|תנך|pdf|C:/a.pdf';
        const after = 'בראשית|תנך|pdf|D:/a.pdf';
        final first = await repository.create(
          draftFor([segmentFor(0, _line, 'אלהים')], uid: before),
          colorOf('yellow'),
        );
        final second = await repository.create(
          draftFor([segmentFor(0, _line, 'אלהים')], uid: after),
          colorOf('green'),
        );
        expect(second.outcome, MarkerCreateOutcome.recolored);
        expect(second.highlight.id, first.highlight.id);
        // הסימון נשאר של הקובץ שבו נוצר.
        expect(second.highlight.bookUid, before);
        expect(await repository.loadBook(bookTitle: 'בראשית'), hasLength(1));
      },
    );

    test(
      'another file of the same title with other text there is a new mark',
      () async {
        const fileA = 'בראשית|תנך|pdf|C:/a.pdf';
        const fileB = 'בראשית|תנך|pdf|C:/b.pdf';
        final other = _line.replaceFirst('אלהים', 'אדמות');
        final first = await repository.create(
          draftFor([segmentFor(0, _line, 'אלהים')], uid: fileA),
          colorOf('yellow'),
        );
        final second = await repository.create(
          draftFor([segmentFor(0, other, 'אדמות')], uid: fileB),
          colorOf('green'),
        );
        expect(second.outcome, MarkerCreateOutcome.created);
        final kept = (await repository.get(first.highlight.id))!;
        expect(kept.colorId, 'yellow');
        expect(kept.segments.single.range.exactText, 'אלהים');
      },
    );

    test('a book with another stable id is never the same mark', () async {
      final first = await repository.create(
        draftFor([segmentFor(0, _line, 'אלהים')], uid: 'id:1'),
        colorOf('yellow'),
      );
      final second = await repository.create(
        draftFor([segmentFor(0, _line, 'אלהים')], uid: 'id:2'),
        colorOf('green'),
      );
      expect(second.outcome, MarkerCreateOutcome.created);
      expect((await repository.get(first.highlight.id))!.colorId, 'yellow');
    });

    test(
      'the same range again changes the colour, not a second mark',
      () async {
        final draft = draftFor([segmentFor(0, _line, 'אלהים')]);
        final first = await repository.create(draft, colorOf('yellow'));
        await repository.setNote(
          first.highlight.id,
          const MarkerNote(content: 'הערה', plain: 'הערה'),
        );
        final second = await repository.create(draft, colorOf('blue'));
        expect(second.outcome, MarkerCreateOutcome.recolored);
        expect(second.highlight.id, first.highlight.id);
        final loaded = await repository.loadBook(bookTitle: 'בראשית');
        expect(loaded, hasLength(1));
        expect(loaded.single.colorId, 'blue');
        expect(loaded.single.note?.plain, 'הערה');
      },
    );

    test('the same range in the same colour changes nothing', () async {
      final draft = draftFor([segmentFor(0, _line, 'אלהים')]);
      await repository.create(draft, colorOf('yellow'));
      changes.clear();
      final again = await repository.create(draft, colorOf('yellow'));
      expect(again.outcome, MarkerCreateOutcome.unchanged);
      expect(changes, isEmpty);
    });

    test('marking a broken mark again repairs its anchor', () async {
      final draft = draftFor([segmentFor(0, _line, 'אלהים')]);
      final first = await repository.create(draft, colorOf('yellow'));
      await repository.saveAnchors({
        first.highlight.id: [
          first.highlight.segments.single.copyWith(
            status: MarkerAnchorStatus.stale,
          ),
        ],
      });
      final again = await repository.create(draft, colorOf('yellow'));
      expect(again.outcome, MarkerCreateOutcome.repaired);
      expect(again.highlight.id, first.highlight.id);
      final loaded = await repository.get(first.highlight.id);
      expect(loaded!.status, MarkerAnchorStatus.active);
    });

    test('overlapping marks coexist', () async {
      await repository.create(
        draftFor([segmentFor(0, _line, 'ברא אלהים את')]),
        colorOf('yellow'),
      );
      await repository.create(
        draftFor([segmentFor(0, _line, 'אלהים')]),
        colorOf('green'),
      );
      expect(await repository.loadBook(bookTitle: 'בראשית'), hasLength(2));
    });

    test(
      'a mark across paragraphs is one record with a segment each',
      () async {
        await repository.create(
          draftFor([
            segmentFor(1, _line2, 'והארץ היתה'),
            segmentFor(0, _line, 'ואת הארץ'),
          ]),
          colorOf('red'),
        );
        final mark = (await repository.loadBook(bookTitle: 'בראשית')).single;
        expect(mark.segments.map((s) => s.sectionIndex), [0, 1]);
        expect(mark.sectionStart, 0);
        expect(mark.sectionEnd, 1);
      },
    );

    test(
      'a book with the same title but another uid is a different book',
      () async {
        final draft = draftFor([segmentFor(0, _line, 'אלהים')]);
        await repository.create(draft, colorOf('yellow'));
        final other = await repository.create(
          draftFor([segmentFor(0, _line, 'אלהים')], uid: 'id:2'),
          colorOf('blue'),
        );
        expect(other.outcome, MarkerCreateOutcome.created);
      },
    );
  });

  group('updates', () {
    late MarkerHighlight mark;

    setUp(() async {
      mark = (await repository.create(
        draftFor([segmentFor(0, _line, 'השמים')]),
        colorOf('yellow'),
      )).highlight;
      changes.clear();
    });

    test('colour, favourite and tags bump the version', () async {
      await repository.setColor([mark.id], colorOf('green'));
      await repository.setFavorite([mark.id], true);
      await repository.setTags(mark.id, ['לעיון, הלכה', 'לְעִיּוּן']);
      final loaded = (await repository.get(mark.id))!;
      expect(loaded.colorId, 'green');
      expect(loaded.favorite, isTrue);
      expect(loaded.tags, ['לעיון', 'הלכה']);
      expect(loaded.version, mark.version + 3);
      expect(changes, hasLength(3));
    });

    test('a note saved against an older version is refused', () async {
      await repository.setNote(
        mark.id,
        const MarkerNote(content: 'א', plain: 'א'),
      );
      expect(
        () => repository.setNote(
          mark.id,
          const MarkerNote(content: 'ב', plain: 'ב'),
          expectedVersion: mark.version,
        ),
        throwsA(isA<MarkerConflictException>()),
      );
      expect((await repository.get(mark.id))!.note?.plain, 'א');
    });

    test('an empty note removes the note', () async {
      await repository.setNote(
        mark.id,
        const MarkerNote(
          content: 'א',
          plain: 'א',
          format: PersonalNoteContentFormat.plain,
        ),
      );
      await repository.setNote(mark.id, null);
      expect((await repository.get(mark.id))!.note, isNull);
    });

    test('updating a mark deleted elsewhere returns null', () async {
      await repository.delete([mark.id]);
      expect(
        await repository.setNote(
          mark.id,
          const MarkerNote(content: 'א', plain: 'א'),
        ),
        isNull,
      );
    });

    test('delete returns the records and restore brings them back', () async {
      await repository.setTags(mark.id, ['תגית']);
      final removed = await repository.delete([mark.id]);
      expect(await repository.get(mark.id), isNull);
      await repository.restore(removed);
      final restored = (await repository.get(mark.id))!;
      expect(restored.tags, ['תגית']);
      expect(restored.createdAt, mark.createdAt);
    });

    test('renaming a tag merges it into an existing one', () async {
      final other = (await repository.create(
        draftFor([segmentFor(0, _line, 'הארץ')]),
        colorOf('yellow'),
      )).highlight;
      await repository.setTags(mark.id, ['הלכה', 'עיון']);
      await repository.setTags(other.id, ['עיון']);
      expect(await repository.replaceTag('עיון', 'הלכה'), 2);
      expect((await repository.get(mark.id))!.tags, ['הלכה']);
      expect((await repository.get(other.id))!.tags, ['הלכה']);
      expect(await repository.replaceTag('הלכה', null), 2);
      expect(await repository.tags(), isEmpty);
    });

    test('re-anchoring saves anchors without counting as an edit', () async {
      final moved = segmentFor(
        0,
        'פתיחה. $_line',
        'השמים',
      ).copyWith(status: MarkerAnchorStatus.stale);
      await repository.saveAnchors({
        mark.id: [moved],
      });
      final loaded = (await repository.get(mark.id))!;
      expect(loaded.segments.single.start, moved.start);
      expect(loaded.status, MarkerAnchorStatus.stale);
      expect(loaded.version, mark.version);
      expect(changes, isEmpty);
    });
  });

  group('list queries', () {
    setUp(() async {
      final base = DateTime.utc(2026, 3, 1);
      await repository.importHighlights([
        highlightFor(
          'a',
          [segmentFor(0, _line, 'בראשית')],
          text: 'וַיֹּאמֶר',
          createdAt: base,
          tags: ['פתיחה'],
        ),
        highlightFor(
          'b',
          [segmentFor(3, _line, 'ברא')],
          book: 'שמות',
          uid: 'id:2',
          colorId: 'green',
          createdAt: base.add(const Duration(days: 1)),
          favorite: true,
        ),
        highlightFor(
          'c',
          [
            segmentFor(
              5,
              _line,
              'אלהים',
            ).copyWith(status: MarkerAnchorStatus.failed),
          ],
          colorId: 'green',
          createdAt: base.add(const Duration(days: 2)),
          note: const MarkerNote(content: 'מקור', plain: 'מקור חשוב'),
        ),
      ]);
    });

    Future<List<String>> ids(MarkerQuery query) async => [
      for (final mark in await repository.query(
        query,
        offset: 0,
        limit: 50,
        colorOrder: const ['yellow', 'green'],
      ))
        mark.id,
    ];

    test('newest first by default, oldest on request', () async {
      expect(await ids(const MarkerQuery()), ['c', 'b', 'a']);
      expect(await ids(const MarkerQuery(sort: MarkerSort.oldest)), [
        'a',
        'b',
        'c',
      ]);
    });

    test('search ignores niqqud and covers notes and tags', () async {
      expect(await ids(const MarkerQuery(search: 'ויאמר')), ['a']);
      expect(await ids(const MarkerQuery(search: 'שמות')), ['b']);
      expect(await ids(const MarkerQuery(search: 'חשוב')), ['c']);
      expect(await ids(const MarkerQuery(search: 'פתיחה')), ['a']);
      expect(await ids(const MarkerQuery(search: '100%')), isEmpty);
    });

    test('the three forms of the Name and typographic marks match', () {
      String n(String text) => normalizeMarkerSearchText(text);
      expect(n('יקוק'), n('יהוה'));
      expect(n("ה'"), n('יְהוָה'));
      expect(n("לה' הארץ"), n('ליהוה הארץ'));
      expect(n("רבה' ימים"), isNot(contains(n('יהוה'))));
      expect(n('רש“י'), n('רש"י'));
      expect(n('‘א’'), n("'א'"));
      expect(n('בית–המקדש'), n('בית המקדש'));
    });

    test('filters by book, colour, tag and status', () async {
      expect(await ids(const MarkerQuery(bookTitle: 'שמות')), ['b']);
      expect(await ids(const MarkerQuery(colorId: 'green')), ['c', 'b']);
      expect(await ids(const MarkerQuery(tag: 'פתיחה')), ['a']);
      expect(
        await ids(const MarkerQuery(status: MarkerStatusFilter.favorites)),
        ['b'],
      );
      expect(await ids(const MarkerQuery(status: MarkerStatusFilter.noted)), [
        'c',
      ]);
      expect(
        await ids(const MarkerQuery(status: MarkerStatusFilter.needsRepair)),
        ['c'],
      );
    });

    test('grouping by colour follows the palette order', () async {
      expect(await ids(const MarkerQuery(group: MarkerGroup.color)), [
        'a',
        'c',
        'b',
      ]);
    });

    test('counts are computed within the other filters', () async {
      final counts = await repository.counts(
        const MarkerQuery(colorId: 'green'),
      );
      expect(counts.total, 3);
      expect(counts.matching, 2);
      expect(counts.favorites, 1);
      expect(counts.noted, 1);
      expect(counts.needsRepair, 1);
      expect(counts.byColor, {'yellow': 1, 'green': 2});
    });

    test('pages do not repeat or skip records', () async {
      final first = await repository.query(
        const MarkerQuery(),
        offset: 0,
        limit: 2,
      );
      final second = await repository.query(
        const MarkerQuery(),
        offset: 2,
        limit: 2,
      );
      expect([...first, ...second].map((m) => m.id), ['c', 'b', 'a']);
    });
  });

  group('import', () {
    test('importing the same records twice adds them once', () async {
      final records = [
        highlightFor('x', [segmentFor(0, _line, 'את')]),
        highlightFor('y', [segmentFor(1, _line2, 'תהו')]),
      ];
      final first = await repository.importHighlights(records);
      final second = await repository.importHighlights(records);
      expect(first.added, 2);
      expect(second.added, 0);
      expect(second.skipped, 2);
      expect(await repository.countAll(), 2);
    });

    test('a failure inside the import leaves nothing behind', () async {
      final broken = highlightFor('z', [segmentFor(0, _line, 'את')]);
      final raw = await db.database;
      raw.execute(
        'CREATE TRIGGER refuse BEFORE INSERT ON marker_highlights '
        "WHEN NEW.id = 'boom' BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );
      await expectLater(
        repository.importHighlights([
          broken,
          highlightFor('boom', [segmentFor(0, _line, 'את')]),
        ]),
        throwsA(isA<SqliteException>()),
      );
      expect(await repository.countAll(), 0);
    });
  });

  group('robustness', () {
    test('a damaged row is skipped, the rest of the book loads', () async {
      await repository.importHighlights([
        highlightFor('good', [segmentFor(0, _line, 'אלהים')]),
        highlightFor('bad', [segmentFor(0, _line, 'הארץ')]),
      ]);
      final raw = await db.database;
      raw.execute(
        "UPDATE marker_highlights SET segments_json = '[{\"sectionIndex\": \"x\"}]' "
        "WHERE id = 'bad'",
      );
      final loaded = await repository.loadBook(
        bookTitle: 'בראשית',
        bookUid: 'id:1',
      );
      expect(loaded.map((mark) => mark.id), ['good']);
    });

    test('a re-anchor does not overwrite an edit saved meanwhile', () async {
      await repository.importHighlights([
        highlightFor('a', [segmentFor(0, _line, 'אלהים')]),
      ]);
      final before = (await repository.get('a'))!;
      // עריכה בחלון אחר מעלה את הגרסה.
      await repository.setRange(
        'a',
        [segmentFor(0, _line, 'ברא אלהים')],
        'ברא אלהים',
        expectedVersion: before.version,
      );
      await repository.saveAnchors(
        {
          'a': [
            before.segments.single.copyWith(status: MarkerAnchorStatus.stale),
          ],
        },
        versions: {'a': before.version},
      );
      final after = (await repository.get('a'))!;
      expect(after.segments.single.range.exactText, 'ברא אלהים');
      expect(after.status, MarkerAnchorStatus.active);
    });
  });

  group('setRange', () {
    test('replaces the segments and the text', () async {
      final created = await repository.create(
        draftFor([segmentFor(0, _line, 'אלהים')], text: 'אלהים'),
        colorOf('yellow'),
      );
      final mark = created.highlight;
      final saved = await repository.setRange(
        mark.id,
        [segmentFor(0, _line, 'ברא אלהים')],
        'ברא אלהים',
        expectedVersion: mark.version,
      );
      expect(saved!.text, 'ברא אלהים');
      expect(saved.version, mark.version + 1);
      expect(saved.segments.single.range.exactText, 'ברא אלהים');
    });

    test('a move to another place takes its reference too', () async {
      final created = await repository.create(
        draftFor([segmentFor(0, _line, 'אלהים')], text: 'אלהים'),
        colorOf('yellow'),
      );
      await repository.setNote(
        created.highlight.id,
        const MarkerNote(content: 'הערה', plain: 'הערה'),
      );
      final mark = (await repository.get(created.highlight.id))!;
      final moved = await repository.setRange(
        mark.id,
        [segmentFor(1, _line2, 'תהו ובהו')],
        'תהו ובהו',
        expectedVersion: mark.version,
        moveTo: (ref: 'בראשית א, ב'),
      );
      expect(moved!.ref, 'בראשית א, ב');
      expect(moved.sectionStart, 1);
      expect(moved.note?.plain, 'הערה');
      expect(moved.colorId, 'yellow');
      final inBook = await repository.loadBook(bookTitle: 'בראשית');
      expect(inBook.single.segments.single.sectionIndex, 1);
      // ביטול ההעברה מחזיר גם מראה מקום ריק.
      final back = await repository.setRange(
        mark.id,
        mark.segments,
        mark.text,
        expectedVersion: moved.version,
        moveTo: (ref: null),
      );
      expect(back!.ref, isNull);
      expect(back.sectionStart, 0);
    });

    test('refuses a range edited elsewhere in the meantime', () async {
      final created = await repository.create(
        draftFor([segmentFor(0, _line, 'אלהים')]),
        colorOf('yellow'),
      );
      await repository.setFavorite([created.highlight.id], true);
      await expectLater(
        repository.setRange(
          created.highlight.id,
          [segmentFor(0, _line, 'ברא אלהים')],
          'ברא אלהים',
          expectedVersion: created.highlight.version,
        ),
        throwsA(isA<MarkerConflictException>()),
      );
    });
  });

  group('backup', () {
    MarkerSegment legacySegment(String id) {
      final segment = segmentFor(0, _line, 'אלהים');
      return MarkerSegment(
        sectionIndex: segment.sectionIndex,
        range: segment.range,
        legacyId: id,
      );
    }

    test('restoring keeps the old plugin ids, even of deleted marks', () async {
      await repository.restoreBackup(
        [
          highlightFor('a', [legacySegment('old-1')]),
        ],
        keepNewerLocal: false,
        importedLegacy: [(id: 'old-2', book: 'בראשית')],
      );
      expect(await repository.allImportedLegacyIds(), {'old-1', 'old-2'});
    });

    test('a restored record gets a version above the local one', () async {
      final local = highlightFor('a', [segmentFor(0, _line, 'את')]);
      await repository.importHighlights([local.copyWith(version: 4)]);
      await repository.restoreBackup([
        local.copyWith(colorId: 'red', updatedAt: DateTime.utc(2026, 2, 1)),
      ], keepNewerLocal: false);
      final restored = await repository.get('a');
      expect(restored!.colorId, 'red');
      expect(restored.version, 5);
    });

    test('importing a backup records its old plugin ids', () async {
      await repository.importHighlights(
        const [],
        importedLegacy: [(id: 'old-3', book: 'בראשית')],
      );
      expect(await repository.allImportedLegacyIds(), {'old-3'});
    });
  });

  group('file database', () {
    late Directory directory;
    late MarkerDatabase fileDb;
    late MarkerRepository fileRepository;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('marker_db_');
      final path = '${directory.path}${Platform.pathSeparator}marker.db';
      fileDb = MarkerDatabase.withDatabase(sqlite3.open(path), path: path);
      fileRepository = MarkerRepository(
        database: fileDb,
        changes: MarkerChanges(),
      );
    });

    tearDown(() {
      fileDb.close();
      directory.deleteSync(recursive: true);
    });

    test(
      'a library move waits for an import that is already running',
      () async {
        final marks = [
          for (var i = 0; i < 2000; i++)
            highlightFor('m$i', [segmentFor(i, _line, 'את')]),
        ];
        final import = fileRepository.importHighlights(marks);
        // הייבוא כבר רץ ב-isolate כשההעברה מתחילה.
        await Future<void>.delayed(Duration.zero);
        var imported = false;
        unawaited(import.then((_) => imported = true));
        await fileDb.lockForStorageMove('move');
        expect(imported, isTrue);
        expect((await import).added, 2000);
        await expectLater(
          fileRepository.importHighlights([
            highlightFor('late', [segmentFor(0, _line, 'את')]),
          ]),
          throwsA(isA<MarkerStorageMovingException>()),
        );
      },
    );

    test('the list page and the backup are read in an isolate', () async {
      await fileRepository.importHighlights(
        [
          highlightFor('a', [segmentFor(0, _line, 'את')], tags: ['עיון']),
          highlightFor('b', [segmentFor(1, _line2, 'תהו')], favorite: true),
        ],
        importedLegacy: [(id: 'old-1', book: 'בראשית')],
      );
      final page = await fileRepository.loadPage(
        const MarkerQuery(),
        limit: 10,
      );
      expect(page.items.map((h) => h.id), unorderedEquals(['a', 'b']));
      expect(page.counts.total, 2);
      expect(page.counts.favorites, 1);
      expect(page.tags.single.tag, 'עיון');

      final backup =
          jsonDecode(await fileRepository.backupJson({'format': 'x'}))
              as Map<String, dynamic>;
      expect(backup['format'], 'x');
      expect((backup['highlights'] as List).map((h) => h['id']), ['a', 'b']);
      expect(backup['importedLegacy'], [
        {'id': 'old-1', 'book': 'בראשית'},
      ]);
    });
  });
}
