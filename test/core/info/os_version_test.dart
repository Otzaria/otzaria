import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/os_version.dart';

void main() {
  String windows(String raw) => displayOsVersion(raw: raw, isWindows: true);

  group('displayOsVersion', () {
    test('Windows 10 (Build 19045) נשאר ללא שינוי', () {
      const raw = '"Windows 10 Pro" 10.0 (Build 19045)';
      expect(windows(raw), raw);
    });

    test('Build 22000 ומעלה מזוהה כ-Windows 11, ושאר המחרוזת נשמרת', () {
      expect(
        windows('"Windows 10 Pro" 10.0 (Build 22000)'),
        '"Windows 11 Pro" 10.0 (Build 22000)',
      );
      expect(
        windows('"Windows 10 Pro" 10.0 (Build 22631)'),
        '"Windows 11 Pro" 10.0 (Build 22631)',
      );
      expect(
        windows('"Windows 10 Home" 10.0 (Build 26100)'),
        '"Windows 11 Home" 10.0 (Build 26100)',
      );
    });

    test('המחרוזת של Dart החדש: קידומת Microsoft ותווי כיוון', () {
      expect(
        windows('"\u200f\u200fMicrosoft Windows 10 Home" 10.0 (Build 26300)'),
        '"\u200f\u200fMicrosoft Windows 11 Home" 10.0 (Build 26300)',
      );
      const already11 =
          '"\u200f\u200fMicrosoft Windows 11 Home" 10.0 (Build 26300)';
      expect(windows(already11), already11);
    });

    test('Build 21999 הוא עדיין Windows 10', () {
      const raw = '"Windows 10 Pro" 10.0 (Build 21999)';
      expect(windows(raw), raw);
    });

    test('מחרוזת בלי מספר Build נשארת ללא שינוי', () {
      expect(windows('"Windows 10 Pro" 10.0'), '"Windows 10 Pro" 10.0');
      expect(windows(''), '');
    });

    test('Windows Server נשאר ללא שינוי', () {
      const server2022 = '"Windows Server 2022 Datacenter" 10.0 (Build 20348)';
      const server2025 = '"Windows Server 2025 Standard" 10.0 (Build 26100)';
      expect(windows(server2022), server2022);
      expect(windows(server2025), server2025);
    });

    test('פלטפורמה שאינה Windows נשארת ללא שינוי', () {
      const raw = '"Windows 10 Pro" 10.0 (Build 26100)';
      expect(displayOsVersion(raw: raw, isWindows: false), raw);
      const mac = 'Version 14.2.1 (Build 23C71)';
      expect(displayOsVersion(raw: mac, isWindows: false), mac);
    });

    test('ברירת המחדל קוראת את מערכת ההפעלה הנוכחית', () {
      expect(
        displayOsVersion(),
        displayOsVersion(
          raw: Platform.operatingSystemVersion,
          isWindows: Platform.isWindows,
        ),
      );
    });
  });

  group('operating system details', () {
    test(
      'Linux includes distribution version and kernel, without machine ID',
      () {
        expect(
          describeOperatingSystem('linux', '6.8.0', {
            'prettyName': 'Ubuntu 24.04.1 LTS',
            'machineId': 'private',
          }),
          'Ubuntu 24.04.1 LTS; kernel 6.8.0',
        );
        expect(
          describeOperatingSystem('linux', '6.1', {
            'name': 'Debian GNU/Linux',
            'version': '12 (bookworm)',
          }),
          'Debian GNU/Linux 12 (bookworm); kernel 6.1',
        );
      },
    );

    test('Android includes release, API, model, build and security patch', () {
      expect(
        describeOperatingSystem('android', 'Linux kernel', {
          'version': {
            'release': '15',
            'sdkInt': 35,
            'securityPatch': '2025-03-05',
          },
          'display': 'AP4A.250305.002',
          'manufacturer': 'Google',
          'model': 'Pixel 9',
          'id': 'not-needed',
        }),
        'Android 15; API 35; Google Pixel 9; build AP4A.250305.002; security patch 2025-03-05',
      );
    });

    test('macOS and iOS report product versions rather than only Darwin', () {
      expect(
        describeOperatingSystem('macos', 'Darwin', {
          'majorVersion': 15,
          'minorVersion': 4,
          'patchVersion': 1,
          'osRelease': '24.4.0',
          'computerName': 'private',
        }),
        'macOS 15.4.1; Darwin 24.4.0',
      );
      expect(
        describeOperatingSystem('ios', 'Darwin', {
          'systemName': 'iPadOS',
          'systemVersion': '18.4',
          'utsname': {
            'release': '24.4.0',
            'machine': 'iPad14,3',
            'nodename': 'private',
          },
          'name': 'private',
        }),
        'iPadOS 18.4; iPad14,3; Darwin 24.4.0',
      );
    });

    test('unknown platforms and incomplete details retain useful fallback', () {
      expect(describeOperatingSystem('fuchsia', 'build123', {}), 'build123');
      expect(describeOperatingSystem('android', '6.8', {}), 'Android 6.8');
      expect(
        describeOperatingSystem('macos', 'Version 14.1', {}),
        'macOS Version 14.1',
      );
      expect(
        describeOperatingSystem('ios', 'Version 18.1', {}),
        'iOS Version 18.1',
      );
      expect(describeOperatingSystem('linux', '6.1', {}), 'Linux; kernel 6.1');
      expect(
        describeOperatingSystem('linux', 'x' * 300, {}).length,
        200,
      );
    });
  });

  group('OS cache', () {
    test(
      'reads never wait and concurrent warmups share one collection',
      () async {
        var calls = 0;
        final result = Completer<Map<String, dynamic>>();
        final cache = OsDescriptionCache(
          platform: 'linux',
          rawVersion: '6.8',
          readDetails: () {
            calls++;
            return result.future;
          },
        );
        expect(cache.value, '6.8');
        expect(calls, 0);
        final first = cache.initialize();
        final second = cache.initialize();
        expect(cache.value, '6.8');
        expect(calls, 1);
        result.complete({'prettyName': 'Ubuntu 24.04'});
        await Future.wait([first, second]);
        expect(cache.value, 'Ubuntu 24.04; kernel 6.8');
        await cache.initialize();
        expect(calls, 1);
      },
    );

    test('failure and timeout preserve fallback without retrying', () async {
      for (final timesOut in [false, true]) {
        var calls = 0;
        final cache = OsDescriptionCache(
          platform: 'linux',
          rawVersion: '6.8',
          timeout: Duration.zero,
          readDetails: () {
            calls++;
            if (timesOut) return Completer<Map<String, dynamic>>().future;
            throw StateError('plugin unavailable');
          },
        );
        await cache.initialize();
        await cache.initialize();
        expect(cache.value, '6.8');
        expect(calls, 1);
      }
    });

    test(
      'Windows keeps existing corrected edition and build without native IO',
      () async {
        final cache = OsDescriptionCache(
          platform: 'windows',
          rawVersion: '"Windows 10 Pro" 10.0 (Build 26100)',
          readDetails: () => throw StateError('must not run'),
        );
        await cache.initialize();
        expect(cache.value, '"Windows 11 Pro" 10.0 (Build 26100)');
      },
    );
  });
}
