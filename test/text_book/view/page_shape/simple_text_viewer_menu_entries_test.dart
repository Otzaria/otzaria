import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../../../test_helpers/context_menu_description.dart';
import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/plugin_menu_click_recorder.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// Pins every entry of the page shape view's context menus, so that sharing
/// their code with the combined view cannot change them unnoticed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() => TargetLineLinksService.resetInstanceForTesting());

  Future<List<String>> menuFor(
    WidgetTester tester, {
    TextBook? book,
    List<String> availableCommentators = const [],
    bool isMainText = true,
    TextBook? reportBook,
    List<String> content = const ['שורה א'],
    Map<int, List<Link>> anchorLinksByLine = const {},
    int? selectLine,
    PluginMenuClickRecorder? recorder,
    void Function(List<AppContextMenuEntry> entries)? onMenu,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bloc = _TextBookBloc(
      _loadedState(
        book: book ?? TextBook(title: 'ספר בדיקה'),
        availableCommentators: availableCommentators,
      ),
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final notesBloc = StubPersonalNotesBloc(const PersonalNotesState.initial());
    addTearDown(() async {
      await bloc.close();
      await settingsBloc.close();
      await notesBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: (recorder?.wrap ?? (Widget child) => child)(
            Scaffold(
              body: SimpleTextViewer(
                content: content,
                fontSize: 18,
                openBookCallback: (_) {},
                isMainText: isMainText,
                bookTitle: isMainText ? null : 'רש"י על ספר בדיקה',
                reportBook: reportBook,
                anchorLinksByLine: anchorLinksByLine,
                onOpenCommentatorsPane: () {},
                onOpenCommentatorsPaneWithFilter: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final regionFinder = find.byType(AppContextMenuRegion).at(selectLine ?? 0);
    if (selectLine != null) {
      final renderedText = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .map((paragraph) => paragraph.text.toPlainText())
          .singleWhere(
            (text) => text.contains(content[selectLine].split(' ').first),
          );
      expect(renderedText, contains('(ז)'));
      tester
          .widget<SelectableRegion>(find.byType(SelectableRegion))
          .onSelectionChanged!(SelectedContent(plainText: renderedText));
      await tester.pump();
    }
    List<String> build() {
      final region = tester.widget<AppContextMenuRegion>(regionFinder);
      final entries = region.menuBuilder(
        tester.element(regionFinder),
        tester.getCenter(regionFinder),
      );
      onMenu?.call(entries);
      return describeContextMenu(entries);
    }

    // The first build starts loading the paragraph's commentators and links.
    build();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    return build();
  }

  testWidgets('main text without a selection', (tester) async {
    expect(await menuFor(tester), [
      '[חיפוש (disabled) | העתקה (disabled) | הערה]',
      'העתק כ... (disabled)',
      '  ניקוד (disabled) [x]',
      '  טעמים (disabled) [x]',
      '  פיסוק (disabled) [x]',
      '  שם הוי"ה ככתבו (disabled)',
      '  ציוני המפרשים (disabled) [x]',
      '  ---',
      '  העתק (disabled)',
      '  כמו בתצוגה (disabled)',
      '---',
      'חיפוש',
      'מפרשים על פסקה זו (disabled)',
      'קישורים (disabled)',
      '---',
      'הוסף סימניה לקטע זה',
      'דווח על טעות בספר',
      '---',
      'העתק את כל הפסקה',
    ]);
  });

  testWidgets('main text of an official book with commentators', (
    tester,
  ) async {
    expect(
      await menuFor(
        tester,
        book: TextBook(title: 'ספר בדיקה', id: 7),
        availableCommentators: const ['רש"י', 'רמב"ן'],
      ),
      [
        '[חיפוש (disabled) | העתקה (disabled) | הערה | קישור >]',
        'העתק כ... (disabled)',
        '  ניקוד (disabled) [x]',
        '  טעמים (disabled) [x]',
        '  פיסוק (disabled) [x]',
        '  שם הוי"ה ככתבו (disabled)',
        '  ציוני המפרשים (disabled) [x]',
        '  ---',
        '  העתק (disabled)',
        '  כמו בתצוגה (disabled)',
        '---',
        'חיפוש',
        'מפרשים על פסקה זו',
        '  בחר מפרשים מרובים',
        '  ---',
        '  הצג את כל המפרשים על פסקה זו',
        '  ---',
        '  הצג את כל ראשונים',
        '  רש"י',
        '  רמב"ן',
        'קישורים (disabled)',
        '---',
        'הוסף סימניה לקטע זה',
        'דווח על טעות בספר',
        '---',
        'העתק את כל הפסקה',
      ],
    );
  });

  testWidgets('a commentary column', (tester) async {
    expect(await menuFor(tester, isMainText: false), [
      // Same icon row, in the same order, as the combined view's commentary.
      '[חיפוש (disabled) | העתקה (disabled) | הערה]',
      'העתק כ... (disabled)',
      '  ניקוד (disabled) [x]',
      '  טעמים (disabled) [x]',
      '  פיסוק (disabled) [x]',
      '  שם הוי"ה ככתבו (disabled)',
      '  ציוני המפרשים (disabled) [x]',
      '  ---',
      '  העתק (disabled)',
      '  כמו בתצוגה (disabled)',
      '---',
      'דווח על טעות בספר',
      '---',
      'העתק את כל הפסקה',
    ]);
  });

  testWidgets('a commentary column with a book id offers the link icon', (
    tester,
  ) async {
    final menu = await menuFor(
      tester,
      isMainText: false,
      reportBook: TextBook(title: 'רש"י על ספר בדיקה', id: 9),
    );
    expect(
      menu.first,
      '[חיפוש (disabled) | העתקה (disabled) | הערה | קישור >]',
    );
    expect(menu, isNot(contains('העתק קישור ישיר')));
  });

  for (final source in [BookSource.official, BookSource.attached('test-db')]) {
    testWidgets(
      'commentary link highlights source text from ${source.wireKey}',
      (
        tester,
      ) async {
        const sourceText = 'בראשית ברא העולם';
        final checkedSources = <BookSource>[];
        BookProtectionRepository.instance.debugRepositoryFor = (source) async {
          checkedSources.add(source);
          return null;
        };
        addTearDown(BookProtectionRepository.instance.debugReset);

        late List<AppContextMenuEntry> entries;
        await menuFor(
          tester,
          isMainText: false,
          reportBook: TextBook(title: 'פירוש בדיקה', id: 9, source: source),
          content: const ['שורה קודמת', sourceText],
          anchorLinksByLine: {
            2: [
              Link(
                heRef: 'שער הציון, ז',
                index1: 2,
                index2: 1,
                path2: 'שער הציון',
                connectionType: 'commentary',
                anchorStart: 7,
                anchorLabel: 'ז',
              ),
            ],
          },
          selectLine: 1,
          onMenu: (menu) => entries = menu,
        );
        String? clipboard;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        entries.first.iconRowActions!
            .singleWhere((action) => action.label == 'קישור')
            .submenuBuilder!()
            .singleWhere((action) => action.label.contains('הדגשת הטקסט'))
            .onTap!();
        await tester.pumpAndSettle();

        final link = Uri.parse(clipboard!);
        expect(link.path, '/book/9');
        expect(link.queryParameters['index'], '1');
        expect(
          link.queryParameters['source'],
          source.isAttached ? 'db:test-db' : null,
        );
        expect(link.queryParameters['m'], sourceText);
        expect(checkedSources, [source]);
      },
    );
  }

  testWidgets('a commentary column gives reader-commentary items its line', (
    tester,
  ) async {
    final recorder = PluginMenuClickRecorder('test.commentary')
      ..register('place', 'פעולה על המפרש', ['reader-commentary']);
    ContextMenuRegistry.instance.registerPayload('test.legacy', {
      'id': 'legacy',
      'title': 'פעולה על הטקסט',
    });
    addTearDown(() => ContextMenuRegistry.instance.removeAll('test.legacy'));

    late List<AppContextMenuEntry> entries;
    final menu = await menuFor(
      tester,
      isMainText: false,
      recorder: recorder,
      onMenu: (e) => entries = e,
    );
    expect(menu.sublist(menu.length - 2), ['---', 'פעולה על המפרש']);
    expect(menu, isNot(contains('פעולה על הטקסט')));

    final payload = await recorder.click(tester, entries.last);
    expect(payload['currentBook'], 'רש"י על ספר בדיקה');
    expect(payload['currentIndex'], 0);
    final mainBook = (payload['selection'] as Map)['mainBook'] as Map;
    expect(mainBook['bookTitle'], 'ספר בדיקה');
    expect(mainBook.containsKey('sectionIndex'), isFalse);
  });
}

Link _commentaryLink(String title) => Link(
  heRef: '',
  index1: 1,
  path2: title,
  index2: 1,
  connectionType: 'commentary',
);

TextBookLoaded _loadedState({
  required TextBook book,
  required List<String> availableCommentators,
}) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: const ['שורה א'],
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: const [],
  commentatorGroups: [
    if (availableCommentators.isNotEmpty)
      CommentatorGroup(title: 'ראשונים', commentators: availableCommentators),
  ],
  availableCommentators: availableCommentators,
  links: const [],
  visibleLinks: const [],
  linksByLine: {
    1: [for (final title in availableCommentators) _commentaryLink(title)],
  },
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  searchText: '',
);

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  late final TextBookRepository repository = _TextBookRepository(
    (state as TextBookLoaded).availableCommentators,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
  _TextBookRepository(this.commentators);

  final List<String> commentators;

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => [for (final title in commentators) _commentaryLink(title)];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
