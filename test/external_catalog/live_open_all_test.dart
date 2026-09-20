// כלי מדידה ידני: **סריקת פתיחה מלאה** — כל ספר בקטלוג, לא מדגם.
//
// מעלה כמה מופעים של פרויקט השו"ת ומחלק ביניהם את הספרים. כל תוצאה
// נכתבת מיד לקובץ TSV בכתיבה סינכרונית, ולכן הרצה שנקטעת ניתנת
// להמשכה: הספרים שכבר נבדקו מדולגים.
//
//   RESPONSA_OUT=all.tsv RESPONSA_WORKERS=4 flutter test --run-skipped \
//     test/external_catalog/live_open_all_test.dart
//
// RESPONSA_LIMIT מגביל את מספר הספרים (לבדיקת הכלי עצמו).
// RESPONSA_WHERE הוא תנאי SQL נוסף, למשל "category_path LIKE '%חסידות%'".
@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_failure.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';
import 'package:sqlite3/sqlite3.dart';

/// ספר אחד לבדיקה. רשומה פשוטה כדי שתעבור בין איזולטים.
typedef _Book = ({
  int pk,
  String title,
  String categoryPath,
  List<String> refs,
});

typedef _Result = ({
  int pk,
  bool ok,
  String detail,
  int ms,
  String usedRef,
  int ladderStep,
});

/// הפניות שכל התקנה מזהה, מארבעה חלקים שונים של המאגר.
///
/// ארבע ולא אחת: נמדד מופע שענה על `בראשית` ונכשל על `ירמיהו` שמונה
/// ספרים ברציפות — הוא היה **עדיין בטעינה**, ולא פגום. הפניה אחת אינה
/// מבדילה בין מופע שסיים לטעון למופע שהתחיל.
const List<String> _smokeReferences = [
  'בראשית',
  'ירמיהו',
  'משנה ברכות',
  'תלמוד בבלי ברכות',
];

/// סוגר את כל חלונות ה-MDI של מופע **שהכלי עצמו העלה**.
///
/// פרויקט השו"ת משחזר את הסשן הקודם: מופע טרי עולה עם עד 22 חלונות,
/// כלומר רווי מהרגע הראשון, והתוכנה מסרבת לפתוח בו חדשים. בסריקה של
/// אלפי ספרים זה אומר שכל הרצה מרעילה את הבאה אחריה.
///
/// מותר כאן בדיוק מפני שהמופעים האלה הם של הכלי, לא של המשתמש.
void _clearWindows(int pid, int? version) {
  try {
    final automation = ResponsaAutomation(
      pid: pid,
      profile: ResponsaVersionProfile.forVersion(version),
    );
    final main = automation.mainWindow;
    final client = ResponsaWin32.mdiClient(main);
    if (client == null) return;
    // **בסבבים עד שהמצב יציב.** השחזור אינו מיידי: חלונות ממשיכים
    // להיווסף דקות אחרי שהמופע עלה, וניקוי חד-פעמי משאיר אחריו זנב
    // שנראה אחר כך כמו "חלון חדש" בכל פתיחה.
    var total = 0;
    for (var round = 0; round < 6; round++) {
      final children = ResponsaWin32.directChildren(client);
      if (children.isEmpty) {
        if (round > 0) break;
      }
      for (final child in children) {
        ResponsaWin32.destroyMdiChild(main, child);
        sleep(const Duration(milliseconds: 150));
      }
      total += children.length;
      sleep(const Duration(seconds: 5));
    }
    if (total > 0) print('  instance $pid: cleared $total restored windows');
  } catch (error) {
    print('  instance $pid: could not clear windows: $error');
  }
}

/// האם המופע באמת מסוגל לענות — ולא רק פתוח.
///
/// **זה הלקח המרכזי מהסריקה הראשונה.** מופע שעלה בזמן שמופע אחר עלה
/// לצידו יכול לעלות **חלקית**: החלון נפתח, דיאלוג העיון נפתח, כל חמשת
/// הפקדים במקומם — והמנתח מחזיר אפס תוצאות לכל הפניה שהיא. נמדד: 48
/// "כשלים" רצופים, כולם באותו עובד, כולם ב-4.6 שניות בדיוק, כולם
/// `referenceNotParsed`, וכולם על ספרים שנפתחים היטב במופע אחר.
///
/// בלי הבדיקה הזו הסריקה מודדת את המופעים שלה ולא את הקטלוג.
bool _isHealthy(int pid, int? version) {
  try {
    final automation = ResponsaAutomation(
      pid: pid,
      profile: ResponsaVersionProfile.forVersion(version),
    );
    for (final reference in _smokeReferences) {
      final attempt = automation.parseReference(
        reference,
        ResponsaDeadline(const Duration(seconds: 45)),
      );
      if (attempt.results.isEmpty) return false;
    }
    return true;
  } catch (error) {
    print('  instance $pid unhealthy: $error');
    return false;
  }
}

