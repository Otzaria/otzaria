import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/hebrew_update_widgets.dart';
import 'package:otzaria/update/install_mode_switch.dart';
import 'package:otzaria/update/updat_compat.dart';

void main() {
  late List<List<String>> launches;
  late int regularUpdates;

  setUp(() {
    launches = [];
    regularUpdates = 0;
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => hebrewDefaultDialog(
                context: context,
                latestVersion: '0.10.2',
                appVersion: '0.10.1',
                status: UpdatStatus.available,
                changelog: null,
                checkForUpdate: () {},
                openDialog: () {},
                startUpdate: () => regularUpdates++,
                launchInstaller: () async {},
                dismissUpdate: () {},
                installModeSwitcher: InstallModeSwitcher(
                  currentScope: WindowsInstallScope.currentUser,
                  downloadInstaller: () async => File('otzaria-0.10.2.exe'),
                  launch: (path, arguments) {
                    launches.add(arguments);
                    return false;
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('without the option the regular update runs', (tester) async {
    await openDialog(tester);

    expect(find.text('התקנת העדכון לכל המשתמשים במחשב'), findsOneWidget);
    await tester.tap(find.text('עדכן כעת'));
    await tester.pumpAndSettle();

    expect(regularUpdates, 1);
    expect(launches, isEmpty);
  });

  testWidgets('with the option the installer runs in switch mode', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.text('התקנת העדכון לכל המשתמשים במחשב'));
    await tester.pump();
    await tester.tap(find.text('עדכן כעת'));
    await tester.pumpAndSettle();

    expect(regularUpdates, 0);
    expect(launches, [
      ['/SWITCHMODE=allusers'],
    ]);
  });
}
