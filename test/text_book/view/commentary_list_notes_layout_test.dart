import 'package:flutter/gestures.dart';
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
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// רגרסיה לבאג החיתוך: כש'הערות' פעיל לצד מפרשים, חלונית "הערות + מפרשים"
/// חילקה את הגובה 50/50 (Flexible+Expanded שניהם flex:1), כך שרשימת המפרשים
/// קיבלה רק חצי מהגובה ונותר חלל ריק מתחתיה. התיקון: "הערות" מוגבל לגובה
/// התוכן שלו (עד ~45%), והמפרשים מקבלים את כל השאר. הבדיקה מודדת את גובה ה-
/// ScrollablePositionedList של המפרשים ומוודאת שהוא תופס את רוב הגובה.
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

    textBookBloc = _TestTextBookBloc(_loadedStateWithNotesAndCommentary());
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  testWidgets(
    'הערות פעיל + מפרשים: רשימת המפרשים מקבלת את רוב הגובה (ללא חלוקת 50/50)',
    (tester) async {
      const panelHeight = 600.0;

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  height: panelHeight,
                  width: 500,
                  child: CommentaryListBase(
                    openBookCallback: (_) {},
                    fontSize: 18,
                    showSearch: true,
                    shrinkWrap: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ודא שמצב "הערות" אכן פעיל (גוף ההערה מוצג ב-RichText) — אחרת אין
      // חלוקת גובה והבדיקה הייתה עוברת באופן ריק.
      expect(
        find.textContaining('הערה לבדיקה', findRichText: true),
        findsWidgets,
        reason: 'מצב ההערות חייב להיות פעיל כדי לשחזר את הבאג',
      );

      final spl = find.byType(ScrollablePositionedList);
      expect(
        spl,
        findsOneWidget,
        reason: 'רשימת המפרשים (ScrollablePositionedList) חייבת להופיע',
      );

      final splHeight = tester.getSize(spl).height;

      // עם הבאג (50/50) הרשימה קיבלה ~45% מהגובה (~270). עם התיקון היא מקבלת
      // את כל השאר (~80%). סף 60% מפריד בבירור בין השניים.
      expect(
        splHeight,
        greaterThan(panelHeight * 0.6),
        reason:
            'רשימת המפרשים תפסה רק ${splHeight.toStringAsFixed(0)} מתוך '
            '$panelHeight — סימן שחזרה חלוקת ה-50/50 (חיתוך + חלל ריק)',
      );
    },
  );

  testWidgets('תוכן ההערות עטוף ב-SelectionArea (בחירת טקסט אפשרית)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: Center(
              child: SizedBox(
                height: 600,
                width: 500,
                child: CommentaryListBase(
                  openBookCallback: (_) {},
                  fontSize: 18,
                  showSearch: true,
                  shrinkWrap: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final noteText = find
        .textContaining('הערה לבדיקה', findRichText: true)
        .first;
    expect(
      noteText,
      findsOneWidget,
      reason: 'גוף ההערה חייב להיות מוצג כדי לבדוק את הבחירה',
    );

    // רגרסיה: ההערות הוחזרו בעבר מחוץ ל-SelectionArea של רשימת המפרשים,
    // ולכן לא ניתן היה לבחור בהן טקסט כלל.
    expect(
      find.ancestor(of: noteText, matching: find.byType(SelectionArea)),
      findsWidgets,
      reason: 'תוכן ההערות חייב להיות בתוך SelectionArea כדי לאפשר בחירה',
    );
  });

  testWidgets('תפריט ההקשר בהערות כולל "דווח על טעות בספר"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: Center(
              child: SizedBox(
                height: 600,
                width: 500,
                child: CommentaryListBase(
                  openBookCallback: (_) {},
                  fontSize: 18,
                  showSearch: true,
                  shrinkWrap: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final noteText = find
        .textContaining('הערה לבדיקה', findRichText: true)
        .first;
    final gesture = await tester.startGesture(
      tester.getCenter(noteText),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.text('דווח על טעות בספר'),
      findsOneWidget,
      reason: 'תפריט ההקשר של ההערות חייב לאפשר דיווח על טעות בספר הראשי',
    );
  });
}

TextBookLoaded _loadedStateWithNotesAndCommentary() {
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
    // שורה עם הערת שוליים inline → notesForLines מחזיר גוף הערה קצר,
    // ולכן notesWidget הוא ה-_NotesCommentaryWidget הקטן (המקרה שחשף את הבאג).
    content: const ['<i class="footnote">הערה לבדיקה</i>גוף הפסוק'],
    fontSize: 18,
    showSplitView: false,
    // 'הערות' פעיל (→ notesIsActive) לצד מפרש אמיתי (→ רשימת מפרשים לא ריקה).
    activeCommentators: const ['מפרש בדיקה', kNotesCommentatorTitle],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה', kNotesCommentatorTitle],
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
