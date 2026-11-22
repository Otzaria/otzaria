import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `#include "x"` מילולי, כמו ש-ISPP רואה אותו.
final _includeLine = RegExp(
  r'^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$',
  multiLine: true,
);

String _read(String name) =>
    File('installer/$name').readAsStringSync().replaceAll('\r\n', '\n');

String _expand(String text) =>
    text.replaceAllMapped(_includeLine, (m) => _expand(_read(m[1]!)));

String _routine(String script, String signature) {
  final start = script.indexOf(signature);
  expect(start, isNonNegative, reason: signature);
  return script.substring(start, script.indexOf('\nend;', start));
}

/// הדגלים הקבועים של `CurlArgs`, כפי שהמסייע מעביר אותם ל-curl.
List<String> _curlBaseArgs(String curl) {
  final args = _routine(curl, 'function CurlArgs(');
  final literals = RegExp(
    "'([^']*)'",
  ).allMatches(args).map((m) => m[1]!).join(' ');
  final flags = RegExp(r'--[a-z-]+(?: \d+)?').allMatches(literals);
  return [
    for (final flag in flags.map((m) => m[0]!))
      if (!flag.startsWith('--stderr') && !flag.startsWith('--output'))
        ...flag.split(' '),
  ];
}

void main() {
  final script = _expand(_read('download_assistant.iss'));
  final curl = _read('download_assistant_curl.iss');

  group('מסייע ההורדה — curl עם המשך הורדה', () {
    test('כל פריט מנסה curl קודם, וכל תוצאה אחרת יורדת בעמוד של Inno', () {
      final run = _routine(script, 'function RunDownloads()');
      expect(run, contains('CurlResetRun();'));
      final curlCall = run.indexOf('case CurlDownloadItem(I) of');
      expect(curlCall, isNonNegative);
      expect(curlCall, lessThan(run.indexOf('DownloadPage.Download;')));
      final cases = run.substring(curlCall, run.indexOf('Attempt := 1;'));
      expect(cases, contains('CurlDone:'));
      expect(cases, contains('CurlFailed:'));
      expect(
        cases,
        isNot(contains('CurlFallback')),
        reason: 'CurlFallback ממשיך ללולאה הקיימת של Inno',
      );
    });

    test('curl של המערכת נבדק לפני שימוש, ובלעדיו — Inno', () {
      final ready = _routine(curl, 'function CurlReady()');
      expect(ready, contains(r"ExpandConstant('{win}\Sysnative\curl.exe')"));
      expect(ready, contains(r"ExpandConstant('{sys}\curl.exe')"));
      expect(ready, contains("'--version'"));
      final item = _routine(curl, 'function CurlDownloadItem(');
      expect(
        item.indexOf('if not CurlReady() then'),
        lessThan(item.indexOf('CurlTryLock(I)')),
      );
    });

    test('ארגומנטים: ניתוק נתקע, Schannel וסינון, פרוקסי, ובלי --retry', () {
      final flags = _curlBaseArgs(curl);
      for (final flag in [
        '--fail',
        '--location',
        '--connect-timeout',
        '--speed-limit',
        '--speed-time',
        '--ssl-revoke-best-effort',
        '--suppress-connect-headers',
      ]) {
        expect(flags, contains(flag));
      }
      // ניסיון חוזר של curl מקצץ את מה שירד בו; הלולאה שלנו ממשיכה מהקובץ.
      expect(flags, isNot(contains('--retry')));
      expect(curl, isNot(contains(RegExp(r"'[^'\n]*--retry"))));
      final start = _routine(curl, 'function CurlStartSegment(');
      expect(start, contains("'--continue-at -'"));
    });

    test('הקבצים החלקיים במטמון הקבוע, כבולים ל-sha256, ולא ב-{tmp}', () {
      expect(curl, isNot(contains('{tmp}')));
      final base = _routine(curl, 'function CurlBase(');
      expect(base, contains('CachePath(QueueFile[I])'));
      expect(base, contains('Copy(Lowercase(QueueSha[I]), 1, 12)'));
      expect(
        _routine(curl, 'function CurlSegPath('),
        contains('IntToStr(SegmentsPerFile)'),
      );
      expect(
        _routine(curl, 'function CurlFetchLocked('),
        contains(
          "CurlDropPartials(QueueFile[I], ExtractFileName(CurlBase(I)) + '.')",
        ),
      );
    });

    test('פיצול רק אחרי 206 עם הגודל הצפוי, והפניה לבדה אינה הוכחה', () {
      expect(curl, contains('SegmentsPerFile = 4;'));
      final probe = _routine(curl, 'function CurlProbeRange(');
      expect(probe, contains('--range 0-0 --max-filesize'));
      expect(
        probe,
        contains(
          "(ContentRange = 'bytes 0-0/' + IntToStr(QueueSize[I]))",
        ),
      );
      expect(probe, contains('if Complete then\n    CurlProven := True;'));
      expect(
        _routine(curl, 'procedure CurlReadHeaders('),
        contains('Complete := (Status < 300) or (Status >= 400);'),
      );
      final fetch = _routine(curl, 'function CurlFetchLocked(');
      expect(fetch, contains('(Probes < 3)'));
      expect(
        fetch,
        contains('(Range = 1) or ((Range < 0) and CurlGridSegExists(I))'),
      );
      // קטע מבקש בדיוק את הטווח החסר, ו-200 נעצר לפני הגוף.
      final start = _routine(curl, 'function CurlStartSegment(');
      expect(start, contains("'--range '"));
      expect(start, contains("' --max-filesize '"));
      expect(start, contains("SegFile[K] + '.more'"));
    });

    test(
      'רק 2xx עם טווח שגוי מעביר לחיבור אחד; שגיאת HTTP היא ניתוק או תקלה',
      () {
        final reply = _routine(curl, 'function CurlSegReplyOk(');
        expect(
          reply,
          contains('if not Known or (Status < 200) or (Status >= 300) then'),
        );
        final finish = _routine(curl, 'function CurlFinishSegment(');
        expect(
          finish.indexOf('Result := CurlSingle;'),
          lessThan(finish.indexOf('CurlIsTransient(Code, ErrText)')),
        );
        // מעבר לחיבור אחד אינו מוחק קטעים שלמים; רק שרת שמתעלם מ-Range.
        final fetch = _routine(curl, 'function CurlFetchLocked(');
        final single = fetch.indexOf('ForceSingle := True;');
        expect(single, isNonNegative);
        final drops = RegExp(
          r'CurlDropSegments\(I\);',
        ).allMatches(fetch).map((m) => m.start).toList();
        expect(drops, hasLength(2), reason: 'Range = 0, ו-hash שגוי');
        expect(
          fetch.indexOf('if Range = 0 then\n      begin'),
          lessThan(drops[0]),
        );
      },
    );

    test('הרכבה שנקטעה ממשיכה מהקטעים, ועצירה בהרכבה משאירה תחילית תקינה', () {
      final absorb = _routine(curl, 'function CurlAbsorb(');
      expect(
        absorb,
        contains('CurlTruncate(CurlWholePath(I), CurlGridStart(I, K))'),
      );
      expect(absorb, contains('CurlGridSegComplete(I, K)'));
      final append = _routine(curl, 'function CurlAppend(');
      expect(append, contains('if AllowStop and StopRequested then'));
      expect(append, contains('SetEndOfFile(Output.Handle);'));
      final fetch = _routine(curl, 'function CurlFetchLocked(');
      final hash = fetch.indexOf('HashFile(Whole) = Lowercase(QueueSha[I])');
      expect(hash, isNonNegative);
      expect(fetch.indexOf('CurlJoinSegments()'), lessThan(hash));
      expect(
        fetch.indexOf('PromoteToCache(Whole, QueueFile[I]'),
        greaterThan(hash),
      );
      expect(fetch, contains('if Restarted then'));
      // כשל בהעברה למטמון מחזיר את הקובץ המאומת לשמו.
      expect(
        _routine(script, 'function PromoteToCache('),
        contains('if not RenameFile(Staged, TempPath) then'),
      );
    });

    test('נסיגה ל-Inno: תקלה, אין תשובה, או שום בית לפריט', () {
      final finish = _routine(curl, 'function CurlFinishSegment(');
      expect(
        finish,
        contains(
          '(not Transient or (not CurlProven and (SegTries[K] > 1)))',
        ),
      );
      expect(finish, contains('if not CurlGained then'));
      expect(finish, contains('Result := CurlFallback;'));
      final transient = _routine(curl, 'function CurlIsTransient(');
      expect(transient, contains('6, 7, 16, 18, 28, 35, 52, 55, 56, 92'));
      expect(
        _routine(curl, 'function CurlFetchLocked('),
        contains(
          'if (Range < 0) and not CurlProven and not CurlGridSegExists(I) and',
        ),
      );
      // ניסיון שהתקדם אינו נספר; רק ניסיונות רצופים בלי בית חדש.
      expect(finish, contains('if Size > SegBest[K] then'));
      expect(finish, contains('SegStrikes[K] >= CurlStallLimit'));
    });

    test('בלי חלון, בלי יתומים: Job שנסגר עם המסייע, ועצירה הורגת הכול', () {
      final spawn = _routine(curl, 'function CurlSpawn(');
      expect(spawn, contains(r'$08000004'));
      expect(spawn, contains('Startup.Size := SizeOf(Startup);'));
      expect(spawn, contains('CurlJoinJob(Info.Process);'));
      expect(_routine(curl, 'procedure CurlJoinJob('), contains(r'$2000'));
      final run = _routine(curl, 'function CurlRunSegments(');
      expect(run, contains('CurlKillSegments(I);'));
      expect(run, contains('StopRequested or DownloadPage.AbortedByUser'));
      expect(run, contains('CurlWaitForSingleObject(SegProc[K], 0)'));
      expect(_routine(curl, 'function CurlStopped('), contains('Log('));
    });

    test('הערכת הזמן: מעריך אחד למשימה, ומהירות רק מבתים שירדו ברשת', () {
      final run = _routine(curl, 'function CurlRunSegments(');
      expect(
        curl,
        isNot(contains('ResetSpeed();')),
        reason: 'ResetSpeed רק ב-RunDownloads — לא לכל קובץ או ניסיון',
      );
      expect(
        run.indexOf('SpeedResume();'),
        lessThan(run.indexOf('while True do')),
      );
      expect(
        run.indexOf('SpeedPause();', run.indexOf('finally')),
        greaterThan(run.indexOf('CurlKillSegments(I);')),
      );
      // המתנה בין ניסיונות כשאף קטע אינו רץ אינה רשת.
      expect(run, contains('if not Running and not EstPaused then'));
      expect(run, contains('else if Running and EstPaused then'));

      final show = _routine(curl, 'procedure CurlShowProgress(');
      expect(show, contains('AddSpeedSample(CurlNetBytes);'));
      expect(
        show,
        isNot(contains('OnDownloadProgress(')),
        reason:
            'OnDownloadProgress דוגם את הבתים שעל הדיסק, כולל ההמשך מהמטמון',
      );
      expect(show, contains('CurrentProgress := Done;'));
      expect(show, contains('Done := CurlItemHave();'));
      // בתים שנמחקו (33/416, .more שנזרק) אינם מורידים את המונה.
      final count = _routine(curl, 'procedure CurlCountNet(');
      expect(count, contains('if Got > SegNet[K] then'));
      expect(count, contains('Got := CurlSegHave(K) - SegBefore[K];'));
      expect(
        _routine(curl, 'function CurlStartSegment('),
        contains('SegNet[K] := 0;'),
      );
      final finish = _routine(curl, 'function CurlFinishSegment(');
      expect(
        finish.indexOf('CurlCountNet(K);'),
        lessThan(finish.indexOf('CurlSettle(I, K, Known, ReplyOk)')),
        reason: 'הבתים האחרונים של ניסיון נספרים לפני שה-.more מצורף או נזרק',
      );
      expect(
        _routine(curl, 'procedure CurlKillSegments('),
        contains('CurlCountNet(K);'),
      );
      expect(
        _routine(curl, 'procedure CurlResetRun('),
        contains('CurlNetBytes := 0;'),
      );

      final item = _routine(curl, 'function CurlDownloadItem(');
      expect(
        item.indexOf('SpeedPause();'),
        lessThan(item.indexOf('CurlTryLock(I)')),
        reason: 'נעילה, בדיקת Range והכנה אינן רשת',
      );
      final cleanup = item.substring(item.lastIndexOf('finally'));
      expect(cleanup, contains('CurlSetJoinPending(0);'));
      expect(cleanup, contains('CurrentProgress := 0;'));
      expect(cleanup, contains('VerifyStartTick := 0;'));
    });

    test('החיבור וה-hash של curl נכללים בהערכה, ובזמנם מוצג שם השלב', () {
      expect(
        _routine(curl, 'procedure CurlPlanSegments('),
        contains('CurlSetJoinPending(QueueSize[I] - CurlSegLen(0));'),
      );
      expect(
        _routine(curl, 'procedure CurlSetJoinPending('),
        contains('JoinCopyLeft := JoinCopyLeft - CurlJoinPending + Bytes;'),
      );
      expect(
        _routine(curl, 'function CurlJoinSegments('),
        contains('CurlSetJoinPending(CurlJoinPending - CurlSegLen(K));'),
      );
      final append = _routine(curl, 'function CurlAppend(');
      expect(
        append,
        contains('CopyMsMeasured := CopyMsMeasured + NowMs() - SliceStart;'),
      );
      expect(append, contains('CopyBytesMeasured := CopyBytesMeasured + Got;'));

      final fetch = _routine(curl, 'function CurlFetchLocked(');
      final verify = fetch.indexOf('VerifyStartTick := NowMs();');
      final join = fetch.indexOf('Outcome := CurlJoinSegments();');
      final hash = fetch.indexOf('HashFile(Whole)');
      expect(verify, greaterThanOrEqualTo(0));
      expect(fetch.indexOf('ShowDownloadStatus();', verify), lessThan(join));
      // GetSHA256OfFile חוסם את החלון: שם השלב מצויר לפניו.
      expect(fetch.indexOf('WizardForm.Update;', join), lessThan(hash));
      final hold = fetch.indexOf('HoldShownEta(True);');
      expect(hold, greaterThan(hash));
      expect(fetch.indexOf('VerifyStartTick := 0;', hash), greaterThan(hold));
      expect(
        fetch,
        contains('HashBytesMeasured := HashBytesMeasured + QueueSize[I];'),
      );
    });

    test('גרסאות שונות של אותו נכס מתחרות על אותה נעילה לפני ניקוי', () {
      final lock = _routine(curl, 'function CurlTryLock(');
      expect(
        lock,
        contains("CurlCreateFile(CachePath(QueueFile[I]) + '.partial.lock'"),
      );
      expect(lock, isNot(contains('CurlBase(')));
      expect(lock, isNot(contains('CurlWholePath(')));
      expect(lock, isNot(contains('QueueSha')));
      final item = _routine(curl, 'function CurlDownloadItem(');
      expect(
        item.indexOf('CurlTryLock(I)'),
        lessThan(item.indexOf('CurlFetchLocked(I)')),
      );
      expect(
        item.indexOf('CurlDropPartials('),
        lessThan(item.indexOf('CurlUnlock()')),
      );
      final forget = _routine(curl, 'procedure CurlForgetItem(');
      expect(
        forget.indexOf('CurlTryLock(I)'),
        lessThan(forget.indexOf('CurlDropPartials(')),
      );
      expect(
        forget.indexOf('CurlDropPartials('),
        lessThan(forget.indexOf('CurlUnlock()')),
      );
    });

    test('שני מסייעים אינם כותבים לאותם קבצים חלקיים', () {
      final lock = _routine(curl, 'function CurlTryLock(');
      expect(lock, contains(r'$04000080'), reason: 'FILE_FLAG_DELETE_ON_CLOSE');
      expect(lock, contains('if Err = 32 then'));
      final item = _routine(curl, 'function CurlDownloadItem(');
      expect(item, contains('while Lock = 0 do'));
      expect(item, contains("Msg1('WaitingForOtherAssistant', QueueLabel[I])"));
      expect(item, contains('if Lock < 0 then\n    exit;'));
      expect(
        item.indexOf('CachedFileIsGood('),
        greaterThan(item.indexOf('while Lock = 0 do')),
        reason: 'בלי hash בכל סבב המתנה',
      );
    });
  });

  group('curl של Windows — ההנחות של המסייע', () {
    const curlExe = r'C:\Windows\System32\curl.exe';
    final skip = !Platform.isWindows || !File(curlExe).existsSync()
        ? 'רק ב-Windows עם curl של המערכת'
        : false;
    late HttpServer server;
    late Directory work;
    final body = List<int>.generate(1 << 20, (i) => i % 251);

    setUp(() async {
      work = await Directory.systemTemp.createTemp('otz_curl_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final response = request.response;
        final path = request.uri.path;
        if (path == '/redirect') {
          response.statusCode = 302;
          response.headers.set('Location', '/file');
        } else if (path == '/503') {
          response.statusCode = 503;
        } else {
          final range = request.headers.value('range');
          final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range ?? '');
          if (path == '/file' && match != null) {
            final start = int.parse(match[1]!);
            final end = match[2]!.isEmpty
                ? body.length - 1
                : int.parse(match[2]!);
            response.statusCode = 206;
            response.headers.set(
              'Content-Range',
              'bytes $start-$end/${body.length}',
            );
            response.contentLength = end - start + 1;
            response.add(body.sublist(start, end + 1));
          } else {
            response.contentLength = body.length;
            response.add(body);
          }
        }
        await response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await work.delete(recursive: true);
    });

    Future<ProcessResult> run(List<String> extra, String path) => Process.run(
      curlExe,
      [
        ..._curlBaseArgs(curl),
        ...extra,
        '--stderr',
        'err.txt',
        '--output',
        'out.bin',
        'http://127.0.0.1:${server.port}$path',
      ],
      workingDirectory: work.path,
    );

    String headers() => File('${work.path}/h.txt').readAsStringSync();

    test('302 ואז 206: התשובה האחרונה ב---dump-header היא הטווח', () async {
      final result = await run([
        '--range',
        '0-0',
        '--max-filesize',
        '1024',
        '--dump-header',
        'h.txt',
      ], '/redirect');
      expect(result.exitCode, 0);
      final text = headers();
      expect(text, contains('302'));
      final last = text.substring(text.lastIndexOf('HTTP/'));
      expect(last, matches(RegExp(r'^HTTP/[\d.]+ 206')));
      expect(last, contains('bytes 0-0/${body.length}'));
    }, skip: skip);

    test('200 על בקשת טווח נעצר ב---max-filesize (63) לפני הגוף', () async {
      final result = await run([
        '--range',
        '0-0',
        '--max-filesize',
        '1024',
        '--dump-header',
        'h.txt',
      ], '/norange');
      expect(result.exitCode, 63);
      expect(headers(), contains('200'));
      final out = File('${work.path}/out.bin');
      expect(out.existsSync() ? out.lengthSync() : 0, lessThan(body.length));
    }, skip: skip);

    test('--fail על 503: קוד 22 וההודעה ש-CurlHttpStatus קורא', () async {
      final result = await run([], '/503');
      expect(result.exitCode, 22);
      expect(
        File('${work.path}/err.txt').readAsStringSync(),
        contains('error: 503'),
      );
    }, skip: skip);

    test('curl אינו מצרף --range ל---continue-at (ולכן .more)', () async {
      final result = await run([
        '--range',
        '0-9',
        '--continue-at',
        '-',
      ], '/file');
      expect(result.exitCode, 2);
    }, skip: skip);

    test(
      '--suppress-connect-headers: ה-CONNECT של פרוקסי אינו בכותרות',
      () async {
        final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        proxy.listen((client) async {
          final head = StringBuffer();
          late StreamSubscription<List<int>> sub;
          Socket? upstream;
          sub = client.listen((data) async {
            if (upstream != null) {
              upstream!.add(data);
              return;
            }
            head.write(latin1.decode(data));
            if (!head.toString().contains('\r\n\r\n')) return;
            sub.pause();
            upstream = await Socket.connect(
              InternetAddress.loopbackIPv4,
              server.port,
            );
            upstream!.listen(client.add, onDone: client.destroy);
            client.write('HTTP/1.1 200 Connection established\r\n\r\n');
            sub.resume();
          }, onDone: () => upstream?.destroy());
        });
        final result = await run([
          '--proxytunnel',
          '--proxy',
          'http://127.0.0.1:${proxy.port}',
          '--range',
          '0-0',
          '--max-filesize',
          '1024',
          '--dump-header',
          'h.txt',
        ], '/file');
        await proxy.close();
        expect(result.exitCode, 0);
        final text = headers();
        expect(text, isNot(contains('Connection established')));
        expect(text, contains('206'));
      },
      skip: skip,
    );
  });
}
