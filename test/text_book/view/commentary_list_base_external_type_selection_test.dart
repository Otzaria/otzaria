// סינון לפי סוג כשהבחירה מנוהלת ע"י ההורה (כרטיסיית המפרשים), ולא בפאנל
// הפנימי של CommentaryListBase. זו הזרימה שנשברה: הצ׳יפים הוצגו בלשונית
// הצדדית אך לא היו מחוברים לסינון הרשימה, ולכן לחיצה עליהם לא עשתה כלום.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentary_type_filter.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'ספר 0',
          categoryId: 1,
          fileType: 'txt',
        ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
  });

  group('בחירת סוגים חיצונית מסננת את הרשימה', () {
    testWidgets('בלי בחירה — כל המפרשים מוצגים', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      await _pump(tester, selection: selection);

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
      expect(find.text('ספר 2'), findsOneWidget);
    });

    testWidgets('בחירת "תרגום" מסתירה את שאר הסוגים', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      await _pump(tester, selection: selection);

      selection.value = const {LinkTypes.targum};
      await tester.pumpAndSettle();

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsNothing);
      expect(find.text('ספר 2'), findsNothing);
    });

    testWidgets('בחירת שני סוגים = איחוד', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      await _pump(tester, selection: selection);

      selection.value = const {LinkTypes.targum, LinkTypes.midrash};
      await tester.pumpAndSettle();

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
      expect(find.text('ספר 2'), findsNothing);
    });

    testWidgets('ביטול הבחירה מחזיר את כל המפרשים', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      await _pump(tester, selection: selection);

      selection.value = const {LinkTypes.targum};
      await tester.pumpAndSettle();
      expect(find.text('ספר 2'), findsNothing);

      selection.value = const {};
      await tester.pumpAndSettle();

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
      expect(find.text('ספר 2'), findsOneWidget);
    });

    testWidgets('בחירת סוג שאין לו קישור מציגה הודעת ריק', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      await _pump(
        tester,
        selection: selection,
        types: const ['TARGUM', 'MIDRASH'],
      );

      selection.value = const {LinkTypes.midrash};
      await tester.pumpAndSettle();

      expect(find.text('ספר 0'), findsNothing);
      expect(find.text('ספר 1'), findsOneWidget);
    });

    testWidgets('בחירת סוג שאינו קיים כלל אינה מסתירה דבר', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      await _pump(
        tester,
        selection: selection,
        types: const ['TARGUM', 'MIDRASH'],
      );

      // לפרשנות אין קישור בקטע, ולכן הבחירה אינה אפקטיבית = הצג הכל.
      selection.value = const {LinkTypes.parshanut};
      await tester.pumpAndSettle();

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
    });

    testWidgets('EXPLICATION נתפס ע"י בחירת ELUCIDATION', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      await _pump(
        tester,
        selection: selection,
        types: const ['EXPLICATION', 'COMMENTARY'],
      );

      selection.value = const {LinkTypes.elucidation};
      await tester.pumpAndSettle();

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsNothing);
    });

    testWidgets('הבחירה שורדת מעבר לקטע אחר', (tester) async {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      final bloc = await _pump(tester, selection: selection);

      selection.value = const {LinkTypes.targum};
      await tester.pumpAndSettle();

      bloc.emitState(_stateWithTypes(const ['TARGUM', 'MIDRASH']));
      await tester.pumpAndSettle();

      expect(selection.value, {LinkTypes.targum});
      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsNothing);
    });
  });

  group('מצב מקומי כשההורה אינו מנהל את הבחירה', () {
    testWidgets('בלי typeSelection הרשימה עדיין נבנית ומציגה הכל', (
      tester,
    ) async {
      await _pump(tester, selection: null);

      expect(find.text('ספר 0'), findsOneWidget);
      expect(find.text('ספר 1'), findsOneWidget);
      expect(find.text('ספר 2'), findsOneWidget);
    });
  });
}

Future<_TestTextBookBloc> _pump(
  WidgetTester tester, {
  required CommentaryTypeSelection? selection,
  List<String> types = const ['TARGUM', 'MIDRASH', 'COMMENTARY'],
}) async {
  final bloc = _TestTextBookBloc(_stateWithTypes(types));
  addTearDown(() async => bloc.close());
  final settingsBloc = _TestSettingsBloc(SettingsState.initial());
  addTearDown(() async => settingsBloc.close());

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

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
              openBookCallback: _noopOpenBook,
              fontSize: 18,
              showSearch: true,
              shrinkWrap: false,
              onSelectedCommentatorsOverrideChanged: (_) {},
              typeSelection: selection,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
  return bloc;
}

void _noopOpenBook(_) {}

Link _link({required String path2, required String type, int index1 = 1}) =>
    Link(
      heRef: 'בראשית א',
      index1: index1,
      path2: path2,
      index2: 1,
      connectionType: type,
      targetCategoryId: 1,
      targetFileType: 'txt',
    );

TextBookLoaded _stateWithTypes(List<String> types) {
  final links = [
    for (var i = 0; i < types.length; i++)
      _link(path2: 'ספר $i.txt', type: types[i]),
  ];
  final titles = [for (var i = 0; i < types.length; i++) 'ספר $i'];

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: titles,
    commentatorGroups: [
      CommentatorGroup(title: 'ראשונים', commentators: titles),
    ],
    availableCommentators: titles,
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

  void emitState(TextBookState state) => emit(state);

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
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => {'ספר 0|1|txt'};

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => null;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async => const [];

  @override
  Future<String> getLinkContent(Link link) async => 'תוכן לבדיקה';

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}
