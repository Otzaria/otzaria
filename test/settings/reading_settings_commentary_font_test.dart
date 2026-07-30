// טסטים ייעודיים להסתרת סליידר "גודל גופן מפרשים" בהגדרות תצוגת הספרים.
//
// רקע: בתצוגה רגילה גודל גופן המפרשים נשלט בהגדרה הכללית
// (commentatorsFontSize). בצורת הדף קיימת הגדרה ייעודית נפרדת, ולכן הסליידר
// הכללי אינו רלוונטי שם ומוסתר. הלוגיקה:
//   * TextSettingsTab(hideCommentaryFontSize: true) → הסליידר מוסתר, ה-dropdown
//     "גופן מפרשים" נשאר.
//   * ReadingSettingsPanel → מזהה אם הטאב הפעיל בצורת הדף ומעביר את הדגל בהתאם.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/panels/reading_settings_panel.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> setWideSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  group('TextSettingsTab — סליידר גודל גופן מפרשים', () {
    Widget buildTab({required bool hide}) {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<SettingsBloc>.value(
            value: _TestSettingsBloc(SettingsState.initial()),
            child: TextSettingsTab(
              isDialog: true,
              hideCommentaryFontSize: hide,
            ),
          ),
        ),
      );
    }

    testWidgets('כברירת מחדל מציג את הסליידר ואת גופן המפרשים', (tester) async {
      await setWideSurface(tester);

      await tester.pumpWidget(buildTab(hide: false));
      await tester.pump();

      expect(find.text('גודל גופן מפרשים'), findsOneWidget);
      expect(find.text('גופן מפרשים'), findsOneWidget);
      expect(
        find.byIcon(OtzariaIcons.alef_near_alef_24_regular),
        findsNWidgets(2),
      );
      expect(
        find.byIcon(OtzariaIcons.beit_near_alef_24_regular),
        findsNWidgets(2),
      );
      expect(
        find.byIcon(OtzariaIcons.alef_with_score_24_regular),
        findsOneWidget,
      );
      expect(
        find.byIcon(OtzariaIcons.alef_with_punctuation_24_regular),
        findsOneWidget,
      );

      await tester.tap(find.byType(AppDropdownField<String>).first);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(OtzariaIcons.alef_behind_alef_24_regular),
        findsWidgets,
      );
    });

    testWidgets(
      'hideCommentaryFontSize=true מסתיר את הסליידר ומשאיר את הגופן',
      (tester) async {
        await setWideSurface(tester);

        await tester.pumpWidget(buildTab(hide: true));
        await tester.pump();

        expect(find.text('גודל גופן מפרשים'), findsNothing);
        // ה-dropdown של גופן המפרשים נשאר — מוסתר רק הסליידר.
        expect(find.text('גופן מפרשים'), findsOneWidget);
        // גודל גופן הספר אינו מושפע.
        expect(find.text('גודל גופן הספר'), findsOneWidget);
      },
    );
  });

  group('ReadingSettingsPanel — זיהוי מצב צורת הדף', () {
    Widget buildBody({required bool pageShape}) {
      final textBloc = _TestTextBookBloc(_loaded(showPageShapeView: pageShape));
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
        blocOverride: textBloc,
      );
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );

      return MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(
                value: _TestSettingsBloc(SettingsState.initial()),
              ),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
            ],
            child: const ReadingSettingsPanel(),
          ),
        ),
      );
    }

    testWidgets('טאב בתצוגה רגילה — הסליידר מוצג', (tester) async {
      await setWideSurface(tester);

      await tester.pumpWidget(buildBody(pageShape: false));
      await tester.pump();

      expect(find.text('גודל גופן מפרשים'), findsOneWidget);
    });

    testWidgets('טאב בצורת הדף — הסליידר מוסתר', (tester) async {
      await setWideSurface(tester);

      await tester.pumpWidget(buildBody(pageShape: true));
      await tester.pump();

      expect(find.text('גודל גופן מפרשים'), findsNothing);
      // גופן המפרשים עדיין רלוונטי בצורת הדף (מפרשים עליונים).
      expect(find.text('גופן מפרשים'), findsOneWidget);
    });
  });
}

// ===== Helpers =====

TextBookLoaded _loaded({required bool showPageShapeView}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א', 'שורה ב'],
  fontSize: 18,
  showSplitView: true,
  showPageShapeView: showPageShapeView,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: null,
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
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
