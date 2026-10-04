import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

import '../support/search_engine_test_init.dart';

Future<void> _holdUntilKilled((String, SendPort) args) async {
  await RustLib.init(externalLibrary: ExternalLibrary.open(args.$1));
  final wait = ReceivePort();
  await LibraryLineSource.holdForExternalWrite();
  args.$2.send(true);
  await wait.first;
}

Future<void> _holdAndExit(String libraryPath) => Isolate.run(() async {
  await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
  await LibraryLineSource.holdForExternalWrite();
});

void main() {
  late Directory tmp;
  late SearchEngine engine;
  late String libraryPath;

  setUpAll(() async {
    expect(await tryInitSearchEngine(), isTrue, reason: searchEngineSkipReason);
    libraryPath = searchEngineLoadedLibraryPath!;
    expect(await LibraryLineSource.ensureHostSqlite(), isTrue);
    tmp = await Directory.systemTemp.createTemp('line_source_exit_');
    final dbPath = p.join(tmp.path, 'seforim.db');
    final db = sqlite3.sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER, content TEXT);
      CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
      INSERT INTO line VALUES (1, 1, 0, 'בראשית ברא אלהים');
    ''');
    db.close();
    await LibraryLineSource.configure(dbPath);
    final index = await Directory(p.join(tmp.path, 'index')).create();
    engine = await SearchEngine.newInstance(path: index.path);
    await engine.addTextBook(
      title: 'ספר',
      topics: '/test',
      filePath: 'id:1',
      catalogueOrder: 0,
      generationOrder: 0,
      text: 'בראשית ברא אלהים',
      textStorage: TextStorage.libraryDb,
    );
    await engine.commit();
    expect((await lineSourceStatus()).libraryFallbacks, BigInt.zero);
  });

  tearDownAll(() async {
    await LibraryLineSource.releaseExternalWriteHold();
    engine.dispose();
    await LibraryLineSource.closeNow();
    await tmp.delete(recursive: true);
  });

  Future<TextStatus> resultStatus() async => (await engine.searchExact(
    query: 'בראשית',
    facets: [],
    limit: 1,
    offset: 0,
    order: ResultsOrder.catalogue,
    matchNikud: false,
    matchTaamim: false,
  )).single.textStatus;

  test('יציאת isolate משחררת את החזקתו בחיפוש הבא', () async {
    await _holdAndExit(libraryPath);
    expect(await resultStatus(), TextStatus.ok);
    expect((await lineSourceStatus()).suspendDepth, 0);
  });

  test('הריגת isolate אינה משחררת החזקה של isolate חי', () async {
    await LibraryLineSource.holdForExternalWrite();
    final ready = ReceivePort();
    final exited = ReceivePort();
    final child = await Isolate.spawn(
      _holdUntilKilled,
      (libraryPath, ready.sendPort),
      onExit: exited.sendPort,
    );
    try {
      await ready.first.timeout(const Duration(seconds: 20));
      expect((await lineSourceStatus()).suspendDepth, 2);
      child.kill(priority: Isolate.immediate);
      await exited.first.timeout(const Duration(seconds: 20));
      expect(await resultStatus(), TextStatus.unavailable);
      expect((await lineSourceStatus()).suspendDepth, 1);
      await LibraryLineSource.releaseExternalWriteHold();
      expect(await resultStatus(), TextStatus.ok);
    } finally {
      child.kill(priority: Isolate.immediate);
      ready.close();
      exited.close();
      await LibraryLineSource.releaseExternalWriteHold();
    }
  });

  test('החזקה מזוהה אידמפוטנטית ושחרור אינו פוגע בבעלים אחר', () async {
    final first = RawReceivePort((_) {});
    final second = RawReceivePort((_) {});
    try {
      final a = first.sendPort.nativePort;
      final b = second.sendPort.nativePort;
      await suspendLineSourceOwned(ownerPort: a);
      await suspendLineSourceOwned(ownerPort: a);
      await suspendLineSourceOwned(ownerPort: b);
      expect((await lineSourceStatus()).suspendDepth, 2);
      await resumeLineSourceOwned(ownerPort: a);
      await resumeLineSourceOwned(ownerPort: a);
      expect((await lineSourceStatus()).suspendDepth, 1);
      second.close();
      expect(await resultStatus(), TextStatus.ok);
      await resumeLineSourceOwned(ownerPort: b);
    } finally {
      first.close();
      second.close();
    }
    expect((await lineSourceStatus()).suspendDepth, 0);
  });
}
