import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/search/settings_search_field.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';
import 'package:otzaria/settings/search/settings_search_results_view.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/view/custom_shortcut_dialog.dart';
import 'package:otzaria/shortcuts/view/shortcut_dropdown_tile.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';

import '../test_helpers/memory_cache_provider.dart';

class _TrackingCache extends MemoryCacheProvider {
  final writes = <String>[];

  @override
  Future<void> setObject<T>(String key, T? value) {
    writes.add(key);
    return super.setObject<T>(key, value);
  }

  @override
  Future<void> remove(String key) {
    writes.add(key);
    return super.remove(key);
  }
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  final dispatched = <SettingsEvent>[];

  _SettingsBloc()
    : super(SettingsState.initial().copyWith(settingsLanguageCode: 'he')) {
    on<SettingsEvent>((event, emit) async {
      dispatched.add(event);
      if (event is UpdateShortcut) {
        await Settings.setValue<String>(event.key, event.value);
        emit(
          state.copyWith(
            shortcuts: {...state.shortcuts, event.key: event.value},
          ),
        );
      }
    });
  }

  Future<void> setShortcut(String key, String value) async {
    await Settings.setValue<String>(key, value);
    emit(state.copyWith(shortcuts: {...state.shortcuts, key: value}));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NavigationBloc extends Cubit<NavigationState> implements NavigationBloc {
  _NavigationBloc()
    : super(const NavigationState(currentScreen: Screen.settings));

  void go(Screen screen) => emit(state.copyWith(currentScreen: screen));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PluginBloc extends Cubit<PluginSystemState> implements PluginSystemBloc {
  _PluginBloc() : super(const PluginSystemLoaded([]));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TourCubit extends Cubit<TourState> implements TourCubit {
  _TourCubit() : super(const TourState.inactive());

  @override
  Future<void> recordInteraction(TourInteraction interaction) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

SettingsSearchEntry _entry(String id) =>
    ShortcutsSettingsTab.searchEntries.singleWhere((entry) => entry.id == id);

Finder _dialogs() => find.byType(CustomShortcutDialog, skipOffstage: false);

Future<void> _finishNavigation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void _expectActionDialog(WidgetTester tester, String key, {String? reason}) {
  expect(
    _dialogs(),
    findsOneWidget,
    reason: reason ?? 'תוצאת החיפוש צריכה לפתוח את הגדרת הפעולה המבוקשת',
  );
  expect(
    tester.widget<CustomShortcutDialog>(_dialogs()).actionName,
    ShortcutValidator.shortcutNames[key],
  );
  expect(find.text('בחר פעולה להוספת קיצור'), findsNothing);
}

Future<void> _cancelDialog(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _dialogs(), matching: find.text('ביטול')),
  );
  await tester.pumpAndSettle();
  expect(_dialogs(), findsNothing);
}

Future<void> _clickSearchResult(WidgetTester tester, String id) async {
  final title = _entry(id).title;
  await tester.enterText(
    find.descendant(
      of: find.byType(SettingsSearchField),
      matching: find.byType(EditableText),
    ),
    title,
  );
  await tester.pumpAndSettle();
  final result = find.descendant(
    of: find.byType(SettingsSearchResultsView),
    matching: find.text(title, findRichText: true),
  );
  expect(result, findsOneWidget, reason: 'תוצאת החיפוש עצמה צריכה להיות קיימת');
  await tester.tap(result);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _TrackingCache cache;
  late _SettingsBloc settings;
  late _NavigationBloc navigation;
  late _PluginBloc plugins;
  late _TourCubit tour;
  late SettingsScreenController controller;

  setUp(() async {
    cache = _TrackingCache();
    await Settings.init(cacheProvider: cache);
    DynamicShortcutRegistry.instance.loadFromJson('[]');
    ShortcutValidator.registerPluginShortcutKeys(const {});
    ShortcutValidator.registerPluginShortcuts(const {});
    SettingsSearchRegistry.instance.consumePendingRequest();
    settings = _SettingsBloc();
    navigation = _NavigationBloc();
    plugins = _PluginBloc();
    tour = _TourCubit();
    controller = SettingsScreenController();
  });

  tearDown(() async {
    SettingsSearchRegistry.instance.consumePendingRequest();
    controller.dispose();
    await settings.close();
    await navigation.close();
    await plugins.close();
    await tour.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<SettingsRepository>.value(
          value: _SettingsRepository(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<NavigationBloc>.value(value: navigation),
              BlocProvider<PluginSystemBloc>.value(value: plugins),
              BlocProvider<TourCubit>.value(value: tour),
            ],
            child: BlocBuilder<NavigationBloc, NavigationState>(
              builder: (context, state) => Offstage(
                offstage: state.currentScreen != Screen.settings,
                child: MySettingsScreen(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> startScroll(WidgetTester tester) async {
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.nav.advanced_search'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ShortcutsSettingsTab),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      scrollable.position.isScrollingNotifier.value,
      isTrue,
      reason: 'הבדיקה צריכה לתפוס את הבקשה בזמן גלילה פעילה',
    );
    expect(_dialogs(), findsNothing);
  }

  const hiddenCases = [
    (
      id: 'shortcuts.nav.advanced_search',
      key: ShortcutValidator.openAdvancedSearchKey,
    ),
    (
      id: 'shortcuts.open_tool.calendar',
      key: 'key-shortcut-open-tool-calendar',
    ),
    (id: 'shortcuts.copy_link.book', key: ShortcutValidator.copyBookLinkKey),
    (id: 'shortcuts.book.print', key: ShortcutValidator.printKey),
  ];
  for (final item in hiddenCases) {
    testWidgets('קיצור מוסתר: ${item.id}', (tester) async {
      if (item.key == ShortcutValidator.printKey) {
        await Settings.setValue<String>(item.key, '');
      }
      await mount(tester);
      cache.writes.clear();
      await _clickSearchResult(tester, item.id);
      await _finishNavigation(tester);
      _expectActionDialog(tester, item.key);
      expect(settings.dispatched, isEmpty);
      expect(cache.writes, isEmpty);
      await _cancelDialog(tester);
      expect(cache.writes, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('בקשה שנשלחה לפני בניית המסך פותחת קיצור מוסתר', (tester) async {
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.nav.advanced_search'),
    );
    await mount(tester);
    cache.writes.clear();
    await _finishNavigation(tester);
    _expectActionDialog(tester, ShortcutValidator.openAdvancedSearchKey);
    await _cancelDialog(tester);
    expect(settings.dispatched, isEmpty);
    expect(cache.writes, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  const zoomCases = [
    (id: 'shortcuts.zoom.in', key: ShortcutValidator.zoomInKey),
    (id: 'shortcuts.zoom.out', key: ShortcutValidator.zoomOutKey),
    (id: 'shortcuts.zoom.reset', key: ShortcutValidator.zoomResetKey),
  ];
  for (final item in zoomCases) {
    testWidgets('קיצור זום שבוטל: ${item.id}', (tester) async {
      await Settings.setValue<String>(item.key, '');
      await mount(tester);
      cache.writes.clear();
      await _clickSearchResult(tester, item.id);
      await _finishNavigation(tester);
      _expectActionDialog(tester, item.key);
      await _cancelDialog(tester);
      expect(cache.writes, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('קיצור מוגדר נשאר בכרטיס הרגיל ללא פתיחת דיאלוג', (tester) async {
    await Settings.setValue<String>(
      ShortcutValidator.openAdvancedSearchKey,
      'ctrl+alt+q',
    );
    await mount(tester);
    cache.writes.clear();
    await _clickSearchResult(tester, 'shortcuts.nav.advanced_search');
    await _finishNavigation(tester);
    expect(_dialogs(), findsNothing);
    final tile = find.byWidgetPredicate(
      (widget) =>
          widget is ShortcutDropDownTile &&
          widget.settingKey == ShortcutValidator.openAdvancedSearchKey,
    );
    expect(tile, findsOneWidget);
    expect(
      tester.getRect(tile).overlaps(Offset.zero & const Size(1400, 900)),
      isTrue,
    );
    expect(cache.writes, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('קיצור שהוגדר אחרי הבקשה נפתר לפי המצב העדכני', (tester) async {
    await mount(tester);
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.nav.advanced_search'),
    );
    await settings.setShortcut(
      ShortcutValidator.openAdvancedSearchKey,
      'ctrl+alt+q',
    );
    cache.writes.clear();
    await tester.pump();
    await _finishNavigation(tester);
    expect(_dialogs(), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ShortcutDropDownTile &&
            widget.settingKey == ShortcutValidator.openAdvancedSearchKey,
      ),
      findsOneWidget,
    );
    expect(cache.writes, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('קיצור שבוטל אחרי הבקשה נפתח כפעולה זמינה', (tester) async {
    await mount(tester);
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.book.print'),
    );
    await settings.setShortcut(ShortcutValidator.printKey, '');
    cache.writes.clear();
    await tester.pump();
    await _finishNavigation(tester);
    _expectActionDialog(tester, ShortcutValidator.printKey);
    await _cancelDialog(tester);
    expect(cache.writes, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final leaveSettings in [true, false]) {
    testWidgets(
      'קיצור שהוגדר בזמן גלילה: ${leaveSettings ? 'יציאה מבטלת את ההבזק' : 'הישארות משלימה את ההבזק'}',
      (tester) async {
        await mount(tester);
        final flash = SettingsSearchRegistry.instance.flashNotifierFor(
          'shortcuts.nav',
        );
        expect(flash.value, isFalse);
        var flashCount = 0;
        void recordFlash() {
          if (flash.value) flashCount++;
        }

        flash.addListener(recordFlash);
        addTearDown(() => flash.removeListener(recordFlash));
        await startScroll(tester);
        await settings.setShortcut(
          ShortcutValidator.openAdvancedSearchKey,
          'ctrl+alt+q',
        );
        cache.writes.clear();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(ShortcutsSettingsTab),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          scrollable.position.isScrollingNotifier.value,
          isTrue,
          reason: 'הגלילה השנייה צריכה להתחיל אחרי הגדרת הקיצור',
        );
        final firstTarget = scrollable.position.pixels;
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          scrollable.position.pixels,
          lessThan(firstTarget),
          reason: 'הגלילה השנייה חוזרת מכרטיס הפעולות הזמינות לכרטיס הניווט',
        );
        expect(flashCount, 0);
        expect(_dialogs(), findsNothing);
        final tabState = tester.state(find.byType(ShortcutsSettingsTab));
        if (leaveSettings) {
          navigation.go(Screen.library);
          await tester.pump();
        }
        expect(
          navigation.state.currentScreen,
          leaveSettings ? Screen.library : Screen.settings,
        );
        expect(
          tester.state(find.byType(ShortcutsSettingsTab, skipOffstage: false)),
          same(tabState),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(
          flashCount,
          leaveSettings ? 0 : 1,
          reason: leaveSettings
              ? 'בקשה שבוטלה אינה רשאית להבזיק בסוף הגלילה השנייה'
              : 'בקשה פעילה ממשיכה להבזיק בכרטיס הקיצור שהוגדר',
        );
        expect(_dialogs(), findsNothing);
        expect(settings.dispatched, isEmpty);
        expect(cache.writes, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('אישור הקיצור כותב רק את הפעולה שנבחרה בחיפוש', (tester) async {
    await mount(tester);
    await _clickSearchResult(tester, 'shortcuts.nav.advanced_search');
    await _finishNavigation(tester);
    _expectActionDialog(tester, ShortcutValidator.openAdvancedSearchKey);
    cache.writes.clear();
    await tester.tap(find.text('התחל הקלטה'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(
      find.descendant(of: _dialogs(), matching: find.text('אישור')),
    );
    await tester.pumpAndSettle();
    expect(_dialogs(), findsNothing);
    expect(settings.dispatched, [
      const UpdateShortcut(
        ShortcutValidator.openAdvancedSearchKey,
        'ctrl+alt+q',
      ),
    ]);
    expect(cache.writes, [ShortcutValidator.openAdvancedSearchKey]);
    expect(
      Settings.getValue<String>(ShortcutValidator.openAdvancedSearchKey),
      'ctrl+alt+q',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('מסך שהוסר בזמן ההמתנה אינו פותח דיאלוג מאוחר', (tester) async {
    await mount(tester);
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.nav.advanced_search'),
    );
    await tester.pump();
    cache.writes.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await _finishNavigation(tester);
    expect(_dialogs(), findsNothing);
    expect(tester.takeException(), isNull);
    expect(cache.writes, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('בקשה חדשה לפני הגלילה מבטלת את הדיאלוג הישן', (tester) async {
    await mount(tester);
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.nav.advanced_search'),
    );
    await tester.pump();
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.open_tool.calendar'),
    );
    await tester.pump();
    await _finishNavigation(tester);
    _expectActionDialog(
      tester,
      'key-shortcut-open-tool-calendar',
      reason: 'רק הבקשה האחרונה רשאית לפתוח דיאלוג לפני תחילת הגלילה',
    );
    await _cancelDialog(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('בקשה חדשה בזמן הגלילה מבטלת את הדיאלוג הישן', (tester) async {
    await mount(tester);
    await startScroll(tester);
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.open_tool.calendar'),
    );
    await tester.pump();
    await _finishNavigation(tester);
    _expectActionDialog(
      tester,
      'key-shortcut-open-tool-calendar',
      reason: 'רק הבקשה האחרונה רשאית לפתוח דיאלוג בסיום הגלילה',
    );
    await _cancelDialog(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('יציאה מההגדרות בזמן גלילה אינה פותחת דיאלוג מעל הספרייה', (
    tester,
  ) async {
    await mount(tester);
    await startScroll(tester);
    cache.writes.clear();
    navigation.go(Screen.library);
    await tester.pump();
    expect(navigation.state.currentScreen, Screen.library);
    expect(
      find.byType(ShortcutsSettingsTab, skipOffstage: false),
      findsOneWidget,
    );
    await _finishNavigation(tester);
    expect(
      _dialogs(),
      findsNothing,
      reason: 'בקשת חיפוש שהמסך שלה כבר לא פעיל אינה רשאית לפתוח דיאלוג',
    );
    expect(cache.writes, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('יציאה וחזרה בזמן גלילה אינן מחיות בקשה ישנה', (tester) async {
    await mount(tester);
    await startScroll(tester);
    final tabState = tester.state(find.byType(ShortcutsSettingsTab));
    cache.writes.clear();
    navigation.go(Screen.library);
    await tester.pump();
    expect(navigation.state.currentScreen, Screen.library);
    expect(
      tester.state(find.byType(ShortcutsSettingsTab, skipOffstage: false)),
      same(tabState),
    );
    navigation.go(Screen.settings);
    await tester.pump();
    expect(navigation.state.currentScreen, Screen.settings);
    expect(tester.state(find.byType(ShortcutsSettingsTab)), same(tabState));
    await _finishNavigation(tester);
    expect(
      _dialogs(),
      findsNothing,
      reason: 'חזרה להגדרות אינה מתירה לבקשה שבוטלה לפתוח דיאלוג',
    );
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.copy_link.book'),
    );
    await tester.pump();
    await _finishNavigation(tester);
    _expectActionDialog(tester, ShortcutValidator.copyBookLinkKey);
    await _cancelDialog(tester);
    expect(settings.dispatched, isEmpty);
    expect(cache.writes, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('שאילתה חדשה ובחירת לשונית מבטלות ניווט שממתין', (tester) async {
    await mount(tester);
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.nav.advanced_search'),
    );
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(SettingsSearchField),
        matching: find.byType(EditableText),
      ),
      'גופן',
    );
    await _finishNavigation(tester);
    expect(_dialogs(), findsNothing);

    await tester.tap(find.widgetWithText(SidebarNavItem, 'מראה'));
    await tester.pump();
    SettingsSearchRegistry.instance.navigateToEntry(
      _entry('shortcuts.nav.advanced_search'),
    );
    await tester.pump();
    controller.openTab(SettingsTab.design);
    await tester.pump();
    await _finishNavigation(tester);
    expect(_dialogs(), findsNothing);
    expect(settings.dispatched, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
