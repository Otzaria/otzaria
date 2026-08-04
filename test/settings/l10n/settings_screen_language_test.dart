import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';

import '../../test_helpers/memory_cache_provider.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('MySettingsScreen — שפת ההגדרות', () {
    late MockSettingsBloc settingsBloc;
    late _FakeSettingsRepository settingsRepository;

    setUp(() {
      settingsBloc = MockSettingsBloc();
      settingsRepository = _FakeSettingsRepository();
    });

    void givenLanguageCode(String code) {
      whenListen(
        settingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial().copyWith(
          settingsLanguageCode: code,
        ),
      );
    }

    /// קובע את שפת המערכת שהמסך יראה במצב "אוטומטי".
    void givenSystemLocale(WidgetTester tester, Locale locale) {
      tester.platformDispatcher.localeTestValue = locale;
      tester.platformDispatcher.localesTestValue = [locale];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    }

    // הספרייה והקורא נשארים RTL, ולכן העץ שמחוץ למסך מדמה את המצב האמיתי.
    Widget buildScreen() => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: RepositoryProvider<SettingsRepository>.value(
          value: settingsRepository,
          child: BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const MySettingsScreen(),
          ),
        ),
      ),
    );

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildScreen());
      await tester.pump(); // SaferModeGuard postFrame
      await tester.pump();
    }

    testWidgets('עברית — לשוניות בעברית והמסך RTL', (tester) async {
      givenLanguageCode(SettingsLanguage.hebrew.code);
      await pumpScreen(tester);

      expect(find.widgetWithText(SidebarNavItem, 'מראה'), findsOneWidget);
      expect(
        find.widgetWithText(SidebarNavItem, 'קיצורי מקשים'),
        findsOneWidget,
      );
      expect(find.text('הגדרות'), findsWidgets);

      expect(
        Directionality.of(tester.element(find.byType(SidebarNavItem).first)),
        TextDirection.rtl,
      );
    });

    testWidgets('אנגלית — לשוניות באנגלית והמסך LTR', (tester) async {
      givenLanguageCode(SettingsLanguage.english.code);
      await pumpScreen(tester);

      expect(find.widgetWithText(SidebarNavItem, 'Appearance'), findsOneWidget);
      expect(
        find.widgetWithText(SidebarNavItem, 'Keyboard shortcuts'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SidebarNavItem, 'מראה'), findsNothing);
      expect(find.text('Settings'), findsWidgets);

      expect(
        Directionality.of(tester.element(find.byType(SidebarNavItem).first)),
        TextDirection.ltr,
      );
    });

    testWidgets('אנגלית — העץ שמחוץ למסך ההגדרות נשאר RTL', (tester) async {
      givenLanguageCode(SettingsLanguage.english.code);
      await pumpScreen(tester);

      // ה-MaterialApp שמעל המסך מייצג את שאר האפליקציה.
      expect(
        Directionality.of(tester.element(find.byType(MySettingsScreen))),
        TextDirection.rtl,
      );
    });

    testWidgets('אנגלית — תוכן לשונית מראה מתורגם', (tester) async {
      givenLanguageCode(SettingsLanguage.english.code);
      await pumpScreen(tester);

      expect(find.text('Settings language'), findsWidgets);
      expect(find.text('Theme'), findsWidgets);
      expect(find.text('ערכת נושא'), findsNothing);
    });

    testWidgets('הבורר סגור מציג את השפה הנבחרת בלבד', (tester) async {
      givenLanguageCode(SettingsLanguage.hebrew.code);
      await pumpScreen(tester);

      expect(find.byType(AppDropdownField<String>), findsOneWidget);
      expect(find.text('עברית'), findsOneWidget);
      // האפשרויות האחרות מוסתרות עד לפתיחת התפריט.
      expect(find.text('English'), findsNothing);
    });

    testWidgets('פתיחת הבורר מציגה אוטומטי וכל שפה נתמכת בשמה שלה', (
      tester,
    ) async {
      givenLanguageCode(SettingsLanguage.hebrew.code);
      await pumpScreen(tester);

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      for (final language in SettingsLanguage.values) {
        expect(
          find.text(language.label),
          findsWidgets,
          reason: 'השפה ${language.code} חסרה בתפריט',
        );
      }
      expect(find.text('אוטומטי'), findsWidgets);
    });

    testWidgets('בחירה בתפריט משדרת את קוד השפה שנבחר', (tester) async {
      givenLanguageCode(SettingsLanguage.hebrew.code);
      await pumpScreen(tester);

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      verify(
        () => settingsBloc.add(
          UpdateSettingsLanguageCode(SettingsLanguage.english.code),
        ),
      ).called(1);
    });

    testWidgets('אוטומטי — מערכת בעברית מציגה הגדרות בעברית ו-RTL', (
      tester,
    ) async {
      givenSystemLocale(tester, const Locale('he', 'IL'));
      givenLanguageCode(kSettingsLanguageSystemCode);
      await pumpScreen(tester);

      expect(find.widgetWithText(SidebarNavItem, 'מראה'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(SidebarNavItem).first)),
        TextDirection.rtl,
      );
    });

    testWidgets('אוטומטי — מערכת באנגלית מציגה הגדרות באנגלית ו-LTR', (
      tester,
    ) async {
      givenSystemLocale(tester, const Locale('en', 'US'));
      givenLanguageCode(kSettingsLanguageSystemCode);
      await pumpScreen(tester);

      expect(find.widgetWithText(SidebarNavItem, 'Appearance'), findsOneWidget);
      expect(find.widgetWithText(SidebarNavItem, 'מראה'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(SidebarNavItem).first)),
        TextDirection.ltr,
      );
    });

    testWidgets('אוטומטי — שפת מערכת שאינה עברית נופלת לאנגלית', (
      tester,
    ) async {
      givenSystemLocale(tester, const Locale('fr', 'FR'));
      givenLanguageCode(kSettingsLanguageSystemCode);
      await pumpScreen(tester);

      expect(find.widgetWithText(SidebarNavItem, 'Appearance'), findsOneWidget);
    });

    testWidgets('בחירה מפורשת גוברת על שפת המערכת', (tester) async {
      givenSystemLocale(tester, const Locale('en', 'US'));
      givenLanguageCode(SettingsLanguage.hebrew.code);
      await pumpScreen(tester);

      expect(find.widgetWithText(SidebarNavItem, 'מראה'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(SidebarNavItem).first)),
        TextDirection.rtl,
      );
    });
  });
}
