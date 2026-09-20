// כלי מדידה ידני: כמה חלונות מופע טרי מחזיר משחזור-הסשן.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session restore', () async {
    final selection = ResponsaInstallationDiscovery.selectInstallation();
    final installation = selection!.installation;
    final before = {for (final i in ResponsaInstance.all()) i.pid};
    await Process.start(
      installation.executable,
      const [],
      workingDirectory: installation.installPath,
      mode: ProcessStartMode.detached,
    );
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      for (final instance in ResponsaInstance.all()) {
        if (before.contains(instance.pid)) continue;
        final titles = ResponsaWin32.mdiTitles(instance.hwnd);
        print(
          't+${i + 1}s pid=${instance.pid} usable=${instance.usable} '
          'mdi=${titles.length}',
        );
        if (i > 25) {
          for (final t in titles.take(6)) {
            print('      $t');
          }
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
