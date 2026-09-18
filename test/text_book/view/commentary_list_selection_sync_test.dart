import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// issues #530 ו-#674: מעבר בעלות בחירה בין אזורים לא יהרוס את ה-SelectionArea
/// של המפרשים. הניקוי נעשה ב-`clearSelection()` ולא בהחלפת מפתח — החלפת מפתח
/// הורסת את עץ הצאצאים, ובמצב 'מפרשים מתחת' היא מחקה את הבחירה שבמפרש והעתקה
/// יצאה ריקה.
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

    final stateBefore = _regionState(tester);

    // אזור אחר (הטקסט הראשי) תופס בעלות בזמן שאין בחירה במפרשים.
    controller.activate(Object());
    await tester.pump();

    expect(_regionState(tester), same(stateBefore));
  });

  testWidgets(
    'בעלות חיצונית כשיש בחירה משלנו — הבחירה מתנקה בלי להרוס את הרשימה',
    (tester) async {
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
        controller: controller,
      );

      final stateBefore = _regionState(tester);

      // בחירת כל הטקסט במפרשים — הופכת את הפאנל לבעל הבחירה.
      _regionState(tester).selectAll();
      await _pumpUntil(tester, () => controller.activeOwner != null);
      expect(controller.activeOwner, isNotNull);
      expect(_regionState(tester).selectionEndpoints, isNotEmpty);

      // אזור אחר תופס בעלות — הבחירה שלנו צריכה להתנקות.
      controller.activate(Object());
      await tester.pump();

      expect(
        _regionState(tester),
        same(stateBefore),
        reason:
            'ניקוי הבחירה חייב להשאיר את אותו SelectableRegion — הריסתו הייתה '
            'טוענת מחדש את המפרשים ומאבדת את מיקום הגלילה בהם',
      );
      expect(
        _hasVisibleSelection(tester),
        isFalse,
        reason: 'הבחירה עצמה כן צריכה להתנקות',
      );
    },
  );

  testWidgets(
    'מעבר בעלות חוזר לא מאבד את ה-state של רשימת המפרשים (issue #674)',
    (tester) async {
      // הלב של #674: כרטיס המפרשים מקונן בעץ של הטקסט הראשי. כל מעבר בעלות
      // שמוביל לבנייה מחדש היה משמיד את ה-State — ואיתו את הבחירה שהמשתמש
      // בדיוק סימן, כך ש-Ctrl+C נשאר בלי טקסט.
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
        controller: controller,
      );

      final listStateBefore = tester.state<CommentaryListBaseState>(
        find.byType(CommentaryListBase),
      );
      final regionBefore = _regionState(tester);

      // שלוש העברות בעלות הלוך ושוב, כולל אחת עם בחירה פעילה שלנו.
      final mainTextOwner = Object();
      controller.activate(mainTextOwner);
      await tester.pump();

      _regionState(tester).selectAll();
      await _pumpUntil(tester, () => controller.activeOwner != mainTextOwner);

      controller.activate(mainTextOwner);
      await tester.pump();
      controller.clear(mainTextOwner);
      await tester.pump();

      expect(
        tester.state<CommentaryListBaseState>(find.byType(CommentaryListBase)),
        same(listStateBefore),
      );
      expect(_regionState(tester), same(regionBefore));
    },
  );

  testWidgets(
    'ה-SelectionArea של המפרשים עטוף ב-SelectionCopyShortcuts (הגנת #674)',
    (tester) async {
      // בלי העטיפה Ctrl+C נופל להעתקת ברירת המחדל של Flutter, שכותבת ללוח את
      // הבחירה כמות שהיא — כולל מחרוזת ריקה, וזה בדיוק התסמין שדווח.
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
        controller: controller,
      );

      expect(
        find.ancestor(
          of: _selectionAreaFinder(),
          matching: find.byType(SelectionCopyShortcuts),
        ),
        findsOneWidget,
        reason: 'העטיפה חייבת להיות *מעל* ה-SelectionArea כדי ליירט',
      );
    },
  );

  testWidgets('Ctrl+C בלי בחירה אינו כותב פריט ריק ללוח (issue #674)', (
    tester,
  ) async {
    final clipboardWrites = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add(
            (call.arguments as Map?)?['text'] as String?,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final controller = SelectionSyncController();
    addTearDown(controller.dispose);

    await _pump(
      tester,
      textBookBloc: textBookBloc,
      settingsBloc: settingsBloc,
      controller: controller,
      autofocus: true,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      clipboardWrites,
      isEmpty,
      reason: 'בלי טקסט נבחר אין להעתיק כלום — ובוודאי לא מחרוזת ריקה',
    );
  });

  testWidgets('בחירת מפרש מתפרסמת ב-controller', (tester) async {
    final controller = SelectionSyncController();
    addTearDown(controller.dispose);

    await _pump(
      tester,
      textBookBloc: textBookBloc,
      settingsBloc: settingsBloc,
      controller: controller,
    );

    _regionState(tester).selectAll();
    await _pumpUntil(
      tester,
      () => controller.activeSelectionText?.trim().isNotEmpty == true,
    );

    expect(controller.activeOwner, isNotNull);
    expect(controller.activeSelectionText?.trim(), isNotEmpty);
  });

  testWidgets('פירוק חלונית מפרשים מנקה בחירה שפורסמה', (tester) async {
    final controller = SelectionSyncController();
    addTearDown(controller.dispose);

    await _pump(
      tester,
      textBookBloc: textBookBloc,
      settingsBloc: settingsBloc,
      controller: controller,
    );

    _regionState(tester).selectAll();
    await _pumpUntil(
      tester,
      () => controller.activeSelectionText?.trim().isNotEmpty == true,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(controller.activeOwner, isNull);
    expect(controller.activeSelectionText, isNull);
    expect(controller.activeSelectionLink, isNull);
  });
}

Finder _selectionAreaFinder() => find.descendant(
  of: find.byType(CommentaryListBase),
  matching: find.byWidgetPredicate(
    (w) => w is SelectionArea && w.key is GlobalKey<SelectionAreaState>,
  ),
);

SelectableRegionState _regionState(WidgetTester tester) =>
    tester.state<SelectableRegionState>(
      find.descendant(
        of: _selectionAreaFinder(),
        matching: find.byType(SelectableRegion),
      ),
    );

/// האם ל-SelectableRegion יש כרגע בחירה מוצגת. `selectionEndpoints` זורק
/// כשאין בחירה פעילה, ולכן החריגה עצמה היא התשובה.
bool _hasVisibleSelection(WidgetTester tester) {
  try {
    return _regionState(tester).selectionEndpoints.isNotEmpty;
  } catch (_) {
    return false;
  }
}

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
  bool autofocus = false,
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
            autofocus: autofocus,
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
