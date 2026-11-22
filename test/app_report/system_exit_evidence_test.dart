import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/system_exit_evidence.dart';

/// באותה צורה ש-EvtRender מחזיר (מרכאות בודדות, שדות בשמות).
String crashEventXml({
  String time = '2026-11-22T13:33:38.2825195Z',
  String app = 'otzaria.exe',
  String processId = '0x4e7c',
  String creation = '0x1dd7a861481c2f7',
  String module = 'libcef.dll',
  String code = 'c0000005',
  String offset = '00000000000a4aee',
}) =>
    "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>"
    "<System><Provider Name='Application Error' "
    "Guid='{a0e9b465-b939-57d7-b27d-95d8e925ff57}'/><EventID>1000</EventID>"
    "<Level>2</Level><TimeCreated SystemTime='$time'/>"
    "<Execution ProcessID='20792' ThreadID='19396'/><Channel>Application</Channel>"
    '<Computer>SECRET-PC</Computer>'
    "<Security UserID='S-1-5-21-1-2-3-1009'/></System><EventData>"
    "<Data Name='AppName'>$app</Data><Data Name='AppVersion'>0.9.99.0</Data>"
    "<Data Name='AppTimeStamp'>6b0252ff</Data>"
    "<Data Name='ModuleName'>$module</Data>"
    "<Data Name='ModuleVersion'>139.0.7258.5</Data>"
    "<Data Name='ModuleTimeStamp'>2c17f02f</Data>"
    "<Data Name='ExceptionCode'>$code</Data>"
    "<Data Name='FaultingOffset'>$offset</Data>"
    "<Data Name='ProcessId'>$processId</Data>"
    "<Data Name='ProcessCreationTime'>$creation</Data>"
    r"<Data Name='AppPath'>C:\Users\moshe\AppData\Local\otzaria\otzaria.exe</Data>"
    r"<Data Name='ModulePath'>C:\Users\moshe\AppData\Local\otzaria\libcef.dll</Data>"
    "<Data Name='IntegratorReportId'>d75c7d28-65cf-4007-af3b-ee917ca8b695</Data>"
    "<Data Name='PackageFullName'></Data></EventData></Event>";

String hangEventXml({
  String processId = '0x4e7c',
  String creation = '0x1dd7a861481c2f7',
}) =>
    "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>"
    "<System><Provider Name='Application Hang'/><EventID>1002</EventID>"
    "<TimeCreated SystemTime='2026-11-22T13:40:07.1472915Z'/>"
    '<Computer>SECRET-PC</Computer></System><EventData>'
    "<Data Name='AppName'>otzaria.exe</Data>"
    "<Data Name='AppVersion'>0.9.99.0</Data>"
    "<Data Name='ProcessId'>$processId</Data>"
    "<Data Name='StartTime'>$creation</Data>"
    "<Data Name='TerminationTime'>4294967295</Data>"
    r"<Data Name='ExeFileName'>C:\Users\moshe\otzaria\otzaria.exe</Data>"
    "<Data Name='ReportId'>ea95c5d4-f7ef-43ee-8443-077c0e476a2e</Data>"
    "<Data Name='HangType'>Top level window is idle</Data></EventData></Event>";