/// מעלה מופע אחד ומחזיר את מזההו — רק אם הוא עבר את בדיקת הכשירות.
///
/// [claimed] הם מופעים ששייכים כבר לעובד אחר, ולעולם לא יוחזרו.
/// **זה אינו זהירות יתרה.** מופע שנמצא בעיצומה של פתיחת דיאלוג אינו
/// ניתן למנייה לרגע, נושר מ-`before`, ואז נבחר שוב כאילו היה חדש.
/// נמדד: שני עובדים נהגו באותו מופע, וכל אחד ראה את חלונות השני
/// כחלונות שהוא עצמו פתח — 128 "ספרים שגויים" שכולם נפתחו כשורה.
///
/// `null` כשלא עלה בזמן או כשנכשל בבדיקה; הקורא מנסה שוב.
Future<int?> _startOneInstance(
  String executable,
  String installPath,
  int? version,
  Set<int> claimed,
) async {
  final before = {
    ...claimed,
    for (final instance in ResponsaInstance.all()) instance.pid,
  };
  await Process.start(
    executable,
    const [],
    workingDirectory: installPath,
    mode: ProcessStartMode.detached,
  );
  int? fresh;
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline) && fresh == null) {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    for (final instance in ResponsaInstance.all()) {
      if (instance.usable && !before.contains(instance.pid)) {
        fresh = instance.pid;
        break;
      }
    }
  }
  if (fresh == null) return null;
  // רווח לפני הבדיקה: המופע ממשיך לטעון את המאגר גם אחרי שחלונו
  // נראה, ובמהלך הטעינה הוא עונה על חלק מההפניות ולא על כולן.
  await Future<void>.delayed(const Duration(seconds: 20));
  _clearWindows(fresh, version);
  if (_isHealthy(fresh, version)) return fresh;
  Process.runSync('taskkill', ['/F', '/PID', '$fresh']);
  return null;
}

/// מעלה [count] מופעים **חדשים** ומחזיר את המזהים שלהם.
///
/// חדשים ולא קיימים: המופעים האלה נבדקים, נטענים בעבודה ומוחלפים
/// במהלך הריצה — ואין לעשות זאת למופע שהמשתמש פתח.
Future<List<int>> _startInstances(
  ResponsaInstallation installation,
  int count,
  int? version,
) async {
  final accepted = <int>[];
  var attempts = 0;
  while (accepted.length < count) {
    if (attempts++ > count * 3) {
      throw StateError('לא עלו $count מופעים כשירים');
    }
    final pid = await _startOneInstance(
      installation.executable,
      installation.installPath,
      version,
      accepted.toSet(),
    );
    if (pid == null) {
      print('  instance did not come up healthy — retrying');
      await Future<void>.delayed(const Duration(seconds: 5));
      continue;
    }
    accepted.add(pid);
    print('  instance $pid healthy (${accepted.length}/$count)');
  }
  return accepted;
}

/// כמה כשלים רצופים מצדיקים חשד במופע עצמו ולא בספרים.
///
/// מופע תקין נכשל מדי פעם — הפניה שהמנתח אינו מכיר היא כשל לגיטימי —
/// אבל שמונה ברצף הוא דפוס של מופע שחדל לענות.
const int _suspectAfter = 8;

/// כל כמה ספרים מוחלף המופע גם בלי סימן לתקלה.
///
/// מופע שמריץ מאות פתיחות נשחק: הוא צובר חלונות, מאט, ובסופו של דבר
/// מפסיק לענות. נמדד: בסריקה של שמונה עובדים, ארבעה הפסיקו לענות תוך
/// כשעה. החלפה יזומה זולה — כ-40 שניות — והיא מה שמאפשר לסריקה של
/// 8,402 ספרים להסתיים בכלל.
const int _recycleEvery = 250;

