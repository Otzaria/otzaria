import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyboardShortcuts', () {
    late MockSettingsBloc settingsBloc;
    late StreamController<SettingsState> settingsController;

    setUp(() {
      settingsBloc = MockSettingsBloc();
      settingsController = StreamController<SettingsState>.broadcast();

      whenListen(
        settingsBloc,
        settingsController.stream,
        initialState: SettingsState.initial(),
      );
    });

    tearDown(() async {
      await settingsController.close();
    });

    testWidgets('לא זורק שגיאה בזמן rebuild של קיצורים כששדה טקסט מחזיק focus',
        (tester) async {
      await tester.pumpWidget(
        BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: const TextField(),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, isNotNull);

      // עדכון shortcuts מטריגר rebuild של ה-FocusScope; לפני התיקון
      // FocusScopeNode חדש בכל rebuild היה זורק שגיאה כששדה טקסט מחזיק focus.
      settingsController.add(
        SettingsState.initial().copyWith(
          shortcuts: const {
            'key-shortcut-open-library-browser': 'ctrl+shift+l',
          },
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
