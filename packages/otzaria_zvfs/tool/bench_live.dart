// Benchmark against a real library DB (not part of CI). The source DB is only
// ever opened read-only. Phases run in separate processes so RSS is per phase:
//   dart run tool/bench_live.dart convert --db <seforim.db> --out <x.zdb> [--zstd-pipe]
//   dart run tool/bench_live.dart query --db <seforim.db> --zdb <x.zdb> [--n 150]
//   dart run tool/bench_live.dart check --zdb <x.zdb>
import 'dart:io';
import 'dart:math';

import 'package:otzaria_zvfs/otzaria_zvfs.dart';
import 'package:sqlite3/sqlite3.dart';

Map<String, String> _args(List<String> a) {
  final m = <String, String>{};
  for (var i = 1; i < a.length; i++) {
    if (!a[i].startsWith('--')) continue;
    final hasValue = i + 1 < a.length && !a[i + 1].startsWith('--');
    m[a[i].substring(2)] = hasValue ? a[++i] : 'true';
  }
  return m;
}

String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)}MB';

int _freeBytes(String dir) {
  if (Platform.isWindows) {
    final drive = File(dir).absolute.path.substring(0, 1);
    final r = Process.runSync('powershell', [
      '-NoProfile',
      '-Command',
      '(Get-PSDrive $drive).Free',
    ]);
    return int.parse((r.stdout as String).trim());
  }
  final r = Process.runSync('df', ['-Pk', dir]);
  final cols = (r.stdout as String)
      .trim()
      .split('\n')
      .last
      .split(RegExp(r'\s+'));
  return int.parse(cols[3]) * 1024;
}

Stream<List<int>> _zstdPipe(String db) async* {
  final p = await Process.start('zstd', ['-c', '-q', '-3', '-T4', db]);
  p.stderr.drain<void>();
  yield* p.stdout;
  if (await p.exitCode != 0) throw StateError('zstd exited with an error');
}

Future<void> convert(Map<String, String> a) async {
  final db = a['db']!;
  final out = a['out']!;
  final dbSize = File(db).lengthSync();
  final free = _freeBytes(File(out).parent.path);
  final need = dbSize ~/ 3 + (1 << 30);
  stdout.writeln('source ${_mb(dbSize)}, free ${_mb(free)}, need ${_mb(need)}');
  if (free < need) {
    stderr.writeln('not enough free disk space; aborting');
    exitCode = 3;
    return;
  }
  final pipe = a.containsKey('zstd-pipe');
  var last = DateTime.now();
  final r = await convertToZdb(
    source: pipe
        ? ZdbSource.stream(() => _zstdPipe(db), compressed: true)
        : ZdbSource.file(db),
    destination: out,
    level: int.parse(a['level'] ?? '9'),
    threads: a['threads'] == null ? null : int.parse(a['threads']!),
    onProgress: (p) {
      if (DateTime.now().difference(last).inSeconds < 10) return;
      last = DateTime.now();
      stdout.writeln(
        '  in ${_mb(p.bytesIn)} out ${_mb(p.bytesOut)} '
        '${p.elapsed.inSeconds}s',
      );
    },
  );
  final i = r.info;
  stdout.writeln(
    'converted${pipe ? ' (zstd pipe)' : ''}: ${_mb(i.logicalSize)}'
    ' -> ${_mb(i.physicalSize)} (${i.ratio.toStringAsFixed(3)}x), '
    '${i.frameCount} frames, ${r.elapsed.inSeconds}s, '
    'peak RSS ${_mb(ProcessInfo.maxRss)}',
  );
}

const _queries = {
  'book range 50 lines':
      'SELECT * FROM line WHERE bookId=?1 AND lineIndex>=?2 AND lineIndex<=?2+49 '
      'ORDER BY lineIndex',
  'links for 30-line window':
      'WITH win(id) AS (SELECT id FROM line WHERE bookId=?1 AND lineIndex '
      'BETWEEN ?2 AND ?2+29) SELECT sl.lineIndex, tl.lineIndex, tl.heRef, '
      'tb.title, tb.id, ct.name FROM link l JOIN line sl ON sl.id=l.sourceLineId '
      'JOIN line tl ON tl.id=l.targetLineId JOIN book tb ON tb.id=l.targetBookId '
      'LEFT JOIN connection_type ct ON ct.id=l.connectionTypeId '
      'WHERE l.sourceLineId IN (SELECT id FROM win) ORDER BY sl.lineIndex, '
      'tb.orderIndex',
  'TOC of book':
      'SELECT t.*, tt.text, COALESCE(l.lineIndex, t.lineId) FROM tocEntry t '
      'JOIN tocText tt ON t.textId=tt.id LEFT JOIN line l ON t.lineId=l.id '
      'WHERE t.bookId=?1 AND ?2 >= 0 ORDER BY 3',
  'commentary text for 10 lines':
      'SELECT tl.content FROM link l JOIN line tl ON tl.id=l.targetLineId '
      'WHERE l.sourceLineId IN (SELECT id FROM line WHERE bookId=?1 AND '
      'lineIndex BETWEEN ?2 AND ?2+9)',
};

