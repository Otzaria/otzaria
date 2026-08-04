import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentators_context_menu.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('shouldOpenPreviewLinkInBook', () {
    Link link(String type) => Link(
      heRef: 'יעד',
      index1: 1,
      path2: 'יעד.txt',
      index2: 2,
      connectionType: type,
    );

    test('משאיר קישור Linker במסלול פתיחת הספר', () {
      expect(shouldOpenPreviewLinkInBook(link('linker')), isTrue);
    });

    test('מפנה מפרש וקישור רגיל לחלוניות הצד', () {
      expect(shouldOpenPreviewLinkInBook(link('COMMENTARY')), isFalse);
      expect(shouldOpenPreviewLinkInBook(link('REFERENCE')), isFalse);
    });
  });

  group('activatePreviewCommentator', () {
    final link = Link(
      heRef: 'טורי זהב',
      index1: 1,
      path2: r'מפרשים\טורי זהב.txt',
      index2: 2,
      connectionType: 'COMMENTARY',
    );

    test('מעביר את מפרש הקישור לראש הבחירה הפעילה', () {
      expect(
        activatePreviewCommentator(
          activeCommentators: const ['שפתי כהן'],
          link: link,
        ),
        ['טורי זהב', 'שפתי כהן'],
      );
    });

    test('מעביר מפרש פעיל מאוחר לראש בלי לשכפל אותו', () {
      expect(
        activatePreviewCommentator(
          activeCommentators: const ['שפתי כהן', 'טורי זהב', 'באר היטב'],
          link: link,
        ),
        ['טורי זהב', 'שפתי כהן', 'באר היטב'],
      );
    });

    test('אינו משנה את הרשימה כשהמפרש כבר ראשון', () {
      const active = ['טורי זהב'];
      expect(
        activatePreviewCommentator(
          activeCommentators: active,
          link: link,
        ),
        same(active),
      );
    });
  });

  group('buildCombinedViewContextMenuLinksForParagraph', () {
    test('מחזירה רק קישורים רגילים של הפסקה שנלחצה', () {
      final linksByLine = <int, List<Link>>{
        3: [
          Link(
            heRef: 'בראשית ג ב',
            index1: 3,
            path2: 'zfoo/zzz.txt',
            index2: 10,
            connectionType: 'REFERENCE',
          ),
          Link(
            heRef: 'בראשית ג',
            index1: 3,
            path2: 'foo/bar.txt',
            index2: 7,
            connectionType: 'REFERENCE',
          ),
          Link(
            heRef: 'רש"י על בראשית ג',
            index1: 3,
            path2: 'commentary/rashi.txt',
            index2: 7,
            connectionType: 'COMMENTARY',
          ),
          Link(
            heRef: 'בראשית ג inline',
            index1: 3,
            path2: 'foo/inline.txt',
            index2: 8,
            connectionType: 'REFERENCE',
            start: 1,
            end: 4,
          ),
        ],
        4: [
          Link(
            heRef: 'בראשית ד',
            index1: 4,
            path2: 'foo/other.txt',
            index2: 9,
            connectionType: 'REFERENCE',
          ),
        ],
      };

      final result = buildCombinedViewContextMenuLinksForParagraph(
        linksByLine: linksByLine,
        paragraphIndex: 2,
      );

      expect(result, hasLength(2));
      expect(result.map((link) => link.heRef), ['בראשית ג', 'בראשית ג ב']);
    });

    test('מחזירה רשימה ריקה כשאין קישורים לפסקה', () {
      final result = buildCombinedViewContextMenuLinksForParagraph(
        linksByLine: const <int, List<Link>>{},
        paragraphIndex: 10,
      );

      expect(result, isEmpty);
    });
  });

  group('shouldShowPersonalNotePreview', () {
    test('מציג תצוגה מקדימה כשטאב ההערות אינו פעיל', () {
      expect(
        shouldShowPersonalNotePreview(isPersonalNotesTabActive: false),
        isTrue,
      );
    });

    test('לא מציג תצוגה מקדימה כשטאב ההערות פעיל', () {
      expect(
        shouldShowPersonalNotePreview(isPersonalNotesTabActive: true),
        isFalse,
      );
    });
  });

  group('shouldShowOpenLinksPaneEntry', () {
    test('מחזירה true כשיש קישורים וטאב הקישורים אינו פעיל', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: true,
          isLinksTabActive: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשאין קישורים', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: false,
          isLinksTabActive: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשטאב הקישורים כבר פעיל', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: true,
          isLinksTabActive: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldRebuildSelectionAreaOnExternalChange', () {
    test('מחזירה false כש-activeOwner הוא null (ניקוי בעלות)', () {
      // אחרי clear ה-controller מודיע עם activeOwner=null — אסור לבנות מחדש,
      // אחרת ניקוי בחירה גורם לקפיצה בגלילה.
      final selfOwner = Object();
      expect(
        shouldRebuildSelectionAreaOnExternalChange(
          activeOwner: null,
          selfOwner: selfOwner,
          hasOwnSelection: true,
        ),
        isFalse,
      );
    });

    test('מחזירה false כש-activeOwner זהה ל-selfOwner', () {
      final selfOwner = Object();
      expect(
        shouldRebuildSelectionAreaOnExternalChange(
          activeOwner: selfOwner,
          selfOwner: selfOwner,
          hasOwnSelection: true,
        ),
        isFalse,
      );
    });

    test(
      "מחזירה false כשאזור חיצוני מקבל בעלות אבל אין לנו בחירה משלנו לנקות "
      "(תרחיש 'מפרשים מתחת': בחירת טקסט במפרש המקונן לא צריכה להרוס את עץ הצאצאים)",
      () {
        // הבאג שתוקן: במצב 'מפרשים מתחת' ה-CommentaryListBase מקונן בעץ
        // ה-SelectionArea של ה-CombinedView. כשהמשתמש מסמן טקסט במפרש,
        // ה-controller מעביר בעלות לאזור המפרש. לפני התיקון, ה-CombinedView
        // היה מעלה את revision ובונה את ה-SelectionArea מחדש — מה שהשמיד את
        // ה-CommentaryListBase וגרם לטעינה מחדש של המפרש.
        final selfOwner = Object();
        final commentaryOwner = Object();
        expect(
          shouldRebuildSelectionAreaOnExternalChange(
            activeOwner: commentaryOwner,
            selfOwner: selfOwner,
            hasOwnSelection: false,
          ),
          isFalse,
        );
      },
    );

    test('מחזירה true כשאזור חיצוני מקבל בעלות ויש לנו בחירה משלנו לנקות', () {
      final selfOwner = Object();
      final externalOwner = Object();
      expect(
        shouldRebuildSelectionAreaOnExternalChange(
          activeOwner: externalOwner,
          selfOwner: selfOwner,
          hasOwnSelection: true,
        ),
        isTrue,
      );
    });
  });

  group('shouldRestoreScrollOnContinuousModeChange', () {
    test('החלפת מצב (רגיל→רציף או להיפך) → משחזרים גלילה', () {
      // הבאג שתוקן: מיפוי שורה↔פריט מתחלף אבל הרשימה נשארת על אינדקס
      // הפריט הישן — בלי שחזור המשתמש קופץ למקום רחוק בספר.
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: false,
          currentMode: true,
        ),
        isTrue,
      );
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: true,
          currentMode: false,
        ),
        isTrue,
      );
    });

    test('אותו מצב → אין שחזור (emit-ים שוטפים לא מזיזים את הגלילה)', () {
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: true,
          currentMode: true,
        ),
        isFalse,
      );
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: false,
          currentMode: false,
        ),
        isFalse,
      );
    });

    test('ה-state הראשון שנצפה (previousMode=null) → אין שחזור', () {
      expect(
        shouldRestoreScrollOnContinuousModeChange(
          previousMode: null,
          currentMode: true,
        ),
        isFalse,
      );
    });
  });

  group('תרחישים חוצי-טאב בחלונית הצד', () {
    test('"פתח מפרשים" מוצגת כשהחלונית פתוחה על טאב הקישורים', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasSelectedCommentators: true,
          showCommentaryAsExpansionTiles: false,
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
    });

    test('"פתח קישורים" מוצגת כשהחלונית פתוחה על טאב המפרשים', () {
      expect(
        shouldShowOpenLinksPaneEntry(
          hasLinks: true,
          isLinksTabActive: false,
        ),
        isTrue,
      );
    });

    test('"פתח מפרשים" מסתתרת כשאין מפרשים נבחרים אפילו אם זמינים בספר', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasSelectedCommentators: false,
          showCommentaryAsExpansionTiles: false,
          isCommentatorsTabActive: false,
        ),
        isFalse,
      );
    });
  });

  testWidgets('לחיצה על פסקה לא שולחת event ל-bloc סגור', (tester) async {
    final textBookBloc = _ClosedTextBookBloc(_loadedState());
    final personalNotesBloc = _TestPersonalNotesBloc(
      PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: const [],
        missingNotes: const [],
        errorMessage: null,
        filteredLocatedNotes: const [],
        filteredMissingNotes: const [],
      ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(
      book: TextBook(title: 'ספר בדיקה'),
      index: 0,
    );

    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CombinedView(
              data: const ['שורה א'],
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
              tab: tab,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byType(EnhancedGestureDetector).first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));

    expect(textBookBloc.addWasCalled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'תת-תפריט "מפרשים" בתצוגה המשולבת נבנה מהבונה המשותף ומעדכן את הבחירה',
    (tester) async {
      // רגרסיה לחילוץ הבונה המשותף עם צורת הדף: הפריטים והתנהגותם בתצוגה
      // המשולבת חייבים להישאר כשהיו.
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final textBookBloc = _RecordingTextBookBloc(
        _loadedState().copyWith(
          availableCommentators: const ['רש"י', 'רמב"ן'],
          activeCommentators: const ['רש"י'],
          commentatorGroups: const [
            CommentatorGroup(
              title: 'ראשונים',
              commentators: ['רש"י', 'רמב"ן'],
            ),
          ],
        ),
      );
      addTearDown(textBookBloc.close);
      final personalNotesBloc = _TestPersonalNotesBloc(
        const PersonalNotesState.initial(),
      );
      addTearDown(personalNotesBloc.close);
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(settingsBloc.close);
      final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
      addTearDown(tab.dispose);
      var openedPane = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: CombinedView(
                data: const ['שורה א'],
                openBookCallback: (_) {},
                openLeftPaneTab: (_, {searchText}) {},
                textSize: 18,
                showCommentaryAsExpansionTiles: false,
                tab: tab,
                onOpenCommentatorsPane: () => openedPane++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final center = tester.getCenter(find.byType(AppContextMenuRegion).first);
      await gesture.moveTo(center);
      await gesture.down(center);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('מפרשים'));
      await tester.pumpAndSettle();

      expect(find.text('פתח את חלונית המפרשים'), findsOneWidget);
      expect(find.text('הצג את כל המפרשים'), findsOneWidget);
      expect(find.text('הצג את כל ראשונים'), findsOneWidget);

      await tester.tap(find.text('רמב"ן'));
      await tester.pumpAndSettle();

      expect(
        textBookBloc.received
            .whereType<UpdateCommentators>()
            .single
            .commentators,
        ['רש"י', 'רמב"ן'],
      );
      expect(openedPane, 1);
    },
  );

  group('applyDisplayTextPreferences', () {
    // קמץ (ניקוד) — נמצא ב-vowelsAndCantillation אך לא ב-cantillationOnly
    const niqqud = 'ָ';
    // אתנחתא (טעם) — נמצא בשתי הקבוצות
    const taam = '֑';

    test('מסיר פיסוק כש-removePunctuation פעיל (באג "העתק את כל הפסקה")', () {
      final result = applyDisplayTextPreferences(
        text: 'שלום, עולם!',
        removeNikud: false,
        removePunctuation: true,
        showTeamim: true,
      );
      expect(result.contains(','), isFalse);
      expect(result.contains('!'), isFalse);
      expect(result.contains('שלום'), isTrue);
      expect(result.contains('עולם'), isTrue);
    });

    test('שומר פיסוק כש-removePunctuation כבוי', () {
      final result = applyDisplayTextPreferences(
        text: 'שלום, עולם!',
        removeNikud: false,
        removePunctuation: false,
        showTeamim: true,
      );
      expect(result, 'שלום, עולם!');
    });

    test('מסיר ניקוד כש-removeNikud פעיל', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqudבג',
        removeNikud: true,
        removePunctuation: false,
        showTeamim: true,
      );
      expect(result, 'אבג');
    });

    test('שומר ניקוד כש-removeNikud כבוי', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqudבג',
        removeNikud: false,
        removePunctuation: false,
        showTeamim: true,
      );
      expect(result, 'א$niqqudבג');
    });

    test('מסיר טעמים בלבד כש-showTeamim כבוי (הניקוד נשמר)', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqud$taamבג',
        removeNikud: false,
        removePunctuation: false,
        showTeamim: false,
      );
      expect(result.contains(taam), isFalse);
      expect(result.contains(niqqud), isTrue);
    });

    test('שומר טעמים כש-showTeamim פעיל', () {
      final result = applyDisplayTextPreferences(
        text: 'א$taamבג',
        removeNikud: false,
        removePunctuation: false,
        showTeamim: true,
      );
      expect(result.contains(taam), isTrue);
    });

    test('מסיר גם ניקוד וגם פיסוק יחד (באג "העתק טקסט מוצג")', () {
      final result = applyDisplayTextPreferences(
        text: 'א$niqqudבג, דה!',
        removeNikud: true,
        removePunctuation: true,
        showTeamim: true,
      );
      expect(result.contains(niqqud), isFalse);
      expect(result.contains(','), isFalse);
      expect(result.contains('!'), isFalse);
    });

    test('ישות HTML (&thinsp;) שורדת הסרת פיסוק ואינה הופכת לטקסט גלוי', () {
      // ה-";" של הישות אינו פיסוק אלא תחביר; מחיקתו השאירה "&thinsp" מוצג
      // ליד כל פסק בתנ"ך.
      const text = 'אֱלֹהִ֤ים&thinsp;<small>׀</small>&thinsp;לָאוֹר֙';

      final result = applyDisplayTextPreferences(
        text: text,
        removeNikud: true,
        removePunctuation: true,
        showTeamim: true,
      );

      expect(result.contains('&thinsp;'), isTrue);
      expect(result.contains('&thinsp<'), isFalse);
    });

    test('לא משנה טקסט כשכל ההעדפות מאפשרות הצגה מלאה', () {
      const text = 'א$niqqudבג';
      final result = applyDisplayTextPreferences(
        text: text,
        removeNikud: false,
        removePunctuation: false,
        showTeamim: true,
      );
      expect(result, text);
    });
  });

  group('hasCommentariesForLine', () {
    const noteLine =
        'שורה<sup class="footnote-marker">א</sup><i class="footnote">גוף ההערה</i>';
    const plainLine = 'שורה רגילה ללא הערות';

    test(
      'מחזירה true כש"הערות" פעיל ויש הערת inline בשורה — גם בלי קישורי מפרשים',
      () {
        // באג: בספרים שבהם ההערות הן המפרש היחיד, "מפרשים מתחת" לא הציג כלום.
        final result = hasCommentariesForLine(
          activeCommentators: const [kNotesCommentatorTitle],
          content: const [noteLine],
          linksByLine: const {},
          index: 0,
        );
        expect(result, isTrue);
      },
    );

    test(
      'מחזירה false כש"הערות" פעיל אך אין הערת inline בשורה ואין קישורים',
      () {
        final result = hasCommentariesForLine(
          activeCommentators: const [kNotesCommentatorTitle],
          content: const [plainLine],
          linksByLine: const {},
          index: 0,
        );
        expect(result, isFalse);
      },
    );

    test('מחזירה false כשאין מפרשים פעילים ואין קישורים', () {
      final result = hasCommentariesForLine(
        activeCommentators: const [],
        content: const [noteLine],
        linksByLine: const {},
        index: 0,
      );
      expect(result, isFalse);
    });

    test('מחזירה true כשיש קישור COMMENTARY למפרש פעיל', () {
      final result = hasCommentariesForLine(
        activeCommentators: const ['רש"י'],
        content: const [plainLine],
        linksByLine: {
          1: [
            Link(
              heRef: 'רש"י על בראשית א',
              index1: 1,
              path2: 'commentary/רש"י.txt',
              index2: 7,
              connectionType: 'COMMENTARY',
            ),
          ],
        },
        index: 0,
      );
      expect(result, isTrue);
    });

    test('מחזירה false כשהקישור הוא למפרש שאינו פעיל', () {
      final result = hasCommentariesForLine(
        activeCommentators: const ['רמב"ן'],
        content: const [plainLine],
        linksByLine: {
          1: [
            Link(
              heRef: 'רש"י על בראשית א',
              index1: 1,
              path2: 'commentary/רש"י.txt',
              index2: 7,
              connectionType: 'COMMENTARY',
            ),
          ],
        },
        index: 0,
      );
      expect(result, isFalse);
    });
  });
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: null,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _ClosedTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _ClosedTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  bool addWasCalled = false;

  @override
  bool get isClosed => true;

  @override
  void add(TextBookEvent event) {
    addWasCalled = true;
    throw StateError('add לא אמור להיקרא כשה-bloc סגור');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _RecordingTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }

  final List<TextBookEvent> received = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
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
