import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_build_policy.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_text_book_bloc.dart';

/// בחירת שורה בטקסט הראשי אינה בונה מחדש את טורי המפרשים ואת שלד צורת הדף;
/// רק הטקסט הראשי, שמסמן את השורה, נבנה מחדש.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookTitle = 'ספר בדיקה';

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      'page_shape_book_$bookTitle',
      'left|null||right|null||bottom|null||bottomRight|null',
    );
    await Settings.setValue<bool>('page_shape_global_visibility_left', false);
    await Settings.setValue<bool>('page_shape_global_visibility_right', false);
    await Settings.setValue<bool>('page_shape_global_visibility_bottom', false);
  });

  group('shouldRebuildIgnoringSelection', () {
    final base = _loadedState(TextBook(title: bookTitle));

    test('שינוי בחירה בלבד אינו בונה מחדש', () {
      expect(
        shouldRebuildIgnoringSelection(
          base,
          base.copyWith(selectedIndex: 1, selectedIndices: {1}),
        ),
        isFalse,
      );
      expect(
        shouldRebuildIgnoringSelection(
          base,
          base.copyWith(clearSelectedIndex: true, clearSelectedIndices: true),
        ),
        isFalse,
      );
    });

    test('כל שינוי אחר ממשיך לבנות מחדש כמו shouldRebuildReader', () {
      for (final next in [
        base.copyWith(fontSize: 30),
        base.copyWith(removeNikud: true),
        base.copyWith(content: const ['שורה אחרת', 'שורה ב']),
        base.copyWith(fontSize: 30, selectedIndex: 1, selectedIndices: {1}),
      ]) {
        expect(shouldRebuildIgnoringSelection(base, next), isTrue);
        expect(shouldRebuildReader(base, next), isTrue);
      }
      expect(
        shouldRebuildIgnoringSelection(
          TextBookLoading(base.book, 0, false, const []),
          base,
        ),
        isTrue,
      );
    });
  });

  testWidgets('טור מפרש אינו נבנה מחדש כשנבחרת שורה בטקסט הראשי', (
    tester,
  ) async {
    final bloc = StubTextBookBloc(_loadedState(TextBook(title: bookTitle)));
    await _pumpWithBlocs(
      tester,
      bloc,
      Row(
        children: [
          Expanded(
            child: SimpleTextViewer(
              key: const ValueKey('commentary'),
              content: const ['מפרש א', 'מפרש ב'],
              fontSize: 16,
              openBookCallback: (_) {},
              isMainText: false,
              bookTitle: 'מפרש',
            ),
          ),
          Expanded(
            child: SimpleTextViewer(
              key: const ValueKey('main'),
              content: const ['שורה א', 'שורה ב'],
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
            ),
          ),
        ],
      ),
    );

    SmartTextWidget firstText(String key) => tester.widget<SmartTextWidget>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(SmartTextWidget),
          )
          .first,
    );
    final commentaryBefore = firstText('commentary');
    final mainBefore = firstText('main');

    bloc.emit(
      (bloc.state as TextBookLoaded).copyWith(
        selectedIndex: 1,
        selectedIndices: {1},
      ),
    );
    await tester.pumpAndSettle();

    expect(firstText('commentary'), same(commentaryBefore));
    expect(firstText('main'), isNot(same(mainBefore)));

    bloc.emit((bloc.state as TextBookLoaded).copyWith(removeNikud: true));
    await tester.pumpAndSettle();
    expect(firstText('commentary'), isNot(same(commentaryBefore)));
  });

  testWidgets('שלד צורת הדף אינו נבנה מחדש כשנבחרת שורה', (tester) async {
    final book = TextBook(title: bookTitle);
    final bloc = StubTextBookBloc(_loadedState(book));
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final tabsBloc = _TestTabsBloc(
      const TabsState(tabs: [], currentTabIndex: 0).copyWith(tabs: [tab]),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await navigationBloc.close();
      await tabsBloc.close();
      tab.dispose();
    });

    await _pumpWithBlocs(
      tester,
      bloc,
      PageShapeScreen(openBookCallback: (_) {}, tab: tab),
      extraProviders: [
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
        BlocProvider<TabsBloc>.value(value: tabsBloc),
      ],
    );

    final viewerBefore = tester.widget(find.byType(SimpleTextViewer));
    final textBefore = tester.widget(find.byType(SmartTextWidget).first);

    bloc.emit(
      (bloc.state as TextBookLoaded).copyWith(
        selectedIndex: 1,
        selectedIndices: {1},
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget(find.byType(SimpleTextViewer)), same(viewerBefore));
    expect(
      tester.widget(find.byType(SmartTextWidget).first),
      isNot(same(textBefore)),
    );
  });
}

Future<void> _pumpWithBlocs(
  WidgetTester tester,
  StubTextBookBloc bloc,
  Widget child, {
  List<BlocProvider> extraProviders = const [],
}) async {
  final notesBloc = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final settingsBloc = StubSettingsBloc(SettingsState.initial());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
    await notesBloc.close();
    await settingsBloc.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ...extraProviders,
          ],
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TextBookLoaded _loadedState(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: const ['שורה א', 'שורה ב'],
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
  visibleIndices: const [0, 1],
  selectedIndex: 0,
  selectedIndices: const {0},
  pinLeftPane: false,
  searchText: '',
);

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
