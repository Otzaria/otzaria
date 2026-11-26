import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/install_mode_switch.dart';

void main() {
  late List<List<String>> launches;
  late int quits;
  late int pins;

  setUp(() {
    launches = [];
    quits = 0;
    pins = 0;
  });

  InstallModeSwitcher switcher(
    WindowsInstallScope current, {
    bool launchSucceeds = true,
  }) => InstallModeSwitcher(
    currentScope: current,
    downloadInstaller: () async => File('otzaria-1.0.0.exe'),
    launch: (path, arguments) {
      launches.add([path, ...arguments]);
      return launchSucceeds;
    },
    keepDataPaths: () async => pins++,
  );

  test('the other scope is offered', () {
    expect(
      switcher(WindowsInstallScope.currentUser).otherScope,
      WindowsInstallScope.allUsers,
    );
    expect(
      switcher(WindowsInstallScope.allUsers).otherScope,
      WindowsInstallScope.currentUser,
    );
  });

  test(
    'launches the downloaded installer with the switch flag, then quits',
    () async {
      final launched = await switcher(
        WindowsInstallScope.currentUser,
      ).switchTo(WindowsInstallScope.allUsers, quit: () async => quits++);

      expect(launched, isTrue);
      expect(launches, [
        [File('otzaria-1.0.0.exe').absolute.path, '/SWITCHMODE=allusers'],
      ]);
      expect(quits, 1);
      expect(pins, 1, reason: 'נתיב האינדקס נקבע לפני ההחלפה');
    },
  );

  test('a failed launch keeps Otzaria open', () async {
    final launched = await switcher(
      WindowsInstallScope.allUsers,
      launchSucceeds: false,
    ).switchTo(WindowsInstallScope.currentUser, quit: () async => quits++);

    expect(launched, isFalse);
    expect(launches.single.last, '/SWITCHMODE=currentuser');
    expect(quits, 0);
  });

  test('outside an installed Windows copy there is nothing to switch', () {
    if (Platform.isWindows) return;
    expect(InstallModeSwitcher.forCurrentProcess(), isNull);
  });
}
