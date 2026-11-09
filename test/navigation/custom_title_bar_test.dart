import 'dart:math' as math;
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/core/windowing/app_window_caption.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/multiview/host_window_app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/core/windowing/window_caption_hit_test.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/navigation/view/tab_search_menu.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:window_manager/window_manager.dart' show WindowCaptionButton;
import '../helpers/memory_settings_cache.dart';
import '../test_helpers/fake_view_window.dart';
import '../test_helpers/second_test_view.dart';

class _NewTabRegistryRepo extends Fake implements PluginRegistryRepository {
  @override
  Future<String?> getNewTabPageOwner() async =>
      PluginNewTabPageRegistry.instance.activePluginId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
    testWidgets('גרירה קצרה מסדרת כרטיסיות אופקיות ב־$kind', (
      tester,
    ) async {
      final tabs = [
        _makeTextTab('ספר א'),
        _makeTextTab('ספר ב'),
        _makeTextTab('ספר ג'),
      ];
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();
      final target = tester.getCenter(find.text('ספר ג'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('ספר א')),
        kind: kind,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final moves = tabsBloc.addedEvents.whereType<MoveTab>().length;
      expect(moves, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  for (final split in [false, true]) {
    testWidgets(
      'לחיצה ארוכה במגע על ה-X פותחת את תפריט הכרטיסיה'
      '${split ? ' — חצי של כרטיסיה מפוצלת' : ''} (issue #2518)',
      (tester) async {
        // כרטיסיה עם מיקום: ה-tooltip של הכותרת עוטף את כל הכרטיסיה, כולל ה-X.
        final OpenedTab tab = split
            ? CombinedTab(
                rightTab: _makeTextTab('ימין', currentTitle: 'פרק א'),
                leftTab: _makeTextTab('שמאל', currentTitle: 'פרק ב'),
              )
            : _makeTextTab('ספר א', currentTitle: 'פרק א');
        final tabsBloc = _TestTabsBloc(
          TabsState(tabs: [tab], currentTabIndex: 0),
        );
        final navigationBloc = _TestNavigationBloc(
          const NavigationState(currentScreen: Screen.reading),
        );
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        final workspaceBloc = _TestWorkspaceBloc();
        addTearDown(() async {
          tab.dispose();
          await tabsBloc.close();
          await navigationBloc.close();
          await settingsBloc.close();
          await workspaceBloc.close();
        });
        await _setSurfaceSize(tester, const Size(1200, 800));
        await _pumpTitleBar(
          tester,
          tabsBloc: tabsBloc,
          navigationBloc: navigationBloc,
          settingsBloc: settingsBloc,
          workspaceBloc: workspaceBloc,
        );

        final closeButton = split
            ? find.byTooltip('סגור חלונית').first
            : find.byIcon(FluentIcons.dismiss_24_regular);
        final gesture = await tester.startGesture(
          tester.getCenter(closeButton),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(
          kLongPressTimeout + const Duration(milliseconds: 100),
        );
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('סגור הכל'), findsOneWidget);
        expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets(
    'adding a tab without plugins keeps correct width on its first frame',
    (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();
      expect(PluginNewTabPageRegistry.instance.hasActiveRegistration, isFalse);
      expect(
        tester.widget<ReadingTabStrip>(find.byType(ReadingTabStrip)).widths,
        [140],
      );
      tabsBloc.emitState(TabsState(tabs: [first, second], currentTabIndex: 0));
      await tester.idle();
      await tester.pump();
      final firstFrame = tester
          .widget<ReadingTabStrip>(find.byType(ReadingTabStrip))
          .widths;
      await tester.pumpAndSettle();
      final finalFrame = tester
          .widget<ReadingTabStrip>(find.byType(ReadingTabStrip))
          .widths;
      expect(
        firstFrame,
        finalFrame,
        reason:
            'Changing count without resizing must not need a corrective frame',
      );
    },
  );

  for (final size in [const Size(1200, 800), const Size(600, 900)]) {
    testWidgets('new tab keeps first plugin as exclusive owner at $size', (
      tester,
    ) async {
      final registry = PluginNewTabPageRegistry.instance;
      registry.repositoryForTesting = _NewTabRegistryRepo();
      final launcher = PluginPageLauncher.instance;
      final oldNavigator = launcher.navigator;
      final opened = <String>[];
      launcher.navigator = opened.add;
      final tabs = List.generate(20, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        registry.repositoryForTesting = null;
        registry.remove('review.first');
        registry.remove('review.second');
        launcher.markPageClosed('review.first');
        launcher.markPageClosed('review.second');
        launcher.navigator = oldNavigator;
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });
      await _setSurfaceSize(tester, size);
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('כרטיסייה חדשה'), findsNothing);
      expect(registry.register('review.first'), isTrue);
      expect(registry.register('review.second'), isFalse);
      await tester.pumpAndSettle();
      expect(find.byTooltip('כרטיסייה חדשה'), findsOneWidget);
      await tester.tap(find.byTooltip('כרטיסייה חדשה'));
      await tester.pump();
      expect(opened, ['review.first']);
      registry.remove('review.second');
      expect(registry.activePluginId, 'review.first');
      registry.remove('review.first');
      await tester.pumpAndSettle();
      expect(find.byTooltip('כרטיסייה חדשה'), findsNothing);
      // A rejected registration cannot silently take over after release.
      expect(registry.activePluginId, isNull);
      expect(registry.register('review.second'), isTrue);
      await tester.pumpAndSettle();
      expect(find.byTooltip('כרטיסייה חדשה'), findsOneWidget);
      await tester.tap(find.byTooltip('כרטיסייה חדשה'));
      await tester.pump();
      expect(opened, ['review.first', 'review.second']);
      registry.remove('review.second');
      await tester.pumpAndSettle();
      expect(find.byTooltip('כרטיסייה חדשה'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tooltip של TextBookTab כולל את כותרת המיקום בפועל', (
    tester,
  ) async {
    final tab = _makeTextTab('ספר א', currentTitle: 'פרק א');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.byTooltip('ספר א, פרק א'), findsOneWidget);
  });

  testWidgets('כרטיסיה שכותרתה נכנסת במלואה אינה מקבלת tooltip', (
    tester,
  ) async {
    final tab = _makeTextTab('ספר א');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.byTooltip('ספר א'), findsNothing);
  });

  group('מיקום הכרטיסיות', () {
    /// שורת כותרת עם כרטיסיה אחת, במיקום הכרטיסיות הנתון.
    Future<void> pumpWithPlacement(
      WidgetTester tester,
      String placement, {
      ThemeData? theme,
    }) async {
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(
        SettingsState.initial().copyWith(readingTabsPlacement: placement),
      );

      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        theme: theme,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('במצב "בצד" הרצועה שבכותרת אינה נבנית', (tester) async {
      await pumpWithPlacement(
        tester,
        SettingsRepository.readingTabsPlacementSide,
      );

      expect(find.byType(ReadingTabStrip), findsNothing);
      expect(find.text('ספר א'), findsNothing);
      // כפתור הגדרות הקריאה נשאר בכותרת גם בלי הרצועה.
      expect(find.byTooltip('הגדרות תצוגת הספרים'), findsOneWidget);
    });

    testWidgets('במצב "למעלה" הרצועה נבנית כרגיל', (tester) async {
      await pumpWithPlacement(
        tester,
        SettingsRepository.readingTabsPlacementTop,
      );

      expect(find.byType(ReadingTabStrip), findsOneWidget);
      expect(find.text('ספר א'), findsOneWidget);
    });

    BoxDecoration barDecoration(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(CustomTitleBar),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;

    testWidgets('במצב "בצד" השורה ברקע הלוח ועם קו, כמו בספרייה (#1939)', (
      tester,
    ) async {
      await pumpWithPlacement(
        tester,
        SettingsRepository.readingTabsPlacementSide,
      );
      final context = tester.element(find.byType(CustomTitleBar));
      final decoration = barDecoration(tester);
      expect(decoration.color, AppSurfaces.panelBackground(context));
      expect(
        (decoration.border! as Border).bottom.color,
        AppSurfaces.subtleDivider(Theme.of(context).colorScheme),
      );
    });

    testWidgets('בערכת "לבן" הקו של השורה במצב "בצד" כהה (#1939)', (
      tester,
    ) async {
      ThemeData theme(Color seed) => AppThemeData.light(
        AppThemeData.createColorScheme(seed, Brightness.light),
        compactMenuMode: false,
        variant: AppThemeVariant.ofSeed(seed),
      );
      await pumpWithPlacement(
        tester,
        SettingsRepository.readingTabsPlacementSide,
        theme: theme(AppSeedColors.white),
      );
      final context = tester.element(find.byType(CustomTitleBar));
      final line = (barDecoration(tester).border! as Border).bottom;
      expect(line.color, AppSurfaces.regionBorder(context));
      expect(line.color, isNotNull);
      expect(line.width, 1);
    });

    testWidgets('בערכת "לבן" גם במצב "למעלה" יש קו כהה בתחתית השורה (#2850)', (
      tester,
    ) async {
      const white = AppSeedColors.white;
      await pumpWithPlacement(
        tester,
        SettingsRepository.readingTabsPlacementTop,
        theme: AppThemeData.light(
          AppThemeData.createColorScheme(white, Brightness.light),
          compactMenuMode: false,
          variant: AppThemeVariant.ofSeed(white),
        ),
      );
      final context = tester.element(find.byType(CustomTitleBar));
      final decoration = barDecoration(tester);
      expect(decoration.color, AppSurfaces.readerBackground(context));
      expect(
        (decoration.border! as Border).bottom.color,
        AppSurfaces.regionBorder(context),
      );
    });

    testWidgets('במצב "למעלה" השורה ברקע הקריאה ובלי קו', (tester) async {
      await pumpWithPlacement(
        tester,
        SettingsRepository.readingTabsPlacementTop,
      );
      final context = tester.element(find.byType(CustomTitleBar));
      final decoration = barDecoration(tester);
      expect(decoration.color, AppSurfaces.readerBackground(context));
      expect(decoration.border, isNull);
    });
  });

  group('כרטיסיית חיפוש וצורת הכרטיסיה הפעילה', () {
    Future<void> pumpTabs(WidgetTester tester, List<OpenedTab> tabs) async {
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
    }

    Finder searchIconInStrip() => find.descendant(
      of: find.byType(ReadingTabStrip),
      matching: find.byIcon(OtzariaIcons.search_24_regular),
    );

    List<OpenedTab> crowdedTabs(int count) => [
      for (var i = 0; i < count; i++) _makeTextTab('ספר $i'),
      SearchingTab('חיפוש: קקק', 'קקק'),
    ];

    testWidgets('כרטיסיית חיפוש צרה מציגה את אייקון החיפוש במקום המילה', (
      tester,
    ) async {
      await pumpTabs(tester, crowdedTabs(10));

      final stripWidth = tester.getSize(find.byType(ReadingTabStrip)).width;
      expect(stripWidth / 15, lessThan(100), reason: 'הכרטיסיות צרות');
      expect(searchIconInStrip(), findsOneWidget);
      expect(find.text('קקק'), findsOneWidget);
      expect(find.text('חיפוש: קקק'), findsNothing);
    });

    // במרחב ביניים האייקון לא נכנס לצד ה-X שבריחוף, ולכן הוא נעדר גם במנוחה;
    // המצב לא משתנה עם הריחוף.
    for (final (count, iconShown) in [(10, true), (14, false)]) {
      testWidgets(
        'אייקון החיפוש בכרטיסיה צרה (${count + 1} כרטיסיות) יציב בריחוף',
        (tester) async {
          await pumpTabs(tester, crowdedTabs(count));

          final searchTab = find.byType(Tab).last;
          void expectStable() {
            expect(
              searchIconInStrip(),
              iconShown ? findsOneWidget : findsNothing,
            );
            expect(
              find.text(iconShown ? 'קקק' : 'חיפוש: קקק'),
              findsWidgets,
            );
          }

          expectStable();

          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await gesture.addPointer(location: tester.getCenter(searchTab));
          addTearDown(gesture.removePointer);
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: searchTab,
              matching: find.byIcon(FluentIcons.dismiss_24_regular),
            ),
            findsOneWidget,
            reason: 'הריחוף חושף את ה-X',
          );
          expectStable();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('בכרטיסיה שאין בה מקום לאייקון אין אייקון ואין גלישה', (
      tester,
    ) async {
      await pumpTabs(tester, crowdedTabs(40));

      expect(searchIconInStrip(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('הרצועה האופקית אינה חותכת את כנפי הכרטיסיה הפעילה', (
      tester,
    ) async {
      await pumpTabs(tester, [_makeTextTab('ספר א'), _makeTextTab('ספר ב')]);

      final scrollView = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(ReadingTabStrip),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(scrollView.clipBehavior, Clip.none);
    });

    testWidgets('רקע הכרטיסיה הפעילה ממשיך פיקסל מתחת לסרגל', (tester) async {
      await pumpTabs(tester, [_makeTextTab('ספר א'), _makeTextTab('ספר ב')]);

      final painted = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_TabBackgroundPainter',
      );
      final size = tester.getSize(painted);
      expect(
        tester.renderObject(painted),
        paints..path(
          includes: [Offset(size.width / 2, size.height + 0.5)],
          excludes: [Offset(size.width / 2, size.height + 1.5)],
        ),
      );
    });
  });

  group('שורה עמוסה בכרטיסיות', () {
    // ברוחב הזה כל כרטיסיה שאינה הנבחרת מקבלת פחות מ-12 פיקסל, כלומר אחרי
    // הריפודים לא נותר בה מקום לתוכן.
    Future<_TestTabsBloc> pumpCrowdedStrip(WidgetTester tester) async {
      final tabs = [for (var i = 0; i < 200; i++) _makeTextTab('ספר $i')];
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      return tabsBloc;
    }

    testWidgets('נבנה תוכן רק לכרטיסיות שיש בהן מקום להציגו', (tester) async {
      await pumpCrowdedStrip(tester);

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 100'), findsNothing);
    });

    testWidgets('כרטיסיה נבחרת במקלדת (Enter) ובפעולת ההקשה של קורא מסך', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final tabs = [_makeTextTab('ספר א'), _makeTextTab('ספר ב')];
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      // צומת הכרטיסיה הוא ה-Semantics של TabActivationRegion, מעל ה-DecoratedBox.
      Finder node(String title) => find
          .descendant(
            of: find.ancestor(
              of: find.text(title),
              matching: find.byType(TabActivationRegion),
            ),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final second = node('ספר ב');
      expect(
        tester.getSemantics(second),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(node('ספר א')),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );

      Focus.of(tester.element(second)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>().map((e) => e.index),
        [1],
      );

      semantics.dispose();
    });

    testWidgets('לחיצה על כרטיסיה צרה עדיין בוחרת אותה', (tester) async {
      final tabsBloc = await pumpCrowdedStrip(tester);

      // אמצע השורה — הרחק מהכרטיסיה הנבחרת שבקצה, כלומר בתוך הכרטיסיות הצרות.
      final stripRect = tester.getRect(find.byType(ReadingTabStrip));
      await tester.tapAt(stripRect.center);
      await tester.pump();

      final selection = tabsBloc.addedEvents.whereType<SetCurrentTab>();
      expect(selection, isNotEmpty);
      expect(selection.last.index, greaterThan(0));
    });
  });

  // הערת בעל הפרויקט (4.11): בטלפון "מסך מלא" למעלה בשמאל, ליד ההגדרות,
  // כשיש בשורת הכותרת מקום; אחרת בסרגל הקורא.
  group('מסך מלא בטלפון בשורת הכותרת', () {
    Future<WindowFullscreenCubit> pumpPhone(
      WidgetTester tester,
      Size size, {
      bool fullscreen = false,
    }) async {
      DeviceChrome.debugMobileOverride = true;
      addTearDown(() => DeviceChrome.debugMobileOverride = null);
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final cubit = WindowFullscreenCubit(
        initial: fullscreen,
        persist: (_) async {},
      );
      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await cubit.close();
      });
      await _setSurfaceSize(tester, size);
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        fullscreenCubit: cubit,
      );
      await tester.pumpAndSettle();
      return cubit;
    }

    for (final size in const [Size(360, 640), Size(844, 390)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}: הכפתור משמאל '
          'להגדרות, ונכנס למסך מלא', (tester) async {
        final cubit = await pumpPhone(tester, size);
        final button = find.byTooltip('מסך מלא');
        expect(button, findsOneWidget);
        final settings = find.byTooltip('הגדרות תצוגת הספרים');
        // סוף השורה, אחרי ההגדרות: באפליקציה (RTL) זו הפינה השמאלית.
        final settingsX = tester.getCenter(settings).dx;
        expect(
          tester.getCenter(button).dx,
          Directionality.of(tester.element(settings)) == TextDirection.rtl
              ? lessThan(settingsX)
              : greaterThan(settingsX),
        );
        expect(
          tester.getCenter(button).dy,
          tester.getCenter(settings).dy,
        );
        await tester.tap(button);
        // אזור הגרירה מזהה גם לחיצה כפולה: הלחיצה הבודדת מוכרעת אחריה.
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
        expect(cubit.state, isTrue);
      });
    }

    testWidgets('בלי מקום (420×390, הכרטיסיות בשורה) אין כפתור בכותרת', (
      tester,
    ) async {
      await pumpPhone(tester, const Size(420, 390));
      expect(find.byTooltip('הגדרות תצוגת הספרים'), findsOneWidget);
      expect(find.byTooltip('מסך מלא'), findsNothing);
    });

    testWidgets('במסך מלא אין כפתור כניסה', (tester) async {
      await pumpPhone(tester, const Size(360, 640), fullscreen: true);
      expect(find.byTooltip('מסך מלא'), findsNothing);
    });
  });

  testWidgets('אייקון pin מוצג כשהכרטיסיה מוצמדת', (tester) async {
    final tab = _makeTextTab('ספר א');
    tab.isPinned = true;
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.pin_24_filled,
      ),
      findsOneWidget,
    );
    // הריחוף של כפתור הנעץ (בגודל הכפתור) לא נוגע בכותרת.
    final pin = tester.getRect(
      find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == FluentIcons.pin_24_filled,
        ),
        matching: find.byType(IconButton),
      ),
    );
    final title = tester.getRect(find.text('ספר א').first);
    expect(
      math.max(pin.left - title.right, title.left - pin.right),
      greaterThanOrEqualTo(4),
      reason: 'רווח בין הנעץ לכותרת',
    );
  });

  testWidgets('הרבה כרטיסיות: הנעץ נצמד לכותרת (LQ-14)', (tester) async {
    final tabs = [
      for (var i = 1; i <= 16; i++) _makeTextTab('ספר $i')..isPinned = true,
    ];
    final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      for (final t in tabs) {
        t.dispose();
      }
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    final pinButtons = find.byType(TabPinButton);
    expect(pinButtons, findsNWidgets(tabs.length));
    // בכרטיסיה צרה הרווחים סביב הנעץ מתכווצים כמו הריפודים: 2 אחריו (עיגול
    // הריחוף לא נוגע בכותרת), ולא 4 כמו בכרטיסיה רחבה.
    for (var i = 0; i < tabs.length; i++) {
      final padding =
          tester
                  .widget<Padding>(
                    find
                        .ancestor(
                          of: pinButtons.at(i),
                          matching: find.byType(Padding),
                        )
                        .first,
                  )
                  .padding
              as EdgeInsetsDirectional;
      expect(padding.end, inInclusiveRange(2, 3), reason: 'אחרי נעץ $i');
      expect(padding.start, lessThanOrEqualTo(2), reason: 'לפני נעץ $i');
    }
  });

  testWidgets('ב-Mac ה-tooltip של כפתורי הכותרת מציג ⌘ ולא CTRL', (
    tester,
  ) async {
    ShortcutHelper.isMacForTesting = true;
    addTearDown(() => ShortcutHelper.isMacForTesting = null);

    final tab = _makeTextTab('ספר א');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    // ⌘H שמור להסתרת היישום ב-Mac, ולכן ההיסטוריה נופלת ל-⌘Y (issue #1269).
    expect(find.byTooltip('הצג היסטוריה (⌘ + Y)'), findsOneWidget);
    expect(find.byTooltip('הצג סימניות (⌘ + ⇧ + B)'), findsOneWidget);
  });

  testWidgets('אייקון pin מוסתר כשהכרטיסיה אינה מוצמדת', (tester) async {
    final tab = _makeTextTab('ספר א');
    // isPinned = false כברירת מחדל
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.pin_24_filled,
      ),
      findsNothing,
    );
  });

  group('שינוי הגדרות', () {
    late _TestSettingsBloc settingsBloc;
    late WindowFullscreenCubit fullscreenCubit;

    Future<void> pumpBar(WidgetTester tester) async {
      final tabs = [for (var i = 0; i < 5; i++) _makeTextTab('ספר $i')];
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      settingsBloc = _TestSettingsBloc(SettingsState.initial());
      fullscreenCubit = WindowFullscreenCubit(
        initial: false,
        persist: (_) async {},
      );
      addTearDown(() async {
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await fullscreenCubit.close();
      });
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        fullscreenCubit: fullscreenCubit,
      );
      await tester.pumpAndSettle();
    }

    Future<void> emitSettings(WidgetTester tester, SettingsState state) async {
      settingsBloc.emitState(state);
      await tester.pump();
      await tester.pump();
    }

    ReadingTabStrip strip(WidgetTester tester) =>
        tester.widget<ReadingTabStrip>(find.byType(ReadingTabStrip));

    testWidgets('הגדרה שהכותרת אינה מציגה אינה בונה מחדש את הרצועה', (
      tester,
    ) async {
      await pumpBar(tester);
      final before = strip(tester);

      await emitSettings(tester, settingsBloc.state.copyWith(fontSize: 30));

      expect(identical(strip(tester), before), isTrue);
    });

    testWidgets('מיקום, מסך מלא וקיצורים עדיין מתעדכנים בכותרת', (
      tester,
    ) async {
      ShortcutHelper.isMacForTesting = false;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      await pumpBar(tester);
      await emitSettings(
        tester,
        settingsBloc.state.copyWith(
          readingTabsPlacement: SettingsRepository.readingTabsPlacementSide,
        ),
      );
      expect(find.byType(ReadingTabStrip), findsNothing);
      await emitSettings(
        tester,
        settingsBloc.state.copyWith(
          readingTabsPlacement: SettingsRepository.readingTabsPlacementTop,
        ),
      );
      expect(find.byType(ReadingTabStrip), findsOneWidget);
      expect(find.byTooltip('מסך מלא'), findsOneWidget);

      await fullscreenCubit.set(true);
      await tester.pump();
      expect(find.byTooltip('צא ממסך מלא'), findsOneWidget);

      await Settings.setValue<String>('key-shortcut-open-history', 'ctrl+j');
      await emitSettings(
        tester,
        settingsBloc.state.copyWith(
          shortcuts: const {'key-shortcut-open-history': 'ctrl+j'},
        ),
      );
      expect(find.byTooltip('הצג היסטוריה (CTRL + J)'), findsOneWidget);
    });
  });

  testWidgets('כרטיסיות מקבלות רוחב קבוע שווה, חסום בתקרה (~140px)', (
    tester,
  ) async {
    final tab1 = _makeTextTab('ספר קצר');
    final tab2 = _makeTextTab('ספר עם שם ארוך מאוד שנמשך הרחק');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab1, tab2], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab1.dispose();
      tab2.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );
    await tester.pumpAndSettle();

    // כל טאב עטוף ב-SizedBox ברוחב המחושב (ילדו ה-Listener של _buildTab); שני
    // הטאבים זהים וחסומים בתקרה (140px) — לא רוחב טבעי לפי אורך הכותרת.
    final widths = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(ReadingTabStrip),
            matching: find.byType(SizedBox),
          ),
        )
        .where((b) => b.width != null && b.child is Listener)
        .map((b) => b.width!)
        .toList();

    expect(widths.length, 2, reason: 'שני טאבים → שני SizedBox ברוחב קבוע');
    expect(
      widths[0],
      moreOrLessEquals(widths[1], epsilon: 1.0),
      reason: 'כל הטאבים ברוחב קבוע שווה',
    );
    expect(
      widths[0],
      lessThanOrEqualTo(141.0),
      reason: 'רוחב הטאב חסום בתקרה (~140px) גם כשיש מקום',
    );
  });

  testWidgets('כותרת ארוכה נחתכת בדהייה (TextOverflow.fade) ללא שלוש נקודות', (
    tester,
  ) async {
    const longTitle = 'ספר עם שם ארוך מאוד שנמשך הרחק אל מעבר לרוחב הטאב';
    final tab = _makeTextTab(longTitle);
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    // הכותרת המלאה מרונדרת (לא קוצרה ל-...) בשורה אחת.
    final titleText = tester.widget<Text>(find.text(longTitle));
    expect(titleText.maxLines, 1);
    expect(titleText.softWrap, false);
    // הדהייה בקצה הסוף נעשית ע"י ShaderMask עוטף (לא TextOverflow.fade, שמציג
    // בעברית את סוף הכותרת במקום ההתחלה).
    expect(
      find.ancestor(
        of: find.text(longTitle),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('...'),
      findsNothing,
      reason: 'אין שלוש נקודות — חיתוך בדהייה כמו כרום',
    );
  });

  testWidgets('CommentatorsTab לא מפיל את שורת הכותרת', (tester) async {
    final sourceTab = _makeTextTab('ספר א', currentTitle: 'פרק א');
    final tab = CommentatorsTab(sourceTab: sourceTab);
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      sourceTab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.text('מפרשים | ספר א'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // רק טאב-PDF מקבל אייקון-סוג; בטאב מפרשים אין אייקון מוביל.
    expect(find.byIcon(OtzariaIcons.book_24_regular), findsNothing);
    expect(find.byIcon(OtzariaIcons.document_pdf_24_regular), findsNothing);
  });

  testWidgets('טאב PDF רחב מציג אייקון PDF ליד שם הספר', (tester) async {
    final tab = _makePdfTab('ספר PDF');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.byIcon(OtzariaIcons.document_pdf_24_regular), findsOneWidget);
  });

  testWidgets('טאב PDF צר (רוחב < 100) מסתיר את אייקון ה-PDF', (tester) async {
    // הרבה טאבים ב-surface צר מצמצמים כל טאב מתחת ל-100px — האייקון נעלם.
    final tabs = List.generate(10, (i) => _makePdfTab('ספר $i'));
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: tabs, currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      for (final tab in tabs) {
        tab.dispose();
      }
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(900, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.byIcon(OtzariaIcons.document_pdf_24_regular), findsNothing);
  });

  testWidgets('CombinedTab מציג את התחלת שני הספרים, כל אחד בחצי', (
    tester,
  ) async {
    final right = _makeTextTab('תרגום אונקלוס על שמות');
    final left = _makeTextTab('רש"י על בראשית פרשת ויחי');
    final tab = CombinedTab(rightTab: right, leftTab: left);
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose(); // מפנה גם את right ו-left
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    // שני הספרים מרונדרים בנפרד (כל אחד ב-Expanded משלו עם ShaderMask לדהייה),
    // ולא כמחרוזת "משולב:" מאוחדת אחת.
    expect(find.text('תרגום אונקלוס על שמות'), findsOneWidget);
    expect(find.text('רש"י על בראשית פרשת ויחי'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('תרגום אונקלוס על שמות'),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('רש"י על בראשית פרשת ויחי'),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('משולב:'),
      findsNothing,
      reason: 'בטאב מוצגים שני החצאים, לא מחרוזת מאוחדת',
    );

    // פס מפריד (2×14) בין שני החצאים בטאב רחב.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 2 &&
            w.constraints?.maxHeight == 14,
      ),
      findsOneWidget,
      reason: 'יש פס מפריד בין שני הספרים בטאב המפוצל',
    );
  });

  group('סגירת חצי של לשונית מפוצלת', () {
    late TextBookTab right;
    late TextBookTab left;
    late _TestTabsBloc tabsBloc;
    late _TestHistoryBloc historyBloc;

    Future<void> pumpCombined(WidgetTester tester) async {
      right = _makeTextTab('ימין');
      left = _makeTextTab('שמאל');
      final tab = CombinedTab(rightTab: right, leftTab: left);
      tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        tab.dispose(); // מפנה גם את right ו-left
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        historyBloc: historyBloc,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('לכל חצי יש X משלו, ולחיצה עליו סוגרת רק את החלונית שלו', (
      tester,
    ) async {
      await pumpCombined(tester);

      final closeButtons = find.byTooltip('סגור חלונית');
      expect(closeButtons, findsNWidgets(2), reason: 'X לכל אחד משני החצאים');

      // ה-X של חצי צמוד לכותרת שלו — מזהים אותו לפי הקרבה אליה, כך שהבדיקה
      // אינה תלויה בכיוון הפריסה של סביבת הבדיקה (LTR מול RTL באפליקציה).
      // סימולציית tap נבלעת ע"י ה-reorder recognizer — קוראים ל-onPressed ישירות.
      final titleCenter = tester.getCenter(find.text('ימין'));
      final xOfRight = closeButtons
          .evaluate()
          .map((e) => find.byWidget(e.widget))
          .reduce(
            (a, b) =>
                (tester.getCenter(a) - titleCenter).distance <
                    (tester.getCenter(b) - titleCenter).distance
                ? a
                : b,
          );
      // ה-tooltip הוא של ה-IconButton עצמו (IconButton.tooltip), ולכן הכפתור
      // הוא אב של ה-Tooltip ולא צאצא שלו (issue #1399).
      tester
          .widget<IconButton>(
            find.ancestor(of: xOfRight, matching: find.byType(IconButton)),
          )
          .onPressed!();
      await tester.pump();

      final closed = tabsBloc.addedEvents.whereType<ClosePane>().toList();
      expect(closed, hasLength(1));
      expect(closed.single.pane, same(right), reason: 'נסגר רק החצי הימני');
      expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
      expect(
        historyBloc.addedEvents.whereType<AddHistory>().map((e) => e.tab),
        contains(same(right)),
        reason: 'החלונית שנסגרה נרשמת בהיסטוריה',
      );
    });

    testWidgets('לחיצת גלגלת על חצי סוגרת רק את החלונית שמתחת לסמן', (
      tester,
    ) async {
      await pumpCombined(tester);

      Future<void> middleClickAt(Offset pos) async {
        final gesture = await tester.startGesture(
          pos,
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await gesture.up();
        await tester.pump();
      }

      // הלחיצה על כותרת החצי — כך הבדיקה אינה תלויה בכיוון הפריסה.
      await middleClickAt(tester.getCenter(find.text('ימין')));
      var closed = tabsBloc.addedEvents.whereType<ClosePane>().toList();
      expect(closed, hasLength(1));
      expect(closed.single.pane, same(right));

      await middleClickAt(tester.getCenter(find.text('שמאל')));
      closed = tabsBloc.addedEvents.whereType<ClosePane>().toList();
      expect(closed, hasLength(2));
      expect(closed.last.pane, same(left));

      expect(
        tabsBloc.addedEvents.whereType<RemoveTab>(),
        isEmpty,
        reason: 'גלגלת על לשונית מפוצלת אינה סוגרת את הלשונית כולה',
      );
    });

    testWidgets('לחיצת גלגלת על לשונית רגילה עדיין סוגרת את כולה', (
      tester,
    ) async {
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        historyBloc: historyBloc,
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('ספר א')),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.up();
      await tester.pump();

      expect(
        tabsBloc.addedEvents.whereType<RemoveTab>().map((e) => e.tab),
        contains(same(tab)),
      );
      expect(tabsBloc.addedEvents.whereType<ClosePane>(), isEmpty);
    });
  });

  group('בחירה וגרירת-סידור של טאבים', () {
    testWidgets('לחיצה על טאב שולחת SetCurrentTab עם האינדקס שלו', (
      tester,
    ) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      // הבחירה מתבצעת ב-onPointerDown (Listener פסיבי), כך שקליק רגיל מספיק.
      // warnIfMissed:false כי ה-drag recognizer של הרצועה עשוי
      // לתפוס את ה-tap; pumpAndSettle מנקה את ה-timer של אנימציית הגרירה.
      await tester.tap(find.text('ספר ב'), warnIfMissed: false);
      await tester.pumpAndSettle();

      final selected = tabsBloc.addedEvents.whereType<SetCurrentTab>().toList();
      expect(
        selected,
        isNotEmpty,
        reason: 'לחיצה על טאב צריכה לשלוח SetCurrentTab',
      );
      expect(selected.last.index, 1, reason: 'האינדקס הנבחר הוא של הטאב שנלחץ');
    });

    testWidgets('גרירת טאב בוחרת אותו (כמו כרום) ושולחת MoveTab לסידור מחדש', (
      tester,
    ) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      // הבחירה מתבצעת ב-onPointerDown — תחילת גרירה (כמו לחיצה) בוחרת את הטאב.
      await tester.tap(find.text('ספר ב'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>().map((e) => e.index),
        contains(1),
        reason: 'תחילת גרירה בוחרת את הטאב הנגרר (אינדקס 1)',
      );

      // סימולציית multidrag מלאה אינה אמינה בבדיקת widget (recognizers של
      // תפריט ההקשר/הגלילה מתחרים ב-arena). בודקים ישירות את לוגיקת
      // האפליקציה: הרצועה ממפה את יעד הגרירה ושולחת MoveTab.
      final strip = tester.widget<ReadingTabStrip>(
        find.byType(ReadingTabStrip),
      );
      strip.onReorder(second, 0);
      await tester.pump();

      final moves = tabsBloc.addedEvents.whereType<MoveTab>().toList();
      expect(moves, isNotEmpty, reason: 'reorder צריך לשלוח MoveTab');
      expect(
        moves.last.tab,
        same(second),
        reason: 'הטאב שמועבר הוא הטאב שנגרר',
      );
      expect(moves.last.newIndex, 0, reason: 'היעד הוא אינדקס 0');
    });

    testWidgets('גרירת כרטיסיה אינה מעבירה את התצוגה אליה', (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      // לחיצה ממושכת שהופכת לגרירה: הבחירה נשמרת לשחרור, והגרירה מבטלת
      // אותה — אחרת התצוגה הייתה קופצת לכרטיסיה שרק מתחילים לגרור.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('ספר ב')),
      );
      await tester.pump();
      // ⚠️ `onDragStarted` מקבל את הכרטיסיה הנגררת מאז שהיא נדרשת לתצוגת
      // הגרירה הנייטיבית; הבדיקה מזמנת אותו ידנית עם הכרטיסיה שנלחצה.
      final strip = tester.widget<ReadingTabStrip>(
        find.byType(ReadingTabStrip),
      );
      strip.onDragStarted!(
        strip.tabs.firstWhere((tab) => tab.title == 'ספר ב'),
        () {},
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>(),
        isEmpty,
        reason: 'גרירה אינה בוחרת כרטיסיה',
      );
      expect(tabsBloc.state.currentTabIndex, 0);
    });

    testWidgets('לחיצה בוחרת כרטיסיה בשחרור', (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('ספר ב')),
      );
      await tester.pump();
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>(),
        isEmpty,
        reason: 'הלחיצה עצמה עדיין לא בוחרת',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(tabsBloc.state.currentTabIndex, 1);
    });

    testWidgets('השהייה מעל כרטיסיה בגרירה פותחת אותה', (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      tester
          .widget<ReadingTabStrip>(find.byType(ReadingTabStrip))
          .onSpringOpen!(second);
      await tester.pumpAndSettle();

      expect(tabsBloc.state.currentTabIndex, 1);
    });

    testWidgets('סידור מחדש שולח MoveTab בלבד — הבחירה בנגררת נעשית ב-bloc', (
      tester,
    ) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final strip = tester.widget<ReadingTabStrip>(
        find.byType(ReadingTabStrip),
      );
      strip.onReorder(second, 0);
      await tester.pump();

      final events = tabsBloc.addedEvents;
      expect(events.whereType<MoveTab>(), isNotEmpty);
      // הבחירה בכרטיסיה הנגררת היא חלק מ-MoveTab עצמו, לא אירוע נפרד.
      expect(events.whereType<SetCurrentTab>(), isEmpty);
    });

    testWidgets(
      'בדסקטופ הטאבים עטופים ב-listener מיידי (גרירה מסדרת מיד)',
      (tester) async {
        final tab = _makeTextTab('ספר א');
        final tabsBloc = _TestTabsBloc(
          TabsState(tabs: [tab], currentTabIndex: 0),
        );
        final navigationBloc = _TestNavigationBloc(
          const NavigationState(currentScreen: Screen.reading),
        );
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());

        addTearDown(() async {
          tab.dispose();
          await tabsBloc.close();
          await navigationBloc.close();
          await settingsBloc.close();
        });

        await _setSurfaceSize(tester, const Size(1200, 800));
        await _pumpTitleBar(
          tester,
          tabsBloc: tabsBloc,
          navigationBloc: navigationBloc,
          settingsBloc: settingsBloc,
        );

        // בדסקטופ הגרירה מיידית בעכבר, ללא LongPressDraggable.
        expect(
          find.byWidgetPredicate((w) => w is Draggable<OpenedTab>),
          findsOneWidget,
        );
        expect(
          find.byType(LongPressDraggable<OpenedTab>),
          findsNothing,
        );
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'בנייד הטאבים עטופים ב-listener מושהה (long-press)',
      (tester) async {
        final tab = _makeTextTab('ספר א');
        final tabsBloc = _TestTabsBloc(
          TabsState(tabs: [tab], currentTabIndex: 0),
        );
        final navigationBloc = _TestNavigationBloc(
          const NavigationState(currentScreen: Screen.reading),
        );
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());

        addTearDown(() async {
          tab.dispose();
          await tabsBloc.close();
          await navigationBloc.close();
          await settingsBloc.close();
        });

        await _setSurfaceSize(tester, const Size(1200, 800));
        await _pumpTitleBar(
          tester,
          tabsBloc: tabsBloc,
          navigationBloc: navigationBloc,
          settingsBloc: settingsBloc,
        );

        expect(
          find.byType(LongPressDraggable<OpenedTab>),
          findsOneWidget,
        );
      },
      variant: TargetPlatformVariant.mobile(),
    );

    testWidgets('הרבה טאבים מצטמצמים והכפתור X מתחבא בטאב צר, ללא חיצי גלילה', (
      tester,
    ) async {
      // ביטול הגלילה: הרבה טאבים מתכווצים, וכשהם צרים מ-80px כפתור ה-X מתחבא
      // (מופיע ב-hover/בנבחר) כדי שהם ימשיכו להצטמצם ויישארו נגישים.
      final tabs = List.generate(10, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsNothing);
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);

      // הטאבים התכווצו אל מתחת ל-80 (אזור הסתרת ה-X) — בלי רצפה ובלי גלילה.
      final widths = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ReadingTabStrip),
              matching: find.byType(SizedBox),
            ),
          )
          .where((b) => b.width != null && b.child is Listener)
          .map((b) => b.width!)
          .toList();
      expect(widths, isNotEmpty);
      expect(widths.first, greaterThan(0));
      expect(widths.first, lessThan(80.0));

      // בטאבים צרים כפתורי ה-X מתחבאים — פחות כפתורי סגירה ממספר הטאבים.
      final closeButtons = find
          .byIcon(FluentIcons.dismiss_24_regular)
          .evaluate()
          .length;
      expect(
        closeButtons,
        lessThan(tabs.length),
        reason: 'X מתחבא בטאבים צרים שאינם נבחרים/תחת hover',
      );
    });

    testWidgets('ה-X של טאב צר תחת ריחוף שורד בנייה מחדש של שורת הטאבים', (
      tester,
    ) async {
      // בטאב צר שאינו נבחר ה-X מוצג רק בריחוף. כשמצב הריחוף לא שרד בנייה מחדש
      // של השורה, ה-IconButton נמחק מתחת לסמן ולחיצה עליו לא סגרה את הטאב.
      final tabs = List.generate(10, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
      });

      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        historyBloc: historyBloc,
      );
      await tester.pumpAndSettle();

      final hoveredTab = find.ancestor(
        of: find.text('ספר מספר 3'),
        matching: find.byType(Tab),
      );
      final closeButton = find.descendant(
        of: hoveredTab,
        matching: find.byIcon(FluentIcons.dismiss_24_regular),
      );
      expect(closeButton, findsNothing, reason: 'בטאב צר לא-נבחר ה-X מוסתר');

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(hoveredTab));
      addTearDown(gesture.removePointer);
      await tester.pumpAndSettle();
      expect(closeButton, findsOneWidget, reason: 'ריחוף חושף את ה-X');

      // בנייה מחדש של השורה מסיבה חיצונית — כמו setState של המסך העוטף.
      tester.element(find.byType(CustomTitleBar)).markNeedsBuild();
      await tester.pumpAndSettle();

      expect(
        closeButton,
        findsOneWidget,
        reason: 'ה-X חייב להישאר תחת הסמן גם אחרי בנייה מחדש',
      );
      tester
          .widget<IconButton>(
            find.ancestor(of: closeButton, matching: find.byType(IconButton)),
          )
          .onPressed!();
      await tester.pump();
      expect(
        tabsBloc.addedEvents.whereType<RemoveTab>().map((e) => e.tab),
        contains(same(tabs[3])),
      );
    });

    testWidgets('בצפיפות הטאב הנבחר שומר רוחב מזערי וכפתור ה-X שלו נשאר', (
      tester,
    ) async {
      // 20 טאבים ברוחב 900 → החלוקה השווה צונחת מתחת לרוחב שמכיל את ה-X. הטאב
      // הנבחר חייב לשמור רוחב מזערי (60px) כך שה-X שלו לא ייעלם, והשאר
      // מתחלקים ביתרה — עדיין ללא חיתוך וללא גלילה.
      final tabs = List.generate(20, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final widths = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ReadingTabStrip),
              matching: find.byType(SizedBox),
            ),
          )
          .where((b) => b.width != null && b.child is Listener)
          .map((b) => b.width!)
          .toList();
      expect(widths.length, 20);
      expect(
        widths.first,
        moreOrLessEquals(60.0, epsilon: 1.0),
        reason: 'הטאב הנבחר (אינדקס 0) שומר רוחב מזערי של 60px',
      );
      expect(
        widths[1],
        lessThan(widths.first),
        reason: 'שאר הטאבים צרים מהנבחר — מתחלקים ביתרה',
      );

      final sumWidth = widths.fold<double>(0, (a, b) => a + b);
      final listWidth = tester.getSize(find.byType(ReadingTabStrip)).width;
      expect(
        sumWidth,
        lessThanOrEqualTo(listWidth + 1.0),
        reason: 'גם עם הרצפה לנבחר — הכול נכנס ללא חיתוך',
      );

      // כפתור ה-X קיים בתוך הטאב הנבחר גם בצפיפות הזו.
      final selectedClose = find.descendant(
        of: find.ancestor(
          of: find.text('ספר מספר 0'),
          matching: find.byType(Tab),
        ),
        matching: find.byIcon(FluentIcons.dismiss_24_regular),
      );
      expect(
        selectedClose,
        findsOneWidget,
        reason: 'לטאב הנבחר תמיד יש כפתור סגירה, גם כשהשורה צפופה',
      );
    });

    testWidgets('מספר טאבים גדול — כולם נכנסים ללא חיתוך וללא גלילה', (
      tester,
    ) async {
      // ללא רצפת רוחב וללא גלילה: סכום רוחבי הטאבים לא חורג מהרוחב הזמין, כך
      // שאף טאב אינו נחתך/בלתי-נגיש (התיקון לרגרסיה של מנגנון הגלילה שהוסר).
      final tabs = List.generate(30, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsNothing);
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);

      final widths = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ReadingTabStrip),
              matching: find.byType(SizedBox),
            ),
          )
          .where((b) => b.width != null && b.child is Listener)
          .map((b) => b.width!)
          .toList();
      expect(widths.length, 30, reason: 'כל 30 הטאבים רונדרו');
      final sumWidth = widths.fold<double>(0, (a, b) => a + b);
      final listWidth = tester.getSize(find.byType(ReadingTabStrip)).width;
      expect(
        sumWidth,
        lessThanOrEqualTo(listWidth + 1.0),
        reason: 'סכום רוחבי הטאבים נכנס ברוחב הזמין — אין חיתוך',
      );
    });
  });

  group('בחירה מרובה של כרטיסיות (Ctrl/Shift/Cmd+לחיצה)', () {
    late TextBookTab first;
    late TextBookTab second;
    late TextBookTab third;
    late _TestTabsBloc tabsBloc;
    late _TestHistoryBloc historyBloc;

    Future<void> pumpWithTabs(
      WidgetTester tester, {
      List<TextBookTab> selected = const [],
    }) async {
      first = _makeTextTab('ספר א');
      second = _makeTextTab('ספר ב');
      third = _makeTextTab('ספר ג');
      tabsBloc = _TestTabsBloc(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: selected,
        ),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        first.dispose();
        second.dispose();
        third.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        historyBloc: historyBloc,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+לחיצה שולחת ToggleTabSelection ולא מחליפה טאב', (
      tester,
    ) async {
      await pumpWithTabs(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('ספר ב'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final toggles = tabsBloc.addedEvents
          .whereType<ToggleTabSelection>()
          .toList();
      expect(toggles, hasLength(1));
      expect(toggles.single.tab, same(second));
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>(),
        isEmpty,
        reason: 'Ctrl+לחיצה בוחרת לקבוצה ואינה מחליפה את הטאב הפעיל',
      );
    });

    testWidgets('Shift+לחיצה שולחת SelectTabRange', (tester) async {
      await pumpWithTabs(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('ספר ג'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      final ranges = tabsBloc.addedEvents.whereType<SelectTabRange>().toList();
      expect(ranges, hasLength(1));
      expect(ranges.single.tab, same(third));
      expect(tabsBloc.addedEvents.whereType<SetCurrentTab>(), isEmpty);
    });

    testWidgets(
      'במק: Command+לחיצה שולחת ToggleTabSelection',
      (tester) async {
        await pumpWithTabs(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.tap(find.text('ספר ב'), warnIfMissed: false);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        final toggles = tabsBloc.addedEvents
            .whereType<ToggleTabSelection>()
            .toList();
        expect(toggles, hasLength(1));
        expect(toggles.single.tab, same(second));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('לחיצה רגילה מנקה בחירה קיימת ומחליפה טאב', (tester) async {
      await pumpWithTabs(tester);
      tabsBloc.emitState(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: [first, second],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ספר ג'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        tabsBloc.addedEvents.whereType<ClearTabSelection>(),
        hasLength(1),
      );
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>().last.index,
        2,
      );
    });

    testWidgets('לחיצה על ה-X של כרטיסיה נבחרת סוגרת את כל הקבוצה', (
      tester,
    ) async {
      await pumpWithTabs(tester);
      tabsBloc.emitState(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: [first, second],
        ),
      );
      await tester.pumpAndSettle();

      // סימולציית tap נבלעת ע"י ה-reorder recognizer — קוראים ל-onPressed ישירות.
      final closeButton = find.descendant(
        of: find.ancestor(of: find.text('ספר א'), matching: find.byType(Tab)),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(closeButton).onPressed!();
      await tester.pump();

      final removals = tabsBloc.addedEvents.whereType<RemoveTabs>().toList();
      expect(removals, hasLength(1));
      expect(removals.single.tabs, [first, second]);
      expect(
        tabsBloc.addedEvents.whereType<RemoveTab>(),
        isEmpty,
        reason: 'סגירת חבר בקבוצה סוגרת את כולה, לא כרטיסיה בודדת',
      );
      // ההיסטוריה נשלחת באירוע קבוצתי אחד — לא אירועי AddHistory מקביליים.
      final historyEvents = historyBloc.addedEvents
          .whereType<AddHistoryForTabs>()
          .toList();
      expect(historyEvents, hasLength(1));
      expect(historyEvents.single.tabs, [first, second]);
      expect(historyBloc.addedEvents.whereType<AddHistory>(), isEmpty);
    });

    testWidgets('כרטיסיות נבחרות מסומנות ברקע (painter)', (tester) async {
      await pumpWithTabs(tester);
      tabsBloc.emitState(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: [second, third],
        ),
      );
      await tester.pumpAndSettle();

      // הנבחרות (2) + הפעילה (1) מצוירות ברקע טאב; ללא בחירה רק הפעילה.
      final paintedTabs = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(ReadingTabStrip),
              matching: find.byType(CustomPaint),
            ),
          )
          .where(
            (w) => w.painter.runtimeType.toString() == '_TabBackgroundPainter',
          )
          .length;
      expect(paintedTabs, 3);
    });
  });

  group('הפס שבין הכרטיסיה לתוכן', () {
    /// ⚠️ הפס הזה הופיע גם כשלא היה שום גבול, צל או מפריד: גוף הכרטיסיה
    /// הוא 32 והסרגל 40, והכרטיסיה ממורכזת בו — כלומר נשארו ארבעה
    /// פיקסלים של **צבע הרצועה** בין הכרטיסיה לתוכן שמתחתיה.
    ///
    /// ⚠️ הבדיקה מודדת את **הערך שהקוד מצייר בו**
    /// ([kTabBackgroundBottomOffset]) מול הפריסה שנמדדה, ולא היסט שהיא
    /// מחשבת בעצמה. הגרסה הראשונה כאן חישבה בעצמה, ולכן עברה גם כשהקוד
    /// צייר בהיסט 0 — כלומר אימתה את החשבון שלה מול עצמו.
    testWidgets('הכרטיסיה הפעילה מגיעה בציור עד תחתית הסרגל', (tester) async {
      final tabs = [_makeTextTab('ספר א'), _makeTextTab('ספר ב')];
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      // הצייר של הכרטיסיה הפעילה — היחיד מסוגו כשאין בחירה מרובה וריחוף.
      final painted = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where(
            (w) => w.painter.runtimeType.toString() == '_TabBackgroundPainter',
          )
          .toList();
      expect(painted, hasLength(1), reason: 'רק הכרטיסיה הפעילה נצבעת');

      final tabRect = tester.getRect(find.byWidget(painted.first));
      final barRect = tester.getRect(find.byType(CustomTitleBar));

      // ⚠️ ההצהרה: שטח הציור **הוא** גובה הסרגל, מלמעלה עד למטה.
      //
      // זו הצהרה חזקה יותר מ"הציור מגיע עד התחתית", והיא זו שנדרשת: כל
      // עוד הצייר חרג מגבולות ה-widget שלו, הרצועה
      // (`SingleChildScrollView`) חתכה את החריגה ברגע שהתוכן גלש —
      // כלומר עם הרבה כרטיסיות או בחלון צר הקו הבהיר חזר. ציור שכולו
      // בתוך הגבולות אינו יכול להיחתך.
      expect(
        tabRect.top,
        moreOrLessEquals(barRect.top, epsilon: 0.01),
        reason: 'שטח הציור מתחיל ב-${tabRect.top} והסרגל ב-${barRect.top}',
      );
      expect(
        tabRect.bottom,
        moreOrLessEquals(barRect.bottom, epsilon: 0.01),
        reason:
            'שטח הציור מסתיים ב-${tabRect.bottom} והסרגל ב-'
            '${barRect.bottom} — ההפרש הוא הפס שנראה בין הכרטיסיה לתוכן',
      );
    });

    testWidgets('הגבהת שטח הציור אינה מזיזה את כותרת הכרטיסיה', (
      tester,
    ) async {
      // ⚠️ ה-widget קיבל את כל גובה הסרגל כדי שהציור לא ייחתך, והתוכן
      // ממורכז בנפרד. בלי המירכוז הכותרת הייתה יורדת ארבעה פיקסלים.
      final tabs = [_makeTextTab('ספר א'), _makeTextTab('ספר ב')];
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final tab in tabs) {
          tab.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      final titleRect = tester.getRect(find.text('ספר א').first);
      final barRect = tester.getRect(find.byType(CustomTitleBar));
      expect(
        titleRect.center.dy,
        moreOrLessEquals(barRect.center.dy, epsilon: 1.0),
        reason:
            'הכותרת ממורכזת ב-${titleRect.center.dy} והסרגל ב-'
            '${barRect.center.dy}',
      );
    });

    testWidgets('הסרגל אינו מתארך כדי לפנות מקום לציור', (tester) async {
      // ⚠️ זה הכיוון שנכשל קודם: הרחבת הסרגל דחפה את התוכן למטה והגדילה
      // את הפער במקום לסגור אותו.
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      expect(tester.getSize(find.byType(CustomTitleBar)).height, 40);
    });
  });

  group('סגירת טאב בלחיצה על כפתור ה-X', () {
    testWidgets('לחיצה על ה-X סוגרת מיד — בלי המתנה ל-timeout של לחיצה כפולה', (
      tester,
    ) async {
      // רגרסיה: מזהה הלחיצה הכפולה (maximize על האזור הריק) החזיק את
      // ה-gesture arena על כל השורה, וה-X הגיב רק אחרי ~300ms. המזהה חייב
      // לדחות מצביעים שמעל טאב, כך שה-RemoveTab נשלח מיד בשחרור הלחיצה.
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        historyBloc: historyBloc,
      );

      final closeButton = find.byIcon(FluentIcons.dismiss_24_regular);
      expect(closeButton, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(closeButton));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      // pump ללא קידום שעון: אסור שהסגירה תחכה ל-timer של הלחיצה הכפולה.
      await tester.pump();

      expect(
        tabsBloc.addedEvents.whereType<RemoveTab>(),
        isNotEmpty,
        reason: 'ה-X חייב לסגור מיד בשחרור הלחיצה, ללא השהיית arena',
      );
    });

    testWidgets('לחיצה על ה-X של טאב שאינו הנבחר סוגרת אותו (RemoveTab)', (
      tester,
    ) async {
      // התרחיש שבו הבאג הופיע: לחיצה על ה-X של טאב לא-נבחר בחרה אותו
      // (SetCurrentTab) וה-rebuild תחת ה-GlobalKey הנבחר הרס את ה-IconButton
      // לפני שה-onPressed שלו ירה — כך שהטאב התחלף במקום להיסגר.
      // _SelectingTabsBloc מדמה את אותו emit/rebuild בבחירה.
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        historyBloc: historyBloc,
      );

      final closeButton = find.descendant(
        of: find.ancestor(
          of: find.text('ספר ב'),
          matching: find.byType(Tab),
        ),
        matching: find.byIcon(FluentIcons.dismiss_24_regular),
      );
      expect(closeButton, findsOneWidget);

      // לחיצה (pointer-down) על ה-X של טאב לא-נבחר אסור שתבחר אותו: בחירה כאן
      // גורמת ל-rebuild תחת ה-GlobalKey הנבחר שמשמיד את ה-IconButton לפני
      // שה-onPressed שלו יורה — כך הטאב התחלף במקום להיסגר (שורש הבאג).
      final gesture = await tester.startGesture(tester.getCenter(closeButton));
      await tester.pump();
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>(),
        isEmpty,
        reason: 'לחיצה על ה-X לא צריכה לבחור את הטאב (שתהרוס את כפתור הסגירה)',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // ה-onPressed של ה-X מחובר לסגירה. נקרא ישירות כי ה-drag recognizer של
      // מזהה הגרירה של הרצועה בולע כל סימולציית tap ב-arena בסביבת הטסט.
      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: closeButton, matching: find.byType(IconButton)),
      );
      iconButton.onPressed!();
      await tester.pump();

      final removed = tabsBloc.addedEvents.whereType<RemoveTab>().toList();
      expect(removed, isNotEmpty, reason: 'כפתור ה-X חייב לסגור את הטאב');
      expect(
        removed.last.tab,
        same(second),
        reason: 'הטאב שנסגר הוא הטאב שעל ה-X שלו נלחץ',
      );
    });

    testWidgets('קיצור הסגירה מוצג רק ב-tooltip של ה-X בטאב הפעיל '
        '(issue #2000)', (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      String closeTooltipOf(String title) => tester
          .widget<IconButton>(
            find.ancestor(
              of: find.descendant(
                of: find.ancestor(
                  of: find.text(title),
                  matching: find.byType(Tab),
                ),
                matching: find.byIcon(FluentIcons.dismiss_24_regular),
              ),
              matching: find.byType(IconButton),
            ),
          )
          .tooltip!;

      final shortcut = ShortcutHelper.formatShortcutForDisplay('ctrl+w');
      expect(closeTooltipOf('ספר א'), 'סגור כרטיסיה ($shortcut)');
      expect(
        closeTooltipOf('ספר ב'),
        'סגור כרטיסיה',
        reason: 'הקיצור סוגר רק את הטאב הפעיל',
      );
    });
  });

  testWidgets('סגירת טאב כשהעכבר בשורה שומרת על רוחב הטאבים (לא מתרחבים)', (
    tester,
  ) async {
    // 6 טאבים ברוחב צר (מתחת לתקרה) — סגירה רגילה תרחיב את הנותרים. כל עוד
    // העכבר בשורה הרוחב אמור להישאר קפוא כדי שה-X של הטאב הבא יישאר תחת הסמן.
    final tabs = List.generate(6, (i) => _makeTextTab('ספר מספר $i'));
    final tabsBloc = _ClosingTabsBloc(
      TabsState(tabs: tabs, currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final historyBloc = _TestHistoryBloc();

    addTearDown(() async {
      for (final t in tabs) {
        t.dispose();
      }
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
    });

    await _setSurfaceSize(tester, const Size(700, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
      historyBloc: historyBloc,
    );
    await tester.pumpAndSettle();

    List<double> tabWidths() => tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(ReadingTabStrip),
            matching: find.byType(SizedBox),
          ),
        )
        .where((b) => b.width != null && b.child is Listener)
        .map((b) => b.width!)
        .toList();

    final widthBefore = tabWidths().first;

    // מביאים את העכבר אל מרכז השורה (hover) — כך _pointerInsideTabStrip=true.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(ReadingTabStrip)),
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    // סוגרים טאב דרך ה-onPressed של ה-X (סימולציית tap נבלעת ע"י ה-reorder
    // recognizer בסביבת הטסט, ולכן קוראים ישירות).
    void closeTabByTitle(String title) {
      final closeButton = find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Tab)),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(closeButton).onPressed!();
    }

    closeTabByTitle('ספר מספר 2');
    await tester.pumpAndSettle();
    expect(
      tabWidths().first,
      moreOrLessEquals(widthBefore, epsilon: 1.0),
      reason: 'סגירה ראשונה: הרוחב נשאר קפוא',
    );

    // סגירה רצופה שנייה — הרוחב חייב להישאר קפוא על אותו ערך, לא להתרחב מחדש.
    closeTabByTitle('ספר מספר 3');
    await tester.pumpAndSettle();

    expect(tabWidths().length, 4, reason: 'שני טאבים נסגרו');
    expect(
      tabWidths().first,
      moreOrLessEquals(widthBefore, epsilon: 1.0),
      reason: 'בסגירות רצופות הרוחב נשאר קפוא על הערך המקורי ולא מתרחב',
    );
  });

  group('פריסת מסך צר (portrait) — טאבים בשורה תחתונה', () {
    testWidgets('landscape: הטאבים באותה שורה של כפתורי הפעולה', (
      tester,
    ) async {
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      final tabsBarSize = tester.getSize(find.byType(ReadingTabStrip));
      expect(
        tabsBarSize.height,
        lessThanOrEqualTo(40),
        reason: 'במצב רחב הטאבים בתוך שורת הכותרת 40px',
      );

      final tabsTop = tester.getTopLeft(find.byType(ReadingTabStrip)).dy;
      expect(
        tabsTop,
        lessThan(40),
        reason: 'בלנדסקייפ הטאבים בשורה העליונה (y < 40)',
      );
    });

    testWidgets('portrait: הטאבים בשורה תחתונה מתחת לשורת הכותרת', (
      tester,
    ) async {
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(400, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      final tabsTop = tester.getTopLeft(find.byType(ReadingTabStrip)).dy;
      expect(
        tabsTop,
        greaterThanOrEqualTo(40),
        reason:
            'ב-portrait הטאבים בשורה תחתונה (y ≥ 40, כי השורה העליונה היא 40)',
      );
    });

    testWidgets('portrait: הטאבים מקבלים רוחב מלא ולא נדחסים', (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(400, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      final tabsBarWidth = tester.getSize(find.byType(ReadingTabStrip)).width;
      expect(
        tabsBarWidth,
        greaterThan(300),
        reason: 'בשורה התחתונה הטאבים מקבלים את הרוחב כמעט-מלא',
      );
    });

    testWidgets('portrait בלי טאבים פתוחים: השורה התחתונה לא מופיעה', (
      tester,
    ) async {
      final tabsBloc = _TestTabsBloc(
        const TabsState(tabs: [], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(400, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      expect(find.byType(ReadingTabStrip), findsNothing);
    });
  });

  group('לחיצה כפולה: על טאב נבלעת, על האזור הריק עושה maximize', () {
    // AppDragToMoveArea עושה maximize/restore ב-onDoubleTap, וכברירת מחדל דרך
    // ה-MethodChannel 'window_manager' (isMaximized → maximize/unmaximize).
    // תופסים את הקריאות כדי לוודא שלחיצה כפולה על טאב אינה מגיעה לשם.
    // אוספים רק את פעולות שינוי-הגודל (maximize/unmaximize). את isMaximized
    // מתעלמים: AppWindowCaption (כפתורי החלון) קורא לו בכל build לבחירת האייקון,
    // והוא אינו מעיד על לחיצה כפולה.
    late List<String> resizeCalls;

    void installWindowChannelSpy(WidgetTester tester) {
      resizeCalls = [];
      const channel = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method == 'maximize' || call.method == 'unmaximize') {
            resizeCalls.add(call.method);
          }
          if (call.method == 'isMaximized') return false;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
    }

    testWidgets('לחיצה כפולה על טאב אינה משנה את גודל החלון', (tester) async {
      // שני טאבים, השני אינו הנבחר — כך לחיצה ראשונה משגרת SetCurrentTab
      // ו-rebuild בין שתי הלחיצות, התרחיש שבו הבליעה נכשלה בעבר (ה-recognizer
      // נהרס כשהוא ממוקם מתחת ל-GlobalKey של הטאב הנבחר).
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      installWindowChannelSpy(tester);
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      await _doubleTapAt(tester, tester.getCenter(find.text('ספר ב')));

      expect(
        resizeCalls,
        isEmpty,
        reason: 'לחיצה כפולה על טאב לא צריכה לשנות את גודל החלון',
      );
    });

    testWidgets('לחיצה כפולה על האזור הריק שבשורת הטאבים עושה maximize', (
      tester,
    ) async {
      // טאב יחיד קצר ברוחב גדול → אזור ריק נרחב בשורת הטאבים, שבו ה-AppDragToMoveArea
      // צריך לפעול כרגיל (maximize/restore).
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      installWindowChannelSpy(tester);
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      // נקודה ריקה: בקצה ה-ListView שרחוק מהטאב (עמיד לכיווניות LTR/RTL).
      final listRect = tester.getRect(find.byType(ReadingTabStrip));
      final tabRect = tester.getRect(find.text('ספר א'));
      final emptyX = tabRect.center.dx < listRect.center.dx
          ? listRect.right - 10
          : listRect.left + 10;
      await _doubleTapAt(tester, Offset(emptyX, listRect.center.dy));

      expect(
        resizeCalls,
        contains('maximize'),
        reason: 'לחיצה כפולה על אזור ריק צריכה לשנות את גודל החלון',
      );
    });
  });

  group('ריחוף על כרטיסיה', () {
    late _TestTabsBloc tabsBloc;

    /// שורת כותרת עם [count] כרטיסיות; ככל שיש יותר הן צרות יותר.
    Future<List<OpenedTab>> pumpTabs(
      WidgetTester tester,
      int count, {
      Size size = const Size(900, 800),
      OpenedTab Function(int index)? makeTab,
    }) async {
      final tabs = List.generate(
        count,
        makeTab ?? (i) => _makeTextTab('ספר מספר $i'),
      );
      tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, size);
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();
      return tabs;
    }

    /// מרחף מעל [position] ומחזיר את המחווה, לשחרור בסוף הבדיקה.
    Future<TestGesture> hoverAt(WidgetTester tester, Offset position) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: position);
      addTearDown(gesture.removePointer);
      await tester.pumpAndSettle();
      return gesture;
    }

    /// המפרידים שבין הכרטיסיות — קווים ברוחב 1 וגובה 24.
    Iterable<Container> dividers(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(ReadingTabStrip),
            matching: find.byType(Container),
          ),
        )
        .where(
          (c) => c.constraints == BoxConstraints.tightFor(width: 1, height: 24),
        );

    testWidgets('ה-X מוצג בריחוף גם בכרטיסיה צרה מאוד', (tester) async {
      // 20 כרטיסיות ברוחב 900 → ~25px לכרטיסיה, פחות מרוחב ה-X המלא.
      await pumpTabs(tester, 20);

      final tab = find.byType(Tab).at(5);
      final closeButton = find.descendant(
        of: tab,
        matching: find.byIcon(FluentIcons.dismiss_24_regular),
      );
      expect(closeButton, findsNothing, reason: 'בלי ריחוף ה-X מוסתר');

      await hoverAt(tester, tester.getCenter(tab));
      expect(
        closeButton,
        findsOneWidget,
        reason: 'ה-X מצטמצם לרוחב שנותר במקום להיעלם',
      );
    });

    // issue #3276: ה-X של כרטיסיה צרה בריחוף תפס את רוב רוחבה, ולחיצה עליה
    // כדי לעבור אליה סגרה אותה.
    group('לחיצה על כרטיסיה צרה בריחוף בוחרת ולא סוגרת (issue #3276)', () {
      /// מרחף מעל הכרטיסיה השישית, מוודא שה-X שלה מוצג, ולוחץ ב-[clickAt].
      Future<void> hoverAndClick(
        WidgetTester tester, {
        required int closeButtonCount,
        required Offset Function(Rect tabRect, List<Rect> closeRects) clickAt,
      }) async {
        final tab = find.byType(Tab).at(5);
        final tabRect = tester.getRect(tab);
        final gesture = await hoverAt(tester, tabRect.center);
        final closeButtons = find.descendant(
          of: tab,
          matching: find.byType(IconButton),
        );
        expect(
          closeButtons,
          findsNWidgets(closeButtonCount),
          reason: 'ה-X עדיין מופיע בריחוף על כרטיסיה צרה (issue #1133)',
        );

        final closeRects = [
          for (final e in closeButtons.evaluate())
            tester.getRect(find.byWidget(e.widget)),
        ];
        await gesture.down(clickAt(tabRect, closeRects));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(
          tabsBloc.addedEvents.whereType<SetCurrentTab>().map((e) => e.index),
          contains(5),
          reason: 'הלחיצה עוברת לכרטיסיה',
        );
        expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
        expect(tabsBloc.addedEvents.whereType<ClosePane>(), isEmpty);

        expect(
          closeRects.fold<double>(0, (sum, r) => sum + r.width),
          lessThan(tabRect.width / 2),
          reason: 'רוב הכרטיסיה נשאר אזור בחירה ולא אזור סגירה',
        );
      }

      // 10 כרטיסיות ← כרטיסיה של כ-50px; 14 ← כ-36px.
      for (final count in [10, 14]) {
        testWidgets('כרטיסיה רגילה ($count כרטיסיות)', (tester) async {
          await pumpTabs(tester, count);
          await hoverAndClick(
            tester,
            closeButtonCount: 1,
            clickAt: (tabRect, _) => tabRect.center,
          );
        });
      }

      testWidgets('לשונית מפוצלת', (tester) async {
        await pumpTabs(
          tester,
          10,
          makeTab: (i) => i == 5
              ? CombinedTab(
                  rightTab: _makeTextTab('ימין'),
                  leftTab: _makeTextTab('שמאל'),
                )
              : _makeTextTab('ספר מספר $i'),
        );
        await hoverAndClick(
          tester,
          closeButtonCount: 2,
          // בין שני ה-X נמצאת כותרת של אחת החלוניות, בכל כיוון פריסה.
          clickAt: (tabRect, closeRects) => Offset(
            (closeRects.first.center.dx + closeRects.last.center.dx) / 2,
            tabRect.center.dy,
          ),
        );
      });
    });

    testWidgets('ה-tooltip מוצג בריחוף על כל שטח הכרטיסיה', (tester) async {
      final tabs = await pumpTabs(tester, 12);
      final title = tabs[5].title;
      final tabRect = tester.getRect(find.byType(Tab).at(5));

      // פינת הכרטיסיה — הרחק מהכותרת עצמה, ששם היה ה-tooltip קודם.
      await hoverAt(tester, tabRect.topLeft + const Offset(2, 2));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text(title),
        findsNWidgets(2),
        reason: 'הכותרת שבכרטיסיה ועותק נוסף ב-tooltip שנפתח',
      );
    });

    testWidgets('הפסים משני צדי הכרטיסיה שבריחוף נעלמים בלי להזיז דבר', (
      tester,
    ) async {
      final tabs = await pumpTabs(tester, 4, size: const Size(1200, 800));

      final coloredBefore = dividers(
        tester,
      ).where((c) => c.color != null).length;
      expect(coloredBefore, greaterThan(0));
      final neighborBefore = tester.getTopLeft(find.text(tabs[3].title));

      await hoverAt(tester, tester.getCenter(find.byType(Tab).at(2)));

      expect(
        dividers(tester).where((c) => c.color != null).length,
        coloredBefore - 2,
        reason: 'הפס שלפני הכרטיסיה שבריחוף והפס שאחריה מתבטלים',
      );
      expect(
        tester.getTopLeft(find.text(tabs[3].title)),
        neighborBefore,
        reason: 'מקום הפס שמור גם כשאינו נצבע — התוכן לא זז',
      );
    });
  });

  testWidgets('חיפוש הכרטיסיות בתחילת הרצועה, צמוד לכפתורי הפעולה', (
    tester,
  ) async {
    final tab = _makeTextTab('ספר א');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    final bookmarkX = tester
        .getCenter(find.byIcon(FluentIcons.bookmark_24_regular))
        .dx;
    final searchX = tester.getCenter(find.byType(TabSearchButton)).dx;
    final tabX = tester.getCenter(find.text('ספר א')).dx;

    // בין כפתורי הפעולה לכרטיסיה הראשונה — בלי תלות בכיווניות.
    expect((searchX - bookmarkX).sign, (tabX - bookmarkX).sign);
    expect((searchX - bookmarkX).abs(), lessThan((tabX - bookmarkX).abs()));
  });

  testWidgets('כפתורי החלון המותאמים מוצגים גם במק', (tester) async {
    final tab = _makeTextTab('ספר א');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.byType(AppWindowCaption), findsOneWidget);
  });

  testWidgets('בחלון Dart כפתורי החלון פועלים על החלון שלו', (tester) async {
    final tab = _makeTextTab('ספר א');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final stub = StubWindowController(SecondTestView(tester.view));
    final handle = StubWindowHandle(stub, (_) {}, fakeHwnd: 9);
    var closes = 0;
    final window = HostWindowAppWindowController(
      id: const AppWindowId('window-view-2'),
      handle: handle,
      onClose: () async => closes++,
      native: FakeViewWindowNative(),
    );

    addTearDown(() async {
      tab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
      role: const AppWindowRole.view(),
      controller: window,
    );

    expect(find.byType(AppWindowCaption), findsOneWidget);
    expect(find.text('ספר א'), findsOneWidget);
    final buttons = find.descendant(
      of: find.byType(AppWindowCaption),
      matching: find.byType(WindowCaptionButton),
    );
    expect(buttons, findsNWidgets(3));

    await tester.tap(buttons.at(1));
    stub.notify();
    await tester.pumpAndSettle();
    expect(stub.maximized, isTrue);
    // אחרי WM_SIZE הכפתור האמצעי מחזיר לגודל רגיל.
    await tester.tap(buttons.at(1));
    stub.notify();
    await tester.pumpAndSettle();
    expect(stub.maximized, isFalse);

    await tester.tap(buttons.first);
    await tester.pump();
    expect(stub.minimized, isTrue);

    await tester.tap(buttons.last);
    await tester.pump();
    expect(closes, 1);
  });

  group('רצועת הכרטיסיות מעל דיאלוג (R6-4)', () {
    late _RecordingWindow window;

    Future<void> pumpWithDialog(
      WidgetTester tester, {
      bool dismissible = false,
    }) async {
      window = _RecordingWindow();
      addTearDown(window.changes.dispose);
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        controller: window,
        captionScope: true,
      );
      showDialog<void>(
        context: tester.element(find.byType(CustomTitleBar)),
        barrierDismissible: dismissible,
        builder: (_) => const Center(
          child: Material(
            child: SizedBox(key: Key('dialog'), width: 200, height: 80),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Rect tabRect(WidgetTester tester) => tester.getRect(
      find
          .ancestor(of: find.text('ספר א'), matching: find.byType(MetaData))
          .first,
    );

    /// נקודה ברצועה, בקצה הרחוק מהכרטיסיה.
    Offset emptyStripPoint(WidgetTester tester) {
      final strip = tester.getRect(find.byType(ReadingTabStrip));
      final tab = tabRect(tester);
      final left = Offset(strip.left + 12, strip.center.dy);
      final right = Offset(strip.right - 12, strip.center.dy);
      return (tab.center - left).distance > (tab.center - right).distance
          ? left
          : right;
    }

    testWidgets('גרירה מהאזור הריק ברצועה מזיזה את החלון', (tester) async {
      await pumpWithDialog(tester);
      final at = emptyStripPoint(tester);
      expect(tabRect(tester).contains(at), isFalse);
      await tester.dragFrom(at, const Offset(40, 0));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(window.calls, contains('startDragging'));
    });

    testWidgets('גרירה מכרטיסיה אינה מזיזה את החלון, והכרטיסיה חסומה', (
      tester,
    ) async {
      await pumpWithDialog(tester);
      await tester.dragFrom(tabRect(tester).center, const Offset(40, 0));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(window.calls, isNot(contains('startDragging')));
    });

    testWidgets('לחיצה על האזור הריק ברצועה סוגרת דיאלוג שנסגר בלחיצה בחוץ', (
      tester,
    ) async {
      await pumpWithDialog(tester, dismissible: true);
      await tester.tapAt(emptyStripPoint(tester));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(find.byKey(const Key('dialog')), findsNothing);
    });

    testWidgets('לחיצה כפולה על האזור הריק ברצועה מגדילה', (tester) async {
      await pumpWithDialog(tester);
      await _doubleTapAt(tester, emptyStripPoint(tester));
      expect(window.calls, contains('maximize'));
    });

    testWidgets('בלי דיאלוג: גרירה מהאזור הריק ברצועה מזיזה פעם אחת', (
      tester,
    ) async {
      await pumpWithDialog(tester);
      Navigator.of(tester.element(find.byType(CustomTitleBar))).pop();
      await tester.pumpAndSettle();
      await tester.dragFrom(emptyStripPoint(tester), const Offset(40, 0));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(window.calls.where((c) => c == 'startDragging'), hasLength(1));
    });
  });
}

class _RecordingWindow extends Fake implements AppWindowController {
  final calls = <String>[];
  final changes = ChangeNotifier();

  @override
  Listenable get stateChanges => changes;

  @override
  Future<void> startDragging() async => calls.add('startDragging');

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<void> maximize() async => calls.add('maximize');

  @override
  Future<void> unmaximize() async => calls.add('unmaximize');

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> close() async => calls.add('close');
}

/// לחיצה כפולה במיקום נתון: שתי הקשות עם השהיה תקפה ל-double-tap, ואז המתנה
/// להשלמת ה-onDoubleTap (שהוא async ב-AppDragToMoveArea).
Future<void> _doubleTapAt(WidgetTester tester, Offset pos) async {
  await tester.tapAt(pos);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(pos);
  await tester.pumpAndSettle();
}

Future<void> _pumpTitleBar(
  WidgetTester tester, {
  required TabsBloc tabsBloc,
  required NavigationBloc navigationBloc,
  required SettingsBloc settingsBloc,
  ThemeData? theme,
  HistoryBloc? historyBloc,
  WorkspaceBloc? workspaceBloc,
  WindowFullscreenCubit? fullscreenCubit,
  AppWindowRole? role,
  AppWindowController? controller,
  bool captionScope = false,
}) async {
  await tester.pumpWidget(
    // CustomTitleBar שולף את החלון מ-[AppWindowScope] (maximize בלחיצה
    // כפולה, מזעור, סגירה, גרירת החלון). הבקר האמיתי מנתב לאותו
    // MethodChannel שממוקם בבדיקה, ולכן ההנחות הקיימות נשארות בתוקף.
    AppWindowScope(
      controller: controller ?? const WindowManagerAppWindowController(),
      geometry: const WindowManagerAppWindowController(),
      role: role,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          if (fullscreenCubit != null)
            BlocProvider<WindowFullscreenCubit>.value(value: fullscreenCubit)
          else
            BlocProvider<WindowFullscreenCubit>(
              create: (_) => WindowFullscreenCubit(
                initial: false,
                persist: (_) async {},
              ),
            ),
          if (historyBloc != null)
            BlocProvider<HistoryBloc>.value(value: historyBloc),
          if (workspaceBloc != null)
            BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
        ],
        child: MaterialApp(
          builder: captionScope
              ? (context, child) => WindowCaptionHitTestScope(child: child!)
              : null,
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: CustomTitleBar(
                onReadingSettingsPressed: () {},
              ),
            ),
          ),
          theme: theme,
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

TextBookTab _makeTextTab(String title, {String currentTitle = ''}) {
  final book = TextBook(title: title);
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: const ['שורה א'],
      fontSize: 18,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      removePunctuation: false,
      visibleIndices: const [0],
      selectedIndex: 0,
      pinLeftPane: false,
      searchText: '',
      currentTitle: currentTitle,
    ),
  );

  final tab = TextBookTab(
    book: book,
    index: 0,
    blocOverride: bloc,
  );
  tab.currentTitle.value = currentTitle;
  return tab;
}

PdfBookTab _makePdfTab(String title) {
  return PdfBookTab(
    book: PdfBook(title: title, path: '$title.pdf'),
    pageNumber: 1,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  /// מתעד את כל ה-events שנשלחו, לבדיקת בחירה/סידור-מחדש של טאבים.
  final List<TabsEvent> addedEvents = [];

  /// מאפשר לטסט לדמות שינוי מצב (בחירה/החלפת רשימת טאבים) אחרי הטעינה.
  void emitState(TabsState state) => emit(state);

  @override
  void add(TabsEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// כמו [_TestTabsBloc], אך SetCurrentTab גם מעדכן את ה-state (emit) — כדי לדמות
/// את ה-rebuild שמתרחש בבחירת טאב, התרחיש שבו בליעת הלחיצה הכפולה נכשלה בעבר.
class _SelectingTabsBloc extends _TestTabsBloc {
  _SelectingTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {
    super.add(event);
    if (event is SetCurrentTab) {
      emit(TabsState(tabs: state.tabs, currentTabIndex: event.index));
    }
  }
}

/// מסיר טאב בפועל ב-RemoveTab — לבדיקת קפיאת רוחב הטאבים בסגירה.
class _ClosingTabsBloc extends _TestTabsBloc {
  _ClosingTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {
    super.add(event);
    if (event is RemoveTab) {
      final newTabs = state.tabs.where((t) => t != event.tab).toList();
      emit(TabsState(tabs: newTabs, currentTabIndex: 0));
    }
  }
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState);

  /// מאפשר לטסט לדמות מעבר מסך (למשל library → reading).
  void emitScreen(Screen screen) =>
      emit(NavigationState(currentScreen: screen));

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  void emitState(SettingsState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWorkspaceBloc extends Cubit<WorkspaceState>
    implements WorkspaceBloc {
  _TestWorkspaceBloc() : super(WorkspaceState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _TestHistoryBloc() : super(HistoryInitial());

  /// מתעד את אירועי ההיסטוריה שנשלחו, לבדיקת סגירה קבוצתית.
  final List<HistoryEvent> addedEvents = [];

  @override
  void add(HistoryEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
