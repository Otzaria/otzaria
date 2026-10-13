// issue #2326: בכרטיסיית המפרשים (useAvailableCommentators) הסדר חייב להיות
// סדר רשימת הבחירה (דורות, בסיסיים ראשונים) ולא א"ב של availableCommentators.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
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
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _rashi = 'רש"י על ברכות';
const _tosafot = 'תוספות על ברכות';
const _chavruta = 'חברותא על ברכות';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    final provider = _FakeLibraryProvider();
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in [_rashi, _tosafot, _chavruta])
          BookCompositeKey.create(title: title, categoryId: 1, fileType: 'txt'):
              provider,
      },
      providers: [provider],
    );
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
  });

  testWidgets('כל המפרשים מוצגים בסדר הקבוצות ולא לפי א"ב', (tester) async {
    final bloc = _TestTextBookBloc(_state());
    addTearDown(() async => bloc.close());
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    addTearDown(() async => settingsBloc.close());

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: const Scaffold(
            body: CommentaryListBase(
              openBookCallback: _noopOpenBook,
              fontSize: 18,
              showSearch: false,
              shrinkWrap: false,
              useAvailableCommentators: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double topOf(String title) =>
        tester.getTopLeft(find.textContaining(title).first).dy;

    expect(topOf(_rashi), lessThan(topOf(_tosafot)));
    expect(topOf(_tosafot), lessThan(topOf(_chavruta)));
  });
}

void _noopOpenBook(_) {}

TextBookLoaded _state() {
  Link linkTo(String title) => Link(
    heRef: 'ברכות ב א',
    index1: 1,
    path2: '$title.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );
  final links = [linkTo(_chavruta), linkTo(_rashi), linkTo(_tosafot)];

  return TextBookLoaded(
    book: TextBook(title: 'ברכות'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [
      CommentatorGroup(title: 'ראשונים', commentators: [_rashi, _tosafot]),
      CommentatorGroup(title: 'מחברי זמננו', commentators: [_chavruta]),
    ],
    availableCommentators: const [_chavruta, _rashi, _tosafot],
    links: links,
    visibleLinks: const [],
    linksByLine: {1: links},
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
    return {
      for (final t in [_rashi, _tosafot, _chavruta]) '$t|1|txt',
    };
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
  Future<String> getLinkContent(Link link) async => 'פירוש לבדיקה';

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return true;
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
