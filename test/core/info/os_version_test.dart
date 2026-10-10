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
}
