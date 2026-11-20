import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/previous_run_system_events.dart';

const _applicationError =
    "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>"
    "<System><Provider Name='Application Error'/>"
    "<EventID Qualifiers='0'>1000</EventID>"
    "<TimeCreated SystemTime='2026-11-15T23:10:00.1234567Z'/></System>"
    "<EventData><Data Name='AppName'>otzaria.exe</Data>"
    "<Data Name='AppVersion'>0.9.99.0</Data>"
    "<Data Name='ModuleName'>flutter_windows.dll</Data>"
    "<Data Name='ExceptionCode'>c0000005</Data>"
    "<Data Name='FaultingOffset'>0000000000a1b2c3</Data>"
    "<Data Name='ProcessId'>0x1092</Data>"
    r"<Data Name='AppPath'>C:\Users\someone\AppData\otzaria.exe</Data>"
    "<Data Name='PackageFullName'></Data>"
    "</EventData></Event>";

const _applicationHang =
    "<Event><System><Provider Name='Application Hang'/>"
    "<EventID Qualifiers='0'>1002</EventID>"
    "<TimeCreated SystemTime='2026-11-15T23:11:00Z'/></System>"
    "<EventData><Data>otzaria.exe</Data><Data>0.9.99.0</Data>"
    "<Data>1092</Data><Data>Quit</Data></EventData></Event>";

void main() {
  group('parseWindowsEvent', () {
    test('Application Error של ההפעלה: בלי נתיבים ושדות ריקים', () {
      final event = parseWindowsEvent(_applicationError, 0x1092);
      expect(event, isNotNull);
      expect(event!['provider'], 'Application Error');
      expect(event['eventId'], 1000);
      expect(event['time'], '2026-11-15T23:10:00.1234567Z');
      final data = event['data']! as Map<String, String>;
      expect(data['ModuleName'], 'flutter_windows.dll');
      expect(data['ExceptionCode'], 'c0000005');
      expect(data.containsKey('AppPath'), isFalse);
      expect(data.containsKey('PackageFullName'), isFalse);
    });

    test('Application Hang בלי שמות שדות, pid בלי 0x', () {
      final event = parseWindowsEvent(_applicationHang, 0x1092);
      expect(event?['eventId'], 1002);
      expect((event!['data']! as Map)['4'], 'Quit');
    });

    test('תהליך אחר: לא מצורף, גם כשה-hex שלו מופיע בשדה אחר', () {
      expect(parseWindowsEvent(_applicationError, 0x2000), isNull);
      expect(parseWindowsEvent(_applicationHang, 0x2000), isNull);
      expect(
        parseWindowsEvent(
          _applicationError.replaceAll('c0000005', '2000'),
          0x2000,
        ),
        isNull,
      );
    });
  });

  test('השאילתה מצומצמת לספקים, לטווח הזמן ולשם הקובץ', () {
    final query = windowsEventQuery(
      'otzaria.exe',
      DateTime.utc(2026, 11, 15, 22),
      DateTime.utc(2026, 11, 16, 8),
    );
    expect(query, contains("@Name='Application Error'"));
    expect(query, contains('EventID=1002'));
    expect(query, contains("@SystemTime>='2026-11-15T22:00:00.000Z'"));
    expect(query, contains("@SystemTime<='2026-11-16T08:00:00.000Z'"));
    expect(query, contains("Data='otzaria.exe'"));
  });

  test('לינוקס: רק הריגת התהליך הזה או OOM של otzaria', () {
    final lines = [
      'kernel: Out of memory: Killed process 4242 (otzaria) total-vm:1kB',
      'kernel: Killed process 42421 (other) total-vm:1kB',
      'kernel: oom-kill:constraint=CONSTRAINT_NONE,task=otzaria,pid=4242,uid=1',
      'kernel: usb 1-1: new device',
      'kernel: Out of memory: Killed process 77 (chrome) total-vm:1kB',
    ].where((line) => isLinuxOomLine(line, 4242)).toList();
    expect(lines, hasLength(2));
    expect(lines.first, contains('Killed process 4242 '));
    expect(lines.last, contains('pid=4242,'));
  });
}
