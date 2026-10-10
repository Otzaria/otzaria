import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../support/search_engine_test_init.dart';

Future<void> main() async {
  // הקוד הנבדק קורא ל-sanitizeQuery/splitQueryWords שמאצילים למנוע ה-Rust;
  // הטסטים המסומנים מדולגים כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  late _TestTextBookBloc textBookBloc;
  late _TestSettingsBloc settingsBloc;

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );

    textBookBloc = _TestTextBookBloc(_loadedState());
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  group('CommentaryListBase - פוקוס חיפוש', () {
    testWidgets('שדה החיפוש שומר פוקוס אחרי rebuild שנגרם מהקלדה', (
      tester,
    ) async {
      await _pumpWidget(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );

      // בעיצוב החדש שדה החיפוש מוסתר מאחורי כפתור אייקון; פותחים אותו ידנית.
      await _openInlineSearch(tester);

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      expect(_searchFocusNode(tester).hasFocus, isTrue);

      await tester.enterText(textField, 'מפרש');
      await tester.pump();
      await tester.pump();

      expect(_searchFocusNode(tester).hasFocus, isTrue);
      expect(find.text('מפרש'), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('לחיצה על dismiss סוגרת את שדה החיפוש ומנקה את הטקסט', (
      tester,
    ) async {
      await _pumpWidget(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );

      await _openInlineSearch(tester);

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'מפרש');
      await tester.pump();
      await tester.pump();

      // שומרים הפניה ל-controller לפני שהשדה נעלם מעץ הוויג'טים.
      final controller = _searchController(tester);

      await tester.tap(
        find.byIcon(FluentIcons.dismiss_24_regular).hitTestable(),
      );
      await tester.pump();
      await tester.pump();

      // השדה נסגר וחוזרים לשורת הלחצנים (כולל אייקון החיפוש).
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(FluentIcons.search_24_regular), findsWidgets);
      expect(controller.text, isEmpty);
    }, skip: !engineReady);
  });

  group('חיפוש במפרשים (issue #1505)', () {
    // מטמון התוכן של Link משותף גם בין בדיקות, לכן הכותרות שונות.
    var caseIndex = 0;
    setUp(() async {
      final commentator = 'ברטנורא על משנה נדה בדיקה ${++caseIndex}';
      // ברטנורא על משנה נדה ב, ו — מתוך הסרטון שבדיווח.
      final provider = _FakeLibraryProvider(
        content:
            '<b>דֵּהֶה.</b> שֶׁנִּדְהֵית מַרְאִיתוֹ וְאֵינוֹ שָׁחֹר כָּל כָּךְ. וְהוּא הַדִּין לְכָל דָּמִים טְמֵאִים<i data-commentator="IkkarTosfotYomTov" data-label="טז"></i>, דִּבְכֻלְּהוּ עָמֹק מִכָּאן טָמֵא, דֵּהֶה מִכָּאן טָהוֹר, חוּץ מִיַּיִן מָזוּג, דְּבֵין עָמֹק בֵּין דֵּהֶה טָהוֹר:',
      );
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          BookCompositeKey.create(
            title: commentator,
            categoryId: 1,
            fileType: 'txt',
          ): provider,
        },
        providers: [provider],
      );
      await textBookBloc.close();
      textBookBloc = _TestTextBookBloc(
        _loadedState(commentator: commentator, linkCount: 40),
      );
    });

    Future<CommentaryListBaseState> search(
      WidgetTester tester, {
      int expectedTotal = 80,
    }) async {
      await _pumpWidget(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );
      await _openInlineSearch(tester);
      await tester.enterText(find.byType(TextField), 'עמק');
      await _pumpSearchCounts(tester);
      final list = tester.state<CommentaryListBaseState>(
        find.byType(CommentaryListBase),
      );
      expect(list.totalSearchResultsNotifier.value, expectedTotal);
      list.currentSearchIndexNotifier.value = 0;
      await tester.pump();
      return list;
    }

    testWidgets('ניווט חיפוש משתמש בהיסטים בלי לסרוק שוב קישורים מחוץ למסך', (
      tester,
    ) async {
      final list = await search(tester);
      final links = (textBookBloc.state as TextBookLoaded).links;
      final offscreen = links.last as _CountingLink;
      expect(
        tester
            .widgetList<CommentaryContent>(find.byType(CommentaryContent))
            .any((content) => identical(content.link, offscreen)),
        isFalse,
      );
      offscreen.keyReads = 0;

      list.currentSearchIndexNotifier.value = 1;
      await tester.pump();
      expect(_contentFor(tester, links.first).currentSearchIndex, 1);
      expect(offscreen.keyReads, 0);

      list.currentSearchIndexNotifier.value = 2;
      await tester.pump();
      expect(_contentFor(tester, links[1]).currentSearchIndex, 0);
      expect(offscreen.keyReads, 0);

      await tester.enterText(find.byType(TextField), '');
      await _pumpSearchCounts(tester);
      expect(list.totalSearchResultsNotifier.value, 0);
      offscreen.keyReads = 0;
      list.currentSearchIndexNotifier.value = 5;
      await tester.pump();
      expect(_contentFor(tester, links.first).currentSearchIndex, -1);
      expect(offscreen.keyReads, 0);
    }, skip: !engineReady);

    testWidgets(
      'עדכון ספירות בלי שינוי בסכום מבטל את ההיסטים לפני ה-notifier',
      (
        tester,
      ) async {
        final list = await search(tester);
        final links = (textBookBloc.state as TextBookLoaded).links;
        final offscreen = links.last as _CountingLink;
        _contentFor(tester, links.first).onSearchResultsCountChanged!(3);
        _contentFor(tester, links[1]).onSearchResultsCountChanged!(1);
        await tester.pump(const Duration(milliseconds: 200));
        expect(list.totalSearchResultsNotifier.value, 80);
        offscreen.keyReads = 0;

        list.currentSearchIndexNotifier.value = 3;
        await tester.pump();
        expect(_contentFor(tester, links.first).currentSearchIndex, -1);
        expect(_contentFor(tester, links[1]).currentSearchIndex, 0);
        expect(offscreen.keyReads, 1);
      },
      skip: !engineReady,
    );

    testWidgets('החלפת שאילתה ורשימת קישורים מעדכנת את ההדגשה והספירה', (
      tester,
    ) async {
      final list = await search(tester);
      final links = (textBookBloc.state as TextBookLoaded).links;
      await tester.enterText(find.byType(TextField), 'יין');
      await _pumpSearchCounts(tester);
      expect(list.totalSearchResultsNotifier.value, 40);
      list.currentSearchIndexNotifier.value = 1;
      await tester.pump();
      expect(_contentFor(tester, links.first).currentSearchIndex, -1);
      expect(_contentFor(tester, links[1]).currentSearchIndex, 0);

      final remaining = links.skip(1).toList();
      textBookBloc.replaceState(
        (textBookBloc.state as TextBookLoaded).copyWith(
          links: remaining,
          linksByLine: {1: remaining},
        ),
      );
      await tester.pumpAndSettle();
      await _pumpSearchCounts(tester);
      expect(list.totalSearchResultsNotifier.value, 39);
      list.currentSearchIndexNotifier.value = 0;
      await tester.pump();
      expect(_contentFor(tester, links[1]).currentSearchIndex, 0);
    }, skip: !engineReady);

    testWidgets('שינוי סדר מפרשים עם אותן ספירות מחשב מחדש את ההיסטים', (
      tester,
    ) async {
      const titles = ['מפרש היסטים ראשון', 'מפרש היסטים שני'];
      final provider = _FakeLibraryProvider(content: 'עמק עמק');
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          for (final title in titles)
            BookCompositeKey.create(
              title: title,
              categoryId: 1,
              fileType: 'txt',
            ): provider,
        },
        providers: [provider],
      );
      final links = [
        for (final title in titles)
          for (var i = 1; i <= 8; i++)
            _CountingLink(
              heRef: 'בראשית א',
              index1: 1,
              path2: '$title.txt',
              index2: i,
              connectionType: 'COMMENTARY',
              targetCategoryId: 1,
              targetFileType: 'txt',
            ),
      ];
      textBookBloc.replaceState(
        _loadedState(commentator: titles.first).copyWith(
          activeCommentators: titles,
          availableCommentators: titles,
          links: links,
          linksByLine: {1: links},
        ),
      );
      final list = await search(tester, expectedTotal: 32);
      expect(_contentFor(tester, links.first).currentSearchIndex, 0);

      textBookBloc.replaceState(
        (textBookBloc.state as TextBookLoaded).copyWith(
          activeCommentators: titles.reversed.toList(),
        ),
      );
      await tester.pumpAndSettle();
      await _pumpSearchCounts(tester);
      expect(list.totalSearchResultsNotifier.value, 32);
      expect(_contentFor(tester, links[8]).currentSearchIndex, 0);
    }, skip: !engineReady);

    for (final useHighlight in [false, true]) {
      testWidgets(
        'שאילתה ${useHighlight ? 'להדגשה' : 'חיצונית'} מרעננת את ההיסטים',
        (
          tester,
        ) async {
          final controller = TextEditingController();
          final highlight = ValueNotifier<String>('');
          addTearDown(controller.dispose);
          addTearDown(highlight.dispose);
          await _pumpWidget(
            tester,
            textBookBloc: textBookBloc,
            settingsBloc: settingsBloc,
            externalSearchController: useHighlight ? null : controller,
            highlightQueryListenable: useHighlight ? highlight : null,
            showSearch: !useHighlight,
          );
          void query(String text) {
            if (useHighlight) {
              highlight.value = text;
            } else {
              controller.text = text;
            }
          }

          final list = tester.state<CommentaryListBaseState>(
            find.byType(CommentaryListBase),
          );
          final links = (textBookBloc.state as TextBookLoaded).links;
          query('עמק');
          await _pumpSearchCounts(tester);
          expect(list.totalSearchResultsNotifier.value, 80);
          list.currentSearchIndexNotifier.value = 1;
          await tester.pump();
          expect(_contentFor(tester, links.first).currentSearchIndex, 1);

          query('יין');
          await _pumpSearchCounts(tester);
          expect(list.totalSearchResultsNotifier.value, 40);
          list.currentSearchIndexNotifier.value = 1;
          await tester.pump();
          expect(_contentFor(tester, links.first).currentSearchIndex, -1);
          expect(_contentFor(tester, links[1]).currentSearchIndex, 0);

          query('');
          await _pumpSearchCounts(tester);
          expect(list.totalSearchResultsNotifier.value, 0);
          expect(_contentFor(tester, links.first).currentSearchIndex, -1);
        },
        skip: !engineReady,
      );
    }

    testWidgets('ניווט לתוצאה רחוקה אינו מפיל את הרשימה', (tester) async {
      await _pumpWidget(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );
      await _openInlineSearch(tester);
      await tester.enterText(find.byType(TextField), 'עמק');
      await _pumpSearchCounts(tester);

      // Enter עובר לתוצאה הבאה; התוצאה ה-30 רחוקה מהמסך ועוד לא נבנתה.
      for (var i = 0; i < 30; i++) {
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('30/'), findsOneWidget);
    }, skip: !engineReady);
  });
}

