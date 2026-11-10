import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';
import 'package:otzaria/widgets/commentary/panel_anchor_links.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

/// קישור לשורה 5 וקישור לשורות 5–7 של אותו ספר הם שני פריטים ברשימת הקישורים,
/// וכל אחד מהם מציג בפתיחה את תוכן הטווח שלו — בכרטיסיית הטקסט ובחלונית ה-PDF.

const _bookTitle = 'ראשונים א';
const _singleContent = 'פירוש שורה 5';
const _rangeContent = 'פירוש שורה 5<br>פירוש שורה 6<br>פירוש שורה 7';

class _LineContentProvider extends Fake implements LibraryProvider {
  @override
  bool get isInitialized => false;

  @override
  Future<String> getLinkContent(Link link) async => 'פירוש שורה ${link.index2}';
}

Link _link({int? index2End}) => Link(
  heRef: index2End == null ? '$_bookTitle, ה' : '$_bookTitle, ה-ז',
  index1: 12,
  path2: '/books/$_bookTitle.txt',
  index2: 5,
  index2End: index2End,
  connectionType: 'reference',
);

Future<void> _pumpTextReader(WidgetTester tester, List<Link> links) async {
  final bloc = StubTextBookBloc(
    TextBookLoaded(
      book: TextBook(title: 'ספר בדיקה'),
      showLeftPane: false,
      content: const ['שורה א'],
      fontSize: 18,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: links,
      visibleLinks: links,
      selectedLinkTypes: const {},
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [0],
      selectedIndex: 0,
      pinLeftPane: false,
      searchText: '',
    ),
  );
  addTearDown(bloc.close);
  final settings = StubSettingsBloc(SettingsState.initial());
  addTearDown(settings.close);

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: bloc),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: SelectedLineLinksView(
              openBookCallback: (_) {},
              fontSize: 18,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPdfReader(WidgetTester tester, List<Link> links) async {
  final tab = PdfBookTab(
    book: PdfBook(title: 'ספר בדיקה', path: '/books/ספר בדיקה.pdf'),
    pageNumber: 1,
  );
  addTearDown(tab.dispose);
  tab.currentTextLineNumber = 10;
  tab.currentTextLineNumberEnd = 40;
  tab.links = links;
  final settings = StubSettingsBloc(SettingsState.initial());
  addTearDown(settings.close);
  final notes = StubPersonalNotesBloc();
  addTearDown(notes.close);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
        ],
        child: Scaffold(
          body: PdfCommentaryPanel(
            tab: tab,
            linksCount: links.length,
            linksLoading: false,
            openBookCallback: (_) {},
            fontSize: 16.0,
            initialTabIndex: 1,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tileOf(Link link) =>
    find.byKey(PageStorageKey<String>(buildSelectedLinkInstanceKey(link)));

Future<void> _expand(WidgetTester tester, Link link) async {
  await tester.tap(
    find.descendant(of: _tileOf(link), matching: find.text(_bookTitle)),
  );
  await tester.pumpAndSettle();
}

String _shownContent(WidgetTester tester, Link link) => tester
    .widget<PanelAnchoredText>(
      find.descendant(
        of: _tileOf(link),
        matching: find.byType(PanelAnchoredText),
      ),
    )
    .html;

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {},
      providers: [_LineContentProvider()],
    );
    Link.clearContentCache();
    CommentaryService.seedEraCache(const {
      _bookTitle: CommentaryEra.rishonim,
    });
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
    Link.clearContentCache();
    CommentaryService.clearEraCache();
  });

  final readers = {'טקסט': _pumpTextReader, 'PDF': _pumpPdfReader};
  for (final reader in readers.entries) {
    for (final rangeFirst in [false, true]) {
      testWidgets(
        '${reader.key}: קישור לשורה וקישור לטווח מאותה שורה מציגים כל אחד את '
        'תוכנו (קישור ${rangeFirst ? 'הטווח' : 'השורה'} נפתח ראשון)',
        (tester) async {
          final single = _link();
          final range = _link(index2End: 7);
          await reader.value(tester, [single, range]);
          expect(_tileOf(single), findsOneWidget);
          expect(_tileOf(range), findsOneWidget);

          for (final link in rangeFirst ? [range, single] : [single, range]) {
            await _expand(tester, link);
          }

          expect(_shownContent(tester, single), _singleContent);
          expect(_shownContent(tester, range), _rangeContent);
        },
      );
    }
  }
}
