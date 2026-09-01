import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import '../helpers/memory_settings_cache.dart';

/// חלונית מדומה: סרגל בסרגל העליון + שתי לשוניות שמפרסמות פעולות חיפוש.
class _Host extends StatefulWidget {
  final bool isOpen;
  final bool showPin;
  final bool isPinned;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowUp;

  const _Host({
    this.isOpen = true,
    this.showPin = false,
    this.isPinned = false,
    this.onArrowDown,
    this.onArrowUp,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  final NavPanelSearchHost host = NavPanelSearchHost();
  final navController = TextEditingController();
  final searchController = TextEditingController();
  final navFocus = FocusNode();
  final searchFocus = FocusNode();
  late final TabController tabs;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
    tabs.addListener(() => host.activeTab = tabs.index);
  }

  @override
  void dispose() {
    tabs.dispose();
    host.dispose();
    navController.dispose();
    searchController.dispose();
    navFocus.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // "הסרגל העליון": הסרגל ואחריו אייקון הפתיחה.
        SizedBox(
          height: 56,
          child: Row(
            children: [
              NavPanelSearchBar(
                host: host,
                isOpen: widget.isOpen,
                paneWidth: 300,
                isPinned: widget.isPinned,
                onTogglePin: widget.showPin ? () {} : null,
              ),
              // אייקון הפתיחה/סגירה — מחוץ לרוחב הסרגל.
              const Icon(Icons.menu),
            ],
          ),
        ),
        Expanded(
          child: NavPanelSearchScope(
            host: host,
            child: Column(
              children: [
                TabBar(
                  controller: tabs,
                  tabs: const [
                    Tab(text: 'ניווט'),
                    Tab(text: 'חיפוש'),
                    Tab(text: 'דפים'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: tabs,
                    children: [
                      NavPanelSearchSlot(
                        index: 0,
                        child: NavPanelSearchPublisher(
                          delegate: NavPanelSearchDelegate(
                            controller: navController,
                            focusNode: navFocus,
                            hintText: 'איתור כותרת...',
                            onArrowDown: widget.onArrowDown,
                            onArrowUp: widget.onArrowUp,
                          ),
                          // כמו במסכי הייצור: שדה מקומי רק כשהלשונית אינה
                          // מורמת, והבדיקה רצה על context שמתחת ל-Scope.
                          child: Builder(
                            builder: (context) => Column(
                              children: [
                                if (!NavPanelSearch.isHoisted(context))
                                  NavPanelLocalSearchField(
                                    delegate: NavPanelSearchDelegate(
                                      controller: navController,
                                      hintText: 'איתור כותרת...',
                                    ),
                                  ),
                                Expanded(
                                  child: NavTreeFocusGroup(
                                    child: ListView(
                                      children: [
                                        for (var i = 0; i < 3; i++)
                                          NavTreeGroupCard(
                                            isGroupStart: i == 0,
                                            isGroupEnd: i == 2,
                                            child: NavTreeTile.category(
                                              title: 'שורה $i',
                                              level: 0,
                                              isSelected: i == 1,
                                              onTap: () {},
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      NavPanelSearchSlot(
                        index: 1,
                        child: NavPanelSearchPublisher(
                          delegate: NavPanelSearchDelegate(
                            controller: searchController,
                            focusNode: searchFocus,
                            hintText: 'חיפוש בספר...',
                          ),
                          child: const Text('תוכן חיפוש'),
                        ),
                      ),
                      // לשונית בלי פעולת חיפוש.
                      const NavPanelSearchSlot(
                        index: 2,
                        child: Text('תמונות עמודים'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SizedBox(width: 1200, height: 700, child: child),
    ),
  ),
);

/// חלונית מדומה מינימלית עם פעולה שמחליפה אייקון — בלי לשנות את אורך
/// רשימת הפעולות. משמשת לרגרסיה של רענון הסרגל המורם.
class _TogglingActionHost extends StatefulWidget {
  const _TogglingActionHost();

  @override
  State<_TogglingActionHost> createState() => _TogglingActionHostState();
}

class _TogglingActionHostState extends State<_TogglingActionHost> {
  final host = NavPanelSearchHost();
  final controller = TextEditingController();
  final focus = FocusNode();
  bool on = false;

  @override
  void dispose() {
    host.dispose();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: NavPanelSearchBar(
            host: host,
            isOpen: true,
            paneWidth: 300,
            isPinned: false,
          ),
        ),
        TextButton(
          onPressed: () => setState(() => on = !on),
          child: const Text('החלף'),
        ),
        Expanded(
          child: NavPanelSearchScope(
            host: host,
            child: NavPanelSearchSlot(
              index: 0,
              child: NavPanelSearchPublisher(
                delegate: NavPanelSearchDelegate(
                  controller: controller,
                  focusNode: focus,
                  hintText: 'חיפוש בספר...',
                  actionsKey: on,
                  trailingActions: [
                    Icon(
                      on
                          ? FluentIcons.text_whole_word_20_filled
                          : FluentIcons.text_whole_word_20_regular,
                    ),
                  ],
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // NavPanelPinButton קורא את הגדרת הנעיצה הגלובלית.
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('הסרגל מציג את פעולת הלשונית הפעילה ומתחלף במעבר לשונית', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    // לשונית 0 — שדה אחד בלבד, בסרגל שמעל החלונית.
    expect(find.byType(OtzariaSearchField), findsOneWidget);
    expect(find.text('איתור כותרת...'), findsOneWidget);

    await tester.tap(find.text('חיפוש'));
    await tester.pumpAndSettle();

    // הפעולה התחלפה לזו של הלשונית הנבחרת — והסרגל נשאר יחיד.
    expect(find.byType(OtzariaSearchField), findsOneWidget);
    expect(find.text('חיפוש בספר...'), findsOneWidget);
    expect(find.text('איתור כותרת...'), findsNothing);
  });

  // רגרסיה: פעולה שהחליפה אייקון בלי לשנות את אורך הרשימה נבלעה בהשוואת
  // המטרה, והסרגל המורם נשאר מצויר עם האייקון הישן. actionsKey הוא מה
  // שמבחין ביניהן.
  testWidgets('פעולה שהחליפה אייקון מתעדכנת בסרגל המורם', (tester) async {
    await tester.pumpWidget(wrap(const _TogglingActionHost()));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(FluentIcons.text_whole_word_20_regular),
      findsOneWidget,
    );

    await tester.tap(find.text('החלף'));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.text_whole_word_20_filled), findsOneWidget);
    expect(find.byIcon(FluentIcons.text_whole_word_20_regular), findsNothing);
  });

  testWidgets('חלונית סגורה — הסרגל מכווץ לרוחב 0', (tester) async {
    await tester.pumpWidget(wrap(const _Host(isOpen: false)));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(NavPanelSearchBar)).width, 0);
  });

  testWidgets('חלונית פתוחה — הסרגל ברוחב החלונית (פחות ריווח הסרגל העליון)', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    // הסרגל העליון מרווח את פריטיו מהדופן, ולכן הרוחב מפצה עליו כדי
    // שהשפה הפנימית תתיישר לשפת החלונית.
    expect(
      tester.getSize(find.byType(NavPanelSearchBar)).width,
      300 - AppTopBar.horizontalPadding(false),
    );
  });

  testWidgets('מחוץ לחלונית ניווט אין הגבהה — הלשונית מציירת שדה מקומי', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            final delegate = NavPanelSearchDelegate(
              controller: controller,
              hintText: 'איתור כותרת...',
            );
            return Column(
              children: [
                if (!NavPanelSearch.isHoisted(context))
                  NavPanelLocalSearchField(delegate: delegate),
                const Text('תוכן'),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OtzariaSearchField), findsOneWidget);
  });

  testWidgets('לשונית מורמת אינה מציירת שדה מקומי — שדה יחיד בסרגל', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    // רק השדה המורם שבסרגל — בלי כפילות בתוך החלונית (רגרסיה: בדיקת
    // isHoisted על context שמעל ה-Scope ציירה את השדה פעמיים).
    expect(find.byType(OtzariaSearchField), findsOneWidget);
    expect(find.byType(NavPanelLocalSearchField), findsNothing);
  });

  testWidgets('לשונית בלי חיפוש — הסרגל נשאר מוצג ומושבת', (tester) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    final fieldBefore = tester.widget<OtzariaSearchField>(
      find.byType(OtzariaSearchField),
    );
    expect(fieldBefore.enabled, isTrue);

    await tester.tap(find.text('דפים'));
    await tester.pumpAndSettle();

    // הסרגל לא נעלם ולא התכווץ — רק התוכן שבתוכו הושבת.
    expect(
      tester.getSize(find.byType(NavPanelSearchBar)).width,
      300 - AppTopBar.horizontalPadding(false),
    );
    final field = tester.widget<OtzariaSearchField>(
      find.byType(OtzariaSearchField),
    );
    expect(field.enabled, isFalse);
  });

  testWidgets('מעבר לשונית אינו בונה מחדש את השדה — אותו element נשמר', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    final elementBefore = tester.element(find.byType(OtzariaSearchField));

    await tester.tap(find.text('חיפוש'));
    await tester.pumpAndSettle();

    expect(
      tester.element(find.byType(OtzariaSearchField)),
      same(elementBefore),
      reason: 'הסרגל נשאר מורכב; רק התוכן הפנימי שלו מתחלף',
    );
  });

  testWidgets('מעבר בין לשוניות מאפס פוקוס ובוחר את השאילתה החדשה', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();
    final state = tester.state<_HostState>(find.byType(_Host));
    state.navController.text = 'ניווט';
    state.searchController.text = 'חיפוש';

    state.navFocus.requestFocus();
    await tester.pump();
    expect(state.navFocus.hasFocus, isTrue);

    state.tabs.index = 1;
    await tester.pumpAndSettle();
    state.searchController.selection = const TextSelection.collapsed(offset: 5);
    state.searchFocus.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(state.searchFocus.hasFocus, isTrue);
    expect(
      state.searchController.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });

  testWidgets('מעבר דרך לשונית בלי חיפוש לא משאיר מצב פוקוס ישן', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();
    final state = tester.state<_HostState>(find.byType(_Host));
    state.navController.text = 'ניווט';
    state.searchController.text = 'חיפוש';
    state.navFocus.requestFocus();
    await tester.pump();

    state.tabs.index = 2;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OtzariaSearchField>(find.byType(OtzariaSearchField))
          .enabled,
      isFalse,
    );

    state.tabs.index = 1;
    await tester.pumpAndSettle();
    state.searchController.selection = const TextSelection.collapsed(offset: 5);
    state.searchFocus.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(
      state.searchController.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });

  testWidgets('כפתור הנעיצה יושב בסרגל, בתוך רוחב החלונית', (tester) async {
    await tester.pumpWidget(
      wrap(const _Host(showPin: true, isPinned: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavPanelPinButton), findsOneWidget);
    expect(find.byIcon(FluentIcons.pin_24_filled), findsOneWidget);

    final bar = tester.getRect(find.byType(NavPanelSearchBar));
    final pin = tester.getRect(find.byType(NavPanelPinButton));
    expect(bar.contains(pin.center), isTrue);

    // אייקון הפתיחה נשאר מחוץ לסרגל.
    final toggle = tester.getRect(find.byIcon(Icons.menu));
    expect(bar.contains(toggle.center), isFalse);
  });

  testWidgets('onTogglePin=null — אין כפתור נעיצה', (tester) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    expect(find.byType(NavPanelPinButton), findsNothing);
  });

  testWidgets('בלי נעיצה: השדה מתיישר לשוליים של תוכן החלונית משני הצדדים', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(NavPanelSearchBar));
    final field = tester.getRect(find.byType(OtzariaSearchField));
    expect(bar.right - field.right, greaterThan(0));
    expect(field.left - bar.left, greaterThan(0));
  });

  testWidgets('עם נעיצה: רווח בין השדה לכפתור, והכפתור גולש אל השוליים', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _Host(showPin: true)));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(NavPanelSearchBar));
    final field = tester.getRect(find.byType(OtzariaSearchField));
    final pin = tester.getRect(find.byType(NavPanelPinButton));

    // הכפתור אינו נצמד לשדה...
    expect(field.left - pin.right, greaterThan(0));
    // ...וגולש אל השוליים הפנימיים, כדי לא להתרחק מאייקון הסגירה.
    expect(pin.left, bar.left);
    // השדה מוותר על השוליים החיצוניים לטובת הרווח הזה.
    expect(bar.right, field.right);
  });

  testWidgets('חץ למטה מסרגל החיפוש מעביר פוקוס לשורה המסומנת', (tester) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    // הפוקוס בשדה החיפוש שבסרגל.
    final field = tester.widget<OtzariaSearchField>(
      find.byType(OtzariaSearchField),
    );
    field.controller.text = '';
    await tester.tap(find.byType(OtzariaSearchField));
    await tester.pumpAndSettle();
    expect(
      find.byType(EditableText).evaluate().isNotEmpty &&
          tester.binding.focusManager.primaryFocus?.context
                  ?.findAncestorWidgetOfExactType<OtzariaSearchField>() !=
              null,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // הפוקוס עבר לשורה המסומנת (שורה 1) ולא לראשונה או ללשוניות.
    String? focusedRowTitle() => tester
        .binding
        .focusManager
        .primaryFocus
        ?.context
        ?.findAncestorWidgetOfExactType<NavTreeTile>()
        ?.title;

    expect(focusedRowTitle(), 'שורה 1');

    // ומכאן החצים מנווטים בין השורות.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedRowTitle(), 'שורה 2');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusedRowTitle(), 'שורה 1');
  });

  testWidgets('פעולה עם onArrowDown/Up — דפדוף בתוצאות בלי לעזוב את השדה', (
    tester,
  ) async {
    var downs = 0;
    var ups = 0;
    await tester.pumpWidget(
      wrap(_Host(onArrowDown: () => downs++, onArrowUp: () => ups++)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(OtzariaSearchField));
    await tester.pumpAndSettle();
    final beforeFocus = tester.binding.focusManager.primaryFocus;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(downs, 2);
    expect(ups, 1);
    // הפוקוס נשאר בשדה — אפשר להמשיך להקליד ולעדכן את השאילתה תוך כדי דפדוף.
    expect(tester.binding.focusManager.primaryFocus, beforeFocus);
    await tester.enterText(find.byType(OtzariaSearchField), 'אבג');
    expect(find.text('אבג'), findsOneWidget);
  });

  testWidgets('חץ ימין/שמאל נשארים בטקסט של שדה החיפוש', (tester) async {
    await tester.pumpWidget(wrap(const _Host()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(OtzariaSearchField));
    await tester.enterText(find.byType(OtzariaSearchField), 'אבג');
    await tester.pumpAndSettle();
    final beforeFocus = tester.binding.focusManager.primaryFocus;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // הפוקוס לא יצא מהשדה, והטקסט לא נפגע.
    expect(tester.binding.focusManager.primaryFocus, beforeFocus);
    expect(find.text('אבג'), findsOneWidget);
  });
}
