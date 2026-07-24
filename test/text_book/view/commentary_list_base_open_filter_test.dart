import 'package:flutter/foundation.dart';
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

  group('CommentaryListBase - openFilterRequest', () {
    testWidgets('עליה ב-counter פותחת את חלונית בחירת המפרשים', (tester) async {
      final notifier = ValueNotifier<int>(0);
      addTearDown(notifier.dispose);

      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
        openFilterRequest: notifier,
      );

      expect(find.text('בחירת מפרשים'), findsNothing);

      notifier.value++;
      await tester.pumpAndSettle();

      expect(find.text('בחירת מפרשים'), findsOneWidget);
    });

    testWidgets(
      'counter ישן (value>0 בעת init) לא פותח את חלונית הסינון אוטומטית',
      (tester) async {
        // אם המשתמש סגר את הפאנל וה-counter נשאר על 3 מהפעולה הקודמת,
        // יצירה מחודשת של ה-state לא צריכה להציג שוב את הסינון.
        final notifier = ValueNotifier<int>(3);
        addTearDown(notifier.dispose);

        await _pump(
          tester,
          textBookBloc: textBookBloc,
          settingsBloc: settingsBloc,
          openFilterRequest: notifier,
        );

        expect(find.text('בחירת מפרשים'), findsNothing);

        // עליה חדשה מעבר ל-baseline פותחת.
        notifier.value = 4;
        await tester.pumpAndSettle();

        expect(find.text('בחירת מפרשים'), findsOneWidget);
      },
    );

    testWidgets(
      'החלפת notifier מאפסת את ה-baseline — counter ישן לא חוסם בקשות עתידיות',
      (tester) async {
        final notifierA = ValueNotifier<int>(9);
        final notifierB = ValueNotifier<int>(0);
        addTearDown(notifierA.dispose);
        addTearDown(notifierB.dispose);

        await _pump(
          tester,
          textBookBloc: textBookBloc,
          settingsBloc: settingsBloc,
          openFilterRequest: notifierA,
        );
        expect(find.text('בחירת מפרשים'), findsNothing);

        // החלפה ל-notifier חדש שמתחיל מ-0.
        await _pump(
          tester,
          textBookBloc: textBookBloc,
          settingsBloc: settingsBloc,
          openFilterRequest: notifierB,
        );
        expect(find.text('בחירת מפרשים'), findsNothing);

        // אילו ה-baseline היה נשאר על 9, value=1 ב-B היה מתעלם.
        // אחרי איפוס baseline, value=1 צריך לפתוח את הסינון.
        notifierB.value = 1;
        await tester.pumpAndSettle();

        expect(find.text('בחירת מפרשים'), findsOneWidget);
      },
    );

    testWidgets('counter עולה בלי notifier (null) אינו זורק חריגה', (
      tester,
    ) async {
      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );

      expect(find.text('בחירת מפרשים'), findsNothing);
      // אין notifier — אין מה לטריגר. הטסט עובר כל עוד לא נזרקה חריגה.
    });
  });

  group('CommentaryListBase - notesIsActive prevents auto-open filter', () {
    // כאשר activeCommentators מכיל רק 'הערות', selectedCommentators הוא ריק
    // (הערות מסוננות החוצה), אך notesIsActive=true, ולכן לא צריכה להיפתח
    // חלונית בחירת המפרשים אוטומטית.

    testWidgets(
      'activeCommentators=[הערות] + onSelectedCommentatorsOverrideChanged: לא נפתח אוטומטית',
      (tester) async {
        final notesOnlyBloc = _TestTextBookBloc(
          _loadedStateWithCommentators([kNotesCommentatorTitle]),
        );
        addTearDown(() async => notesOnlyBloc.close());

        await _pumpWithOverride(
          tester,
          textBookBloc: notesOnlyBloc,
          settingsBloc: settingsBloc,
        );

        // selectedCommentators ריק (הערות מסוננות), אך notesIsActive=true
        // → אין פתיחה אוטומטית של חלונית הסינון
        expect(find.text('בחירת מפרשים'), findsNothing);
      },
    );

    testWidgets(
      'activeCommentators=[] (ריק לחלוטין) + onSelectedCommentatorsOverrideChanged: נפתח אוטומטית',
      (tester) async {
        // ביקורת: כאשר אין גם מפרשים וגם הערות, חלונית הסינון נפתחת.
        final emptyBloc = _TestTextBookBloc(_loadedStateWithCommentators([]));
        addTearDown(() async => emptyBloc.close());

        await _pumpWithOverride(
          tester,
          textBookBloc: emptyBloc,
          settingsBloc: settingsBloc,
        );

        expect(find.text('בחירת מפרשים'), findsOneWidget);
      },
    );

    testWidgets(
      'activeCommentators=[הערות, מפרש] — selectedCommentators לא ריק, לא נפתח',
      (tester) async {
        final mixedBloc = _TestTextBookBloc(
          _loadedStateWithCommentators([kNotesCommentatorTitle, 'מפרש בדיקה']),
        );
        addTearDown(() async => mixedBloc.close());

        await _pumpWithOverride(
          tester,
          textBookBloc: mixedBloc,
          settingsBloc: settingsBloc,
        );

        // selectedCommentators=['מפרש בדיקה'] (לא ריק) → אין פתיחה אוטומטית
        expect(find.text('בחירת מפרשים'), findsNothing);
      },
    );

    testWidgets(
      'activeCommentators=[הערות] + onFilterOpenRequested: נקרא פעם אחת בלבד גם תחת rebuilds',
      (tester) async {
        // כרטיסיית המפרשים פותחת את הבחירה בלשונית צד נפרדת (onFilterOpenRequested)
        // שאינה מסתירה את ההערות. לכן גם כש'הערות' פעיל ואין מפרשים נבחרים,
        // יש להעביר את המשתמש לבחירת מפרשים ולא להשאירו תקוע על "אין הערות".
        // הקולבק כאן עושה setState (כמו _openCommentatorsSelectionPane שמעדכן
        // _navPaneOpen), מה שמפעיל rebuild — ה-latch חייב למנוע קריאה חוזרת,
        // אחרת תיווצר לולאת rebuild + side-effect (pumpAndSettle יזרוק timeout).
        final notesOnlyBloc = _TestTextBookBloc(
          _loadedStateWithCommentators([kNotesCommentatorTitle]),
        );
        addTearDown(() async => notesOnlyBloc.close());

        var filterOpenCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<TextBookBloc>.value(value: notesOnlyBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
              ],
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    return CommentaryListBase(
                      openBookCallback: (_) {},
                      fontSize: 18,
                      showSearch: true,
                      shrinkWrap: false,
                      onSelectedCommentatorsOverrideChanged: (_) {},
                      onFilterOpenRequested: () {
                        filterOpenCount++;
                        setState(() {}); // מדמה את ה-setState של ההורה
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        // pump-ים נוספים — אילו ה-latch לא היה קיים, כל אחד היה מוסיף קריאה.
        await tester.pump();
        await tester.pump();

        expect(filterOpenCount, 1);
      },
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
  ValueListenable<int>? openFilterRequest,
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
            showSearch: true,
            shrinkWrap: false,
            openFilterRequest: openFilterRequest,
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
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

TextBookLoaded _loadedStateWithCommentators(List<String> active) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: active,
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה', kNotesCommentatorTitle],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
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

Future<void> _pumpWithOverride(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
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
            showSearch: true,
            shrinkWrap: false,
            // מדמה מצב override (כרטיסיית מפרשים) שבו הפאנל נפתח אוטומטית
            // כשאין מפרשים נבחרים — אלא אם notesIsActive מונע זאת.
            onSelectedCommentatorsOverrideChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
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
