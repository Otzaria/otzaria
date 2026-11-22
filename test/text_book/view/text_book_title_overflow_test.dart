import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
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
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_display/models/text_display_policy.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

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
    TextDisplayPolicy? displayPolicy,
    List<TocEntry> tableOfContents = const [],
  }) async {
    final book = TextBook(title: bookTitle, author: author);
    final bloc = StubTextBookBloc(
      _loadedState(
        book,
        currentTitle,
        displayPolicy: displayPolicy,
        tableOfContents: tableOfContents,
      ),
    );
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final settingsBloc = StubSettingsBloc(SettingsState.initial());

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

  testWidgets('הסתרת שם השם חלה גם על הכותרת בסרגל העליון (#3543)', (
    tester,
  ) async {
    await pumpWithTitle(
      tester,
      bookTitle: 'ספר בדיקה',
      currentTitle: 'ספר בדיקה, ברכת יהוה',
      displayPolicy: TextDisplayPolicy.fromLegacy(
        defaultRemoveNikud: false,
        removeNikudFromTanach: false,
        defaultRemovePunctuation: false,
        showTeamim: true,
        replaceHolyNames: true,
        holyNameStyle: HolyNameStyle.kufKuf,
      ),
    );

    expect(find.textContaining('יהוה'), findsNothing);
    expect(find.textContaining('ברכת יקוק'), findsOneWidget);
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

  group('כותרת צרה שומרת את הכותרת העמוקה (issue #5712)', () {
    const bookTitle = 'שמירת שבת כהלכתה';
    const headings = ['חלק א', 'פרק כ - דיני הוצאה', 'סעיף יג'];
    final location = headings.join(', ');
    final fullTitle = '$bookTitle, $location';
    final toc = _tocChain(headings);

    /// טקסט הכותרת הגלוי שמסתיים במיקום הנוכחי, אם יש כזה.
    Text? deepestTitleText(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(AppSelectionArea),
            matching: find.byType(Text),
          ),
        )
        .where((t) => t.data?.endsWith('סעיף יג') ?? false)
        .firstOrNull;

    // בגופן הבדיקות כל אות היא ריבוע ברוחב גודל הגופן (22px), ולכן מרכז
    // הסרגל ב-1400px (340px) צר עבור הכותרת הזאת כמו סרגל של כ-500px בגופן
    // עברי אמיתי.
    testWidgets('בסרגל צר הכותרת מסתיימת בכותרת העמוקה ואינה נחתכת', (
      tester,
    ) async {
      await pumpWithTitle(
        tester,
        bookTitle: bookTitle,
        currentTitle: location,
        tableOfContents: toc,
      );

      expect(tester.takeException(), isNull);
      final text = deepestTitleText(tester);
      expect(text, isNotNull, reason: 'הכותרת העמוקה "סעיף יג" אינה גלויה');
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byWidget(text!),
          matching: find.byType(RichText),
        ),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'הכותרת העמוקה נחתכה',
      );
      expect(text.data, startsWith('…, '));

      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .whereType<String>();
      expect(tooltips.any((m) => m.contains(fullTitle)), isTrue);
    });

    testWidgets('כשאין מקום ל"…, " — מוצגת הכותרת העמוקה לבדה', (
      tester,
    ) async {
      await pumpWithTitle(
        tester,
        bookTitle: bookTitle,
        currentTitle: location,
        tableOfContents: toc,
        size: const Size(900, 900),
      );

      expect(tester.takeException(), isNull);
      expect(deepestTitleText(tester)?.data, 'סעיף יג');
    });

    testWidgets('כותרת שנכנסת במלואה מוצגת ללא השמטה', (tester) async {
      await pumpWithTitle(
        tester,
        bookTitle: 'ספר',
        currentTitle: 'א, ב',
        tableOfContents: _tocChain(['א', 'ב']),
      );

      expect(find.textContaining('…'), findsNothing);
      expect(find.textContaining('א, ב'), findsOneWidget);
    });

    testWidgets('הגדלת טקסט פי 2 אינה גורמת לחריגה', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpWithTitle(
        tester,
        bookTitle: bookTitle,
        currentTitle: location,
        tableOfContents: toc,
      );

      expect(tester.takeException(), isNull);
      expect(deepestTitleText(tester), isNotNull);
    });

    test('startTruncatedTitle שומר את הסיפא הארוכה ביותר שנכנסת', () {
      bool fitsUpTo(String text, int max) => text.length <= max;
      String full(ElidedTitle e) =>
          e.omitted + e.shown.substring(e.markerLength);

      expect(startTruncatedTitle(['שם בלבד'], (_) => true), isNull);
      final cut = startTruncatedTitle([
        'א',
        'ב',
        'ג',
        'ד',
      ], (t) => fitsUpTo(t, 9))!;
      expect(cut.shown, '…, ג, ד');
      expect(full(cut), 'א, ב, ג, ד');
      expect(
        startTruncatedTitle(['א', 'ב', 'ג', 'ד'], (_) => true)!.shown,
        '…, ב, ג, ד',
      );
      final none = startTruncatedTitle(['א', 'ב', 'ג', 'ד'], (_) => false)!;
      expect(
        none.shown,
        'ד',
        reason: 'גם כשדבר אינו נכנס — הכותרת העמוקה היא שמוצגת',
      );
      expect(full(none), 'א, ב, ג, ד');
    });

    test('פסיק בתוך כותרת אינו נקודת חיתוך', () {
      const deepest = 'דין המטלטל, והמוציא מרשות לרשות';
      final elided = startTruncatedTitle([
        'ספר',
        'חלק א',
        deepest,
      ], (t) => t.length <= '…, $deepest'.length + 2)!;
      expect(elided.shown, '…, $deepest');
      expect(elided.omitted, 'ספר, חלק א');
    });

    // ב-340px נכנסות כ-15 אותיות: הכותרת העמוקה (14) נכנסת, אך לא אחרי "…, ".
    // חלוקה לפי ", " הייתה מציגה "…, ובעלי חי" — חצי כותרת.
    testWidgets('כותרת עמוקה עם פסיק בסרגל צר — אינה נחתכת בפסיק שבתוכה', (
      tester,
    ) async {
      const deepest = 'כלים, ובעלי חי';
      const deepHeadings = ['חלק א', 'פרק כ - דיני הוצאה', deepest];
      await pumpWithTitle(
        tester,
        bookTitle: bookTitle,
        currentTitle: deepHeadings.join(', '),
        tableOfContents: _tocChain(deepHeadings),
      );

      expect(tester.takeException(), isNull);
      final shown = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AppSelectionArea),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .toList();
      expect(shown, contains(deepest));
      expect(shown.where((d) => d?.contains('…') ?? false), isEmpty);
    });

    testWidgets('העתקת כותרת מקוצרת מחזירה את הכותרת המלאה', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpWithTitle(
        tester,
        bookTitle: bookTitle,
        currentTitle: location,
        tableOfContents: toc,
      );
      expect(deepestTitleText(tester)?.data, startsWith('…, '));

      final region = tester.state<SelectableRegionState>(
        find.descendant(
          of: find.byType(AppSelectionArea),
          matching: find.byType(SelectableRegion),
        ),
      );
      region.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      region.contextMenuButtonItems
          .firstWhere((item) => item.type == ContextMenuButtonType.copy)
          .onPressed!();
      await tester.pump();

      expect(copied, fullTitle);
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

/// שרשרת כותרות מקוננות שכולן חלות על השורה הראשונה, כמו בספר אמיתי.
List<TocEntry> _tocChain(List<String> headings) {
  TocEntry? parent;
  final roots = <TocEntry>[];
  for (var i = 0; i < headings.length; i++) {
    final entry = TocEntry(
      text: headings[i],
      index: 0,
      level: i + 2,
      parent: parent,
    );
    (parent?.children ?? roots).add(entry);
    parent = entry;
  }
  return roots;
}

TextBookLoaded _loadedState(
  TextBook book,
  String currentTitle, {
  TextDisplayPolicy? displayPolicy,
  List<TocEntry> tableOfContents = const [],
}) {
  return TextBookLoaded(
    displayPolicy: displayPolicy,
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
    tableOfContents: tableOfContents,
    removeNikud: false,
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    searchText: '',
    currentTitle: currentTitle,
    searchMode: SearchMode.exact,
  );
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
