import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/search_engine_test_init.dart';
import '../test_helpers/stub_settings_bloc.dart';
import '../test_helpers/text_occurrence_visibility.dart';

// כותרות ייחודיות: מטמון התוכן של Link סטטי ומשותף לכל הבדיקות.
const _commentatorPrefix = 'מטמון בכותרת מפרש חיפוש PDF 1505';
const _groupCount = 40;

// ריפוד באפסים: מיון הקישורים לפי כותרת שווה למיון המספרי.
String _title(int i) => '$_commentatorPrefix ${i.toString().padLeft(2, "0")}';

/// שורת המפרש הראשון שתוכנה ארוך: התאמה בתחילתו ואחת באמצעו.
const _longIndex2 = 2534;
const _longQuery = 'מטמון';
final _plainLongContent = [
  _longQuery,
  for (var i = 0; i < 400; i++) 'מילה',
  _longQuery,
  for (var i = 0; i < 400; i++) 'סוף',
].join(' ');

String _longContent = _plainLongContent;
final _longContentCases = <String, String>{
  'רגיל': _plainLongContent,
  'מנוקד': [
    _longQuery,
    for (var i = 0; i < 800; i++) 'מִילָה',
    _longQuery,
    for (var i = 0; i < 800; i++) 'סוף',
  ].join(' '),
  'HTML':
      '<span title="מטמון" style="color:red">$_longQuery</span> '
      '${List.filled(800, 'מִילָה &amp;').join(' ')} '
      '<b><i>$_longQuery</i></b> ${List.filled(800, 'סוף').join(' ')}',
  'מקטעים': [
    _longQuery,
    for (var i = 0; i < 8000; i++) 'מילה',
    _longQuery,
    for (var i = 0; i < 4000; i++) 'סוף',
  ].join(' '),
};

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    final provider = _FakeLibraryProvider();
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (var i = 1; i <= _groupCount; i++)
          BookCompositeKey.create(
            title: _title(i),
            categoryId: 1,
            fileType: 'txt',
          ): provider,
      },
      providers: [provider],
    );
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  group('חיפוש חיצוני לאחר שינוי קטע המפרשים', () {
    late PdfBookTab tab;
    late GlobalKey<PdfCommentaryPanelState> key;
    late TextEditingController query;
    late ValueNotifier<int> total;
    late ValueNotifier<int> current;
    late ValueNotifier<List<CommentarySearchSnippet>> snippets;
    late ValueNotifier<bool> expanded;

    setUp(() {
      tab = _tab()..linksAreComplete = true;
      key = GlobalKey<PdfCommentaryPanelState>();
      query = TextEditingController();
      total = ValueNotifier(0);
      current = ValueNotifier(0);
      snippets = ValueNotifier([]);
      expanded = ValueNotifier(false);
    });
    tearDown(() {
      tab.dispose();
      query.dispose();
      total.dispose();
      current.dispose();
      snippets.dispose();
      expanded.dispose();
    });

    Widget panel(
      int start,
      int end, {
      Set<int>? extraLines,
      bool externalSearch = true,
    }) => _wrap(
      PdfCommentaryPanel(
        key: key,
        tab: tab,
        linksCount: tab.links.length,
        openBookCallback: (_) {},
        fontSize: 16,
        isFullScreen: true,
        enableInternalFilter: false,
        lineStartOverride: start,
        lineEndOverride: end,
        extraLineIndices: extraLines,
        externalSearchController: externalSearch ? query : null,
        externalTotalResultsNotifier: total,
        externalCurrentIndexNotifier: current,
        externalSearchSnippetsNotifier: snippets,
        externalAllExpandedNotifier: expanded,
        commentaryGroupsLoader: (links) async => [
          for (final link in links)
            LinkGroup(
              bookTitle: link.path2.replaceAll('.txt', ''),
              links: [link],
            ),
        ],
      ),
    );

    Future<void> finishSearch(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    }

    testWidgets('טעינת תוכן ישן אינה מחזירה תוצאות לקטע ריק', (tester) async {
      final content = Completer<String>();
      final link = _SearchLink(2, 1, content.future);
      tab.links = [link];
      await tester.pumpWidget(panel(1, 9));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      key.currentState!.toggleAllExpanded();
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await tester.pump(const Duration(milliseconds: 300));
      expect(link.contentReads, greaterThan(1));

      await tester.pumpWidget(panel(10, 19));
      await tester.pumpAndSettle();
      content.complete('אמר אמר אמר');
      await finishSearch(tester);

      expect(query.text, 'אמר');
      expect(total.value, 0);
      expect(current.value, -1);
      expect(snippets.value, isEmpty);
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);

    testWidgets('ביטול extras באותו טווח מסנכרן ספירה ואינדקס', (tester) async {
      tab.links = [
        _SearchLink(2, 1, Future.value('אמר אמר')),
        _SearchLink(10, 2, Future.value('אמר')),
      ];
      final extraLines = <int>{10};
      await tester.pumpWidget(panel(1, 9, extraLines: extraLines));
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await finishSearch(tester);
      expect(total.value, 3);
      key.currentState!.navigateToGlobalIndex(2);
      await tester.pumpAndSettle();
      expect(current.value, 2);

      // מסך הניווט משנה את אותה קבוצת extras לפני עדכון ה-widget.
      extraLines.clear();
      await tester.pumpWidget(panel(1, 9, extraLines: extraLines));
      await finishSearch(tester);

      expect(query.text, 'אמר');
      expect(total.value, 2);
      expect(current.value, -1);
      expect(snippets.value.map((snippet) => snippet.path), [
        '${_title(1)}.txt',
      ]);
      expect(snippets.value.single.globalIndex, 0);
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);

    testWidgets('עדכוני ספירה ממתינים מבוטלים לפני הסרת extras', (
      tester,
    ) async {
      tab.links = [
        _SearchLink(2, 1, Future.value('אמר אמר')),
        _SearchLink(10, 2, Future.value('אמר')),
      ];
      final extraLines = <int>{10};
      await tester.pumpWidget(panel(1, 9, extraLines: extraLines));
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await tester.pump();
      expect(total.value, 0);

      extraLines.clear();
      await tester.pumpWidget(panel(1, 9, extraLines: extraLines));
      await finishSearch(tester);

      expect(total.value, 2);
      expect(current.value, -1);
      expect(snippets.value.map((snippet) => snippet.path), [
        '${_title(1)}.txt',
      ]);
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);

    testWidgets('איפוס קטע אינו דורס שאילתה חדשה שנקבעת בסוף ה-frame', (
      tester,
    ) async {
      tab.links = [
        _SearchLink(2, 1, Future.value('אמר אמר')),
        _SearchLink(10, 2, Future.value('חדש')),
      ];
      await tester.pumpWidget(panel(1, 9));
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await finishSearch(tester);
      expect(total.value, 2);

      WidgetsBinding.instance.addPostFrameCallback((_) => query.text = 'חדש');
      await tester.pumpWidget(panel(10, 19));
      await finishSearch(tester);

      expect(query.text, 'חדש');
      expect(total.value, 1);
      // שאילתה חדשה שעוד לא נווטה.
      expect(current.value, -1);
      expect(snippets.value.single.path, '${_title(2)}.txt');
      expect(snippets.value.single.snippet, contains('חדש'));
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);

    testWidgets('החלפת controller חיצוני מנתקת את הישן ואת ההסרה', (
      tester,
    ) async {
      tab.links = [_SearchLink(2, 1, Future.value('אמר אמר חדש'))];
      await tester.pumpWidget(panel(1, 9));
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await finishSearch(tester);
      expect(total.value, 2);
      final old = query;
      addTearDown(old.dispose);
      query = TextEditingController(text: 'חדש');
      final retained = key.currentState;
      await tester.pumpWidget(panel(1, 9));
      await finishSearch(tester);
      expect(key.currentState, same(retained));
      expect(total.value, 1);
      query.clear();
      await finishSearch(tester);
      old.text = 'אמר';
      await finishSearch(tester);
      expect(total.value, 0);
      await tester.pumpWidget(panel(1, 9, externalSearch: false));
      old.text = 'ישן';
      query.text = 'אמר';
      await tester.pump();
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);

    testWidgets('notifiers חדשים מקבלים חיפוש קיים באותו State', (
      tester,
    ) async {
      tab.links = [_SearchLink(2, 1, Future.value('אמר אמר חדש'))];
      await tester.pumpWidget(panel(1, 9));
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await finishSearch(tester);
      key.currentState!.navigateSearchNext();
      await tester.pumpAndSettle();
      expect(total.value, 2);
      expect(current.value, 0);
      final retained = key.currentState;
      final savedSnippets = snippets.value;
      expect(savedSnippets, isNotEmpty);
      addTearDown(total.dispose);
      addTearDown(current.dispose);
      addTearDown(snippets.dispose);
      addTearDown(expanded.dispose);
      total = ValueNotifier(-99);
      current = ValueNotifier(-99);
      snippets = ValueNotifier([]);
      expanded = ValueNotifier(false);
      await tester.pumpWidget(panel(1, 9));
      await finishSearch(tester);
      expect(key.currentState, same(retained));
      expect(total.value, 2);
      expect(current.value, 0);
      expect(snippets.value, same(savedSnippets));
      expect(expanded.value, isTrue);
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);

    testWidgets('שאילתה חדשה: התוצאה הבאה היא הראשונה (#2606)', (tester) async {
      tab.links = [_SearchLink(2, 1, Future.value('אמר אמר'))];
      await tester.pumpWidget(panel(1, 9));
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await finishSearch(tester);
      expect(total.value, 2);
      expect(current.value, -1);

      key.currentState!.navigateSearchNext();
      await tester.pumpAndSettle();
      expect(current.value, 0);
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);

    testWidgets('חיפוש נשמר במעבר בין קטעים וחזרה גם בקבוצה מכווצת', (
      tester,
    ) async {
      tab.links = [
        _SearchLink(2, 1, Future.value('אמר אמר')),
        _SearchLink(10, 2, Future.value('אמר')),
      ];
      await tester.pumpWidget(panel(1, 9));
      await tester.pumpAndSettle();
      query.text = 'אמר';
      await finishSearch(tester);
      expect(total.value, 2);
      key.currentState!.toggleAllExpanded();
      await tester.pumpAndSettle();

      for (final scope in [(10, 19, 1), (20, 29, 0), (1, 9, 2)]) {
        await tester.pumpWidget(panel(scope.$1, scope.$2));
        await finishSearch(tester);
        expect(query.text, 'אמר');
        expect(total.value, scope.$3);
        // קטע חדש: עוד לא נווט לאף תוצאה בו.
        expect(current.value, -1);
        expect(snippets.value.length, scope.$3 == 0 ? 0 : 1);
      }
      key.currentState!.navigateToGlobalIndex(0);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining('אמר אמר').hitTestable(), findsWidgets);
      expect(tester.takeException(), isNull);
    }, skip: !engineReady);
  });

  group('חיפוש בחלונית המפרשים של PDF (issue #1505)', () {
    testWidgets('ניווט לתוצאה רחוקה אינו מפיל את הרשימה', (tester) async {
      final tab = _tab();
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        _wrap(
          PdfCommentaryPanel(
            tab: tab,
            linksCount: tab.links.length,
            openBookCallback: (_) {},
            fontSize: 16,
            commentaryGroupsLoader: (links) async => [
              for (final link in links)
                LinkGroup(
                  bookTitle: link.path2.replaceAll('.txt', ''),
                  links: [link],
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'עמק');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // התוצאה ה-30 נמצאת בקבוצה רחוקה מהמסך שעוד לא נבנתה.
      final nextButton = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byIcon(FluentIcons.chevron_down_24_regular),
              matching: find.byType(IconButton),
            )
            .first,
      );
      final next = nextButton.onPressed!;
      for (var i = 0; i < 29; i++) {
        next();
      }
      await tester.pump();
      // היעד הבא מחליף את jumpTo בזמן שהקבוצה הקודמת עדיין נבנית.
      next();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('30/'), findsOneWidget);
      expect(
        find.text(_title(30)).hitTestable(),
        findsWidgets,
        reason: 'הגלילה העדינה צריכה להביא את המפרש של התוצאה לתצוגה',
      );
    }, skip: !engineReady);

    testWidgets('Enter בשדה החיפוש עובר לתוצאה הבאה', (tester) async {
      final tab = _tab(index2: 2);
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        _wrap(
          PdfCommentaryPanel(
            tab: tab,
            linksCount: tab.links.length,
            openBookCallback: (_) {},
            fontSize: 16,
            commentaryGroupsLoader: (links) async => [
              for (final link in links)
                LinkGroup(
                  bookTitle: link.path2.replaceAll('.txt', ''),
                  links: [link],
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'עמק');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.textContaining('/$_groupCount'), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.textContaining('1/$_groupCount'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.textContaining('2/$_groupCount'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
    }, skip: !engineReady);

    testWidgets('מונה התוצאות לא חוטף את סימון הטקסט במפרשים (issue #2198)', (
      tester,
    ) async {
      final tab = _tab(index2: 2198);
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        _wrap(
          PdfCommentaryPanel(
            tab: tab,
            linksCount: tab.links.length,
            openBookCallback: (_) {},
            fontSize: 16,
            commentaryGroupsLoader: (links) async => [
              for (final link in links)
                LinkGroup(
                  bookTitle: link.path2.replaceAll('.txt', ''),
                  links: [link],
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'עמק');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('1/$_groupCount'), findsOneWidget);

      // המונה "1/40" הוא תוכן LTR בתוך אזור בחירה RTL: גרירה מתחתיו נתפסה
      // בו ונעצרה, והמפרש לא סומן.
      final paragraph = find
          .descendant(
            of: find.byType(CommentaryContent).first,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText().contains('עָמֹק'),
            ),
          )
          .first;
      final rect = tester.getRect(paragraph);
      final start = rect.centerRight - const Offset(2, 0);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var step = 1; step <= 5; step++) {
        await gesture.moveTo(start - Offset(20.0 * step, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final selections = tester
          .renderObject<RenderParagraph>(paragraph)
          .selections;
      expect(selections, hasLength(1));
      expect(selections.single.isCollapsed, isFalse);
      final counter = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.text('1/$_groupCount'),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(counter.selections, isEmpty);
    }, skip: !engineReady);

    for (final entry in _longContentCases.entries) {
      testWidgets(
        '${entry.key}: מעבר לתוצאה שבאמצע מפרש ארוך מציג אותה ולא את תחילת המפרש (issue #2534)',
        (tester) async {
          _longContent = entry.value;
          Link.clearContentCache();
          tester.view.physicalSize = const Size(500, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final tab = _tab(index2: _longIndex2);
          addTearDown(tab.dispose);

          await tester.pumpWidget(
            _wrap(
              PdfCommentaryPanel(
                tab: tab,
                linksCount: tab.links.length,
                openBookCallback: (_) {},
                fontSize: 16,
                commentaryGroupsLoader: (links) async => [
                  for (final link in links)
                    LinkGroup(
                      bookTitle: link.path2.replaceAll('.txt', ''),
                      links: [link],
                    ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), _longQuery);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();

          double matchPosition(int occurrence) =>
              textOccurrenceViewportFraction(
                tester,
                find.byType(CommentaryContent),
                _longQuery,
                occurrence,
              );

          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(find.textContaining('1/2'), findsOneWidget);
          expect(matchPosition(0), isInViewport);

          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(find.textContaining('2/2'), findsOneWidget);
          // ההתאמה עצמה סמוך לקו היישור של הקפיצה (10% מראש הרשימה).
          expect(matchPosition(1), inInclusiveRange(0.05, 0.2));
        },
        skip: !engineReady,
      );
    }
  });
}

/// [index2] keeps each test's links apart in the static content cache: a
/// future cached by an earlier test never completes in a later one.
PdfBookTab _tab({int index2 = 1}) {
  final tab = PdfBookTab(
    book: PdfBook(title: 'ספר בדיקה', path: '/books/ספר בדיקה.pdf'),
    pageNumber: 1,
  );
  tab.currentTextLineNumber = 10;
  tab.currentTextLineNumberEnd = 40;
  tab.links = [
    for (var i = 1; i <= _groupCount; i++)
      Link(
        heRef: _title(i),
        index1: 12,
        path2: '${_title(i)}.txt',
        index2: index2,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      ),
  ];
  tab.activeCommentators = {
    for (var i = 1; i <= _groupCount; i++) _title(i),
  };
  return tab;
}

Widget _wrap(Widget child) => MaterialApp(
  builder: (context, child) =>
      Directionality(textDirection: TextDirection.rtl, child: child!),
  home: MultiBlocProvider(
    providers: [
      BlocProvider<SettingsBloc>.value(value: StubSettingsBloc()),
      BlocProvider<PersonalNotesBloc>.value(value: _FakePersonalNotesBloc()),
    ],
    child: Scaffold(body: child),
  ),
);

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeLibraryProvider implements LibraryProvider {
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
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => const {};

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => null;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => const [];

  @override
  Future<String> getLinkContent(Link link) async =>
      link.index2 == _longIndex2 && link.path2 == '${_title(1)}.txt'
      ? _longContent
      : 'דְּבֵין עָמֹק בֵּין דֵּהֶה טָהוֹר.';

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      title.startsWith(_commentatorPrefix);

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}

class _SearchLink extends Link {
  _SearchLink(int line, int commentator, this._content)
    : super(
        heRef: _title(commentator),
        index1: line,
        path2: '${_title(commentator)}.txt',
        index2: 1,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      );

  final Future<String> _content;
  int contentReads = 0;

  @override
  Future<String> get content {
    contentReads++;
    return _content;
  }
}
