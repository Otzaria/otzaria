import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';
import '../../test_helpers/text_occurrence_visibility.dart';

const _commentator = 'מטמון בכותרת מפרש ארוך 2534';
const _query = 'מטמון';

/// מפרש ארוך: התאמה אחת בתחילתו ואחת באמצעו, הרחק מתחת למסך.
final _plainContent = [
  _query,
  for (var i = 0; i < 400; i++) 'מילה',
  _query,
  for (var i = 0; i < 400; i++) 'סוף',
].join(' ');

String _longContent = _plainContent;
final _contentCases = <String, String>{
  'טקסט רגיל': _plainContent,
  'ניקוד': [
    _query,
    for (var i = 0; i < 800; i++) 'מִילָה',
    _query,
    for (var i = 0; i < 800; i++) 'סוף',
  ].join(' '),
  'HTML ותכונת title':
      '<span title="מטמון" style="color:red">$_query</span> '
      '${List.filled(800, 'מִילָה &amp;').join(' ')} '
      '<b><i>$_query</i></b> ${List.filled(800, 'סוף').join(' ')}',
  'מקטעים ארוכים': [
    _query,
    for (var i = 0; i < 80000; i++) 'מילה',
    _query,
    for (var i = 0; i < 4000; i++) 'סוף',
  ].join(' '),
};

/// הגלילה בין תוצאות החיפוש במפרשים מביאה למסך את ההתאמה עצמה, ולא רק את
/// תחילת המפרש שבו היא נמצאת (issue #2534).
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: _commentator,
          categoryId: 1,
          fileType: 'txt',
        ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
  });
  tearDown(LibraryProviderManager.instance.resetForTesting);

  for (final entry in _contentCases.entries) {
    testWidgets(
      '${entry.key}: מעבר לתוצאה שבאמצע מפרש ארוך מציג אותה ולא את תחילת המפרש (issue #2534)',
      (tester) async {
        _longContent = entry.value;
        Link.clearContentCache();
        tester.view.physicalSize = const Size(500, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final textBookBloc = StubTextBookBloc(_loadedState());
        final settingsBloc = StubSettingsBloc(SettingsState.initial());
        addTearDown(textBookBloc.close);
        addTearDown(settingsBloc.close);
        var fontSize = 18.0;
        Widget pane() => MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: CommentaryListBase(
                openBookCallback: (_) {},
                fontSize: fontSize,
                showSearch: true,
                shrinkWrap: false,
              ),
            ),
          ),
        );
        await tester.pumpWidget(pane());
        await tester.pumpAndSettle();
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

        await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), _query);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        Future<void> next() async {
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
        }

        await next();
        expect(find.textContaining('1/2'), findsOneWidget);
        expect(_matchPosition(tester, 0), isInViewport);

        // ההתאמה עצמה סמוך לקו היישור של הקפיצה (10% מראש הרשימה).
        await next();
        expect(find.textContaining('2/2'), findsOneWidget);
        expect(_matchPosition(tester, 1), inInclusiveRange(0.05, 0.2));

        if (entry.key == 'מקטעים ארוכים') {
          final state = tester.state<CommentaryListBaseState>(
            find.byType(CommentaryListBase),
          );
          Future<void> rebuildPartially() async {
            fontSize += 2;
            await tester.pumpWidget(pane());
            final split = tester
                .widget<LongLineChunks>(find.byType(LongLineChunks))
                .split;
            final built = tester
                .renderObjectList<RenderParagraph>(find.byType(RichText))
                .where((paragraph) => longLineChunkOf(paragraph) != null)
                .length;
            expect(built, lessThan(split.chunks.length));
          }

          await rebuildPartially();
          state.navigateSearchPrev();
          state.navigateSearchNext();
          await tester.pumpAndSettle();
          expect(_matchPosition(tester, 1), inInclusiveRange(0.05, 0.2));

          await rebuildPartially();
          state.navigateSearchPrev();
          state.navigateSearchNext();
          state.navigateSearchPrev();
          await tester.pumpAndSettle();
          expect(_matchPosition(tester, 0), isInViewport);
          expect(_matchPosition(tester, 1), greaterThan(1));
        }

        // וחזרה לתוצאה הראשונה, שבראש המפרש.
        tester
            .state<CommentaryListBaseState>(find.byType(CommentaryListBase))
            .navigateToGlobalIndex(0);
        await tester.pumpAndSettle();
        expect(find.textContaining('1/2'), findsOneWidget);
        expect(_matchPosition(tester, 0), isInViewport);
      },
      skip: !engineReady,
    );
  }
}

double _matchPosition(WidgetTester tester, int occurrence) =>
    textOccurrenceViewportFraction(
      tester,
      find.byType(CommentaryContent),
      _query,
      occurrence,
    );

TextBookLoaded _loadedState() {
  final link = Link(
    heRef: 'מטמון בכותרת בלבד',
    index1: 1,
    path2: '$_commentator.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [_commentator],
    commentatorGroups: const [],
    availableCommentators: const [_commentator],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
  );
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
  ) async => throw UnimplementedError();

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => {'$_commentator|1|txt'};

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
  Future<String> getLinkContent(Link link) async => _longContent;

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      title == _commentator;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}
