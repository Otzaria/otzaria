import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// issue #530: מעבר בעלות בחירה לאזור אחר לא יהרוס את ה-SelectionArea של
/// המפרשים כשאין להם בחירה משלהם (ההריסה איפסה את הרשימה ואת מצב הבחירה
/// באמצע אינטראקציה, מה ששבר את ההעתקה במצב 'מפרשים מתחת').
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

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

  testWidgets('בעלות חיצונית בלי בחירה משלנו — ה-SelectionArea לא נבנה מחדש', (
    tester,
  ) async {
    final controller = SelectionSyncController();
    addTearDown(controller.dispose);

    await _pump(
      tester,
      textBookBloc: textBookBloc,
      settingsBloc: settingsBloc,
      controller: controller,
    );

    final keyBefore = tester.widget(_selectionAreaFinder()).key;

    // אזור אחר (הטקסט הראשי) תופס בעלות בזמן שאין בחירה במפרשים.
    controller.activate(Object());
    await tester.pump();

    expect(tester.widget(_selectionAreaFinder()).key, keyBefore);
  });

  testWidgets(
    'בעלות חיצונית כשיש בחירה משלנו — ה-SelectionArea מתנקה ב-rebuild',
    (tester) async {
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
        controller: controller,
      );

      final keyBefore = tester.widget(_selectionAreaFinder()).key;

      // בחירת כל הטקסט במפרשים — הופכת את הפאנל לבעל הבחירה.
      final region = tester.state<SelectableRegionState>(
        find.descendant(
          of: _selectionAreaFinder(),
          matching: find.byType(SelectableRegion),
        ),
      );
      region.selectAll();
      await _pumpUntil(tester, () => controller.activeOwner != null);
      expect(controller.activeOwner, isNotNull);

      // אזור אחר תופס בעלות — עכשיו כן צריך rebuild כדי לנקות את הבחירה.
      controller.activate(Object());
      await tester.pump();

      expect(tester.widget(_selectionAreaFinder()).key, isNot(keyBefore));
    },
  );
}

Finder _selectionAreaFinder() => find.byWidgetPredicate(
  (w) =>
      w is SelectionArea &&
      (w.key is ValueKey<String>) &&
      (w.key as ValueKey<String>).value.startsWith('commentary_list_'),
);

/// שואב פריימים עד שהתנאי מתקיים או שנגמרו הניסיונות. עמיד יותר מ-
/// `pumpAndSettle` כשתוכן נטען דרך Future (שעלול להיפתר אחרי ש-settle חוזר).
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTries = 80,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
  required SelectionSyncController controller,
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
            showSearch: false,
            shrinkWrap: false,
            selectionSyncController: controller,
          ),
        ),
      ),
    ),
  );

  // תוכן המפרשים (הקבוצות והטקסט) נטען אסינכרונית; ה-SelectionArea נבנה רק
  // אחרי שהקבוצות נפתרות, והטקסט לבחירה רק אחרי טעינת ה-content.
  await _pumpUntil(
    tester,
    () =>
        _selectionAreaFinder().evaluate().isNotEmpty &&
        find
            .textContaining('פירוש לבדיקה', findRichText: true)
            .evaluate()
            .isNotEmpty,
  );
  expect(_selectionAreaFinder(), findsOneWidget);
}

TextBookLoaded _loadedState() {
  final link = Link(
    heRef: 'בראשית א',
    index1: 1,
    path2: 'מפרש בדיקה.txt',
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
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
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
    return {'מפרש בדיקה|1|txt'};
  }

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
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
