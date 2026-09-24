// כלי מדידה ידני: מה גילוי ההתקנות מוצא על המכונה הזו, וכמה זמן הוא לוקח.
@Tags(['live'])
library;

// כלי מדידה ידני: הפלט שלו הוא **התוצר**, והוא נקרא בטרמינל.
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';

void main() {
  test('discover', () {
    final watch = Stopwatch()..start();
    final installations = ResponsaInstallationDiscovery.discover();
    watch.stop();
    print('discovery took ${watch.elapsedMilliseconds}ms');
    for (final installation in installations) {
      print(
        '  ${installation.installPath}\n'
        '     source=${installation.source} version=${installation.version} '
        'exists=${installation.exists}\n'
        '     archive=${installation.archivePath}\n'
        '     dataLocation=${installation.dataLocation}\n'
        '     instances=${ResponsaInstallationDiscovery.instancesOf(installation.installPath).length}',
      );
    }
    final selection = ResponsaInstallationDiscovery.selectInstallation();
    print(
      'selected: ${selection?.installation.installPath} '
      'instances=${selection?.instances.length}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
