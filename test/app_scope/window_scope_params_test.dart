import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/app_scope/window_scope_providers.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  tearDown(() {
    ProcessDuties.debugOverride = null;
  });

  Future<Map<String, BuildContext>> pumpWindows(
    WidgetTester tester,
    Map<String, Widget Function(Widget child)> windows,
  ) async {
    final contexts = <String, BuildContext>{};
    await tester.pumpWidget(
      AppScopeProviders(
        settingsRepository: SettingsRepository(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              for (final entry in windows.entries)
                Expanded(
                  child: entry.value(
                    Builder(
                      builder: (context) {
                        contexts[entry.key] = context;
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return contexts;
  }

  testWidgets('שני חלונות עם פרמטרים שונים מקבלים ערכים נפרדים', (
    tester,
  ) async {
    final dutiesA = ProcessDuties(isProcessOwner: () => true);
    final dutiesB = ProcessDuties(
      isProcessOwner: () => false,
      hostsPluginBackground: false,
    );
    // בלי משבצת: הטעינה והשמירה של הכרטיסיות אינן נוגעות בדיסק.
    var slotReadsA = 0;
    var slotReadsB = 0;
    final sessionA = WindowTabsSession(
      slot: () {
        slotReadsA++;
        return null;
      },
    );
    final sessionB = WindowTabsSession(
      slot: () {
        slotReadsB++;
        return null;
      },
    );
    final tab = ToolTab(toolId: 'calendar', title: 'לוח שנה');

    final contexts = await pumpWindows(tester, {
      'a': (child) => WindowScopeProviders(
        historyRepository: HistoryRepository(),
        initialTab: tab,
        tabsSession: sessionA,
        duties: dutiesA,
        child: child,
      ),
      'b': (child) => WindowScopeProviders(
        historyRepository: HistoryRepository(),
        tabsSession: sessionB,
        duties: dutiesB,
        child: child,
      ),
    });
    final a = contexts['a']!;
    final b = contexts['b']!;

    expect(ProcessDuties.of(a), same(dutiesA));
    expect(ProcessDuties.of(b), same(dutiesB));
    expect(ProcessDuties.of(b).hostsPluginBackground, isFalse);

    final tabsA = a.read<TabsBloc>();
    final tabsB = b.read<TabsBloc>();
    await tester.pump();
    // כל חלון טוען דרך הסשן שלו בלבד.
    expect(slotReadsA, greaterThan(0));
    expect(slotReadsB, greaterThan(0));
    expect(tabsA.state.tabs, [same(tab)]);
    expect(tabsB.state.tabs, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ברירת המחדל של ProcessDuties היא current, עם host תוספים', (
    tester,
  ) async {
    final contexts = await pumpWindows(tester, {
      'a': (child) => WindowScopeProviders(
        historyRepository: HistoryRepository(),
        child: child,
      ),
    });
    final a = contexts['a']!;

    expect(ProcessDuties.of(a), same(ProcessDuties.current));
    expect(ProcessDuties.of(a).hostsPluginBackground, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('AppWindowScope.roleOf', () {
    final controller = WindowManagerAppWindowController();

    Future<BuildContext> pumpScope(
      WidgetTester tester, {
      AppWindowRole? role,
    }) async {
      late BuildContext context;
      await tester.pumpWidget(
        AppWindowScope(
          controller: controller,
          geometry: controller,
          role: role,
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return context;
    }

    testWidgets('בלי תפקיד מפורש — החלון הראשי', (tester) async {
      final context = await pumpScope(tester);
      expect(AppWindowScope.roleOf(context), AppWindowRole.main);
    });

    testWidgets('תפקיד מפורש גובר על ברירת המחדל', (tester) async {
      const role = AppWindowRole.view(openedWithTab: true);
      final context = await pumpScope(tester, role: role);
      expect(AppWindowScope.roleOf(context), role);
    });

    testWidgets('בלי scope מעל — AppWindowRole.main', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      );
      expect(
        AppWindowScope.roleOf(context),
        AppWindowRole.main,
      );
    });
  });
}
