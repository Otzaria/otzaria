// כלי מדידה ידני: מצב המופעים החיים של פרויקט השו"ת.
//
// `lifecycle` דוגם את מחזור החיים סביב הפעלה קרה — כולל המופע החונה
// שנשאר אחרי סגירה. `parked` מבדיל בין ממוזער לחונה ובודק אם החונה
// מגיב לפקודות.
//
//   flutter test --run-skipped test/external_catalog/live_probe_instances_test.dart
//   RESPONSA_LAUNCH=1 flutter test --run-skipped \
//     test/external_catalog/live_probe_instances_test.dart --plain-name lifecycle
@Tags(['live'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/responsa_failure.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:win32/win32.dart';

final _isHungAppWindow = DynamicLibrary.open('user32.dll')
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsHungAppWindow',
    );

String _describe(ResponsaInstance instance) {
  final handle = HWND(Pointer.fromAddress(instance.hwnd));

  final rect = calloc<RECT>();
  GetWindowRect(handle, rect);
  final corner = '${rect.ref.left},${rect.ref.top}';
  calloc.free(rect);

  final placement = calloc<WINDOWPLACEMENT>()
    ..ref.length = sizeOf<WINDOWPLACEMENT>();
  GetWindowPlacement(handle, placement);
  final showCmd = placement.ref.showCmd;
  calloc.free(placement);

  return 'pid=${instance.pid} usable=${instance.usable} '
      'visible=${instance.visible} onScreen=${instance.onScreen} '
      'iconic=${instance.minimized} showCmd=$showCmd '
      'hung=${_isHungAppWindow(instance.hwnd) != 0} '
      'at=$corner mdi=${instance.openWindows}';
}

String _snapshot() {
  final lines = [for (final i in ResponsaInstance.all()) '    ${_describe(i)}'];
  return lines.isEmpty ? '    (none)' : lines.join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lifecycle', () async {
    print('=== now ===\n${_snapshot()}');
    if (Platform.environment['RESPONSA_LAUNCH'] != '1') return;

    final selection = ResponsaInstallationDiscovery.selectInstallation();
    expect(selection, isNotNull);
    final installation = selection!.installation;
    print('install: ${installation.installPath}');

    Process.runSync('taskkill', ['/F', '/IM', 'RESPONSA.exe']);
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      print('=== kill+${(i + 1) * 500}ms ===\n${_snapshot()}');
    }

    final watch = Stopwatch()..start();
    await Process.start(
      installation.executable,
      const [],
      workingDirectory: installation.installPath,
      mode: ProcessStartMode.detached,
    );

    var previous = '';
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final line = _snapshot();
      if (line != previous) {
        print('=== t+${watch.elapsedMilliseconds}ms ===\n$line');
        previous = line;
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('parked', () async {
    final instances = ResponsaInstance.all();
    print(_snapshot());

    final onScreen = instances.where((i) => i.onScreen).toList();
    if (onScreen.isNotEmpty) {
      final handle = HWND(Pointer.fromAddress(onScreen.first.hwnd));
      print('\n-- minimizing ${onScreen.first.pid}');
      ShowWindow(handle, SHOW_WINDOW_CMD(6)); // SW_MINIMIZE
      await Future<void>.delayed(const Duration(seconds: 1));
      print('   ${_describe(onScreen.first)}');
      ShowWindow(handle, SHOW_WINDOW_CMD(9)); // SW_RESTORE
      await Future<void>.delayed(const Duration(seconds: 1));
      print('   ${_describe(onScreen.first)}');
    }

    // האם מופע חונה בכלל מגיב? אם כן — ספרים נפתחו לתוכו בלי שאיש ראה.
    for (final instance in instances.where((i) => !i.onScreen)) {
      print('\n-- driving parked ${instance.pid}');
      final automation = ResponsaAutomation(
        pid: instance.pid,
        profile: ResponsaVersionProfile.forVersion(
          ResponsaInstallationDiscovery.versionFromWindowTitle(instance.title),
        ),
      );
      try {
        final dialog = automation.ensureCitationDialog(
          ResponsaDeadline(const Duration(seconds: 20)),
        );
        print(
          '   citation dialog FOUND: ${dialog.controls.length} controls — '
          'מופע חונה פותח ספרים בהצלחה, והמשתמש אינו רואה דבר',
        );
      } on ResponsaAutomationException catch (error) {
        print('   no dialog: ${error.failure.name} ${error.message}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