/// עובד אחד: פותח את הספרים שהוקצו לו, ומחליף את המופע כשצריך.
///
/// **המופע מוחלף, העובד אינו נעצר.** עצירת עובד מפקירה אלף ספרים
/// להרצה חוזרת; החלפת מופע עולה 40 שניות. נמדד: מדיניות העצירה הרגה
/// ארבעה מתוך שמונה עובדים בסריקה אחת.
Future<void> _worker(
  ({
    SendPort send,
    int pid,
    int? version,
    String executable,
    String installPath,
    int recycleOffset,
    Set<int> siblings,
    List<_Book> books,
  })
  request,
) async {
  var pid = request.pid;
  final mine = <int>{pid};
  var automation = ResponsaAutomation(
    pid: pid,
    profile: ResponsaVersionProfile.forVersion(request.version),
  );

  /// מחליף את המופע. מחזיר `false` כשלא הצליח — ואז העובד עוצר, כי
  /// בלי מופע אין מה לעשות.
  Future<bool> recycle(String why) async {
    print('  worker $pid recycling: $why');
    Process.runSync('taskkill', ['/F', '/PID', '$pid']);
    await Future<void>.delayed(const Duration(seconds: 5));
    for (var attempt = 0; attempt < 3; attempt++) {
      final fresh = await _startOneInstance(
        request.executable,
        request.installPath,
        request.version,
        // המופעים של שאר העובדים, כפי שהיו בתחילת הריצה. עובד אינו
        // רשאי לקחת מופע של עובד אחר, גם אם הוא נראה פנוי לרגע.
        {...request.siblings, ...mine},
      );
      if (fresh != null) {
        pid = fresh;
        mine.add(pid);
        automation = ResponsaAutomation(
          pid: pid,
          profile: ResponsaVersionProfile.forVersion(request.version),
        );
        print('  worker replaced its instance with $pid');
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    return false;
  }

  var consecutiveFailures = 0;
  var sinceRecycle = request.recycleOffset;
  for (final book in request.books) {
    // החלפה יזומה, לפני שהמופע מתחיל להיכשל.
    if (sinceRecycle++ >= _recycleEvery) {
      sinceRecycle = 0;
      if (!await recycle('scheduled after $_recycleEvery books')) break;
    }
    if (consecutiveFailures >= _suspectAfter) {
      // בדיקה אחת, ואם היא נכשלת — מופע חדש. מופע עסוק ייתפס כתקין
      // בבדיקה, ומופע שחדל לענות יוחלף מיד.
      if (_isHealthy(pid, request.version)) {
        consecutiveFailures = 0;
      } else {
        sinceRecycle = 0;
        if (!await recycle('$_suspectAfter consecutive failures')) break;
        consecutiveFailures = 0;
      }
    }

    final watch = Stopwatch()..start();
    _Result result;
    try {
      final outcome = automation.openBook(
        book.refs,
        ResponsaDeadline(const Duration(minutes: 3)),
        expectedTitle: book.title,
      );
      result = (
        pk: book.pk,
        ok: true,
        detail: outcome.window,
        ms: watch.elapsedMilliseconds,
        usedRef: outcome.usedRef,
        ladderStep: outcome.triedRefs.indexOf(outcome.usedRef) + 1,
      );
    } on ResponsaAutomationException catch (error) {
      result = (
        pk: book.pk,
        ok: false,
        detail: '${error.failure.name}: ${error.message}',
        ms: watch.elapsedMilliseconds,
        usedRef: '',
        ladderStep: 0,
      );
    } catch (error) {
      // כשל בלתי צפוי אינו עוצר את העובד — נשארו עוד אלפי ספרים.
      result = (
        pk: book.pk,
        ok: false,
        detail: 'unexpected: $error',
        ms: watch.elapsedMilliseconds,
        usedRef: '',
        ladderStep: 0,
      );
    }
    consecutiveFailures = result.ok ? 0 : consecutiveFailures + 1;
    request.send.send(result);
  }
  request.send.send(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('open every book', () async {
    final catalogPath =
        Platform.environment['RESPONSA_DB'] ??
        '${Platform.environment['LOCALAPPDATA']}'
            r'\ResponsaBridge\responsa_catalog.db';
    final outPath = Platform.environment['RESPONSA_OUT'] ?? 'responsa_all.tsv';
    final workers = int.parse(Platform.environment['RESPONSA_WORKERS'] ?? '4');
    final limit = int.tryParse(Platform.environment['RESPONSA_LIMIT'] ?? '');
    final where = Platform.environment['RESPONSA_WHERE'];

    final db = sqlite3.open(catalogPath, mode: OpenMode.readOnly);
    final installPath = db
        .select("SELECT value FROM db_meta WHERE key='install_path'")
        .map((r) => r['value'].toString())
        .firstOrNull;
    final all = db
        .select(
          'SELECT book_pk, title, category_path, open_ref, alt_refs FROM books'
          '${where == null ? '' : ' WHERE $where'} ORDER BY book_pk',
        )
        .map(
          (r) => (
            pk: r['book_pk'] as int,
            title: r['title'].toString(),
            categoryPath: r['category_path']?.toString() ?? '',
            refs: <String>[
              r['open_ref'].toString(),
              ...(r['alt_refs']?.toString() ?? '')
                  .split('\n')
                  .where((s) => s.trim().isNotEmpty),
            ],
          ),
        )
        .toList();
    db.close();

    // המשכה: מה שכבר נכתב לא נבדק שוב.
    //
    // ב-RESPONSA_RETRY השורות שנכשלו נמחקות ונבדקות מחדש במופעים טריים.
    // זו לא הקלה בדרישה אלא ההפך: ספר שנכשל פעם אחת ונפתח בהרצה שנייה
    // מלמד שהכשל היה במופע, וספר שנכשל בשתיהן הוא כשל אמיתי.
    final retry = Platform.environment['RESPONSA_RETRY'] == '1';
    final out = File(outPath);
    final done = <int>{};
    if (out.existsSync()) {
      final kept = <String>[];
      var dropped = 0;
      final lines = out.readAsLinesSync();
      for (final line in lines.skip(1)) {
        final parts = line.split('\t');
        final pk = int.tryParse(parts.first);
        if (pk == null) continue;
        if (retry && parts.length > 1 && parts[1] == '0') {
          dropped++;
          continue;
        }
        done.add(pk);
        kept.add(line);
      }
      if (retry) {
        out.writeAsStringSync('${lines.first}\n${kept.join('\n')}\n');
        print('retry: $dropped failed rows will be re-checked');
      }
    } else {
      out.writeAsStringSync('pk\tok\tms\tstep\tcategory\ttitle\tdetail\n');
    }

    var pending = all.where((b) => !done.contains(b.pk)).toList();
    if (limit != null && limit < pending.length) {
      pending = pending.take(limit).toList();
    }
    print(
      'catalog=${all.length} done=${done.length} pending=${pending.length} '
      'workers=$workers out=$outPath',
    );
    if (pending.isEmpty) return;

    final selection = ResponsaInstallationDiscovery.selectInstallation(
      preferredPath: installPath,
    );
    expect(selection, isNotNull, reason: 'לא נמצאה התקנה של בר אילן');
    final version = selection!.installation.version;
    final pids = await _startInstances(
      selection.installation,
      workers,
      version,
    );
    print('instances: $pids (version $version)');

    // חלוקה סבבית ולא רציפה: ספרים סמוכים בקטלוג הם מאותה קטגוריה,
    // וחלוקה רציפה הייתה מרכזת את הכשלים בעובד אחד ומעוותת את הזמנים.
    final batches = [for (var i = 0; i < pids.length; i++) <_Book>[]];
    for (var i = 0; i < pending.length; i++) {
      batches[i % pids.length].add(pending[i]);
    }

    final handle = out.openSync(mode: FileMode.append);
    final byPk = {for (final book in all) book.pk: book};
    var ok = 0;
    var failed = 0;
    var finished = 0;
    final times = <int>[];
    final watch = Stopwatch()..start();
    final complete = Completer<void>();
    final receive = ReceivePort();

    receive.listen((message) {
      if (message == null) {
        finished++;
        if (finished == pids.length && !complete.isCompleted) {
          complete.complete();
        }
        return;
      }
      final result = message as _Result;
      final book = byPk[result.pk]!;
      if (result.ok) {
        ok++;
        times.add(result.ms);
      } else {
        failed++;
      }
      handle.writeStringSync(
        '${result.pk}\t${result.ok ? 1 : 0}\t${result.ms}\t'
        '${result.ladderStep}\t${book.categoryPath}\t${book.title}\t'
        '${result.detail.replaceAll(RegExp(r'\s+'), ' ')}\n',
      );
      final seen = ok + failed;
      if (seen % 25 == 0) {
        final rate = seen / watch.elapsed.inSeconds.clamp(1, 1 << 30);
        final left = Duration(
          seconds: ((pending.length - seen) / rate).round(),
        );
        print(
          '[${watch.elapsed.inMinutes}m] $seen/${pending.length} '
          'ok=$ok fail=$failed  ~$left left',
        );
      }
    });

    for (var i = 0; i < pids.length; i++) {
      await Isolate.spawn(_worker, (
        send: receive.sendPort,
        pid: pids[i],
        version: version,
        executable: selection.installation.executable,
        installPath: selection.installation.installPath,
        // היסט שונה לכל עובד, כדי ששמונה מופעים לא יוחלפו יחד: העלאה
        // מקבילה של כמה מופעים היא בדיוק מה שמייצר מופע חלקי.
        recycleOffset: (i * 31) % _recycleEvery,
        siblings: pids.toSet(),
        books: batches[i],
      ));
    }

    await complete.future;
    receive.close();
    handle.closeSync();

    times.sort();
    print(
      '\n=== $ok/${pending.length} opened, $failed failed '
      'in ${watch.elapsed.inMinutes} minutes',
    );
    if (times.isNotEmpty) {
      print('median ${times[times.length ~/ 2]}ms  max ${times.last}ms');
    }
  }, timeout: const Timeout(Duration(hours: 12)));
}
