import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/windows_exit_evidence.dart';

void main() {
  final start = DateTime.utc(2026, 11, 20, 18);
  final end = DateTime.utc(2026, 11, 20, 20);
  const windowsFileTime = 0x1dd641d4200f000;
  const expectedPid = 0x1ed0;

  String event({
    int id = 1000,
    String? provider,
    String application = 'otzaria.exe',
    String pid = '0x1ed0',
    String? creationTime = '0x1dd641d4200f000',
    String exceptionCode = 'C0000005',
    String time = '2026-11-20T19:00:00.1234567Z',
    String additionalFields = '',
  }) {
    final startField = id == 1002 ? 'StartTime' : 'ProcessCreationTime';
    return '''
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <Provider Name="${provider ?? (id == 1002 ? 'Application Hang' : 'Application Error')}" />
    <EventID>$id</EventID>
    <TimeCreated SystemTime="$time" />
    <Execution ProcessID="$expectedPid" ThreadID="1" />
    <Computer>private-host</Computer>
  </System>
  <EventData>
    <Data Name="AppName">$application</Data>
    <Data Name="ProcessId">$pid</Data>
    ${creationTime == null ? '' : '<Data Name="$startField">$creationTime</Data>'}
    <Data Name="ExceptionCode">$exceptionCode</Data>
    <Data Name="AppPath">C:\\Users\\Private\\otzaria.exe</Data>
    <Data Name="ReportId">private-report-id</Data>
    $additionalFields
  </EventData>
</Event>
''';
  }

  WindowsExitEvidence? parse(String xml) => parseWindowsExitEvent(
    xml,
    executable: 'Otzaria.exe',
    processId: expectedPid,
    creationFileTime: windowsFileTime,
    from: start,
    until: end,
  );

  test('ראיית קריסה מכילה רק מזהה אירוע, זמן וקוד חריגה', () {
    final evidence = parse(event())!;
    expect(evidence.isHang, isFalse);
    expect(evidence.toJson(), {
      'eventId': 1000,
      'occurredAt': '2026-11-20T19:00:00.123456Z',
      'exceptionCode': '0xc0000005',
    });
  });

  test('Application Hang מזוהה לפי StartTime ואינו מדווח כקריסה', () {
    final evidence = parse(event(id: 1002))!;
    expect(evidence.isHang, isTrue);
    expect(evidence.toJson(), {
      'eventId': 1002,
      'occurredAt': '2026-11-20T19:00:00.123456Z',
    });
  });

  test('PID שגוי נדחה גם כשה-PID של ספק האירוע תואם', () {
    expect(parse(event(pid: '0x1ed1')), isNull);
  });

  test('PID ממוחזר, זמן יצירה חסר או שדה כפול אינם ראיה', () {
    expect(parse(event(creationTime: '0x1dd641d4200f001')), isNull);
    expect(parse(event(creationTime: null)), isNull);
    expect(
      parse(event(additionalFields: '<Data Name="ProcessId">0x1ed0</Data>')),
      isNull,
    );
  });

  test('התאמת השם ועמידה בטווח הזמן נבדקות גם לאחר שאילתת Windows', () {
    expect(parse(event(application: 'other-otzaria.exe')), isNull);
    expect(parse(event(time: '2026-11-20T17:59:59.999999Z')), isNull);
    expect(parse(event(time: end.toIso8601String())), isNull);
  });

  test('ספק או מזהה אירוע זר, או XML פגום, נדחים', () {
    expect(parse(event(id: 1002, provider: 'Application Error')), isNull);
    expect(parse(event(id: 1001)), isNull);
    expect(parse('<Event><System>'), isNull);
  });

  test('טקסט במקום קוד חריגה מושמט', () {
    expect(
      parse(event(exceptionCode: 'private value'))?.exceptionCode,
      isNull,
    );
  });
}