Future<void> _openInlineSearch(WidgetTester tester) async {
  await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
  await tester.pumpAndSettle();
}

Future<void> _pumpWidget(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
  TextEditingController? externalSearchController,
  ValueListenable<String>? highlightQueryListenable,
  bool showSearch = true,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CommentaryListBase(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: showSearch,
            externalSearchController: externalSearchController,
            highlightQueryListenable: highlightQueryListenable,
            shrinkWrap: false,
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

FocusNode _searchFocusNode(WidgetTester tester) {
  final textField = tester.widget<TextField>(find.byType(TextField).first);
  return textField.focusNode!;
}

TextEditingController _searchController(WidgetTester tester) {
  final textField = tester.widget<TextField>(find.byType(TextField).first);
  return textField.controller!;
}

TextBookLoaded _loadedState({
  String commentator = 'מפרש בדיקה',
  int linkCount = 1,
}) {
  final links = [
    for (var i = 1; i <= linkCount; i++)
      _CountingLink(
        heRef: 'בראשית א',
        index1: 1,
        path2: '$commentator.txt',
        index2: i,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      ),
  ];

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: [commentator],
    commentatorGroups: const [],
    availableCommentators: [commentator],
    links: links,
    visibleLinks: const [],
    linksByLine: {
      1: links,
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void replaceState(TextBookLoaded next) => emit(next);

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

class _FakeLibraryProvider implements LibraryProvider {
  _FakeLibraryProvider({
    this.content = 'זהו פירוש לבדיקה עם טקסט שניתן לבחור',
  });

  final String content;

  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return {'מפרש בדיקה|1|txt'};
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return content;
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return title == 'מפרש בדיקה';
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}

CommentaryContent _contentFor(WidgetTester tester, Link link) => tester
    .widgetList<CommentaryContent>(find.byType(CommentaryContent))
    .firstWhere((content) => identical(content.link, link));

class _CountingLink extends Link {
  _CountingLink({
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.connectionType,
    super.targetCategoryId,
    super.targetFileType,
  });

  int keyReads = 0;

  @override
  int get index2 {
    keyReads++;
    return super.index2;
  }
}

Future<void> _pumpSearchCounts(WidgetTester tester) async {
  // חישוב הספירות אסינכרוני; משפך העדכון מתוזמן רק אחרי שהוא חוזר.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}
