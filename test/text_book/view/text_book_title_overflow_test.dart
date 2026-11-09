import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// כותרת ארוכה כמו שנוצרת מספר Word אישי: פסקת גוף שלמה שסומנה ב-Word
/// בסגנון "heading 3", ולכן הפכה לערך בתוכן העניינים.
const _longLocation =
    'בגמ\' "ומילתא אגב אורחיה קמ"ל דמועד לאדם הוה מועד לבהמה, '
    'ומועד לבהמה לא הוה מועד לאדם", וצריך להבין את החילוק שבין הדברים';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusRepository focusRepository;
  late _FakeShamorZachorDataProvider shamorZachorDataProvider;
  late _FakeShamorZachorProgressProvider shamorZachorProgressProvider;
  late _TestBookmarkBloc bookmarkBloc;
  late PersonalNotesBloc personalNotesBloc;
  late TourCubit tourCubit;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    focusRepository = FocusRepository()..resetForTesting();
    shamorZachorDataProvider = _FakeShamorZachorDataProvider();
    shamorZachorProgressProvider = _FakeShamorZachorProgressProvider();
    bookmarkBloc = _TestBookmarkBloc();
    personalNotesBloc = PersonalNotesBloc();
    tourCubit = TourCubit();
  });

  tearDown(() async {
    await bookmarkBloc.close();
    await personalNotesBloc.close();
    await tourCubit.close();
    focusRepository.resetForTesting();
  });

  /// מרנדר את מסך הספר עם [currentTitle] ומחזיר את ה-Finder של אזור הכותרת.
  Future<void> pumpWithTitle(
    WidgetTester tester, {
    required String bookTitle,
    required String currentTitle,
    String? author,
    bool isInCombinedView = false,
    Size size = const Size(1400, 900),
  }) async {
    final book = TextBook(title: bookTitle, author: author);
    final bloc = _TestTextBookBloc(_loadedState(book, currentTitle));
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await tabsBloc.close();
      await settingsBloc.close();
      tab.dispose();
    });

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: focusRepository),
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: shamorZachorDataProvider,
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: shamorZachorProgressProvider,
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
          ],
          child: MaterialApp(
            // אותה תצורה כמו באפליקציה (lib/app.dart) — RTL גלובלי, שקובע
            // באיזה צד יושבים כפתורי הסרגל ולאיזה כיוון הכותרת חורגת.
            localizationsDelegates: const [
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('he', 'IL')],
            locale: const Locale('he', 'IL'),
            home: TextBookViewerBloc(
              tab: tab,
              isInCombinedView: isInCombinedView,
              openBookCallback: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('כותרת מסך הספר — כותרת ארוכה (ספר Word אישי)', () {
    testWidgets('כותרת ארוכה נחתכת ואינה חורגת ממרכז הסרגל', (tester) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'שור גמל וחמור',
        currentTitle: 'שור גמל וחמור, $_longLocation',
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'חריגת RenderFlex בסרגל העליון',
      );

      final centerRect = tester.getRect(find.byType(ReaderNavCenter));
      for (final textRect in _titleTextRects(tester)) {
        expect(
          textRect.left,
          greaterThanOrEqualTo(centerRect.left - _kTolerance),
          reason: 'הכותרת חורגת משמאל ונדרסת על הכפתורים',
        );
        expect(
          textRect.right,
          lessThanOrEqualTo(centerRect.right + _kTolerance),
          reason: 'הכותרת חורגת מימין ונדרסת על הכפתורים',
        );
      }
    });

    testWidgets('כותרת ארוכה אינה דורסת את כפתורי הפעולות', (tester) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'שור גמל וחמור',
        currentTitle: 'שור גמל וחמור, $_longLocation',
      );

      final buttonRects = {
        'כפתור הניווט': tester.getRect(find.byType(NavPanelToggleButton)),
        'סרגל הפעולות': tester.getRect(find.byType(ResponsiveActionBar)),
      };

      for (final textRect in _titleTextRects(tester)) {
        buttonRects.forEach((name, buttonRect) {
          expect(
            textRect.overlaps(buttonRect.deflate(_kTolerance)),
            isFalse,
            reason: 'הכותרת דורסת את $name',
          );
        });
      }
    });

    testWidgets('בתצוגה משולבת (ללא כפתורי ניווט) הכותרת הארוכה אינה חורגת', (
      tester,
    ) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'שור גמל וחמור',
        currentTitle: 'שור גמל וחמור, $_longLocation',
        isInCombinedView: true,
        size: const Size(1000, 900),
      );

      expect(tester.takeException(), isNull);

      final leadingRect = tester.getRect(find.byType(NavPanelToggleButton));
      for (final textRect in _titleTextRects(tester)) {
        expect(
          textRect.overlaps(leadingRect.deflate(_kTolerance)),
          isFalse,
          reason: 'הכותרת דורסת את כפתור הניווט בתצוגה משולבת',
        );
      }
    });

    testWidgets('כותרת ארוכה עם מחבר — שתי השורות נחתכות בתוך הסרגל', (
      tester,
    ) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'שור גמל וחמור',
        currentTitle: 'שור גמל וחמור, $_longLocation',
        author: 'מחבר עם שם ארוך במיוחד לצורך הבדיקה הזאת',
      );

      expect(tester.takeException(), isNull);

      final centerRect = tester.getRect(find.byType(ReaderNavCenter));
      final rects = [
        ..._titleTextRects(tester),
        tester.getRect(
          find.text('מחבר עם שם ארוך במיוחד לצורך הבדיקה הזאת'),
        ),
      ];
      for (final textRect in rects) {
        expect(
          textRect.left,
          greaterThanOrEqualTo(centerRect.left - _kTolerance),
        );
        expect(
          textRect.right,
          lessThanOrEqualTo(centerRect.right + _kTolerance),
        );
      }
    });

    testWidgets('הטולטיפ מציג את הכותרת המלאה שנחתכה', (tester) async {
      const title = 'שור גמל וחמור, $_longLocation';
      await pumpWithTitle(
        tester,
        bookTitle: 'שור גמל וחמור',
        currentTitle: title,
      );

      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .whereType<String>();
      expect(
        tooltips.any((m) => m.contains(_longLocation)),
        isTrue,
        reason: 'כותרת שנחתכה חייבת להיות זמינה במלואה בטולטיפ',
      );
    });
  });

  group('כותרת מסך הספר — התנהגות קיימת נשמרת', () {
    testWidgets('מיקום קצר מוצג במלואו לצד שם הספר', (tester) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'שולחן ערוך אורח חיים',
        currentTitle: 'שולחן ערוך אורח חיים, סימן א, סעיף ב',
      );

      expect(tester.takeException(), isNull);
      // המיקום נשאר גלוי במלואו — הדרישה שממנה נולד הפיצול לשני חלקים.
      expect(find.textContaining('סימן א, סעיף ב'), findsOneWidget);
    });

    testWidgets('שם ספר ארוך מתקצר כדי לפנות מקום למיקום הקצר', (tester) async {
      const longName =
          'ספר עם שם ארוך מאוד מאוד שאינו נכנס בשום אופן בתוך הסרגל העליון';
      await pumpWithTitle(
        tester,
        bookTitle: longName,
        currentTitle: '$longName, דף ב עמוד א',
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('דף ב עמוד א'), findsOneWidget);

      final centerRect = tester.getRect(find.byType(ReaderNavCenter));
      for (final textRect in _titleTextRects(tester)) {
        expect(
          textRect.right,
          lessThanOrEqualTo(centerRect.right + _kTolerance),
        );
        expect(
          textRect.left,
          greaterThanOrEqualTo(centerRect.left - _kTolerance),
        );
      }
    });

    testWidgets('כותרת ריקה מציגה את שם הספר בלבד', (tester) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'ספר בדיקה',
        currentTitle: '',
      );

      expect(tester.takeException(), isNull);
      expect(find.text('ספר בדיקה'), findsWidgets);
    });
  });

  group('combined view title alignment', () {
    testWidgets('the title is centered like in a regular tab', (tester) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'ספר בדיקה',
        currentTitle: 'ספר בדיקה, פרק א',
        isInCombinedView: true,
      );

      expect(tester.takeException(), isNull);
      final row = tester.widget<Row>(
        find.ancestor(of: find.text('פרק א'), matching: find.byType(Row)).first,
      );
      expect(row.mainAxisAlignment, MainAxisAlignment.center);
    });

    testWidgets('a title without a location is centered too', (tester) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'ספר בדיקה',
        currentTitle: '',
        isInCombinedView: true,
      );

      final title = tester.widget<Text>(find.text('ספר בדיקה').first);
      expect(title.textAlign, TextAlign.center);
    });
  });

  group('מקור הכותרת הארוכה: פסקת גוף שסומנה כ-heading ב-Word', () {
    test('פסקה בסגנון heading 3 הופכת לערך תוכן עניינים באורך מלא', () {
      // בדיוק המבנה של הקובץ שדווח: styleId מספרי ("3") שהוגדר ב-styles.xml
      // כ-heading 3 — ולכן פסקת גוף שלמה נכנסת לתוכן העניינים.
      final content =
          '<h1>שור גמל וחמור</h1>\n'
          '<h3>$_longLocation</h3>\n'
          'טקסט הגוף';

      final toc = TocParser.parseEntriesFromContent(content);
      final ref = refFromTocList(1, toc);

      expect(
        addBookTitleToRef(ref, 'שור גמל וחמור'),
        'שור גמל וחמור, $_longLocation',
        reason: 'זה הטקסט שמגיע לסרגל העליון — ולכן חייב להיחתך בתצוגה',
      );
    });

    test('גרסת הממיר לא ירדה — כותרות styleId מספרי עדיין מזוהות', () {
      expect(kDocxConverterVersion, greaterThanOrEqualTo(9));
    });
  });
}

const double _kTolerance = 0.5;

/// מלבני חלקי הכותרת בסרגל העליון (שם הספר והמיקום).
List<Rect> _titleTextRects(WidgetTester tester) {
  final finder = find.descendant(
    of: find.descendant(
      of: find.byType(AppTopBar),
      matching: find.byType(AppSelectionArea),
    ),
    matching: find.byType(Text),
  );
  final rects = <Rect>[];
  for (final element in finder.evaluate()) {
    final text = (element.widget as Text).data;
    if (text == null || text.trim().isEmpty) continue;
    rects.add(tester.getRect(find.byWidget(element.widget)));
  }
  expect(rects, isNotEmpty, reason: 'לא נמצא טקסט כותרת בסרגל העליון');
  return rects;
}

TextBookLoaded _loadedState(TextBook book, String currentTitle) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב', 'שורה ג'],
    fontSize: 18,
    showSplitView: false,
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
    currentTitle: currentTitle,
    searchMode: SearchMode.exact,
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

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

  @override
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) {
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  _FakeShamorZachorDataProvider();

  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  _FakeShamorZachorProgressProvider();

  @override
  Future<void> ensureLoaded() async {}
}
