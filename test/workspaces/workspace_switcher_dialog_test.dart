import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('שמירת פוקוס מקלדת בשינוי שם שולחן עבודה', () {
    testWidgets(
      'מצב העריכה שורד rebuild של ה-viewport (פתיחת מקלדת וירטואלית)',
      (tester) async {
        // רגרסיה: במצב עריכת שם, פתיחת המקלדת מכווצת את ה-viewport וגורמת
        // rebuild של הדיאלוג. בעבר מצב העריכה אוחסן במשתני closure בתוך Builder
        // ולכן התאפס ב-rebuild — שדה הקלט נעלם והמקלדת נסגרה מיד אחרי שנפתחה.
        final workspace = Workspace(name: 'שולחן א', tabs: const []);
        final workspaceBloc = _TestWorkspaceBloc(
          WorkspaceState(
            workspaces: [workspace],
            isLoading: false,
            activeWorkspaceId: workspace.id,
          ),
        );
        final tabsBloc = _TestTabsBloc(TabsState.initial());
        final navigationBloc = _TestNavigationBloc(
          const NavigationState(currentScreen: Screen.reading),
        );

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await workspaceBloc.close();
          await tabsBloc.close();
          await navigationBloc.close();
        });

        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              BlocProvider<NavigationBloc>.value(value: navigationBloc),
            ],
            child: const MaterialApp(
              locale: Locale('he', 'IL'),
              home: Scaffold(body: WorkspaceSwitcherDialog()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // כניסה למצב עריכה — לחיצה על עיפרון העריכה.
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == FluentIcons.edit_24_regular,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(RtlTextField),
          findsOneWidget,
          reason: 'שדה עריכת השם אמור להופיע אחרי לחיצה על עיפרון',
        );

        // כיווץ ה-viewport — מדמה פתיחת מקלדת וירטואלית שגורמת rebuild לדיאלוג.
        tester.view.physicalSize = const Size(1200, 700);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.byType(RtlTextField),
          findsOneWidget,
          reason:
              'מצב העריכה אסור שיתאפס ב-rebuild — אחרת שדה הקלט נעלם '
              'והמקלדת נסגרת מיד',
        );
      },
    );

    testWidgets('שמירת השם שולחת RenameWorkspace לבלוק', (tester) async {
      final workspace = Workspace(name: 'שולחן א', tabs: const []);
      final workspaceBloc = _TestWorkspaceBloc(
        WorkspaceState(
          workspaces: [workspace],
          isLoading: false,
          activeWorkspaceId: workspace.id,
        ),
      );
      final tabsBloc = _TestTabsBloc(TabsState.initial());
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await workspaceBloc.close();
        await tabsBloc.close();
        await navigationBloc.close();
      });

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
          ],
          child: const MaterialApp(
            locale: Locale('he', 'IL'),
            home: Scaffold(body: WorkspaceSwitcherDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == FluentIcons.edit_24_regular,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(RtlTextField), 'שם חדש');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final renameEvents = workspaceBloc.addedEvents
          .whereType<RenameWorkspace>()
          .toList();
      expect(renameEvents, hasLength(1));
      expect(renameEvents.single.workspaceId, workspace.id);
      expect(renameEvents.single.newName, 'שם חדש');
    });
  });
}

class _TestWorkspaceBloc extends Cubit<WorkspaceState>
    implements WorkspaceBloc {
  _TestWorkspaceBloc(super.initialState);

  final List<WorkspaceEvent> addedEvents = [];

  @override
  void add(WorkspaceEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState);

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
