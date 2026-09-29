import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:otzaria_zvfs/otzaria_zvfs.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_db.dart';

late Directory tmp;

String p(String name) => '${tmp.path}${Platform.pathSeparator}$name';

Database openZdb(String path) =>
    sqlite3.open(path, vfs: ZVfs.name, mode: OpenMode.readOnly);

Map<String, String> digests(Database db) => {
  for (final q in testQueries) q: queryDigest(db, q),
};

Future<void> convertFile(String src, String dst, {int threads = 3}) async {
  await convertToZdb(
    source: ZdbSource.file(src),
    destination: dst,
    threads: threads,
    level: 6,
  );
}

Stream<List<int>> _chunked(String path) async* {
  final rnd = Random(7);
  final bytes = File(path).readAsBytesSync();
  var off = 0;
  while (off < bytes.length) {
    final n = min(1 + rnd.nextInt(90000), bytes.length - off);
    yield Uint8List.sublistView(bytes, off, off + n);
    off += n;
  }
}

void main() {
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('zvfs_test_');
    ZVfs.register();
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('register is idempotent and exposes the vfs', () {
    ZVfs.register();
    expect(ZVfs.isRegistered, isTrue);
    expect(ZVfs.zstdVersion, '1.5.7');
    print('sqlite ${sqlite3.version}');
  });

  test('built-in dictionary matches its pinned sha256 and id', () {
    final bytes = ZdbDictionary.seforimV1.bytes;
    expect(sha256.convert(bytes).toString(), ZdbDictionary.seforimV1Sha256);
    expect(
      bytes.buffer.asByteData().getUint32(4, Endian.little),
      ZdbDictionary.seforimV1Id,
    );
    expect(ZdbDictionary.builtinNames.first, 'seforim-v1');
  });

  for (final (pageSize, wal) in [
    (4096, false),
    (16384, true),
    (65536, false),
  ]) {
    test(
      'roundtrip page=$pageSize wal=$wal: identical results and bytes',
      () async {
        final plain = p('rt_$pageSize.db');
        final zdb = p('rt_$pageSize.zdb');
        createTestDb(plain, pageSize: pageSize, wal: wal);
        await convertFile(plain, zdb);
        expect(isZdb(zdb), isTrue);
        expect(isZdb(plain), isFalse);

        final a = sqlite3.open(plain, mode: OpenMode.readOnly);
        final b = openZdb(zdb);
        try {
          expect(digests(b), digests(a));
          expect(b.select('PRAGMA integrity_check').single.values.single, 'ok');
        } finally {
          a.close();
          b.close();
        }

        final info = readZdbInfo(zdb);
        final src = File(plain).readAsBytesSync();
        expect(info.logicalSize, src.length);
        expect(info.pageSize, pageSize);
        expect(info.walHeaderPatched, wal);
        expect(info.dictName, 'seforim-v1');
        final served = readZdbBytes(zdb, 0, src.length);
        if (wal) {
          expect(served[18], 1);
          expect(served[19], 1);
          served[18] = src[18];
          served[19] = src[19];
        }
        expect(served, src);
        final verified = await verifyZdb(zdb);
        expect(verified.contentXxh64, info.contentXxh64);
      },
    );
  }

  test('stream source in random chunks equals file source', () async {
    final plain = p('stream.db');
    createTestDb(plain);
    final fromFile = p('stream_a.zdb');
    final fromStream = p('stream_b.zdb');
    await convertFile(plain, fromFile);
    final progress = <ZdbConvertProgress>[];
    final r = await convertToZdb(
      source: ZdbSource.stream(
        () => _chunked(plain),
        totalBytes: File(plain).lengthSync(),
      ),
      destination: fromStream,
      threads: 2,
      level: 6,
      batchBytes: 64 << 10,
      onProgress: progress.add,
    );
    expect(r.info.contentXxh64, readZdbInfo(fromFile).contentXxh64);
    expect(
      readZdbBytes(fromStream, 0, r.info.logicalSize),
      File(plain).readAsBytesSync(),
    );
    expect(progress, isNotEmpty);
    expect(progress.last.bytesIn, File(plain).lengthSync());
    expect(File('$fromStream.part').existsSync(), isFalse);
  });

  test('zstd-compressed source is decoded while streaming', () async {
    final zstd = Process.runSync('zstd', ['--version'], runInShell: true);
    if (zstd.exitCode != 0) {
      markTestSkipped('zstd CLI not available');
      return;
    }
    final plain = p('zsrc.db');
    createTestDb(plain);
    final zst = '$plain.zst';
    final c = Process.runSync('zstd', [
      '-q',
      '-f',
      '-3',
      plain,
      '-o',
      zst,
    ], runInShell: true);
    expect(c.exitCode, 0, reason: '${c.stderr}');
    final out = p('zsrc.zdb');
    await convertToZdb(
      source: ZdbSource.zstdFile(zst),
      destination: out,
      level: 6,
    );
    expect(
      readZdbBytes(out, 0, File(plain).lengthSync()),
      File(plain).readAsBytesSync(),
    );

    final truncated = p('zsrc_trunc.zst');
    final zb = File(zst).readAsBytesSync();
    File(truncated).writeAsBytesSync(zb.sublist(0, zb.length - 20));
    await expectLater(
      convertToZdb(
        source: ZdbSource.zstdFile(truncated),
        destination: p('bad.zdb'),
      ),
      throwsA(isA<ZdbException>()),
    );
    expect(File(p('bad.zdb')).existsSync(), isFalse);
    expect(File(p('bad.zdb.part')).existsSync(), isFalse);
  });

  test('invalid sources are rejected', () async {
    final junk = p('junk.bin');
    File(junk).writeAsBytesSync(List.filled(8192, 7));
    await expectLater(
      convertToZdb(source: ZdbSource.file(junk), destination: p('j.zdb')),
      throwsA(
        isA<ZdbException>().having((e) => e.code, 'code', ZdbException.invalid),
      ),
    );
    final plain = p('short.db');
    createTestDb(plain);
    final bytes = File(plain).readAsBytesSync();
    final short = p('short_cut.db');
    File(short).writeAsBytesSync(bytes.sublist(0, bytes.length - 4096));
    await expectLater(
      convertToZdb(source: ZdbSource.file(short), destination: p('s.zdb')),
      throwsA(isA<ZdbException>()),
    );
  });

  test(
    'cancellation stops the conversion and removes the partial file',
    () async {
      final plain = p('cancel.db');
      createTestDb(plain);
      final token = ZdbCancellationToken()..cancel();
      await expectLater(
        convertToZdb(
          source: ZdbSource.file(plain),
          destination: p('cancel.zdb'),
          cancellationToken: token,
        ),
        throwsA(isA<ZdbCancelledException>()),
      );
      expect(File(p('cancel.zdb')).existsSync(), isFalse);
      expect(File(p('cancel.zdb.part')).existsSync(), isFalse);

      final token2 = ZdbCancellationToken();
      final f = convertToZdb(
        source: ZdbSource.stream(() => _chunked(plain)),
        destination: p('cancel2.zdb'),
        batchBytes: 16 << 10,
        threads: 1,
        level: 19,
        onProgress: (_) => token2.cancel(),
        cancellationToken: token2,
      );
      await expectLater(f, throwsA(isA<ZdbCancelledException>()));
      expect(File(p('cancel2.zdb.part')).existsSync(), isFalse);
    },
  );

  test('non-zdb files pass through, including writes and WAL', () {
    final path = p('pass.db');
    final db = sqlite3.open(path, vfs: ZVfs.name);
    try {
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('CREATE TABLE t(x); INSERT INTO t VALUES (1), (2), (3)');
      expect(db.select('SELECT sum(x) AS s FROM t').single['s'], 6);
    } finally {
      db.close();
    }
    final plain = sqlite3.open(path, mode: OpenMode.readOnly);
    expect(plain.select('SELECT count(*) AS c FROM t').single['c'], 3);
    plain.close();
  });

  test(
    'read-only opens refuse writes; read-write opens use the overlay',
    () async {
      final plain = p('ro.db');
      final zdb = p('ro.zdb');
      createTestDb(plain);
      await convertFile(plain, zdb);
      final ro = openZdb(zdb);
      try {
        expect(
          () => ro.execute("INSERT INTO book VALUES (9999, 'x', 1)"),
          throwsA(
            isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 8),
          ),
        );
      } finally {
        ro.close();
      }
      expect(File('$zdb-zovl').existsSync(), isFalse);
      final base = File(zdb).readAsBytesSync();
      final db = sqlite3.open(zdb, vfs: ZVfs.name);
      try {
        db.execute("INSERT INTO book VALUES (9999, 'x', 1)");
        expect(db.select('SELECT count(*) AS c FROM book').single['c'], 151);
      } finally {
        db.close();
      }
      expect(
        File(zdb).readAsBytesSync(),
        base,
        reason: 'the base is immutable',
      );
      expect(readZdbOverlayInfo(zdb).seq, greaterThan(0));
      final again = openZdb(zdb);
      expect(
        again
            .select('SELECT title FROM book WHERE id = 9999')
            .single
            .columnAt(0),
        'x',
      );
      again.close();
    },
  );

  test('a torn sidecar is ignored, a foreign one refused', () async {
    final plain = p('ov.db');
    final zdb = p('ov.zdb');
    createTestDb(plain);
    await convertFile(plain, zdb);
    File('$zdb-zovl').writeAsStringSync('x');
    openZdb(zdb).close();
    File('$zdb-zovl').writeAsBytesSync(List.filled(300, 0x33));
    expect(
      () => openZdb(zdb),
      throwsA(
        isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 11),
      ),
    );
    File('$zdb-zovl').deleteSync();
    openZdb(zdb).close();
  });

  test('an open file is probed from its state, not reopened', () async {
    final plain = p('st.db');
    final zdb = p('st.zdb');
    createTestDb(plain);
    await convertFile(plain, zdb);
    final before = readZdbInfo(zdb);
    expect(ZVfs.isOpen(zdb), isFalse);
    final db = openZdb(zdb);
    try {
      expect(ZVfs.isOpen(zdb), isTrue);
      expect(isZdb(zdb), isTrue);
      expect(readZdbInfo(zdb).contentXxh64, before.contentXxh64);
      expect(
        () => readZdbBytes(zdb, 0, 16),
        throwsA(
          isA<ZdbException>().having((e) => e.code, 'code', ZdbException.busy),
        ),
      );
      await expectLater(
        verifyZdb(zdb),
        throwsA(
          isA<ZdbException>().having((e) => e.code, 'code', ZdbException.busy),
        ),
      );
    } finally {
      db.close();
    }
    expect(ZVfs.isOpen(zdb), isFalse);
    final pl = sqlite3.open(plain, vfs: ZVfs.name);
    try {
      expect(ZVfs.isOpen(plain), isTrue);
      expect(isZdb(plain), isFalse);
      expect(() => readZdbInfo(plain), throwsA(isA<ZdbException>()));
    } finally {
      pl.close();
    }
    await verifyZdb(zdb);
  });

  test('corruption fuzz: never crashes, never returns wrong rows', () async {
    final plain = p('fuzz.db');
    final zdb = p('fuzz.zdb');
    createTestDb(plain, pageSize: 4096);
    await convertFile(plain, zdb);
    final good = File(zdb).readAsBytesSync();
    final info = readZdbInfo(zdb);
    final expected = sqlite3.open(plain, mode: OpenMode.readOnly);
    const queries = [
      'SELECT * FROM book ORDER BY id',
      'SELECT bookId, count(*), sum(length(content)) FROM line GROUP BY 1',
      'SELECT * FROM meta ORDER BY k',
    ];
    final want = {for (final q in queries) q: queryDigest(expected, q)};
    expected.close();
    final dictStart = 4096;
    final framesStart = dictStart + info.dictLength;
    final indexStart = info.physicalSize - (info.frameCount + 1) * 8;
    final rnd = Random(99);
    final iters =
        int.tryParse(Platform.environment['ZVFS_FUZZ_ITERS'] ?? '') ?? 300;
    var opened = 0, intact = 0, corrupt = 0;
    final path = p('fuzz_mut.zdb');
    for (var it = 0; it < iters; it++) {
      final m = Uint8List.fromList(good);
      var len = m.length;
      for (var k = 0, n = 1 + rnd.nextInt(4); k < n; k++) {
        final (lo, hi) = switch (rnd.nextInt(8)) {
          0 => (0, 256),
          1 => (dictStart, framesStart),
          2 => (indexStart, m.length),
          3 => (0, m.length),
          _ => (framesStart, indexStart),
        };
        final pos = min(lo + rnd.nextInt(max(1, hi - lo)), len - 1);
        switch (rnd.nextInt(4)) {
          case 0:
            m[pos] ^= 1 << rnd.nextInt(8);
          case 1:
            m[pos] = rnd.nextInt(256);
          case 2:
            len = pos + 1;
          default:
            for (var j = 0; j < 16 && pos + j < len; j++) {
              m[pos + j] = rnd.nextInt(256);
            }
        }
      }
      File(path).writeAsBytesSync(Uint8List.sublistView(m, 0, len));
      Database db;
      try {
        db = openZdb(path);
      } on SqliteException {
        continue;
      }
      opened++;
      try {
        for (final q in queries) {
          try {
            expect(queryDigest(db, q), want[q], reason: 'iteration $it');
            intact++;
          } on SqliteException {
            corrupt++;
          }
        }
      } finally {
        db.close();
      }
    }
    print(
      'fuzz: $iters mutations, $opened opened, $intact intact queries, '
      '$corrupt reported errors',
    );
  });

  test('verifyZdb detects a damaged frame', () async {
    final plain = p('v.db');
    final zdb = p('v.zdb');
    createTestDb(plain);
    await convertFile(plain, zdb);
    final info = readZdbInfo(zdb);
    final bytes = File(zdb).readAsBytesSync();
    final mid =
        4096 +
        info.dictLength +
        (info.physicalSize - 4096 - info.dictLength) ~/ 3;
    bytes[mid] ^= 0x40;
    File(zdb).writeAsBytesSync(bytes);
    await expectLater(
      verifyZdb(zdb),
      throwsA(
        isA<ZdbException>().having((e) => e.code, 'code', ZdbException.corrupt),
      ),
    );
  });

  test('isolates read the same zdb concurrently', () async {
    final plain = p('mt.db');
    final zdb = p('mt.zdb');
    createTestDb(plain, pageSize: 16384);
    await convertFile(plain, zdb);
    final a = sqlite3.open(plain, mode: OpenMode.readOnly);
    final want = digests(a);
    a.close();
    ZVfs.cacheBytesPerFile = 40 * 16384;
    try {
      final results = await Future.wait([
        for (var i = 0; i < 6; i++)
          Isolate.run(() {
            ZVfs.register();
            var ok = 0;
            for (var round = 0; round < 4; round++) {
              final db = openZdb(zdb);
              try {
                final d = digests(db);
                for (final q in testQueries) {
                  if (d[q] == want[q]) ok++;
                }
              } finally {
                db.close();
              }
            }
            return ok;
          }),
      ]);
      expect(results, everyElement(4 * testQueries.length));
      // per path: other suites run in the same process
      expect(ZVfs.isOpen(zdb), isFalse);
    } finally {
      ZVfs.cacheBytesPerFile = 16 << 20;
    }
  });
}
