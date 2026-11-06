import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/search/library_line_source.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/fake_line_source_engine.dart';
import '../test_helpers/memory_cache_provider.dart';

const _bookRows = 400000;
const _payloadBytes = 512;
const _targetTitle = 'Alpha 400000';
const _heartbeatPeriod = Duration(milliseconds: 10);

Future<int> _seedDatabase(String dbPath) => Isolate.run(() {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute('''
      CREATE TABLE category (id INTEGER PRIMARY KEY, title TEXT, level INTEGER);
      INSERT INTO category VALUES (1, 'Category', 0);
      CREATE TABLE book (
        id INTEGER PRIMARY KEY, title TEXT NOT NULL, categoryId INTEGER,
        sourceId INTEGER, orderIndex REAL, totalLines INTEGER, heDesc TEXT
      );
      BEGIN;
      WITH RECURSIVE n(i) AS (
        SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < $_bookRows
      )
      INSERT INTO book
      SELECT i, printf('Alpha %06d', i), 1, 1, i, 1,
             printf('%0${_payloadBytes}d', i) FROM n;
      COMMIT;
      CREATE INDEX idx_book_title ON book(title);
    ''');
    for (final (table, column, value) in [
      ('author', 'name', 'Author'),
      ('topic', 'name', 'Topic'),
      ('pub_place', 'name', 'Place'),
      ('pub_date', 'date', '2026'),
    ]) {
      final foreignKey = switch (table) {
        'pub_place' => 'pubPlaceId',
        'pub_date' => 'pubDateId',
        _ => '${table}Id',
      };
      db.execute('''
        CREATE TABLE $table (id INTEGER PRIMARY KEY, $column TEXT);
        CREATE TABLE book_$table (
          bookId INTEGER, $foreignKey INTEGER, PRIMARY KEY(bookId, $foreignKey)
        );
        INSERT INTO $table VALUES (1, '$value');
        INSERT INTO book_$table VALUES ($_bookRows, 1);
      ''');
    }
    return File(dbPath).lengthSync();
  } finally {
    db.close();
  }
});

Future<List<String>> _queryPlan(String dbPath, {bool dropIndex = false}) =>
    Isolate.run(() {
      final db = sqlite3.sqlite3.open(dbPath);
      try {
        if (dropIndex) db.execute('DROP INDEX idx_book_title');
        return db
            .select(
              'EXPLAIN QUERY PLAN SELECT * FROM book '
              'WHERE title = ? AND categoryId = ? LIMIT 1',
              [_targetTitle, 1],
            )
            .map((row) => row['detail'] as String)
            .toList();
      } finally {
        db.close();
      }
    });

