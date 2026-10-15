import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

import '../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // הנתונים לא נטענים לעולם: הבדיקה עוסקת בסגירת הדיאלוג ולא בתצוגה המקדימה.
  Future<Future<bool?>> openPrintDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    await tester.pumpWidget(
      RepositoryProvider<SettingsRepository>.value(
        value: _FakeSettingsRepository(),
        child: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: const MaterialApp(home: Scaffold(body: SizedBox.expand())),
        ),
      ),
    );
    final result = showDialog<bool>(
      context: tester.element(find.byType(SizedBox).last),
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: Completer<String>().future,
        bookId: 'ספר',
        startLine: 0,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PrintingScreen), findsOneWidget);
    return result;
  }

  testWidgets('ESC סוגר את תצוגת ההדפסה ומחזיר null', (tester) async {
    final result = await openPrintDialog(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PrintingScreen), findsNothing);
    expect(await result, isNull);
  });

  testWidgets('לחיצה מחוץ לתצוגת ההדפסה אינה סוגרת', (tester) async {
    await openPrintDialog(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PrintingScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
