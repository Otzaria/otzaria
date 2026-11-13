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

const _nextSegmentKey = 'key-shortcut-next-segment';
const _prevSegmentKey = 'key-shortcut-prev-segment';
const _nextTocKey = 'key-shortcut-next-toc';
const _prevTocKey = 'key-shortcut-prev-toc';
const _navigationKeys = [
  _prevSegmentKey,
  _nextSegmentKey,
  _prevTocKey,
  _nextTocKey,
];

/// קיצורי הניווט בספר טקסט נבדקים רק אחרי עץ הפוקוס, וחץ לבד לא מגיע
/// אליהם לעולם: באזור הקריאה הוא מנווט וגולל, ומחוץ לו מעביר פוקוס (issue #2851).
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

  Future<void> recordAndConfirm(
    WidgetTester tester,
    LogicalKeyboardKey key,
  ) async {
    await tester.tap(find.text('התחל הקלטה'));
    await tester.pump();
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.tap(find.text('עצור הקלטה'));
    await tester.pump();
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();
  }

  for (final (language, message) in [
    (
      SettingsLanguage.hebrew,
      'באזור הקריאה החיצים כבר מנווטים וגוללים, ולכן קיצור ניווט על חץ לבדו '
          'לא יפעל. בחר צירוף אחר.',
    ),
    (
      SettingsLanguage.english,
      'In the reading area the arrow keys already navigate and scroll, so a '
          "navigation shortcut on an arrow key alone won't work. Choose a "
          'different combination.',
    ),
  ]) {
    testWidgets('← ל"הקטע הבא" מהאריח נדחה בהודעה והדיאלוג נשאר פתוח '
        '(${language.name})', (tester) async {
      await pumpShortcutsTab(tester, language: language);
      final field = find.byKey(
        const ValueKey('${_nextSegmentKey}_alt+arrowdown'),
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      tester.widget<AppDropdownField<String>>(field).onSelected!('__custom__');
      await tester.pumpAndSettle();

      await recordAndConfirm(tester, LogicalKeyboardKey.arrowLeft);

      verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
      expect(find.text('הגדרת קיצור מקשים מותאם אישית'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('"הוסף קיצור" ל"הדף/פרק הבא": ↓ נדחה, PageDown נשמר', (
    tester,
  ) async {
    // ערך ריק = הקיצור בוטל, ולכן הפעולה מוצעת ב"הוסף קיצור".
    await SettingsRepository().updateShortcut(_nextTocKey, '');
    await pumpShortcutsTab(tester);
    await tester.ensureVisible(find.text('הוסף קיצור'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הוסף קיצור'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הדף/פרק הבא'));
    await tester.pumpAndSettle();

    await recordAndConfirm(tester, LogicalKeyboardKey.arrowDown);
    verifyNever(() => settingsBloc.add(any(that: isA<UpdateShortcut>())));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // מחוץ לטקסט (כפתור בסרגל, למשל) PageDown מגיע לקיצור ומפעיל אותו.
    await recordAndConfirm(tester, LogicalKeyboardKey.pageDown);
    final saved =
        verify(
              () => settingsBloc.add(captureAny(that: isA<UpdateShortcut>())),
            ).captured.single
            as UpdateShortcut;
    expect((saved.key, saved.value), (_nextTocKey, 'pagedown'));
  });

  test('←/→ לקטעים ששמורים מגרסה קודמת נמחקים בטעינת ההגדרות, '
      'ו-Ctrl+→ ו-PageDown לדף/פרק נשארים', () async {
    final repository = SettingsRepository();
    // ההגדרה מהדיווח: ← לקטע הבא, → לקודם, Ctrl+→ לדף/פרק הקודם.
    await repository.updateShortcut(_nextSegmentKey, 'arrowleft');
    await repository.updateShortcut(_prevSegmentKey, 'arrowright');
    await repository.updateShortcut(_prevTocKey, 'ctrl+arrowright');
    await repository.updateShortcut(_nextTocKey, 'pagedown');

    final settings = await repository.loadSettings();

    expect(settings['shortcuts'], {
      ...ShortcutValidator.defaultShortcuts,
      _prevTocKey: 'ctrl+arrowright',
      _nextTocKey: 'pagedown',
    });
    expect(cache.getString(_nextSegmentKey), isNull);
    expect(cache.getString(_prevSegmentKey), isNull);
  });

  test('כל ברירת מחדל, כל צירוף אחר לניווט וחץ לבד לפעולה אחרת נשמרים '
      '(Windows ו-Mac)', () async {
    const modifiers = ['ctrl+', 'shift+', 'alt+', 'ctrl+alt+', 'ctrl+shift+'];
    const mainKeys = ['arrowleft', 'arrowright', 'arrowup', 'arrowdown'];
    const otherKeys = ['pageup', 'pagedown', 'home', 'end', 'tab', 'space'];
    for (final mac in [false, true]) {
      ShortcutHelper.isMacForTesting = mac;
      final cases = <Map<String, String>>[
        {
          for (final MapEntry(:key, :value)
              in ShortcutValidator.defaultShortcuts.entries)
            if (value.isNotEmpty) key: value,
        },
        for (final modifier in ['', ...modifiers])
          for (final mainKey in [...mainKeys, ...otherKeys])
            if (modifier.isNotEmpty || otherKeys.contains(mainKey))
              {for (final key in _navigationKeys) key: '$modifier$mainKey'},
        {
          for (final key in ShortcutValidator.shortcutKeys)
            if (!_navigationKeys.contains(key)) key: 'arrowleft',
        },
      ];
      for (final shortcuts in cases) {
        await Settings.init(cacheProvider: cache = MemorySettingsCache());
        final repository = SettingsRepository();
        for (final MapEntry(:key, :value) in shortcuts.entries) {
          await repository.updateShortcut(key, value);
        }

        await repository.loadSettings();

        for (final MapEntry(:key, :value) in shortcuts.entries) {
          expect(cache.getString(key), value, reason: 'mac=$mac $key: $value');
        }
      }
    }
  });
}