Future<Map<String, Object?>> _writerMain(String dbPath, SendPort events) async {
  final db = sqlite3.sqlite3.open(dbPath);
  final commands = ReceivePort();
  final start = Completer<void>();
  var stopped = false;
  final subscription = commands.listen((message) {
    if (message == 'stop') stopped = true;
    if (!start.isCompleted) start.complete();
  });
  final clock = Stopwatch();
  var batches = 0;
  const chunkSize = 256;
  try {
    db.execute('PRAGMA busy_timeout=5000');
    final mode = db.select('PRAGMA journal_mode=WAL').single.values.single;
    if (mode != 'wal') throw StateError('Writer could not enable WAL: $mode');
    db.execute('PRAGMA synchronous=NORMAL');
    db.execute('PRAGMA wal_autocheckpoint=1000');
    events.send(commands.sendPort);
    await start.future;
    clock.start();
    while (!stopped) {
      final first = 1 + (batches % 32) * chunkSize;
      db.execute('BEGIN IMMEDIATE');
      try {
        db.execute(
          'UPDATE book SET heDesc = printf(\'%0${_payloadBytes}d\', ?) '
          'WHERE id >= ? AND id < ?',
          [batches, first, first + chunkSize],
        );
        db.execute('DELETE FROM book WHERE id >= ? AND id < ?', [
          first,
          first + 16,
        ]);
        db.execute(
          '''
          WITH RECURSIVE n(i) AS (
            SELECT ?1 UNION ALL SELECT i + 1 FROM n WHERE i < ?1 + 15
          )
          INSERT INTO book
          SELECT i, printf('Alpha %06d', i), 1, 1, i, 1,
                 printf('%0${_payloadBytes}d', i) FROM n
        ''',
          [first],
        );
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      batches++;
      if (batches == 1) events.send('started');
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    clock.stop();
    return {
      'journalMode': mode,
      'batches': batches,
      'updatedRows': batches * chunkSize,
      'deletedAndReinsertedRows': batches * 16,
      'idRange': [1, 8192],
      'elapsedUs': clock.elapsedMicroseconds,
    };
  } finally {
    db.close();
    await subscription.cancel();
    commands.close();
  }
}

Future<Map<String, Object?>> _runWriter(String path, SendPort events) =>
    Isolate.run(() => _writerMain(path, events));

class _WalWriter {
  _WalWriter(this._control, this._started, this._done, this._closeEvents);

  final SendPort _control;
  final Future<void> _started;
  final Future<Map<String, Object?>> _done;
  final Future<void> Function() _closeEvents;

  static Future<_WalWriter> prepare(String path) async {
    final events = ReceivePort();
    final ready = Completer<SendPort>();
    final started = Completer<void>();
    final subscription = events.listen((message) {
      if (message is SendPort) ready.complete(message);
      if (message == 'started') started.complete();
    });
    final done = _runWriter(path, events.sendPort);
    done.ignore();
    try {
      final control = await Future.any([
        ready.future,
        done.then<SendPort>((_) => throw StateError('Writer exited early')),
      ]);
      return _WalWriter(control, started.future, done, () async {
        await subscription.cancel();
        events.close();
      });
    } catch (_) {
      await subscription.cancel();
      events.close();
      rethrow;
    }
  }

  Future<void> start() {
    _control.send('start');
    return Future.any([
      _started,
      _done.then<void>((_) => throw StateError('Writer exited before writing')),
    ]);
  }

  Future<Map<String, Object?>> stop() async {
    _control.send('stop');
    try {
      return await _done;
    } finally {
      await _closeEvents();
    }
  }
}

Map<String, Object> _statistics(List<int> values) {
  final sorted = List.of(values)..sort();
  return {
    'count': sorted.length,
    'medianUs': sorted[(sorted.length * 0.5).ceil() - 1],
    'p95Us': sorted[(sorted.length * 0.95).ceil() - 1],
    'maxUs': sorted.last,
  };
}

void _verifyBook(Book? book, {required bool hydrated}) {
  expect(book?.id, _bookRows);
  expect(book?.title, _targetTitle);
  if (hydrated) {
    expect(book!.authors.single.name, 'Author');
    expect(book.topics.single.name, 'Topic');
    expect(book.pubPlaces.single.name, 'Place');
    expect(book.pubDates.single.date, '2026');
  }
}

Future<Map<String, Object?>> _measure(
  Future<Book?> Function() read, {
  required int samples,
  required bool hydrated,
}) async {
  final gaps = <int>[];
  final latencies = <int>[];
  final clock = Stopwatch()..start();
  var lastTickUs = 0;
  final rssBefore = ProcessInfo.currentRss;
  final timer = Timer.periodic(_heartbeatPeriod, (_) {
    final nowUs = clock.elapsedMicroseconds;
    gaps.add(nowUs - lastTickUs);
    lastTickUs = nowUs;
  });
  try {
    await Future<void>.delayed(_heartbeatPeriod * 2);
    for (var i = 0; i < samples; i++) {
      final lookup = Stopwatch()..start();
      final book = await read();
      lookup.stop();
      latencies.add(lookup.elapsedMicroseconds);
      _verifyBook(book, hydrated: hydrated);
      // Give timers an event turn; a chain of completed Futures can starve them.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // Include the delayed heartbeat after the last synchronous read.
    await Future<void>.delayed(_heartbeatPeriod * 2);
  } finally {
    timer.cancel();
    clock.stop();
  }
  return {
    'latency': _statistics(latencies),
    'heartbeatGap': _statistics(gaps),
    'latencyUs': latencies,
    'heartbeatGapUs': gaps,
    'wallUsIncludingYields': clock.elapsedMicroseconds,
    'processRssBeforeBytes': rssBefore,
    'processRssAfterBytes': ProcessInfo.currentRss,
    'processPeakRssBytes': ProcessInfo.maxRss,
  };
}

/// `flutter test --dart-define=RUN_BOOK_READ_BENCHMARK=true test/data_providers/book_reads_benchmark_test.dart`
/// Synthetic debug benchmark; latency and 10 ms event-loop gaps are separate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'book lookup latency and main-isolate heartbeat under WAL writes',
    () async {
      final provider = SqliteDataProvider.instance;
      final temp = await Directory.systemTemp.createTemp(
        'book_reads_benchmark_',
      );
      final dbPath = p.join(temp.path, DatabaseConstants.databaseFileName);
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue(SettingsRepository.keyLibraryPath, temp.path);
      await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, '');
      LibraryLineSource.debugReset(engine: FakeLineSourceEngine());
      try {
        final databaseBytes = await _seedDatabase(dbPath);
        for (final indexed in [true, false]) {
          await provider.dispose();
          final plan = await _queryPlan(dbPath, dropIndex: !indexed);
          expect(plan.join(' '), contains(indexed ? 'INDEX' : 'SCAN book'));
          for (final hydrated in [false, true]) {
            _WalWriter? writer;
            try {
              if (!indexed) writer = await _WalWriter.prepare(dbPath);
              provider.keepWalJournal = !indexed;
              await provider.initialize();
              final repository = provider.repository!;
              Future<Book?> read() => hydrated
                  ? repository.getBookByTitleAndCategory(_targetTitle, 1)
                  : repository.database.bookDao.getBookByTitle(_targetTitle);
              for (var i = 0; i < (indexed ? 20 : 3); i++) {
                _verifyBook(await read(), hydrated: hydrated);
                await Future<void>.delayed(Duration.zero);
              }
              await writer?.start();
              final measurements = await _measure(
                read,
                samples: indexed ? 250 : 20,
                hydrated: hydrated,
              );
              final writerStats = await writer?.stop();
              writer = null;
              debugPrintSynchronously(
                'BOOK_READ_BENCHMARK ${jsonEncode({
                  'label': const String.fromEnvironment('BOOK_READ_BENCHMARK_LABEL'),
                  'scenario': indexed ? 'warm_indexed' : 'scan_with_wal_writer',
                  'api': hydrated ? 'repository_title_category' : 'dao_title',
                  'buildMode': kDebugMode ? 'debug' : 'profile_or_release',
                  'os': Platform.operatingSystem,
                  'dart': Platform.version,
                  'processors': Platform.numberOfProcessors,
                  'fixture': {
                    'bookRows': _bookRows,
                    'payloadBytesPerRow': _payloadBytes,
                    'databaseBytes': databaseBytes,
                    'targetId': _bookRows,
                    'targetTitle': _targetTitle,
                    'queryPlan': plan,
                  },
                  'heartbeatPeriodUs': _heartbeatPeriod.inMicroseconds,
                  'writer': writerStats,
                  ...measurements,
                })}',
              );
            } finally {
              await writer?.stop();
              await provider.dispose();
            }
          }
        }
      } finally {
        provider.keepWalJournal = false;
        await provider.dispose();
        DbReadWorker.disposeForTesting();
        LibraryLineSource.debugReset();
        await temp.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_BOOK_READ_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
