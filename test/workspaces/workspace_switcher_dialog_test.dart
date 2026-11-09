import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../helpers/memory_settings_cache.dart';

Future<_TestWorkspaceBloc> _pumpSwitcherAt(
  WidgetTester tester,
  Size window,
  List<String> names,
) async {
  final workspaces = [
    for (final name in names) Workspace(name: name, tabs: const []),
  ];
  final workspaceBloc = _TestWorkspaceBloc(
    WorkspaceState(
      workspaces: workspaces,
      isLoading: false,
      activeWorkspaceId: workspaces.first.id,
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
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
      ],
      child: MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const WorkspaceSwitcherDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return workspaceBloc;
}

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
          _renameField,
          findsOneWidget,
          reason: 'שדה עריכת השם אמור להופיע אחרי לחיצה על עיפרון',
        );

        // כיווץ ה-viewport — מדמה פתיחת מקלדת וירטואלית שגורמת rebuild לדיאלוג.
        tester.view.physicalSize = const Size(1200, 700);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          _renameField,
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

      await tester.enterText(_renameField, 'שם חדש');
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

  // issue #2728 — אחרי שמירת השם הפוקוס נזרק, ו-Enter נוסף לא פתח את השולחן.
  for (final saveWithButton in [false, true]) {
    testWidgets(
      'Enter אחרי שמירת השם פותח את השולחן (issue #2728), '
      'שמירה ב${saveWithButton ? 'כפתור' : '-Enter'}',
      (tester) async {
        final active = Workspace(name: 'שולחן א', tabs: const []);
        final renamed = Workspace(name: 'שולחן ב', tabs: const []);
        final workspaceBloc = _TestWorkspaceBloc(
          WorkspaceState(
            workspaces: [active, renamed],
            isLoading: false,
            activeWorkspaceId: active.id,
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
          find.descendant(
            of: find.ancestor(
              of: find.text('שולחן ב'),
              matching: find.byType(AppCard),
            ),
            matching: find.byIcon(FluentIcons.edit_24_regular),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(_renameField, 'שולחן לימוד');
        if (saveWithButton) {
          await tester.tap(find.byTooltip('שמור'));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.testTextInput.receiveAction(TextInputAction.done);
        }
        await tester.pumpAndSettle();

        expect(_renameField, findsNothing);
        expect(
          workspaceBloc.addedEvents.whereType<RenameWorkspace>().single.newName,
          'שולחן לימוד',
        );
        expect(
          workspaceBloc.addedEvents.whereType<SwitchToWorkspace>(),
          isEmpty,
          reason: 'שמירת השם לבדה אינה פותחת את השולחן',
        );
        // הבלוק מפרסם את השם החדש לפני ה-Enter השני.
        workspaceBloc.emit(
          workspaceBloc.state.copyWith(
            workspaces: [
              active,
              renamed.copyWith(name: 'שולחן לימוד'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        final switches = workspaceBloc.addedEvents
            .whereType<SwitchToWorkspace>()
            .toList();
        expect(switches, hasLength(1));
        expect(switches.single.targetWorkspaceId, renamed.id);
      },
    );
  }

  // q9 שאלה 7: פח בשורת השם, מושבת בפעיל; מסגרת הבחירה ורק התצוגה המקדימה
  // בצבע "נבחר" בפעיל; הלא פעילים על רקע נייטרלי; הגוף בצבע הדיאלוג.
  group('גודל הבורר (#3627)', () {
    testWidgets('בחלון 1366x768 שישה אריחים שלמים, בשלוש עמודות', (
      tester,
    ) async {
      await _pumpSwitcherAt(tester, const Size(1366, 768), [
        for (var i = 0; i < 5; i++) 'שולחן $i',
      ]);
      final grid = tester.getRect(find.byType(GridView));
      final cards = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(AppCard),
      );
      expect(cards, findsNWidgets(6));
      final rects = [
        for (final e in cards.evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      for (final r in rects) {
        expect(
          r.top >= grid.top && r.bottom <= grid.bottom,
          isTrue,
          reason: '$r חתוך בתוך $grid',
        );
      }
      expect(rects.map((r) => r.left.round()).toSet(), hasLength(3));
      // הדיאלוג ברוחב large הקבוע, ולא 80% מהחלון.
      expect(grid.width, lessThanOrEqualTo(720));
    });
  });

  group('חיפוש בבורר (#2841)', () {
    const names = [
      'לימוד יומי',
      'הִלְכוֹת שבת',
      'פרשת השבוע',
      'דף יומי',
      'הלכות ברכות',
      'מוסר',
      'שיעור ערב',
    ];

    testWidgets('שדה החיפוש מוצג תמיד, גם בשולחן אחד (#2841)', (tester) async {
      await _pumpSwitcherAt(
        tester,
        const Size(1366, 768),
        names.take(1).toList(),
      );
      expect(find.byType(OtzariaSearchField), findsOneWidget);
    });

    testWidgets('סינון לפי שם בלי ניקוד, ואריח "חדש" נשאר', (
      tester,
    ) async {
      await _pumpSwitcherAt(tester, const Size(1366, 768), names);
      expect(find.byType(OtzariaSearchField), findsOneWidget);
      final dialogHeight = tester.getSize(find.byType(GridView)).height;
      await tester.enterText(find.byType(EditableText), 'הלכות');
      await tester.pumpAndSettle();
      expect(find.text('הִלְכוֹת שבת'), findsOneWidget);
      expect(find.text('הלכות ברכות'), findsOneWidget);
      expect(find.text('מוסר'), findsNothing);
      expect(find.text('שולחן עבודה חדש'), findsOneWidget);
      // הגובה קבוע: הגריד לא מתכווץ כשנשארות פחות תוצאות.
      expect(tester.getSize(find.byType(GridView)).height, dialogHeight);

      await tester.enterText(find.byType(EditableText), 'גמרא');
      await tester.pumpAndSettle();
      expect(find.text('לא נמצאו שולחנות עבודה'), findsOneWidget);
      expect(find.text('שולחן עבודה חדש'), findsOneWidget);
    });
  });

  // R7-1, #2841: "לבדוק גם שינוי שם בזמן סינון".
  testWidgets('שינוי שם בזמן סינון נשאר עם השולחן שלו כשהסינון משתנה', (
    tester,
  ) async {
    final bloc = await _pumpSwitcherAt(tester, const Size(1366, 768), [
      'גמרא',
      'שבת',
      'שבועות',
      'משנה',
      'הלכה',
      'מוסר',
      'תפילה',
    ]);
    final shabbat = bloc.state.workspaces[1];
    final search = find.descendant(
      of: find.byType(OtzariaSearchField),
      matching: find.byType(EditableText),
    );
    final renameField = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(EditableText),
    );

    await tester.enterText(search, 'שב');
    await tester.pumpAndSettle();
    expect(find.text('גמרא'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('שבת'), matching: find.byType(AppCard)),
        matching: find.byIcon(FluentIcons.edit_24_regular),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(renameField, 'שבת קודש');
    await tester.pumpAndSettle();

    // ניקוי החיפוש: הרשימה המלאה חוזרת, ו"גמרא" שוב באינדקס 0.
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(renameField, findsOneWidget, reason: 'העריכה אבדה');

    await tester.showKeyboard(renameField);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final renames = bloc.addedEvents.whereType<RenameWorkspace>().toList();
    expect(renames, hasLength(1));
    expect(
      renames.single.workspaceId,
      shabbat.id,
      reason: 'השם החדש הלך לשולחן אחר',
    );
    expect(renames.single.newName, 'שבת קודש');
  });

  group('כרטיס שולחן העבודה', () {
    Future<_TestWorkspaceBloc> pumpDialog(
      WidgetTester tester,
      Workspace active,
      Workspace other,
    ) async {
      final workspaceBloc = _TestWorkspaceBloc(
        WorkspaceState(
          workspaces: [active, other],
          isLoading: false,
          activeWorkspaceId: active.id,
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
      return workspaceBloc;
    }

    Finder card(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(AppCard));

    IconButton deleteIn(WidgetTester tester, String name) =>
        tester.widget<IconButton>(
          find.ancestor(
            of: find.descendant(
              of: card(name),
              matching: find.byIcon(FluentIcons.delete_24_regular),
            ),
            matching: find.byType(IconButton),
          ),
        );

    testWidgets('פח בשורת השם: מושבת בשולחן הפעיל, ואין X בפינה', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        Workspace(name: 'פעיל', tabs: const []),
        Workspace(name: 'אחר', tabs: const []),
      );
      expect(deleteIn(tester, 'פעיל').onPressed, isNull);
      expect(deleteIn(tester, 'אחר').onPressed, isNotNull);
      expect(
        deleteIn(tester, 'פעיל').tooltip,
        'לא ניתן למחוק שולחן עבודה פעיל',
      );
      expect(deleteIn(tester, 'אחר').tooltip, 'מחק שולחן עבודה');
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byIcon(FluentIcons.dismiss_24_regular),
        ),
        findsNothing,
      );

      await tester.tap(
        find.descendant(
          of: card('אחר'),
          matching: find.byIcon(FluentIcons.delete_24_regular),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('למחוק את שולחן העבודה?'), findsOneWidget);
    });

    testWidgets('הפעיל במסגרת הבחירה, ורק התצוגה המקדימה שלו בצבע "נבחר"', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        Workspace(name: 'פעיל', tabs: const []),
        Workspace(name: 'אחר', tabs: const []),
      );
      final cs = Theme.of(tester.element(card('פעיל'))).colorScheme;
      expect(tester.widget<AppCard>(card('פעיל')).active, isTrue);
      expect(tester.widget<AppCard>(card('אחר')).active, isFalse);
      expect(tester.widget<AppCard>(card('פעיל')).selected, isFalse);

      Color? previewColor(String name) =>
          (tester
                      .widgetList<Container>(
                        find.descendant(
                          of: card(name),
                          matching: find.byType(Container),
                        ),
                      )
                      .firstWhere((c) => c.decoration is BoxDecoration)
                      .decoration!
                  as BoxDecoration)
              .color;
      expect(previewColor('פעיל'), AppSurfaces.selectedRow(cs));
      expect(previewColor('אחר'), cs.surfaceContainerHighest);
    });
  });

  group('תצוגת הכרטיסיות של שולחן העבודה הפעיל', () {
    testWidgets(
      'שולחן חדש ופעיל מציג את הכרטיסיות הפתוחות בו לפני שעוזבים אותו '
      '(issue #1984)',
      (tester) async {
        final other = Workspace(name: 'שולחן ישן', tabs: [_PreviewTab('ישן')]);
        // השמירה של השולחן הפעיל ריקה: הכרטיסיות נשמרות אליו רק ביציאה.
        final fresh = Workspace(name: 'שולחן חדש', tabs: const []);
        final workspaceBloc = _TestWorkspaceBloc(
          WorkspaceState(
            workspaces: [other, fresh],
            isLoading: false,
            activeWorkspaceId: fresh.id,
          ),
        );
        final tabsBloc = _TestTabsBloc(
          TabsState(
            tabs: [_PreviewTab('ברכות'), _PreviewTab('שבת')],
            currentTabIndex: 0,
          ),
        );
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

        Iterable<String> previewTitles(String workspaceName) => tester
            .widgetList<Tooltip>(
              find.descendant(
                of: find.ancestor(
                  of: find.text(workspaceName),
                  matching: find.byType(AppCard),
                ),
                matching: find.byType(Tooltip),
              ),
            )
            // תצוגת הכרטיסיות; טולטיפים של כפתורי הכרטיס אינם כרטיסיות.
            .where((t) => t.child is Column)
            .expand((t) => (t.message ?? '').split('\n'));

        expect(previewTitles('שולחן חדש'), ['ברכות', 'שבת']);
        expect(previewTitles('שולחן ישן'), ['ישן']);

        // כרטיסייה שנפתחת כשהרשימה פתוחה מתווספת מיד.
        tabsBloc.emit(
          TabsState(
            tabs: [
              _PreviewTab('ברכות'),
              _PreviewTab('שבת'),
              _PreviewTab('עירובין'),
            ],
            currentTabIndex: 0,
          ),
        );
        await tester.pumpAndSettle();
        expect(previewTitles('שולחן חדש'), ['ברכות', 'שבת', 'עירובין']);
      },
    );
  });
}

class _PreviewTab extends OpenedTab {
  _PreviewTab(super.title);

  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'title': title};
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

/// שדה שינוי השם שבאריח. שדה החיפוש שמעל הגריד מוצג תמיד (#2841), ולכן
/// RtlTextField לבדו אינו ייחודי.
Finder get _renameField => find.descendant(
  of: find.byType(GridView),
  matching: find.byType(RtlTextField),
);
