import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_catalogs.g.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/l10n/settings_text_scope.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
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
// Ctrl+Y שייך להיסטוריה ב-macOS; הצירוף הזה פנוי בכל הפלטפורמות.
const String _unusedShortcut1 = 'ctrl+alt+y';
const String _unusedShortcut2 = 'ctrl+shift+y';

Widget _buildTile({
  required _MockSettingsBloc bloc,
  required String settingKey,
  required String selectedShortcut,
  Map<String, String> allShortcuts = const {
    'ctrl+l': 'Ctrl+L',
    'ctrl+f': 'Ctrl+F',
    _unusedShortcut1: 'Ctrl+Alt+Y',
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

void _expectUnusedShortcut(String shortcut) {
  expect(
    [
      for (final key in ShortcutValidator.shortcutKeys)
        if (ShortcutValidator.getShortcutValue(key) == shortcut) key,
    ],
    isEmpty,
    reason: 'הקיצור במתקן הבדיקה חייב להיות פנוי: $shortcut',
  );
}

Future<void> _drainUiSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

/// מקליט [keys] בדיאלוג הפתוח ומאשר, כמו משתמש: הקלטה, עצירה ואישור.
Future<void> _recordInDialog(
  WidgetTester tester,
  List<LogicalKeyboardKey> keys,
) async {
  await tester.tap(find.text('התחל הקלטה'));
  await tester.pump();
  for (final key in keys) {
    await tester.sendKeyDownEvent(key);
  }
  for (final key in keys.reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.tap(find.text('עצור הקלטה'));
  await tester.pump();
  await tester.tap(find.text('אישור'));
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
      _expectUnusedShortcut(_unusedShortcut1);
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

      final saved = verify(
        () => settingsBloc.add(captureAny(that: isA<UpdateShortcut>())),
      );
      saved.called(1);
      final event = saved.captured.single as UpdateShortcut;
      expect(event.key, 'key-shortcut-search-current-window');
      expect(event.value, _unusedShortcut1);
    });

    testWidgets('מאפשר שיתוף קיצור בין הגדרות מקבוצה תואמת', (tester) async {
      // key-shortcut-add-note ו-key-shortcut-calendar-toggle-events תואמות
      // גם כשהקיצור משותף ידנית, אין להציג שגיאת כפילות
      await tester.pumpWidget(
        _buildTile(
          bloc: settingsBloc,
          settingKey: 'key-shortcut-add-note',
          selectedShortcut: 'ctrl+n',
          allShortcuts: const {
            'ctrl+n': 'Ctrl+N',
            _unusedShortcut1: 'Ctrl+Alt+Y',
          },
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

    testWidgets('מציע "ללא קיצור" גם לפעולה מובנית ושומר ערך ריק', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTile(
          bloc: settingsBloc,
          settingKey: 'key-shortcut-open-library-browser',
          selectedShortcut: 'ctrl+l',
        ),
      );
      await tester.pump();

      final field = tester.widget<AppDropdownField<String>>(
        find.byType(AppDropdownField<String>),
      );
      expect(
        field.entries.map((e) => e.label),
        contains('ללא קיצור'),
      );

      field.onSelected?.call('__clear__');
      await tester.pump();

      final captured =
          verify(
                () => settingsBloc.add(captureAny(that: isA<UpdateShortcut>())),
              ).captured.single
              as UpdateShortcut;
      expect(captured.key, 'key-shortcut-open-library-browser');
      expect(captured.value, '');
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

    for (final mac in [false, true]) {
      testWidgets(
        'מקשי ניווט שהוקלטו לקטע הבא נדחים, וברירת המחדל Alt+↓ נשמרת '
        '(${mac ? 'macOS' : 'Windows'}) (issue #2851)',
        (tester) async {
          ShortcutHelper.isMacForTesting = mac;
          addTearDown(() => ShortcutHelper.isMacForTesting = null);
          await tester.pumpWidget(
            _buildTile(
              bloc: settingsBloc,
              settingKey: 'key-shortcut-next-segment',
              selectedShortcut: 'alt+arrowdown',
            ),
          );
          await tester.pump();
          tester
              .widget<AppDropdownField<String>>(
                find.byType(AppDropdownField<String>),
              )
              .onSelected
              ?.call('__custom__');
          await tester.pumpAndSettle();

          final primary = mac
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft;
          for (final keys in [
            [LogicalKeyboardKey.arrowLeft],
            [primary, LogicalKeyboardKey.arrowRight],
            [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.tab],
            [LogicalKeyboardKey.pageDown],
            [primary, LogicalKeyboardKey.home],
          ]) {
            await _recordInDialog(tester, keys);
            verifyNever(
              () => settingsBloc.add(any(that: isA<UpdateShortcut>())),
            );
            expect(find.text('הגדרת קיצור מקשים מותאם אישית'), findsOneWidget);
            expect(
              find.text(CommonMessages.shortcutNavigationKey),
              findsOneWidget,
            );
            await _drainUiSnack(tester);
          }

          await _recordInDialog(tester, [
            LogicalKeyboardKey.altLeft,
            LogicalKeyboardKey.arrowDown,
          ]);
          final saved = verify(
            () => settingsBloc.add(captureAny(that: isA<UpdateShortcut>())),
          );
          saved.called(1);
          expect(
            (saved.captured.single as UpdateShortcut).value,
            'alt+arrowdown',
          );
        },
      );
    }
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
    Widget buildTab({
      SettingsLanguage language = SettingsLanguage.hebrew,
    }) {
      final pluginBloc = _MockPluginSystemBloc();
      whenListen(
        pluginBloc,
        const Stream<PluginSystemState>.empty(),
        initialState: PluginSystemInitial(),
      );
      return MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: SettingsTextScope(
            language: language,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
                BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
              ],
              child: const ShortcutsSettingsTab(),
            ),
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
      // בוויופורט של slivers מיקום הילדים מתעדכן רק בפריסה הבאה, ובלי הפריים
      // הזה ההקשה נופלת על המיקום הישן שמחוץ למסך.
      await tester.pumpAndSettle();
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
      _expectUnusedShortcut(_unusedShortcut1);
      await openCustomDialog(tester);

      // הקלטת ctrl+alt+y — פנוי גם ב-macOS.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.pump();

      await tester.tap(find.text('עצור הקלטה'));
      await tester.pump();
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      final saved = verify(
        () => settingsBloc.add(captureAny(that: isA<UpdateShortcut>())),
      );
      saved.called(1);
      final event = saved.captured.single as UpdateShortcut;
      expect(event.key, 'key-shortcut-open-commentators-tab');
      expect(event.value, _unusedShortcut1);
    });

    testWidgets(
      'Tab שהוקלט ב"הוסף קיצור" נדחה בהודעה באנגלית (issue #2851)',
      (tester) async {
        await tester.pumpWidget(buildTab(language: SettingsLanguage.english));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Add shortcut'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add shortcut'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('פתח כרטיסיית מפרשים'));
        await tester.pumpAndSettle();

        await _recordInDialog(tester, [LogicalKeyboardKey.tab]);

        verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
        expect(
          find.text(
            kSettingsCatalogs['en']![CommonMessages.shortcutNavigationKey]!,
          ),
          findsOneWidget,
        );
        await _drainUiSnack(tester);
      },
    );
  });
}