Database _open(String path, bool zdb) =>
    sqlite3.open(path, vfs: zdb ? ZVfs.name : null, mode: OpenMode.readOnly);

String _stats(List<double> ms) {
  ms.sort();
  final mean = ms.reduce((a, b) => a + b) / ms.length;
  double q(double f) => ms[min(ms.length - 1, (ms.length * f).floor())];
  return 'mean ${mean.toStringAsFixed(2)} p50 ${q(.5).toStringAsFixed(2)} '
      'p95 ${q(.95).toStringAsFixed(2)} max ${ms.last.toStringAsFixed(1)} ms';
}

void query(Map<String, String> a) {
  ZVfs.register(cacheBytesPerFile: int.parse(a['cache-mb'] ?? '16') << 20);
  final plain = a['db']!;
  final zdb = a['zdb']!;
  final n = int.parse(a['n'] ?? '150');
  final rnd = Random(1234567);
  final picks = <(int, int)>[];
  final p0 = _open(plain, false);
  final maxId = p0.select('SELECT max(id) AS m FROM line').single['m'] as int;
  final st = p0.prepare('SELECT bookId, lineIndex FROM line WHERE id = ?');
  while (picks.length < n) {
    final r = st.select([1 + rnd.nextInt(maxId)]);
    if (r.isNotEmpty) {
      picks.add((r.single['bookId'] as int, r.single['lineIndex'] as int));
    }
  }
  st.close();
  p0.close();
  stdout.writeln('RSS before queries ${_mb(ProcessInfo.currentRss)}');
  for (final (label, isZdb) in [('plain', false), ('zdb', true)]) {
    final path = isZdb ? zdb : plain;
    final keeper = _open(path, isZdb); // keeps the shared zvfs state alive
    for (final e in _queries.entries) {
      for (final pass in ['first ', 'repeat']) {
        final ms = <double>[];
        for (final (book, li) in picks) {
          final sw = Stopwatch()..start();
          final db = _open(path, isZdb);
          final s = db.prepare(e.value);
          s.select([book, li]);
          s.close();
          db.close();
          ms.add(sw.elapsedMicroseconds / 1000);
        }
        stdout.writeln('$label ${e.key.padRight(30)} $pass ${_stats(ms)}');
      }
    }
    final big =
        keeper
                .select(
                  'SELECT bookId, count(*) AS c FROM line GROUP BY bookId '
                  'ORDER BY c DESC LIMIT 1',
                )
                .single['bookId']
            as int;
    for (final pass in ['first ', 'repeat']) {
      final sw = Stopwatch()..start();
      final db = _open(path, isZdb);
      var bytes = 0;
      for (final row in db.select(
        'SELECT content FROM line WHERE bookId=? ORDER BY lineIndex',
        [big],
      )) {
        bytes += (row['content'] as String?)?.length ?? 0;
      }
      db.close();
      stdout.writeln(
        '$label largest book full read $pass: '
        '${sw.elapsedMilliseconds}ms ($bytes chars)',
      );
    }
    keeper.close();
    stdout.writeln(
      '$label RSS now ${_mb(ProcessInfo.currentRss)} '
      'peak ${_mb(ProcessInfo.maxRss)}',
    );
  }
  stdout.writeln(ZVfs.stats);
}

void check(Map<String, String> a) {
  ZVfs.register();
  final sw = Stopwatch()..start();
  final db = _open(a['zdb']!, true);
  final r = db
      .select('PRAGMA quick_check')
      .map((r) => r.values.first)
      .join(',');
  db.close();
  stdout.writeln(
    'quick_check: $r in ${sw.elapsed.inSeconds}s, '
    'peak RSS ${_mb(ProcessInfo.maxRss)}',
  );
}

Future<void> main(List<String> argv) async {
  final a = _args(argv);
  switch (argv.firstOrNull) {
    case 'convert':
      await convert(a);
    case 'query':
      query(a);
    case 'check':
      check(a);
    default:
      stderr.writeln('usage: see the header of tool/bench_live.dart');
      exitCode = 2;
  }
}
