import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/storage/marker_changes.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import 'marker_test_helpers.dart';

const _line = 'בראשית ברא אלהים את השמים ואת הארץ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late MarkerDatabase db;
  late MarkerRepository repository;
  late MarkerBookCache cache;
  late ({MarkerDatabase db, MarkerRepository repository, MarkerChanges changes})
  store;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('marker_cache_');
    Hive.init(hiveDir.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    await Settings.init(cacheProvider: HiveCache());
    MarkerSettings.instance.reload();
    store = openTestMarkerStore();
    db = store.db;
    repository = store.repository;
    cache = MarkerBookCache(repository: repository, changes: store.changes);
  });

  tearDown(() async {
    db.close();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  List<String> paintedIds({String? uid = 'id:1', int section = 0}) => [
    for (final piece in cache.paint(
      bookTitle: 'בראשית',
      bookUid: uid,
      sectionIndex: section,
      brightness: Brightness.light,
    ))
      piece.highlightId,
  ];

  test(
    'the first request loads the book, then notifies its listeners',
    () async {
      await repository.importHighlights([
        highlightFor('a', [segmentFor(0, _line, 'אלהים')]),
      ]);
      var notified = 0;
      cache.listenable('בראשית').addListener(() => notified++);
      expect(paintedIds(), isEmpty);
      await cache.ensureLoaded('בראשית', 'id:1');
      expect(notified, 1);
      expect(paintedIds(), ['a']);
    },
  );

  test('a change in the book reloads it; another book is untouched', () async {
    await cache.ensureLoaded('בראשית', 'id:1');
    await cache.ensureLoaded('שמות', 'id:2');
    var genesis = 0;
    var exodus = 0;
    cache.listenable('בראשית').addListener(() => genesis++);
    cache.listenable('שמות').addListener(() => exodus++);
    await repository.create(
      draftFor([segmentFor(0, _line, 'השמים')]),
      colorOf('green'),
    );
    await pumpEventQueue();
    expect(genesis, 1);
    expect(exodus, 0);
    expect(paintedIds(), hasLength(1));
  });

  test('a note changes the content but does not repaint the book', () async {
    final made = await repository.create(
      draftFor([segmentFor(0, _line, 'השמים')]),
      colorOf('green'),
    );
    await cache.ensureLoaded('בראשית', 'id:1');
    final before = cache.revision;
    var painted = 0;
    var content = 0;
    cache.listenable('בראשית').addListener(() => painted++);
    cache.contentListenable('בראשית').addListener(() => content++);
    await repository.setNote(
      made.highlight.id,
      const MarkerNote(content: 'הערה', plain: 'הערה'),
    );
    expect(painted, 0);
    expect(content, 1);
    expect(cache.revision, before);
    expect(cache.marksOf('בראשית', 'id:1')!.single.note?.plain, 'הערה');
    await repository.setColor([made.highlight.id], colorOf('blue'));
    expect(painted, 1);
    expect(cache.marksOf('בראשית', 'id:1')!.single.colorId, 'blue');
  });

  test('a change from another window reads only the changed marks', () async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, _line, 'אלהים')]),
      highlightFor('b', [segmentFor(0, _line, 'הארץ')]),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    // Another window recolored "a" and deleted "b".
    final other = MarkerRepository(database: db, changes: MarkerChanges());
    await other.setColor(['a'], colorOf('blue'));
    await other.delete(['b']);
    expect(paintedIds(), unorderedEquals(['a', 'b']));
    store.changes.handleRequest({
      'type': MarkerChanges.requestChanged,
      'origin': 99,
      'books': ['בראשית'],
      'saved': ['a'],
      'removed': ['b'],
    });
    await pumpEventQueue();
    expect(paintedIds(), ['a']);
    expect(cache.marksOf('בראשית', 'id:1')!.single.colorId, 'blue');
  });

  test('a mark of another book with the same title is not drawn', () async {
    await repository.importHighlights([
      highlightFor('mine', [segmentFor(0, _line, 'אלהים')]),
      highlightFor('theirs', [segmentFor(0, _line, 'הארץ')], uid: 'id:9'),
      highlightFor('legacy', [segmentFor(0, _line, 'בראשית')], uid: null),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    expect(paintedIds(), unorderedEquals(['mine', 'legacy']));
  });

  test(
    'a personal book and an official book with the same title stay apart',
    () async {
      await repository.importHighlights([
        highlightFor('official', [segmentFor(0, _line, 'אלהים')], uid: 'id:5'),
        highlightFor('personal', [segmentFor(0, _line, 'הארץ')], uid: 'uid:5'),
      ]);
      await cache.ensureLoaded('בראשית', 'uid:5');
      expect(paintedIds(uid: 'uid:5'), ['personal']);
    },
  );

  test('a hidden book draws nothing until it is shown again', () async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, _line, 'אלהים')]),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    await MarkerSettings.instance.setBookHidden('בראשית', true);
    expect(paintedIds(), isEmpty);
    await MarkerSettings.instance.setBookHidden('בראשית', false);
    expect(paintedIds(), ['a']);
  });

  test('hiding a PDF of the same title leaves the text book shown', () async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, _line, 'אלהים')]),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    await MarkerSettings.instance.setBookHidden('בראשית', true, pdf: true);
    expect(MarkerSettings.instance.isBookHidden('בראשית'), isFalse);
    expect(MarkerSettings.instance.isBookHidden('בראשית', pdf: true), isTrue);
    expect(paintedIds(), ['a']);
    expect(
      MarkerSettings.bookOfHiddenKey(
        MarkerSettings.instance.hiddenBooks.single,
      ),
      (title: 'בראשית', pdf: true),
    );
    await MarkerSettings.instance.setBookHidden('בראשית', false, pdf: true);
    expect(MarkerSettings.instance.hiddenBooks, isEmpty);
  });

  test('changed text re-anchors the mark and saves the new anchor', () async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, _line, 'השמים')]),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    const edited = 'פתיחה חדשה. $_line';
    cache.reanchorSection(
      bookTitle: 'בראשית',
      bookUid: 'id:1',
      sectionIndex: 0,
      sourceText: edited,
    );
    await pumpEventQueue();
    final saved = (await repository.get('a'))!.segments.single;
    expect(saved.status, MarkerAnchorStatus.active);
    expect(saved.start, edited.indexOf('השמים'));
  });

  test(
    'text that disappeared marks the record for repair without moving it',
    () async {
      await repository.importHighlights([
        highlightFor('a', [segmentFor(0, _line, 'השמים')]),
      ]);
      await cache.ensureLoaded('בראשית', 'id:1');
      cache.reanchorSection(
        bookTitle: 'בראשית',
        bookUid: 'id:1',
        sectionIndex: 0,
        sourceText: 'טקסט אחר לגמרי',
      );
      await pumpEventQueue();
      final saved = (await repository.get('a'))!;
      expect(saved.status, MarkerAnchorStatus.failed);
      expect(saved.segments.single.start, _line.indexOf('השמים'));
      expect(paintedIds(), isEmpty);
    },
  );

  test('text that has not loaded yet does not break the anchor', () async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, _line, 'אלהים')]),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    cache.reanchorSection(
      bookTitle: 'בראשית',
      bookUid: 'id:1',
      sectionIndex: 0,
      sourceText: '',
    );
    await pumpEventQueue();
    expect((await repository.get('a'))!.status, MarkerAnchorStatus.active);
    expect(paintedIds(), ['a']);
  });

  test('a word that stayed once elsewhere is not a move', () async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, 'אלף בית גימל', 'בית')]),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    cache.reanchorSection(
      bookTitle: 'בראשית',
      bookUid: 'id:1',
      sectionIndex: 0,
      sourceText: 'דלת הא ושם בית חדש ו',
    );
    await pumpEventQueue();
    final saved = (await repository.get('a'))!.segments.single;
    expect(saved.status, MarkerAnchorStatus.stale);
    expect(saved.start, 4);
  });

  test('ambiguous text is not guessed', () async {
    await repository.importHighlights([
      highlightFor('a', [segmentFor(0, 'אלף בית אלף', 'אלף')]),
    ]);
    await cache.ensureLoaded('בראשית', 'id:1');
    cache.reanchorSection(
      bookTitle: 'בראשית',
      bookUid: 'id:1',
      sectionIndex: 0,
      sourceText: 'גימל אלף דלת אלף הא',
    );
    await pumpEventQueue();
    expect((await repository.get('a'))!.status, MarkerAnchorStatus.stale);
  });

  test(
    'legacy ids of imported marks are reported for de-duplication',
    () async {
      await repository.importHighlights([
        highlightFor('a', [
          segmentFor(0, _line, 'אלהים', legacyId: 'marker-1'),
        ]),
      ]);
      expect(cache.legacyIds(), isEmpty);
      await pumpEventQueue();
      expect(cache.legacyIds(), {'marker-1'});
    },
  );
}
