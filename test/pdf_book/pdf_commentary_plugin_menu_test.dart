// פריטי תפריט ההקשר של תוספים בלחיצה ימנית על מפרש בחלונית המפרשים של PDF.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
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
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/context_menu_description.dart';
import '../test_helpers/plugin_menu_click_recorder.dart';
import '../test_helpers/stub_settings_bloc.dart';

const _kCommentator = 'מפרש בדיקת תפריט PDF';
const _kContent = 'פירוש לבדיקת תפריט התוספים';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PluginMenuClickRecorder recorder;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    final provider = _FakeLibraryProvider();
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: _kCommentator,
          categoryId: 1,
          fileType: 'txt',
        ): provider,
      },
      providers: [provider],
    );
    BookProtectionRepository.instance.debugRepositoryFor = (_) async => null;
    recorder = PluginMenuClickRecorder('test.commentary')
      ..register('place', 'פעולה על המפרש', ['reader-commentary'])
      ..register('text', 'פעולה על הסימון', ['reader-commentary-selection']);
    ContextMenuRegistry.instance.registerPayload('test.pdf', {
      'id': 'page',
      'title': 'פעולה על העמוד',
      'contexts': ['reader-pdf'],
    });
  });

  tearDown(() {
    ContextMenuRegistry.instance.removeAll('test.pdf');
    BookProtectionRepository.instance.debugReset();
    LibraryProviderManager.instance.resetForTesting();
  });

  Future<List<AppContextMenuEntry> Function()> pumpPanel(
    WidgetTester tester,
  ) async {
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: '/books/ספר בדיקה.pdf'),
      pageNumber: 4,
    );
    addTearDown(tab.dispose);
    tab.currentTextLineNumber = 10;
    tab.currentTextLineNumberEnd = 40;
    tab.links = [
      Link(
        heRef: '$_kCommentator, א',
        index1: 12,
        path2: '$_kCommentator.txt',
        index2: 6,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      ),
    ];
    tab.activeCommentators = {_kCommentator};

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: StubSettingsBloc()),
            BlocProvider<PersonalNotesBloc>.value(
              value: _FakePersonalNotesBloc(),
            ),
          ],
          child: recorder.wrap(
            Scaffold(
              body: PdfCommentaryPanel(
                displayProfile: TextDisplayProfile.defaults,
                tab: tab,
                linksCount: tab.links.length,
                openBookCallback: (_) {},
                fontSize: 16,
                commentaryGroupsLoader: (links) async => [
                  LinkGroup(bookTitle: _kCommentator, links: links),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final regionFinder = find
        .ancestor(
          of: find.textContaining(_kContent),
          matching: find.byType(AppContextMenuRegion),
        )
        .first;
    return () => tester
        .widget<AppContextMenuRegion>(regionFinder)
        .menuBuilder(
          tester.element(regionFinder),
          tester.getCenter(regionFinder),
        );
  }

  testWidgets('בלי סימון — המפרש הוא הספר, וה-PDF נמסר עם מספר העמוד', (
    tester,
  ) async {
    final menu = (await pumpPanel(tester))();
    final labels = describeContextMenu(menu);
    expect(labels.sublist(labels.length - 2), ['---', 'פעולה על המפרש']);
    expect(labels, isNot(contains('פעולה על העמוד')));

    final payload = await recorder.click(tester, menu.last);
    expect(payload['currentBook'], _kCommentator);
    expect(payload['currentIndex'], 5);
    final mainBook = (payload['selection'] as Map)['mainBook'] as Map;
    expect(mainBook['bookTitle'], 'ספר בדיקה');
    expect(mainBook['type'], 'pdf');
    expect(mainBook['pageNumber'], 4);
    expect(mainBook['sectionIndex'], 4);
    expect(mainBook['currentRef'], 'עמוד 4');
  });

  testWidgets('עם סימון — פריט reader-commentary-selection מקבל את הטקסט', (
    tester,
  ) async {
    final buildMenu = await pumpPanel(tester);
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();

    final menu = buildMenu();
    expect(describeContextMenu(menu).last, 'פעולה על הסימון');
    final payload = await recorder.click(tester, menu.last);
    expect(payload['selectedText'], contains(_kContent));
  });
}

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
  Future<String> getLinkContent(Link link) async => _kContent;

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      title == _kCommentator;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}
