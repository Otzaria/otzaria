import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/view/shortcut_dropdown_tile.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import '../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPluginSystemBloc
    extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

class _FakeSettingsEvent extends Fake implements SettingsEvent {}

// קיצורים שאינם בשימוש כברירת מחדל על ידי אף הגדרה
const String _unusedShortcut1 = 'ctrl+y';
const String _unusedShortcut2 = 'ctrl+shift+y';

Widget _buildTile({
  required _MockSettingsBloc bloc,
  required String settingKey,
  required String selectedShortcut,
  Map<String, String> allShortcuts = const {
    'ctrl+l': 'Ctrl+L',
    'ctrl+f': 'Ctrl+F',
    _unusedShortcut1: 'Ctrl+Y',
    _unusedShortcut2: 'Ctrl+Shift+Y',
  },
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    home: Scaffold(
      body: BlocProvider<SettingsBloc>.value(
        value: bloc,
        child: ShortcutDropDownTile(
          settingKey: settingKey,
          title: 'בדיקה',
          selected: selectedShortcut,
          allShortcuts: allShortcuts,
        ),
      ),
    ),
  );
}

Future<void> _drainUiSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeSettingsEvent());
  });

  late _MockSettingsBloc settingsBloc;
  late MemorySettingsCache cache;
  late StreamController<SettingsState> stateController;

  setUp(() async {
    cache = MemorySettingsCache();
    await Settings.init(cacheProvider: cache);
    settingsBloc = _MockSettingsBloc();
    stateController = StreamController<SettingsState>.broadcast();
    whenListen(
      settingsBloc,
      stateController.stream,
      initialState: SettingsState.initial(),
    );
  });

  tearDown(() async {
    await stateController.close();
    // MockBloc אינו זקוק לסגירה — close() על Mock זורק שגיאה
  });

  group('ShortcutDropDownTile - מניעת שמירת קיצורים כפולים', () {
    testWidgets('אינו שומר קיצור שכבר שייך להגדרה אחרת (ברירת מחדל)', (
      tester,
    ) async {
      // ברירת מחדל: key-shortcut-open-library-browser משתמש ב-ctrl+l
      await tester.pumpWidget(
        _buildTile(
          bloc: settingsBloc,
          settingKey: 'key-shortcut-search-current-window',
          selectedShortcut: 'ctrl+f',
        ),
      );
      await tester.pump();

      // מדמים בחירה ישירה של ctrl+l שתפוס על ידי open-library-browser
      final field = tester.widget<AppDropdownField<String>>(
        find.byType(AppDropdownField<String>),
      );
      field.onSelected?.call('ctrl+l');
      await tester.pump();

      verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
      await _drainUiSnack(tester);
    });

    testWidgets('שומר קיצור שאינו בשימוש על ידי אף הגדרה', (tester) async {
      await tester.pumpWidget(
        _buildTile(
          bloc: settingsBloc,
          settingKey: 'key-shortcut-search-current-window',
          selectedShortcut: 'ctrl+f',
        ),
      );
      await tester.pump();

      final field = tester.widget<AppDropdownField<String>>(
        find.byType(AppDropdownField<String>),
      );
      field.onSelected?.call(_unusedShortcut1);
      await tester.pump();

      verify(
        () => settingsBloc.add(any(that: isA<UpdateShortcut>())),
      ).called(1);
    });

    testWidgets('מאפשר שיתוף קיצור בין הגדרות מקבוצה תואמת', (tester) async {
      // key-shortcut-add-note ו-key-shortcut-calendar-toggle-events תואמות
      // גם כשהקיצור משותף ידנית, אין להציג שגיאת כפילות
      await tester.pumpWidget(
        _buildTile(
          bloc: settingsBloc,
          settingKey: 'key-shortcut-add-note',
          selectedShortcut: 'ctrl+n',
          allShortcuts: const {'ctrl+n': 'Ctrl+N', _unusedShortcut1: 'Ctrl+Y'},
        ),
      );
      await tester.pump();

      final field = tester.widget<AppDropdownField<String>>(
        find.byType(AppDropdownField<String>),
      );
      field.onSelected?.call('ctrl+n');
      await tester.pump();

      verify(
        () => settingsBloc.add(any(that: isA<UpdateShortcut>())),
      ).called(1);
    });

    testWidgets(
      'אינו שומר קיצור מותאם אישית שנשמר ב-cache ותפוס על ידי הגדרה אחרת',
      (tester) async {
        // מגדירים ידנית ב-cache שהגדרה אחרת משתמשת ב-_unusedShortcut2
        await cache.setString('key-shortcut-close-tab', _unusedShortcut2);

        await tester.pumpWidget(
          _buildTile(
            bloc: settingsBloc,
            settingKey: 'key-shortcut-open-history',
            selectedShortcut: 'ctrl+h',
          ),
        );
        await tester.pump();

        final field = tester.widget<AppDropdownField<String>>(
          find.byType(AppDropdownField<String>),
        );
        // מדמים קיצור מותאם אישית שמוחזר מהדיאלוג — אותו ערך שכבר תפוס
        field.onSelected?.call(_unusedShortcut2);
        await tester.pump();

        verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
        await _drainUiSnack(tester);
      },
    );
  });

  group('ShortcutValidator - זיהוי קיצורים כפולים', () {
    test('checkConflicts מגלה ערכים זהים בין הגדרות שאינן תואמות', () async {
      await cache.setString(
        'key-shortcut-open-library-browser',
        _unusedShortcut1,
      );
      await cache.setString('key-shortcut-close-tab', _unusedShortcut1);

      final conflicts = ShortcutValidator.checkConflicts();

      expect(conflicts, contains(_unusedShortcut1));
      expect(
        conflicts[_unusedShortcut1],
        containsAll(<String>[
          'key-shortcut-open-library-browser',
          'key-shortcut-close-tab',
        ]),
      );
    });

    test('checkConflicts אינו מדווח על קיצורים תואמים כקונפליקט', () async {
      // add-note ו-calendar-toggle-events מוגדרות כ-compatible
      await cache.setString('key-shortcut-add-note', _unusedShortcut2);
      await cache.setString(
        'key-shortcut-calendar-toggle-events',
        _unusedShortcut2,
      );

      final conflicts = ShortcutValidator.checkConflicts();

      expect(conflicts, isNot(contains(_unusedShortcut2)));
    });

    test('canShareShortcut מחזיר true עבור הגדרות מקבוצה תואמת', () {
      expect(
        ShortcutValidator.canShareShortcut(
          'key-shortcut-add-note',
          'key-shortcut-calendar-toggle-events',
        ),
        isTrue,
      );
    });

    test('canShareShortcut מחזיר false עבור הגדרות שאינן תואמות', () {
      expect(
        ShortcutValidator.canShareShortcut(
          'key-shortcut-open-library-browser',
          'key-shortcut-search-current-window',
        ),
        isFalse,
      );
    });
  });

  // ── ShortcutsSettingsTab._addShortcut ─────────────────────────────────────
  // בודק את זרימת "הוסף קיצור לפעולה זמינה": בחירת פעולה ריקה → הקלטת קיצור.
  // key-shortcut-open-commentators-tab ריק כברירת מחדל ולכן הכרטיס תמיד מופיע.

  group('ShortcutsSettingsTab - זרימת הוסף קיצור', () {
    Widget buildTab() {
      final pluginBloc = _MockPluginSystemBloc();
      whenListen(
        pluginBloc,
        const Stream<PluginSystemState>.empty(),
        initialState: PluginSystemInitial(),
      );
      return MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
            ],
            child: const ShortcutsSettingsTab(),
          ),
        ),
      );
    }

    // מסייע: מנווט עד ל-CustomShortcutDialog ומחזיר לאחר פתיחתו.
    Future<void> openCustomDialog(
      WidgetTester tester, {
      bool startRecording = true,
    }) async {
      await tester.pumpWidget(buildTab());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('הוסף קיצור'));
      await tester.tap(find.text('הוסף קיצור'));
      await tester.pumpAndSettle();

      // בחירת "פתח כרטיסיית מפרשים" (הפעולה הריקה כברירת מחדל)
      await tester.tap(find.text('פתח כרטיסיית מפרשים'));
      await tester.pumpAndSettle();

      if (startRecording) {
        // מצב הקלטה
        await tester.tap(find.text('התחל הקלטה'));
        await tester.pump();
      }
    }

    testWidgets('מציג כפתור "הוסף קיצור" כשיש פעולה ללא קיצור', (tester) async {
      await tester.pumpWidget(buildTab());
      await tester.pumpAndSettle();

      expect(find.text('הוסף קיצור'), findsOneWidget);
    });

    testWidgets('מציג את קיצור שחזור הכרטיסייה שנסגרה ברשימת הקיצורים', (
      tester,
    ) async {
      await tester.pumpWidget(buildTab());
      await tester.pumpAndSettle();

      expect(find.text('פתח כרטיסייה אחרונה שנסגרה'), findsOneWidget);
    });

    testWidgets('אינו שומר קיצור מוקלט שכבר תפוס', (tester) async {
      await openCustomDialog(tester);

      // הקלטת ctrl+l — תפוס על ידי key-shortcut-open-library-browser
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.pump();

      await tester.tap(find.text('עצור הקלטה'));
      await tester.pump();
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
      await _drainUiSnack(tester);
    });

    testWidgets('לא סוגר את הדיאלוג כשמנסים לאשר בלי להקליט קיצור', (
      tester,
    ) async {
      await openCustomDialog(tester, startRecording: false);

      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      expect(find.text('הגדרת קיצור מקשים מותאם אישית'), findsOneWidget);
      expect(find.text('יש לבחור קיצור'), findsOneWidget);
      verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
      await _drainUiSnack(tester);
    });

    testWidgets('שומר קיצור מוקלט שאינו בשימוש', (tester) async {
      await openCustomDialog(tester);

      // הקלטת ctrl+y — אינו בשימוש
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.pump();

      await tester.tap(find.text('עצור הקלטה'));
      await tester.pump();
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      verify(
        () => settingsBloc.add(any(that: isA<UpdateShortcut>())),
      ).called(1);
    });
  });
}
