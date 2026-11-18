import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';

import '../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPluginSystemBloc
    extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

class _FakeSettingsEvent extends Fake implements SettingsEvent {}

/// מקשי החיצים שאזור הקריאה מטפל בהם, כקיצורים עם ברירת מחדל (issue #2851).
const _readerDefaults = [
  ('key-shortcut-next-segment-reader', 'הקטע הבא (באזור הקריאה)', 'arrowleft'),
  (
    'key-shortcut-prev-segment-reader',
    'הקטע הקודם (באזור הקריאה)',
    'arrowright',
  ),
  (
    'key-shortcut-next-toc-reader',
    'הדף/פרק הבא (באזור הקריאה)',
    'ctrl+arrowleft',
  ),
  (
    'key-shortcut-prev-toc-reader',
    'הדף/פרק הקודם (באזור הקריאה)',
    'ctrl+arrowright',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => registerFallbackValue(_FakeSettingsEvent()));

  late MemorySettingsCache cache;
  late _MockSettingsBloc settingsBloc;

  setUp(() async {
    ShortcutHelper.isMacForTesting = false;
    addTearDown(() => ShortcutHelper.isMacForTesting = null);
    cache = MemorySettingsCache();
    await Settings.init(cacheProvider: cache);
    settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
  });

  Future<void> pumpShortcutsTab(
    WidgetTester tester, {
    SettingsLanguage language = SettingsLanguage.hebrew,
  }) async {
    final pluginBloc = _MockPluginSystemBloc();
    whenListen(
      pluginBloc,
      const Stream<PluginSystemState>.empty(),
      initialState: PluginSystemInitial(),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) =>
            SettingsTextScope(language: language, child: child!),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
            ],
            child: const ShortcutsSettingsTab(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// מקליט [key] (עם [modifier] לחוץ) לאריח [settingKey] דרך "התאמה אישית".
  Future<void> record(
    WidgetTester tester,
    String settingKey,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
  }) async {
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is AppDropdownField<String> &&
          '${widget.key}'.contains("'${settingKey}_"),
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    tester.widget<AppDropdownField<String>>(field).onSelected!('__custom__');
    await tester.pumpAndSettle();
    await tester.tap(find.text('התחל הקלטה'));
    await tester.pump();
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    await tester.tap(find.text('עצור הקלטה'));
    await tester.pump();
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();
  }

  List<(String, String)> savedShortcuts() => [
    for (final event in verify(
      () => settingsBloc.add(captureAny(that: isA<UpdateShortcut>())),
    ).captured.cast<UpdateShortcut>())
      (event.key, event.value),
  ];

  Future<void> dismissSnack(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  for (final mac in [false, true]) {
    testWidgets('מקשי החיצים של אזור הקריאה מוצגים כברירות מחדל (mac=$mac)', (
      tester,
    ) async {
      ShortcutHelper.isMacForTesting = mac;
      await pumpShortcutsTab(tester);

      for (final (key, label, value) in _readerDefaults) {
        expect(find.text(label), findsOneWidget, reason: key);
        expect(
          find.descendant(
            of: find.byKey(ValueKey('${key}_$value')),
            matching: find.text(ShortcutHelper.formatShortcutForDisplay(value)),
          ),
          findsOneWidget,
          reason: key,
        );
      }
    });
  }

  testWidgets('בממשק באנגלית השורות מתורגמות', (tester) async {
    await pumpShortcutsTab(tester, language: SettingsLanguage.english);

    expect(find.text('Next Section (Reading Area)'), findsOneWidget);
  });

  test('תוצאות החיפוש של קיצורי הקורא מתורגמות לאנגלית', () {
    for (final key in ShortcutValidator.readerShortcutKeys) {
      final entry = ShortcutsSettingsTab.searchEntries.singleWhere(
        (entry) => entry.expandSection == key,
      );
      expect(
        entry.titleIn(SettingsLanguage.english),
        isNot(contains(entry.title)),
      );
      expect(
        entry.subtitleIn(SettingsLanguage.english),
        isNot(contains(entry.subtitle)),
      );
    }
  });

  testWidgets('← לפעולה אחרת תפוס כמו כל קיצור, ואחרי ביטולו באזור הקריאה '
      'נקלט', (tester) async {
    await pumpShortcutsTab(tester);

    await record(
      tester,
      'key-shortcut-open-settings',
      LogicalKeyboardKey.arrowLeft,
    );
    verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
    expect(
      find.text('קיצור זה כבר בשימוש עבור: הקטע הבא (באזור הקריאה)'),
      findsOneWidget,
    );
    await dismissSnack(tester);

    await SettingsRepository().updateShortcut(
      'key-shortcut-next-segment-reader',
      '',
    );
    await record(
      tester,
      'key-shortcut-open-settings',
      LogicalKeyboardKey.arrowLeft,
    );
    expect(savedShortcuts(), [('key-shortcut-open-settings', 'arrowleft')]);
  });

  testWidgets('←/→ ו-Ctrl+←/→ נקלטים לפעולות הניווט עצמן, וחץ בכיוון ההפוך '
      'תפוס בידי הפעולה ההפוכה', (tester) async {
    await pumpShortcutsTab(tester);

    await record(
      tester,
      'key-shortcut-next-segment',
      LogicalKeyboardKey.arrowLeft,
    );
    await record(
      tester,
      'key-shortcut-prev-toc',
      LogicalKeyboardKey.arrowRight,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(savedShortcuts(), [
      ('key-shortcut-next-segment', 'arrowleft'),
      ('key-shortcut-prev-toc', 'ctrl+arrowright'),
    ]);

    await record(
      tester,
      'key-shortcut-next-segment',
      LogicalKeyboardKey.arrowRight,
    );
    verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
    expect(
      find.text('קיצור זה כבר בשימוש עבור: הקטע הקודם (באזור הקריאה)'),
      findsOneWidget,
    );
    await dismissSnack(tester);
  });

  test('קיצורים שמורים נשארים כפי שהם בטעינת ההגדרות, כולל ← ל"הקטע הבא" '
      'ו-Alt+↓ לספרייה', () async {
    const saved = {
      'key-shortcut-next-segment': 'arrowleft',
      'key-shortcut-open-library-browser': 'alt+arrowdown',
      'key-shortcut-prev-segment': 'arrowright',
      'key-shortcut-next-toc': 'ctrl+arrowleft',
      'key-shortcut-open-settings': 'arrowup',
      'key-shortcut-prev-toc-reader': '',
    };
    for (final mac in [false, true]) {
      ShortcutHelper.isMacForTesting = mac;
      await Settings.init(cacheProvider: cache = MemorySettingsCache());
      final repository = SettingsRepository();
      for (final MapEntry(:key, :value) in saved.entries) {
        await repository.updateShortcut(key, value);
      }

      final settings = await repository.loadSettings();

      final shortcuts = settings['shortcuts'] as Map<String, String>;
      for (final MapEntry(:key, :value) in saved.entries) {
        expect(cache.getString(key), value, reason: 'mac=$mac $key');
        expect(shortcuts[key], value, reason: 'mac=$mac $key');
      }
    }
  });
}
