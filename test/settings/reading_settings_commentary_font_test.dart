// טסטים ייעודיים לסליידר "גודל גופן מפרשים" בהגדרות תצוגת הספרים.
//
// רקע: בתצוגה רגילה גודל גופן המפרשים נשלט בהגדרה הכללית
// (commentatorsFontSize). בצורת הדף קיימת הגדרה ייעודית נפרדת, ולכן שם מוצג
// הסליידר של צורת הדף במקום הכללי (#3244). הלוגיקה:
//   * TextSettingsTab(pageShapeCommentaryFontSize: true) → הסליידר הכללי מוחלף
//     ב"גודל גופן מפרשים (צורת הדף)", ה-dropdown "גופן מפרשים" נשאר.
//   * ReadingSettingsPanel → מזהה אם הטאב הפעיל בצורת הדף ומעביר את הדגל בהתאם.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
import 'package:otzaria/text_book/view/page_shape/page_shape_commentary_font_slider.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';

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
              pageShapeCommentaryFontSize: hide,
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
      // כל אחת מארבע ההגדרות מקבלת אייקון משלה: גודל/גופן × טקסט/מפרשים.
      expect(
        find.byIcon(OtzariaIcons.alef_near_alef_24_filled),
        findsOneWidget,
      );
      expect(find.byIcon(OtzariaIcons.alef_alef_24_filled), findsOneWidget);
      expect(
        find.byIcon(OtzariaIcons.beit_near_alef_24_filled),
        findsOneWidget,
      );
      expect(
        find.byIcon(OtzariaIcons.beit_behind_alef_24_filled),
        findsOneWidget,
      );
      expect(
        find.byIcon(OtzariaIcons.alef_niqqud_24_filled),
        findsOneWidget,
      );
      expect(
        find.byIcon(OtzariaIcons.alef_punctuation_24_filled),
        findsOneWidget,
      );

      await tester.tap(find.byType(AppDropdownField<String>).first);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(OtzariaIcons.alef_behind_alef_24_filled),
        findsWidgets,
      );
    });

    testWidgets(
      'pageShapeCommentaryFontSize=true מציג את סליידר צורת הדף ומשאיר את הגופן',
      (tester) async {
        await setWideSurface(tester);

        await tester.pumpWidget(buildTab(hide: true));
        await tester.pump();

        expect(find.text('גודל גופן מפרשים'), findsNothing);
        expect(find.text(_pageShapeLabel), findsOneWidget);
        expect(find.byType(PageShapeCommentaryFontSizeSlider), findsOneWidget);
        // ה-dropdown של גופן המפרשים נשאר — מוסתר רק הסליידר.
        expect(find.text('גופן מפרשים'), findsOneWidget);
        // גודל גופן הספר אינו מושפע.
        expect(find.text('גודל גופן הספר'), findsOneWidget);
      },
    );
  });

  group('סליידר צורת הדף (#3244)', () {
    testWidgets('שמירה באחד מעדכנת את השני ונכתבת להגדרה של צורת הדף', (
      tester,
    ) async {
      await PageShapeSettingsManager.saveCommentaryFontSize(16);
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PageShapeCommentaryFontSizeSlider(
                  title: 'כללי',
                  onSaved: () => saved++,
                ),
                const PageShapeCommentaryFontSizeSlider(title: 'צורת הדף'),
              ],
            ),
          ),
        ),
      );
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(2));
      final general = tester.widget<Slider>(sliders.first);
      expect(general.min, 10);
      expect(general.max, 30);
      general.onChangeEnd!(20);
      await tester.pump();
      await tester.pump();

      expect(PageShapeSettingsManager.getCommentaryFontSize(), 20);
      expect(saved, 1);
      expect(tester.widget<Slider>(sliders.last).value, 20);
      expect(find.text('20'), findsNWidgets(2));
    });
  });

  group('ReadingSettingsPanel — זיהוי מצב צורת הדף', () {
    Widget buildPanel(TabsBloc tabsBloc) {
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

    Widget buildBody({required bool pageShape, _TestTextBookBloc? textBloc}) {
      textBloc ??= _TestTextBookBloc(_loaded(showPageShapeView: pageShape));
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
        blocOverride: textBloc,
      );
      return buildPanel(
        _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0)),
      );
    }

    testWidgets('טאב בתצוגה רגילה — הסליידר מוצג', (tester) async {
      await setWideSurface(tester);

      await tester.pumpWidget(buildBody(pageShape: false));
      await tester.pump();

      expect(find.text('גודל גופן מפרשים'), findsOneWidget);
    });

    testWidgets('טאב בצורת הדף — הסליידר של צורת הדף במקום הכללי', (
      tester,
    ) async {
      await setWideSurface(tester);

      await tester.pumpWidget(buildBody(pageShape: true));
      await tester.pump();

      expect(find.text('גודל גופן מפרשים'), findsNothing);
      expect(find.text(_pageShapeLabel), findsOneWidget);
      // גופן המפרשים עדיין רלוונטי בצורת הדף (מפרשים עליונים).
      expect(find.text('גופן מפרשים'), findsOneWidget);
    });

    // הפאנל נשאר חי גם כשהוא סגור, וגלילה בקורא משדרת מצב בכל שורה.
    testWidgets('גלילה בקורא אינה בונה מחדש את ההגדרות', (tester) async {
      await setWideSurface(tester);
      final textBloc = _TestTextBookBloc(_loaded(showPageShapeView: false));
      await tester.pumpWidget(buildBody(pageShape: false, textBloc: textBloc));
      await tester.pump();
      final before = tester.widget(find.byType(TextSettingsTab));

      for (var line = 1; line <= 5; line++) {
        textBloc.push(
          (textBloc.state as TextBookLoaded).copyWith(visibleIndices: [line]),
        );
        await tester.pump();
      }

      expect(
        identical(tester.widget(find.byType(TextSettingsTab)), before),
        isTrue,
      );
    });

    testWidgets('מעבר לצורת הדף מחליף את הסליידר', (tester) async {
      await setWideSurface(tester);
      final textBloc = _TestTextBookBloc(_loaded(showPageShapeView: false));
      await tester.pumpWidget(buildBody(pageShape: false, textBloc: textBloc));
      await tester.pump();
      expect(find.text('גודל גופן מפרשים'), findsOneWidget);

      textBloc.push(_loaded(showPageShapeView: true));
      await tester.pumpAndSettle();
      expect(find.text('גודל גופן מפרשים'), findsNothing);
      expect(find.text(_pageShapeLabel), findsOneWidget);

      textBloc.push(_loaded(showPageShapeView: false));
      await tester.pumpAndSettle();
      expect(find.text('גודל גופן מפרשים'), findsOneWidget);
    });

    // הפאנל נשאר חי גם כשהוא סגור; הסליידר תלוי רק במצב הספר הפעיל.
    testWidgets('מעבר טאב אינו בונה מחדש את ההגדרות, והסליידר לפי הספר הפעיל', (
      tester,
    ) async {
      await setWideSurface(tester);
      TextBookTab tabOf(String title, {required bool pageShape}) => TextBookTab(
        book: TextBook(title: title),
        index: 0,
        blocOverride: _TestTextBookBloc(
          _loaded(showPageShapeView: pageShape),
        ),
      );
      final tabs = [
        tabOf('ספר א', pageShape: false),
        tabOf('ספר ב', pageShape: false),
        tabOf('ספר ג', pageShape: true),
      ];
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
      await tester.pumpWidget(buildPanel(tabsBloc));
      await tester.pump();
      final before = tester.widget(find.byType(TextSettingsTab));

      tabsBloc.push(TabsState(tabs: tabs, currentTabIndex: 1));
      await tester.pumpAndSettle();
      expect(
        identical(tester.widget(find.byType(TextSettingsTab)), before),
        isTrue,
      );

      tabsBloc.push(TabsState(tabs: tabs, currentTabIndex: 2));
      await tester.pumpAndSettle();
      expect(find.text('גודל גופן מפרשים'), findsNothing);

      tabsBloc.push(TabsState(tabs: tabs, currentTabIndex: 0));
      await tester.pumpAndSettle();
      expect(find.text('גודל גופן מפרשים'), findsOneWidget);
    });
  });
}

const _pageShapeLabel = 'גודל גופן מפרשים (צורת הדף)';

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

  void push(TextBookState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  void push(TabsState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