void main() {
  const pid = 0x4e7c;
  // ProcessCreationTime של האירועים לעיל.
  final start = DateTime.utc(2026, 11, 22, 13, 33, 37);
  final end = DateTime.utc(2026, 11, 22, 14);

  SystemExitEvidence? windows(List<String> xml, {int processId = pid}) =>
      windowsExitEvidence(
        xml,
        pid: processId,
        exeName: 'otzaria.exe',
        start: start,
        end: end,
      );

  group('Windows Application Error / Hang', () {
    test('קריסה של ה-pid: חתימה כמו מ-minidump, בלי נתיבים', () {
      final evidence = windows([crashEventXml()])!;
      expect(evidence.isHang, isFalse);
      expect(evidence.signature.exceptionType, '0xc0000005 libcef.dll+0xa4aee');
      expect(evidence.signature.frames, ['libcef.dll+0xa4aee']);
      expect(evidence.details, contains('Faulting module: libcef.dll'));
      expect(evidence.details, contains('Module version: 139.0.7258.5'));
      for (final secret in ['moshe', 'SECRET-PC', 'S-1-5-21', r'C:\']) {
        expect(evidence.details, isNot(contains(secret)));
        expect(evidence.signature.exceptionType, isNot(contains(secret)));
      }
    });

    test('pid אחר אינו נספר', () {
      expect(windows([crashEventXml(processId: '0xee4')]), isNull);
    });

    test('pid בהקסדצימלי באותיות גדולות ובעשרוני', () {
      expect(windows([crashEventXml(processId: '0x4E7C')]), isNotNull);
      expect(windows([crashEventXml(processId: '$pid')]), isNotNull);
    });

    test('אותו pid של תוכנה אחרת אינו נספר', () {
      expect(windows([crashEventXml(app: 'dalvikvm.exe')]), isNull);
    });

    test('אירוע מחוץ לחלון הזמן של ההפעלה אינו נספר', () {
      expect(windows([crashEventXml(time: '2026-11-22T14:10:00Z')]), isNull);
      expect(windows([crashEventXml(time: '2026-11-22T13:00:00Z')]), isNull);
    });

    test('pid ממוחזר: תהליך שנוצר אחרי תחילת ההפעלה אינו נספר', () {
      // 13:50 UTC בזמן FILETIME.
      final later = DateTime.utc(
        2026,
        11,
        22,
        13,
        50,
      ).difference(DateTime.utc(1601)).inMicroseconds;
      expect(
        windows([
          crashEventXml(creation: '0x${(later * 10).toRadixString(16)}'),
        ]),
        isNull,
      );
    });

    test('זמן יצירה חסר, פגום או אפס אינו מוכיח את זהות התהליך', () {
      for (final creation in ['', 'invalid', '0x0']) {
        expect(windows([crashEventXml(creation: creation)]), isNull);
        expect(windows([hangEventXml(creation: creation)]), isNull);
      }
    });

    test('זמן יצירה לפני התחלת Dart עדיין שייך להפעלה', () {
      final created = start.subtract(const Duration(minutes: 1));
      final ticks = created.difference(DateTime.utc(1601)).inMicroseconds * 10;
      expect(
        windows([crashEventXml(creation: '0x${ticks.toRadixString(16)}')]),
        isNotNull,
      );
    });

    test('נתיב בשם המודול נחתך לשם הקובץ', () {
      final evidence = windows([
        crashEventXml(module: r'C:\Users\moshe\plugins\x.dll'),
      ])!;
      expect(evidence.signature.frames, ['x.dll+0xa4aee']);
      expect(evidence.details, isNot(contains('moshe')));
    });

    test('אירוע בלי שמות שדות (Windows ישן) לפי המיקום', () {
      final xml = crashEventXml().replaceAll(
        RegExp(r"<Data Name='[^']*'>"),
        '<Data>',
      );
      final evidence = windows([xml])!;
      expect(evidence.signature.exceptionType, '0xc0000005 libcef.dll+0xa4aee');
      expect(windows([xml], processId: 0xee4), isNull);
    });

    test('תקיעה שנסגרה; קריסה גוברת עליה', () {
      final hang = windows([hangEventXml()])!;
      expect(hang.isHang, isTrue);
      expect(hang.details, contains('Hang type: Top level window is idle'));
      expect(hang.details, isNot(contains('moshe')));
      expect(windows([hangEventXml(processId: '0x1')]), isNull);
      expect(windows([hangEventXml(), crashEventXml()])!.isHang, isFalse);
    });

    test('XPath מסנן לפי ה-pid ולפי הזמן', () {
      final query = windowsEventQuery(pid, start, end);
      expect(query, contains("Data='0x4e7c'"));
      expect(query, contains("Data='0x4E7C'"));
      expect(query, contains("Data='$pid'"));
      expect(query, contains("@SystemTime>='2026-11-22T13:33:37.000Z'"));
    });
  });

  group('Linux oom-kill', () {
    const linuxPid = 4321;
    final linuxStart = DateTime.utc(2026, 11, 22, 10);
    final linuxEnd = DateTime.utc(2026, 11, 22, 12);
    final inWindow =
        DateTime.utc(2026, 11, 22, 11).millisecondsSinceEpoch / 1000;

    SystemExitEvidence? linux(List<String> lines) => linuxOomKillEvidence(
      lines,
      pid: linuxPid,
      processName: 'otzaria',
      start: linuxStart,
      end: linuxEnd,
    );

    String killed(int pid, {double? at, String name = 'otzaria'}) =>
        '${at ?? inWindow} my-laptop kernel: Out of memory: Killed process '
        '$pid ($name) total-vm:9000000kB, anon-rss:5000000kB, '
        'file-rss:0kB, shmem-rss:0kB, UID:1000 pgtables:20000kB '
        'oom_score_adj:0';

    String oomKill(int pid, {String name = 'otzaria'}) =>
        '$inWindow my-laptop kernel: oom-kill:constraint=CONSTRAINT_NONE,'
        'nodemask=(null),cpuset=/,mems_allowed=0,global_oom,'
        'task_memcg=/user.slice/user-1000.slice/session-2.scope,'
        'task=$name,pid=$pid,uid=1000';

    test('פקודת היומן מסננת קרנל וזמן בלי להגביל לאתחול הנוכחי', () {
      expect(linuxOomJournalArguments(linuxStart, linuxEnd), [
        '-q',
        '--no-pager',
        '-o',
        'short-unix',
        '--since',
        '@${linuxStart.millisecondsSinceEpoch ~/ 1000}',
        '--until',
        '@${linuxEnd.millisecondsSinceEpoch ~/ 1000 + 1}',
        '_TRANSPORT=kernel',
      ]);
    });

    test('הריגת OOM של ה-pid: סוג ונתוני זיכרון בלבד', () {
      final evidence = linux([oomKill(linuxPid), killed(linuxPid)])!;
      expect(evidence.signature.exceptionType, 'SIGKILL (oom-kill)');
      expect(evidence.details, contains('Anon RSS: 5000000 kB'));
      expect(evidence.details, contains('Total VM: 9000000 kB'));
      for (final secret in ['my-laptop', 'user-1000', 'UID', 'otzaria']) {
        expect(evidence.details, isNot(contains(secret)));
      }
    });

    test('תהליך אחר בשם otzaria אינו נספר', () {
      expect(linux([killed(9999), oomKill(9999)]), isNull);
      // pid שמכיל את ה-pid הקודם כתת-מחרוזת.
      expect(linux([killed(43210), oomKill(14321)]), isNull);
    });

    test('pid ממוחזר של תהליך אחר אינו נספר', () {
      expect(
        linux([
          killed(linuxPid, name: 'chrome'),
          oomKill(linuxPid, name: 'chrome'),
        ]),
        isNull,
      );
    });

    test('הריגה מחוץ לחלון הזמן אינה נספרת', () {
      final before = linuxStart.millisecondsSinceEpoch / 1000 - 60;
      expect(linux([killed(linuxPid, at: before)]), isNull);
    });

    test('שורה בלי חותמת זמן אינה נספרת', () {
      expect(linux([killed(linuxPid).replaceFirst('$inWindow', 'x')]), isNull);
    });
  });
}
