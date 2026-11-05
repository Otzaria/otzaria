import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

import '../../../test_helpers/memory_cache_provider.dart';

/// כשחלוניות הצד פתוחות, הדף מקבל רק חלק מרוחב החלון; טורי המפרשים
/// חייבים להיכנס ברוחב הזה ולא לגלוש (issue #1844).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookTitle = 'ספר בדיקה';
  const windowWidth = 1366.0;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      'page_shape_book_$bookTitle',
      'left|null||right|null||bottom|null||bottomRight|null',
    );
    await Settings.setValue<bool>('page_shape_global_visibility_left', true);
    await Settings.setValue<bool>('page_shape_global_visibility_right', true);
    await Settings.setValue<bool>('page_shape_global_visibility_bottom', false);
    // רוחב שנגרר כשהחלון היה פנוי — בתוך מגבלת 40% מרוחב החלון.
    await Settings.setValue<double>('page_shape_left_width', 300);
    await Settings.setValue<double>('page_shape_right_width', 300);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required double sidePanesWidth,
    double textMaxWidth = 0,
    double width = windowWidth,
  }) async {
    await Settings.setValue<bool>(
      'page_shape_apply_text_max_width',
      textMaxWidth != 0,
    );
    tester.view.physicalSize = Size(width, 736);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final book = TextBook(title: bookTitle);
    final textBookBloc = _TestTextBookBloc(_loadedState(book));
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(textMaxWidth: textMaxWidth),
    );
    final tab = TextBookTab(book: book, index: 0, blocOverride: textBookBloc);
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final tabsBloc = _TestTabsBloc(
      const TabsState(tabs: [], currentTabIndex: 0).copyWith(tabs: [tab]),
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await textBookBloc.close();
      await personalNotesBloc.close();
      await settingsBloc.close();
      await navigationBloc.close();
      await tabsBloc.close();
      tab.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: sidePanesWidth),
              Expanded(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<TextBookBloc>.value(value: textBookBloc),
                    BlocProvider<PersonalNotesBloc>.value(
                      value: personalNotesBloc,
                    ),
                    BlocProvider<SettingsBloc>.value(value: settingsBloc),
                    BlocProvider<NavigationBloc>.value(value: navigationBloc),
                    BlocProvider<TabsBloc>.value(value: tabsBloc),
                  ],
                  child: PageShapeScreen(openBookCallback: (_) {}, tab: tab),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectColumnsFit(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    expect(find.text('בחר מפרש'), findsNWidgets(2));
    final mainText = tester.getSize(find.byType(SimpleTextViewer));
    expect(mainText.width, greaterThan(0));
  }

  testWidgets('טורי הצד נכנסים ברוחב הדף כשחלוניות הצד פתוחות', (
    tester,
  ) async {
    // ניווט + מפרשים + סרגל שמחוץ לאזור הדף.
    await pumpScreen(tester, sidePanesWidth: 815);
    expectColumnsFit(tester);
  });

  testWidgets('טורי הצד נכנסים ברוחב הדף כשהגבלת רוחב הטקסט מצרה אותו', (
    tester,
  ) async {
    await pumpScreen(tester, sidePanesWidth: 0, textMaxWidth: 600);
    expectColumnsFit(tester);
  });

  testWidgets(
    'בחלון צר הטקסט הראשי שומר על חלקו גם מול רוחבים ישנים בפיקסלים',
    (
      tester,
    ) async {
      // נגרר בחלון רחב בגרסה קודמת (issue #2782).
      await Settings.setValue<double>('page_shape_left_width', 500);
      await Settings.setValue<double>('page_shape_right_width', 500);
      await pumpScreen(tester, sidePanesWidth: 0, width: 820);
      expectColumnsFit(tester);
      final mainWidth = tester.getSize(find.byType(SimpleTextViewer)).width;
      expect(mainWidth, greaterThanOrEqualTo(0.3 * (820 - 64)));
    },
  );

  testWidgets('היחס בין הטורים לטקסט הראשי נשמר כשהחלון מוקטן', (
    tester,
  ) async {
    // פיקסלים מגרסה קודמת: רבע מחלון של 1600.
    await Settings.setValue<double>('page_shape_left_width', 400);
    await Settings.setValue<double>('page_shape_right_width', 400);
    await pumpScreen(tester, sidePanesWidth: 0, width: 1600);
    final wideRatio =
        tester.getSize(find.byType(SimpleTextViewer)).width / 1600;

    tester.view.physicalSize = const Size(800, 736);
    await tester.pumpAndSettle();
    expectColumnsFit(tester);
    final narrowRatio =
        tester.getSize(find.byType(SimpleTextViewer)).width / 800;
    expect(narrowRatio, closeTo(wideRatio, 0.05));
  });

  testWidgets('גרירת טור כששני הטורים מוקטנים יחד מזיזה רק אותו', (
    tester,
  ) async {
    await Settings.setValue<double>('page_shape_left_width', 0.4);
    await Settings.setValue<double>('page_shape_right_width', 0.4);
    await pumpScreen(tester, sidePanesWidth: 0, width: 1064);
    final before = tester.getSize(find.byType(SimpleTextViewer)).width;

    final handle = find.byType(ResizableDragHandle).first;
    // הידית רחבה מהעמודה בת 8 הפיקסלים שמכילה אותה; לוחצים בתוך העמודה.
    final handleRect = tester.getRect(handle);
    final gesture = await tester.startGesture(
      Offset(handleRect.left + 4, handleRect.center.dy),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final after = tester.getSize(find.byType(SimpleTextViewer)).width;
    expect(after - before, greaterThan(25));
  });
  for (final hiddenColumn in ['left', 'right']) {
    testWidgets('גרירה משמרת יחס טור $hiddenColumn מוסתר גם בהצגה מחדש', (
      tester,
    ) async {
      final visibleColumn = hiddenColumn == 'left' ? 'right' : 'left';
      await Settings.setValue<double>('page_shape_${hiddenColumn}_width', 0.17);
      await Settings.setValue<double>(
        'page_shape_${visibleColumn}_width',
        0.25,
      );
      await Settings.setValue<bool>(
        'page_shape_global_visibility_$hiddenColumn',
        false,
      );
      await pumpScreen(tester, sidePanesWidth: 700, width: 1000);
      expect(find.text('בחר מפרש'), findsOneWidget);

      final handle = find.byType(ResizableDragHandle).first;
      final rect = tester.getRect(handle);
      final gesture = await tester.startGesture(
        Offset(rect.left + 4, rect.center.dy),
      );
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(Offset(hiddenColumn == 'right' ? -10 : 10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        Settings.getValue<double>('page_shape_${hiddenColumn}_width'),
        0.17,
      );
      expect(
        Settings.getValue<double>('page_shape_${visibleColumn}_width'),
        isNot(0.25),
      );

      await Settings.setValue<bool>(
        'page_shape_global_visibility_$hiddenColumn',
        true,
      );
      tester.view.physicalSize = const Size(1700, 736);
      await tester.pumpAndSettle();
      expectColumnsFit(tester);
      final pane = find
          .ancestor(
            of: find.text('בחר מפרש').at(hiddenColumn == 'left' ? 0 : 1),
            matching: find.byWidgetPredicate(
              (widget) => widget is SizedBox && widget.child is Container,
            ),
          )
          .first;
      expect(tester.getSize(pane).width, closeTo(0.17 * (1000 - 64), 0.001));
    });
  }

  group('רוחב חלונית הצד לפי המסך עצמו, לא לפי החלון (MIG-21)', () {
    // חלון 1600, המסך מקבל 800 (כמו בתצוגה מפוצלת).
    double paneWidth(WidgetTester tester) => tester
        .widget<AdaptiveSidePane>(find.byType(AdaptiveSidePane))
        .paneWidth;

    testWidgets('בלי רוחב שמור: ברירת המחדל 22% מרוחב המסך', (tester) async {
      await pumpScreen(tester, sidePanesWidth: 800, width: 1600);
      expect(paneWidth(tester), closeTo(0.22 * 800, 0.001));
    });

    testWidgets('רוחב שמור גדול מהתקרה נחתך בתצוגה ל-35% מהמסך, ונשמר', (
      tester,
    ) async {
      await Settings.setValue<double>('page_shape_left_sidebar_width', 500);
      await pumpScreen(tester, sidePanesWidth: 800, width: 1600);
      // אחרת הגרירה הראשונה הייתה מכווצת את החלונית בקפיצה ל-280.
      expect(paneWidth(tester), closeTo(0.35 * 800, 0.001));
      expect(Settings.getValue<double>('page_shape_left_sidebar_width'), 500);
    });
  });
}

TextBookLoaded _loadedState(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: const ['שורה א'],
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  removePunctuation: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
  searchMode: SearchMode.exact,
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState) {
    on<NavigationEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
