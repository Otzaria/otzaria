// Regression test for commit 8c3496072 ("סינכרון אוטומטי - לא רק במסך
// ספרייה", https://otzaria.org/forum/post/5795): לפני התיקון הסינכרון
// האוטומטי (FileSyncBloc.StartSync / כיום LibraryUpdateBloc.StartLibraryUpdate)
// הופעל רק בתוך initState של LibraryBrowser, כך שמשתמש שלא פתח את מסך
// הספרייה לא קיבל סינכרון אוטומטי בכלל. התיקון מעביר את ההפעלה ל-
// MainWindowScreen._startFileSync, שרץ כחלק מהאתחול הכללי (דרך
// _tryStartDeferredStartupWork + StartupWorkGate) ללא תלות במסך הספרייה.
//
// הבדיקה משכפלת את הגארד מ-main_window_screen.dart._startFileSync ומוודאת
// שהוא יורה מבלי ש-LibraryBrowser אי-פעם נבנה.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/navigation/view/startup_work_gate.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

import '../helpers/memory_settings_cache.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

/// משכפל את `_startFileSync` + השער `_tryStartDeferredStartupWork` מ-
/// main_window_screen.dart: מפעיל סינכרון פעם אחת כשמותר להתחיל עבודות
/// startup, ללא כל תלות במסך הספרייה.
class _StartupSyncProbe extends StatefulWidget {
  final StartupWorkGate gate;
  const _StartupSyncProbe({required this.gate});

  @override
  State<_StartupSyncProbe> createState() => _StartupSyncProbeState();
}

class _StartupSyncProbeState extends State<_StartupSyncProbe> {
  bool _hasStartedFileSync = false;

  void _startFileSync() {
    if (_hasStartedFileSync) return;
    _hasStartedFileSync = true;

    final isAutoSync =
        Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true;
    final settingsState = context.read<SettingsBloc>().state;
    if (isAutoSync && settingsState.canUseSoftwareAndBookUpdates) {
      context.read<LibraryUpdateBloc>().add(const StartLibraryUpdate());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.gate.consumeStartPermission()) {
      _startFileSync();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const StartLibraryUpdate());
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<MockLibraryUpdateBloc> pumpProbe(
    WidgetTester tester, {
    required StartupWorkGate gate,
    required SettingsState settingsState,
  }) async {
    final settingsBloc = MockSettingsBloc();
    final libraryUpdateBloc = MockLibraryUpdateBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: settingsState,
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
        ],
        child: MaterialApp(home: _StartupSyncProbe(gate: gate)),
      ),
    );

    addTearDown(() async {
      await settingsBloc.close();
      await libraryUpdateBloc.close();
    });

    return libraryUpdateBloc;
  }

  group('סינכרון אוטומטי בעליית האפליקציה (רגרסיה לבאג פורום #5795)', () {
    testWidgets(
        'שולח StartLibraryUpdate ברגע שהשער נפתח - בלי מסך ספרייה בעץ הווידג\'טים',
        (tester) async {
      final gate = StartupWorkGate();
      gate.markLibraryLoaded();
      gate.markIndexingDecisionResolved(expectIndexing: false);

      final libraryUpdateBloc = await pumpProbe(
        tester,
        gate: gate,
        settingsState: SettingsState.initial(),
      );

      verify(() => libraryUpdateBloc.add(const StartLibraryUpdate()))
          .called(1);
    });

    testWidgets('לא שולח כשהשער עדיין לא נפתח (אינדוקס טרם הוכרע)',
        (tester) async {
      final gate = StartupWorkGate(); // לא סומן library/indexing

      final libraryUpdateBloc = await pumpProbe(
        tester,
        gate: gate,
        settingsState: SettingsState.initial(),
      );

      verifyNever(() => libraryUpdateBloc.add(const StartLibraryUpdate()));
    });

    testWidgets('לא שולח כשמצב מנותק (canUseSoftwareAndBookUpdates == false)',
        (tester) async {
      final gate = StartupWorkGate();
      gate.markLibraryLoaded();
      gate.markIndexingDecisionResolved(expectIndexing: false);

      final libraryUpdateBloc = await pumpProbe(
        tester,
        gate: gate,
        settingsState: SettingsState.initial().copyWith(isOfflineMode: true),
      );

      verifyNever(() => libraryUpdateBloc.add(const StartLibraryUpdate()));
    });
  });
}
