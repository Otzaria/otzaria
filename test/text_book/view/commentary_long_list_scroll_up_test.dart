// גלילה למעלה ברשימה ארוכה של מפרשים קפצה חזרה למטה: פריט שנבנה מחדש מעל
// התצוגה הוצג לפריים אחד בשלד טעינה קצר, ואז גדל ודחף את התוכן (issue #1588).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// כמו אצל המדווח: כל המפרשים מסומנים, 29 מפרשים לפסקה.
final List<String> _commentators = [
  for (var i = 0; i < 29; i++) 'מפרש ${i + 1}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in _commentators)
          BookCompositeKey.create(
            title: title,
            categoryId: 1,
            fileType: 'txt',
          ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  /// המיקום על המסך של כותרת כל מפרש שבנוי כרגע.
  Map<String, double> headerTops(WidgetTester tester) => {
    for (final title in _commentators)
      if (find.text(title).evaluate().isNotEmpty)
        title: tester.getTopLeft(find.text(title).first).dy,
  };

  Future<void> wheel(WidgetTester tester, Offset at, double dy) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(position: at, scrollDelta: Offset(0, dy)),
    );
    await tester.pump();
  }

  testWidgets('גלילה למעלה ברשימה ארוכה אינה קופצת חזרה למטה', (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester);
    await tester.pumpAndSettle();
    final list = tester.getCenter(find.byType(ScrollablePositionedList));

    for (var i = 0; i < 400; i++) {
      await wheel(tester, list, 400);
    }
    await tester.pumpAndSettle();
    expect(
      find.text(_commentators.first),
      findsNothing,
      reason: 'הבדיקה חייבת להתחיל בסוף הרשימה, כשראשה כבר לא בנוי',
    );

    var steps = 0;
    while (find.text(_commentators.first).evaluate().isEmpty && steps < 600) {
      final before = headerTops(tester);
      await wheel(tester, list, -60);
      final after = headerTops(tester);
      for (final title in before.keys.where(after.containsKey)) {
        expect(
          after[title]! - before[title]!,
          greaterThanOrEqualTo(-0.5),
          reason: 'צעד $steps: "$title" זז למעלה בגלילה למעלה',
        );
      }
      steps++;
    }
    expect(find.text(_commentators.first), findsWidgets);
  });
}

Future<void> _pump(WidgetTester tester) async {
  final bloc = _TestTextBookBloc(_state());
  final settingsBloc = _TestSettingsBloc.initial();
  addTearDown(bloc.close);
  addTearDown(settingsBloc.close);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CommentaryListBase(
              openBookCallback: (_) {},
              fontSize: 18,
              showSearch: false,
              shrinkWrap: false,
              indexes: const [0],
              onSelectedCommentatorsOverrideChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Link _link(String title) => Link(
  heRef: 'שורה 1',
  index1: 1,
  path2: '$title.txt',
  index2: 1,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 1,
  targetFileType: 'txt',
);

TextBookLoaded _state() {
  final links = [for (final title in _commentators) _link(title)];
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: _commentators,
    commentatorGroups: [
      CommentatorGroup(title: 'ראשונים', commentators: _commentators),
    ],
    availableCommentators: _commentators,
    links: links,
    visibleLinks: const [],
    linksByLine: {1: links},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    selectedIndices: const {0},
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  factory _TestSettingsBloc.initial() =>
      _TestSettingsBloc(SettingsState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  ) async {
    return const [];
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async => {
    for (final title in _commentators) '$title|1|txt',
  };

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
  Future<String> getLinkContent(Link link) async =>
      List.filled(20 + link.path2.length * 3, 'מילה בפירוש').join(' ');

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}
