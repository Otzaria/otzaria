// פריטי תפריט ההקשר של תוספים בלחיצה ימנית על מפרש ברשימת המפרשים.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../../test_helpers/context_menu_description.dart';
import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/plugin_menu_click_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late _TestSettingsBloc settingsBloc;
  late PluginMenuClickRecorder recorder;

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): FakeCommentaryLibraryProvider(),
      },
      providers: [FakeCommentaryLibraryProvider()],
    );
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
    BookProtectionRepository.instance.debugRepositoryFor = (_) async => null;
    recorder = PluginMenuClickRecorder('test.commentary')
      ..register('place', 'פעולה על המפרש', ['reader-commentary'])
      ..register('text', 'פעולה על הסימון', ['reader-commentary-selection']);
    ContextMenuRegistry.instance.registerPayload('test.legacy', {
      'id': 'legacy',
      'title': 'פעולה על הטקסט',
    });
  });

  tearDown(() async {
    ContextMenuRegistry.instance.removeAll('test.legacy');
    BookProtectionRepository.instance.debugReset();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  Future<AppContextMenuRegion Function()> pumpList(WidgetTester tester) async {
    final link = Link(
      heRef: 'מפרש בדיקה, ג ב',
      index1: 1,
      path2: 'מפרש בדיקה.txt',
      index2: 3,
      connectionType: 'commentary',
      targetCategoryId: 1,
      targetFileType: 'txt',
    );
    final bloc = _TestTextBookBloc(_loadedState(links: [link]));
    addTearDown(() async => bloc.close());
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
          child: recorder.wrap(
            Scaffold(
              body: CommentaryListBase(
                openBookCallback: (_) {},
                fontSize: 18,
                showSearch: false,
                shrinkWrap: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find
        .ancestor(
          of: find.text(_kFakeContent),
          matching: find.byType(AppContextMenuRegion),
        )
        .first;
    return () => tester.widget<AppContextMenuRegion>(finder);
  }

  List<AppContextMenuEntry> menuOf(
    WidgetTester tester,
    AppContextMenuRegion region,
  ) {
    final element = tester.element(find.byWidget(region));
    return region.menuBuilder(element, tester.getCenter(find.byWidget(region)));
  }

  testWidgets('בלי סימון — פריט reader-commentary מקבל את המפרש ואת הספר', (
    tester,
  ) async {
    final region = await pumpList(tester);
    final menu = menuOf(tester, region());
    final labels = describeContextMenu(menu);
    expect(labels.sublist(labels.length - 2), ['---', 'פעולה על המפרש']);
    expect(labels, isNot(contains('פעולה על הטקסט')));

    final payload = await recorder.click(tester, menu.last);
    expect(payload['currentBook'], 'מפרש בדיקה');
    expect(payload['currentIndex'], 2);
    expect(payload['selectedText'], isEmpty);
    final mainBook = (payload['selection'] as Map)['mainBook'] as Map;
    expect(mainBook['bookTitle'], 'ספר בדיקה');
    expect(mainBook['sectionIndex'], 0);
  });

  testWidgets('עם סימון — פריט reader-commentary-selection מקבל את הטקסט', (
    tester,
  ) async {
    final region = await pumpList(tester);
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();

    final menu = menuOf(tester, region());
    expect(describeContextMenu(menu).last, 'פעולה על הסימון');
    final payload = await recorder.click(tester, menu.last);
    expect(payload['selectedText'], contains('זהו פירוש לבדיקה'));
    expect(payload['currentBook'], 'מפרש בדיקה');
  });
}

const _kFakeContent = 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';

TextBookLoaded _loadedState({required List<Link> links}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const ['מפרש בדיקה'],
  commentatorGroups: const [],
  availableCommentators: const ['מפרש בדיקה'],
  links: links,
  visibleLinks: const [],
  linksByLine: {
    for (final link in links) link.index1: [link],
  },
  tableOfContents: [TocEntry(text: 'ג ב', index: 0)],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

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
