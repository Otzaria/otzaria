import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/panels/install_mode_panel.dart';
import 'package:otzaria/update/install_mode_switch.dart';

void main() {
  late List<List<String>> launches;
  late int quits;

  setUp(() {
    launches = [];
    quits = 0;
  });

  Future<void> pumpPanel(
    WidgetTester tester,
    WindowsInstallScope current, {
    bool downloadFails = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: InstallModePanel(
              switcher: InstallModeSwitcher(
                currentScope: current,
                downloadInstaller: () async => downloadFails
                    ? throw const SocketException('offline')
                    : File('otzaria-1.0.0.exe'),
                launch: (path, arguments) {
                  launches.add(arguments);
                  return true;
                },
              ),
              quit: () async => quits++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('per-user install: shows the mode and moves to all users', (
    tester,
  ) async {
    await pumpPanel(tester, WindowsInstallScope.currentUser);

    expect(find.text('מותקנת רק למשתמש הנוכחי'), findsOneWidget);
    await tester.tap(find.text('העברה לכל המשתמשים'));
    await tester.pumpAndSettle();

    // אישור לפני שאוצריא נסגרת.
    expect(find.text('העברת אוצריא לכל המשתמשים'), findsOneWidget);
    expect(launches, isEmpty);
    await tester.tap(find.text('המשך'));
    await tester.pumpAndSettle();

    expect(launches, [
      ['/SWITCHMODE=allusers'],
    ]);
    expect(quits, 1);
  });

  testWidgets('all-users install: moves back to the current user', (
    tester,
  ) async {
    await pumpPanel(tester, WindowsInstallScope.allUsers);

    expect(find.text('מותקנת לכל המשתמשים במחשב'), findsOneWidget);
    await tester.tap(find.text('העברה למשתמש הנוכחי בלבד'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('המשך'));
    await tester.pumpAndSettle();

    expect(launches, [
      ['/SWITCHMODE=currentuser'],
    ]);
    expect(quits, 1);
  });

  testWidgets('cancel leaves everything as is', (tester) async {
    await pumpPanel(tester, WindowsInstallScope.currentUser);

    await tester.tap(find.text('העברה לכל המשתמשים'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(launches, isEmpty);
    expect(quits, 0);
  });

  testWidgets('a failed download keeps Otzaria open', (tester) async {
    await pumpPanel(
      tester,
      WindowsInstallScope.currentUser,
      downloadFails: true,
    );

    await tester.tap(find.text('העברה לכל המשתמשים'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('המשך'));
    await tester.pumpAndSettle();

    expect(launches, isEmpty);
    expect(quits, 0);
    expect(find.text('העברה לכל המשתמשים'), findsOneWidget);
  });

  testWidgets('hidden outside an installed Windows copy', (tester) async {
    if (Platform.isWindows) return;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: InstallModePanel())),
    );

    expect(find.text('סוג ההתקנה'), findsNothing);
  });
}
