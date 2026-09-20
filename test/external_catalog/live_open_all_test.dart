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

/// מעלה [count] מופעים **חדשים** ומחזיר את המזהים שלהם.
///
/// חדשים ולא קיימים: המופעים האלה נבדקים, נטענים בעבודה ועשויים
/// להיסגר — ואין לעשות זאת למופע שהמשתמש פתח.
///
/// אין single-instance, ולכן כל הפעלה מייצרת תהליך נוסף. ההמתנה היא
/// למופע **שימושי** (חלון שנוצר עדיין אינו חלון שנראה) ואחריה לבדיקת
/// כשירות — מופע שנכשל בה נסגר ומוחלף.
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
    final before = {
      for (final instance in ResponsaInstance.all()) instance.pid,
    };
    await Process.start(
      installation.executable,
      const [],
      workingDirectory: installation.installPath,
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
    if (fresh == null) {
      print('  instance did not come up within 90s');
      continue;
    }
    // רווח לפני הבדיקה: המופע ממשיך לטעון את המאגר גם אחרי שחלונו
    // נראה, ובמהלך הטעינה הוא עונה על חלק מההפניות ולא על כולן.
    await Future<void>.delayed(const Duration(seconds: 20));
    if (_isHealthy(fresh, version)) {
      accepted.add(fresh);
      print('  instance $fresh healthy (${accepted.length}/$count)');
    } else {
      print('  instance $fresh failed the smoke test — replacing');
      Process.runSync('taskkill', ['/F', '/PID', '$fresh']);
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
  return accepted;
}

/// כמה כשלים רצופים מצדיקים חשד במופע עצמו ולא בספרים.
///
/// מופע תקין נכשל מדי פעם — הפניה שהמנתח אינו מכיר היא כשל לגיטימי —
/// אבל שמונה ברצף הוא דפוס של מופע שחדל לענות.
const int _suspectAfter = 8;

/// עובד אחד: פותח את הספרים שהוקצו לו במופע קבוע.
///
/// כשהוא חושד במופע הוא **עוצר ואינו ממשיך**. הספרים שנותרו לו לא
/// נכתבים לקובץ, ולכן הרצה חוזרת אוספת אותם — עדיף על אלף שורות כשל
/// שאינן מתארות את הקטלוג אלא את המופע.
void _worker(
  ({SendPort send, int pid, int? version, List<_Book> books}) request,
) {
  final automation = ResponsaAutomation(
    pid: request.pid,
    profile: ResponsaVersionProfile.forVersion(request.version),
  );
  var consecutiveFailures = 0;
  var stop = false;
  for (final book in request.books) {
    if (consecutiveFailures >= _suspectAfter) {
      // שלוש בדיקות עם המתנה ביניהן. מופע עסוק או שעדיין טוען נראה
      // בבדיקה אחת כמו מופע מת, ועצירה בגללה הפקירה 1,050 ספרים
      // לעובד — נמדד פעמיים בסריקה הראשונה.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_isHealthy(request.pid, request.version)) {
          consecutiveFailures = 0;
          break;
        }
        if (attempt == 2) {
          print('  worker ${request.pid} stopped: instance stopped answering');
          stop = true;
        } else {
          sleep(const Duration(seconds: 30));
        }
      }
      if (stop) break;
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
