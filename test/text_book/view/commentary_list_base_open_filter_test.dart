import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';

import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_text_book_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late StubTextBookBloc textBookBloc;
  late _TestSettingsBloc settingsBloc;

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

    textBookBloc = StubTextBookBloc(_loadedState());
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

  group('CommentaryListBase - links future', () {
    Future<List<Link>> currentFuture(WidgetTester tester) => tester
        .widget<FutureBuilder<List<Link>>>(
          find.byType(FutureBuilder<List<Link>>),
        )
        .future!;

    testWidgets('rebuild בלי שינוי בקלטים שומר על אותו future', (tester) async {
      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );
      final before = currentFuture(tester);

      final state = textBookBloc.state as TextBookLoaded;
      textBookBloc.emit(state.copyWith(fontSize: 20));
      await tester.pumpAndSettle();

      expect(identical(currentFuture(tester), before), isTrue);
    });

    testWidgets('שינוי בקישורים או בשורות יוצר future עם התוצאה החדשה', (
      tester,
    ) async {
      await _pump(
        tester,
        textBookBloc: textBookBloc,
        settingsBloc: settingsBloc,
      );
      final first = currentFuture(tester);
      final state = textBookBloc.state as TextBookLoaded;
      final secondLine = Link(
        heRef: 'בראשית ב',
        index1: 2,
        path2: 'מפרש בדיקה.txt',
        index2: 2,
        connectionType: 'COMMENTARY',
        targetCategoryId: 1,
        targetFileType: 'txt',
      );

      textBookBloc.emit(
        state.copyWith(
          content: const ['שורה א', 'שורה ב'],
          links: [...state.links, secondLine],
          linksByLine: {
            ...state.linksByLine,
            2: [secondLine],
          },
        ),
      );
      await tester.pumpAndSettle();
      final withNewLinks = currentFuture(tester);
      expect(identical(withNewLinks, first), isFalse);
      expect((await withNewLinks).map((l) => l.index1), [1]);

      textBookBloc.emit(
        (textBookBloc.state as TextBookLoaded).copyWith(
          visibleIndices: const [1],
          selectedIndex: 1,
        ),
      );
      await tester.pumpAndSettle();
      final withNewIndexes = currentFuture(tester);
      expect(identical(withNewIndexes, withNewLinks), isFalse);
      expect((await withNewIndexes).map((l) => l.index1), [2]);
    });
  });

  group('CommentaryListBase - notesIsActive prevents auto-open filter', () {
    // 'הערות' אינה מפרש רגיל, אבל בחירה בה עדיין מונעת פתיחה שמסתירה אותה.

    testWidgets(
      'activeCommentators=[הערות] + onSelectedCommentatorsOverrideChanged: לא נפתח אוטומטית',
      (tester) async {
        final notesOnlyBloc = StubTextBookBloc(
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
        final emptyBloc = StubTextBookBloc(_loadedStateWithCommentators([]));
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
        final mixedBloc = StubTextBookBloc(
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
        // פתיחת לשונית הבחירה בונה שוב את ההורה; ה-latch מונע לולאת פתיחות.
        final notesOnlyBloc = StubTextBookBloc(
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

  group('חלונית צד: הערות כבויות ובחירה ריקה (issue #3514)', () {
    const emptyMessage = 'לא נמצאו מפרשים לקטע הנבחר';
    final notes = (BookNotesBuilder()..add(0, 0, '*', 'הערה על שורה א'))
        .build();

    testWidgets(
      'רק "הערות" זמינות — מוצגת הודעה בקטע עם הערה ובלעדיו, וסינון שנפתח נסגר',
      (tester) async {
        TextBookLoaded at(int line) => _loadedStateWithCommentators(
          [],
          available: const [kNotesCommentatorTitle],
          bookNotes: notes,
          line: line,
        );
        final bloc = StubTextBookBloc(at(0));
        addTearDown(bloc.close);

        await _pumpWithOverride(
          tester,
          textBookBloc: bloc,
          settingsBloc: settingsBloc,
        );
        expect(find.text('בחירת מפרשים'), findsNothing);
        expect(find.text(emptyMessage), findsOneWidget);

        bloc.emit(at(1));
        await tester.pumpAndSettle();
        expect(find.text('בחירת מפרשים'), findsNothing);
        expect(find.text(emptyMessage), findsOneWidget);

        await tester.tap(find.byType(CommentatorsFilterButton));
        await tester.pumpAndSettle();
        expect(find.text('בחירת מפרשים'), findsOneWidget);
        await tester.tap(find.byTooltip('חזרה למפרשים'));
        await tester.pumpAndSettle();
        expect(find.text('בחירת מפרשים'), findsNothing);
        expect(find.text(emptyMessage), findsOneWidget);
      },
    );

    for (final delegated in [false, true]) {
      testWidgets(
        'מפרש נדיר שאינו רלוונטי מוסתר — אין פתיחה חוזרת (delegated=$delegated)',
        (tester) async {
          final bloc = StubTextBookBloc(
            _loadedStateWithCommentators([], bookNotes: notes).copyWith(
              rareCommentators: const {'מפרש בדיקה'},
              linksByLine: {
                2: [_commentaryLink(2)],
              },
            ),
          );
          addTearDown(bloc.close);
          var openRequests = 0;

          await _pumpWithOverride(
            tester,
            textBookBloc: bloc,
            settingsBloc: settingsBloc,
            onFilterOpenRequested: delegated ? () => openRequests++ : null,
          );
          expect(find.text('בחירת מפרשים'), findsNothing);
          expect(find.text(emptyMessage), findsOneWidget);
          expect(openRequests, 0);

          if (!delegated) {
            await tester.tap(find.byType(CommentatorsFilterButton));
            await tester.pumpAndSettle();
            expect(find.text('בחירת מפרשים'), findsOneWidget);
            expect(find.text('מפרש בדיקה'), findsNothing);
            expect(find.text(kNotesCommentatorTitle), findsOneWidget);
            await tester.tap(find.byTooltip('חזרה למפרשים'));
            await tester.pumpAndSettle();
            expect(find.text('בחירת מפרשים'), findsNothing);
            expect(find.text(emptyMessage), findsOneWidget);
          }
        },
      );
    }

    for (final selection in ['visible', 'multiple', 'override']) {
      testWidgets('מפרש נדיר רלוונטי ל-$selection — הבחירה נפתחת', (
        tester,
      ) async {
        final bloc = StubTextBookBloc(
          _loadedStateWithCommentators(
            [],
            bookNotes: notes,
            line: selection == 'visible' ? 1 : 0,
          ).copyWith(
            rareCommentators: const {'מפרש בדיקה'},
            selectedIndices: selection == 'multiple' ? const {0, 1} : const {},
            linksByLine: {
              2: [_commentaryLink(2)],
            },
          ),
        );
        addTearDown(bloc.close);

        await _pumpWithOverride(
          tester,
          textBookBloc: bloc,
          settingsBloc: settingsBloc,
          indexes: selection == 'override' ? const [1] : null,
        );
        expect(find.text('בחירת מפרשים'), findsOneWidget);
        expect(find.text('מפרש בדיקה'), findsOneWidget);
      });
    }

    testWidgets('יש גם מפרש רגיל לבחירה — הבחירה נפתחת אוטומטית', (
      tester,
    ) async {
      final bloc = StubTextBookBloc(
        _loadedStateWithCommentators([], bookNotes: notes),
      );
      addTearDown(bloc.close);

      await _pumpWithOverride(
        tester,
        textBookBloc: bloc,
        settingsBloc: settingsBloc,
      );
      expect(find.text('בחירת מפרשים'), findsOneWidget);
    });

    testWidgets('כרטיסיית המפרשים: רק "הערות" זמינות — לא נפתחת לשונית בחירה', (
      tester,
    ) async {
      final bloc = StubTextBookBloc(
        _loadedStateWithCommentators(
          [kNotesCommentatorTitle],
          available: const [kNotesCommentatorTitle],
          bookNotes: notes,
        ),
      );
      addTearDown(bloc.close);
      var openRequests = 0;

      await _pumpWithOverride(
        tester,
        textBookBloc: bloc,
        settingsBloc: settingsBloc,
        onFilterOpenRequested: () => openRequests++,
      );
      expect(openRequests, 0);
    });
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

Link _commentaryLink(int line) => Link(
  heRef: 'מפרש בדיקה',
  index1: line,
  path2: 'מפרש בדיקה.txt',
  index2: 1,
  connectionType: 'COMMENTARY',
);

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
  );
}

TextBookLoaded _loadedStateWithCommentators(
  List<String> active, {
  List<String> available = const ['מפרש בדיקה', kNotesCommentatorTitle],
  BookNotes bookNotes = BookNotes.empty,
  int line = 0,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: active,
    commentatorGroups: [
      CommentatorGroup(title: 'שאר מפרשים', commentators: available),
    ],
    availableCommentators: available,
    bookNotes: bookNotes,
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: [line],
    selectedIndex: line,
    pinLeftPane: false,
    searchText: '',
  );
}

Future<void> _pumpWithOverride(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
  VoidCallback? onFilterOpenRequested,
  List<int>? indexes,
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
            indexes: indexes,
            onSelectedCommentatorsOverrideChanged: (_) {},
            onFilterOpenRequested: onFilterOpenRequested,
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
