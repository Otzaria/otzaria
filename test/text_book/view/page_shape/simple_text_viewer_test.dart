import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('סימון הערה inline מוזרק לטקסט ולחיצתו פותחת את טאב ההערות', (
    tester,
  ) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final personalNotesBloc = _TestPersonalNotesBloc(
      PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: [_note()],
        missingNotes: const [],
        errorMessage: null,
        filteredLocatedNotes: [_note()],
        filteredMissingNotes: const [],
      ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    int? openedTab;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SimpleTextViewer(
              content: const ['שורה א'],
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
              onOpenSidebarTab: (tabIndex) => openedTab = tabIndex,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // הסימון מוזרק כקישור inline בטקסט הראשי (otzaria://note?line=0).
    final mainText = tester
        .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
        .firstWhere((w) => w.onNoteTap != null);
    expect(mainText.text.contains('otzaria://note?line=0'), isTrue);

    // לחיצה על הסימון (דרך ה-callback) פותחת את טאב ההערות הפנימי.
    mainText.onNoteTap!(0);
    await tester.pumpAndSettle();

    expect(openedTab, 1);
  });

  testWidgets('בצורת הדף ריחוף על עוגן נקודה ועל עוגן טווח מציג פופאפ', (
    tester,
  ) async {
    final pointLink = Link(
      heRef: 'מפרש א, א',
      index1: 1,
      path2: 'מפרש א',
      index2: 1,
      connectionType: 'commentary',
      anchorStart: 0,
      anchorLabel: 'א',
    );
    final rangeLink = Link(
      heRef: 'מקור א, א',
      index1: 1,
      path2: 'מקור א',
      index2: 1,
      connectionType: 'linker',
      anchorStart: 2,
      anchorEnd: 5,
    );
    final loadedState = _loadedState().copyWith(
      links: [pointLink, rangeLink],
      linksByLine: {
        1: [pointLink, rangeLink],
      },
    );
    final textBookBloc = _TestTextBookBloc(loadedState);
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        filteredLocatedNotes: [],
        filteredMissingNotes: [],
      ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    addTearDown(LinkPreviewOverlay.dismiss);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SimpleTextViewer(
              content: const ['abcdef'],
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final smartText = tester
        .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
        .firstWhere((widget) => widget.onAnchorHover != null);
    expect(smartText.text, contains('otzaria://anchor?ref=0_0'));
    expect(smartText.text, contains('otzaria://anchor?ref=0_1&range=1'));

    smartText.onAnchorHover!(
      'otzaria://anchor?ref=0_0',
      const Offset(100, 100),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinkHoverPreviewContent), findsOneWidget);

    LinkPreviewOverlay.dismiss();
    smartText.onAnchorHover!(
      'otzaria://anchor?ref=0_1&range=1',
      const Offset(120, 100),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinkHoverPreviewContent), findsOneWidget);
  });

  testWidgets('בצורת הדף ריחוף על Linker מסוג start/end מציג פופאפ', (
    tester,
  ) async {
    final inlineLink = Link(
      heRef: 'מקור א, א',
      index1: 1,
      path2: 'מקור א',
      index2: 1,
      connectionType: 'linker',
      start: 0,
      end: 6,
    );
    final textBookBloc = _TestTextBookBloc(
      _loadedState().copyWith(
        links: [inlineLink],
        linksByLine: {
          1: [inlineLink],
        },
      ),
    );
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState(
        isLoading: false,
        bookId: 'ספר בדיקה',
        locatedNotes: [],
        missingNotes: [],
        errorMessage: null,
        filteredLocatedNotes: [],
        filteredMissingNotes: [],
      ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    addTearDown(LinkPreviewOverlay.dismiss);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SimpleTextViewer(
              content: const ['abcdef'],
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final smartText = tester
        .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
        .firstWhere((widget) => widget.onAnchorHover != null);
    const url =
        'otzaria://inline-link?path=%D7%9E%D7%A7%D7%95%D7%A8%20%D7%90&index=1&ref=%D7%9E%D7%A7%D7%95%D7%A8%20%D7%90%2C%20%D7%90';
    expect(smartText.text, contains(url));

    smartText.onAnchorHover!(url, const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinkHoverPreviewContent), findsOneWidget);
  });

  testWidgets('ריחוף על הסרגל בצורת הדף מציג תווית יעד מתוך labelForIndex', (
    tester,
  ) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
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

    // תוכן ארוך כדי שהסרגל הפנימי יוצג (יש מה לגלול).
    final content = List<String>.generate(200, (i) => 'שורה $i');

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SimpleTextViewer(
              content: content,
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
              labelForIndex: (index) => 'יעד $index',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // הסרגל יושב בקצה (LTR בבדיקה) ברוחב 12; מרחפים פנימה אליו.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(400, 300));
    addTearDown(() => gesture.removePointer());
    await tester.pump();
    await gesture.moveTo(const Offset(6, 300));
    await tester.pump();

    expect(find.textContaining('יעד'), findsOneWidget);
  });

  testWidgets(
    'הוספת הערה ממפרש פותחת דיאלוג עצמאי ולא עוברת דרך הסיידבר של הספר הראשי',
    (tester) async {
      // רגרסיה: בצורת הדף המפרש חולק את ה-TextBookBloc של הספר הראשי. הוספת הערה
      // ממפרש חייבת להישמר תחת ספר המפרש (דרך דיאלוג עצמאי), ולא לשלוח
      // StartCreatingPersonalNote — שהיה שומר תחת הספר הראשי במספר שורה שגוי.
      final textBookBloc = _TestTextBookBloc(_loadedState());
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

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: SimpleTextViewer(
                content: const ['שורת מפרש'],
                fontSize: 18,
                openBookCallback: (_) {},
                isMainText: false, // מפרש — לא הטקסט הראשי
                bookTitle: 'רש"י',
                reportBook: TextBook(title: 'רש"י'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // פתיחת תפריט ההקשר בלחיצה ימנית על שורת המפרש
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final regionCenter = tester.getCenter(
        find.byType(AppContextMenuRegion).first,
      );
      await gesture.moveTo(regionCenter);
      await gesture.down(regionCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final addNoteFinder = find.textContaining('הוסף הערה אישית');
      expect(
        addNoteFinder,
        findsOneWidget,
        reason: 'תפריט ההקשר במפרש חייב לכלול "הוסף הערה אישית"',
      );

      await tester.tap(addNoteFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // נפתח דיאלוג עורך עצמאי לשמירה תחת ספר המפרש
      expect(
        find.byType(PersonalNoteEditorDialog),
        findsOneWidget,
        reason: 'הוספת הערה ממפרש צריכה לפתוח דיאלוג עצמאי',
      );

      // ה-bloc של הספר הראשי לא קיבל StartCreatingPersonalNote
      expect(
        personalNotesBloc.receivedEvents.whereType<StartCreatingPersonalNote>(),
        isEmpty,
        reason: 'הערה על מפרש לא צריכה לעבור דרך הסיידבר של הספר הראשי',
      );

      // ניקוי: סגירת הדיאלוג כדי לא להשאיר טיימרים של העורך פתוחים
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'דיאלוג ההערה ממפרש מכוון לספר המפרש ולשורה הנכונה (bookId + draftLineNumber)',
    (tester) async {
      // מאמת את היעד של השמירה: הדיאלוג חייב לקבל את ה-bookId של המפרש ואת מספר
      // השורה המקומי בתוך תוכן המפרש — אותם ערכים שמועברים גם ל-addNote.
      final textBookBloc = _TestTextBookBloc(_loadedState());
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

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: SimpleTextViewer(
                // שלוש שורות — נבחר את השנייה כדי לוודא lineNumber=2 ולא 1
                content: const ['שורה ראשונה', 'שורה שנייה', 'שורה שלישית'],
                fontSize: 18,
                openBookCallback: (_) {},
                isMainText: false,
                bookTitle: 'רש"י',
                reportBook: TextBook(title: 'רש"י'),
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

      // ה-regions מסודרים לפי סדר השורות; השני (index 1) = שורה שנייה = lineNumber 2
      final regions = find.byType(AppContextMenuRegion);
      expect(regions, findsNWidgets(3));
      final secondLineCenter = tester.getCenter(regions.at(1));
      await gesture.moveTo(secondLineCenter);
      await gesture.down(secondLineCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('הוסף הערה אישית'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final dialog = tester.widget<PersonalNoteEditorDialog>(
        find.byType(PersonalNoteEditorDialog),
      );
      expect(
        dialog.bookId,
        'רש"י',
        reason: 'הדיאלוג חייב לכוון לספר המפרש, לא לספר הראשי',
      );
      expect(
        dialog.draftLineNumber,
        2,
        reason: 'מספר השורה חייב להתאים לשורה שנבחרה בתוך תוכן המפרש',
      );

      // ניקוי: סגירת הדיאלוג כדי לא להשאיר טיימרים של העורך פתוחים
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
    },
  );

  test(
    'saveCommentaryNoteToRepository ממפה את תוצאת העורך לקריאת addNote',
    () async {
      final repo = _RecordingNotesRepository();

      await saveCommentaryNoteToRepository(
        repository: repo,
        bookId: 'רש"י',
        lineNumber: 2,
        result: const PersonalNoteEditorResult(
          content: 'דלתא',
          contentPlain: 'תוכן ההערה',
          contentFormat: PersonalNoteContentFormat.quillDelta,
        ),
        selectedText: 'טקסט נבחר',
        selectionColumn: 12,
        categoryId: 7,
      );

      expect(
        repo.addNoteCallCount,
        1,
        reason: 'חייבת להתבצע קריאה אחת בדיוק ל-addNote',
      );
      expect(repo.capturedBookId, 'רש"י', reason: 'ההערה נשמרת תחת ספר המפרש');
      expect(repo.capturedLineNumber, 2);
      expect(repo.capturedContentPlain, 'תוכן ההערה');
      expect(repo.capturedCategoryId, 7);
      expect(
        repo.capturedSelectionColumn,
        12,
        reason: 'רמז עמודת הבחירה מועבר לזיהוי המופע הנכון בטקסט חוזר',
      );
    },
  );

  test('שומר בחירה אחרונה רק כאשר הטקסט הנבחר אינו ריק', () {
    expect(shouldPersistSelectedText('טקסט נבחר'), isTrue);
    expect(shouldPersistSelectedText('  טקסט עם רווחים  '), isTrue);
    expect(shouldPersistSelectedText(''), isFalse);
    expect(shouldPersistSelectedText('   '), isFalse);
    expect(shouldPersistSelectedText(null), isFalse);
  });

  test('בחירה ריקה לא דורסת את הטקסט האחרון שנשמר', () {
    expect(
      resolvePersistedSelectedText(
        previousSelectedText: 'טקסט קודם',
        latestSelectedText: '',
      ),
      'טקסט קודם',
    );
    expect(
      resolvePersistedSelectedText(
        previousSelectedText: 'טקסט קודם',
        latestSelectedText: null,
      ),
      'טקסט קודם',
    );
    expect(
      resolvePersistedSelectedText(
        previousSelectedText: 'טקסט קודם',
        latestSelectedText: 'טקסט חדש',
      ),
      'טקסט חדש',
    );
  });

  test('ניווט מקלדת בצורת הדף נופל חזרה למיקום הנראה ולא לתחילת הספר', () {
    expect(
      resolvePageShapeNavigationBaseIndex(
        selectedIndex: null,
        liveVisibleIndices: const [48, 49, 50],
        stateVisibleIndices: const [47, 48, 49],
      ),
      48,
    );

    expect(
      resolvePageShapeNavigationBaseIndex(
        selectedIndex: 49,
        liveVisibleIndices: const [48, 49, 50],
        stateVisibleIndices: const [47, 48, 49],
      ),
      49,
    );

    expect(
      resolvePageShapeNavigationBaseIndex(
        selectedIndex: 12,
        liveVisibleIndices: const [48, 49, 50],
        stateVisibleIndices: const [47, 48, 49],
      ),
      48,
    );

    // הקטע הנבחר מתחת לחלון הנראה (השהיית גלילה בלחיצה רציפה על חץ-למטה):
    // ממשיכים מהקצה התחתון ולא קופצים לראש החלון (issue: גלילה בחיצים).
    expect(
      resolvePageShapeNavigationBaseIndex(
        selectedIndex: 51,
        liveVisibleIndices: const [48, 49, 50],
        stateVisibleIndices: const [47, 48, 49],
      ),
      50,
    );
  });

  test('אירועי החזקה של מקש מוכרים לצורך גלילה רציפה', () {
    expect(
      shouldHandlePageShapeNavigationKeyEvent(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    expect(
      shouldHandlePageShapeNavigationKeyEvent(
        KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    expect(
      shouldHandlePageShapeNavigationKeyEvent(
        KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
      ),
      isFalse,
    );
  });

  test('Shift לחוץ — הניווט מוותר כדי לאפשר הרחבת בחירה (Shift+חץ)', () {
    final downEvent = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: LogicalKeyboardKey.arrowDown,
      timeStamp: Duration.zero,
    );

    // ללא Shift — ממשיכים לטפל בניווט (גלילה/דילוג שורה)
    expect(
      shouldHandlePageShapeNavigationKeyEvent(downEvent),
      isTrue,
    );

    // עם Shift — הניווט מוותר, האירוע יעבור להרחבת הבחירה
    expect(
      shouldHandlePageShapeNavigationKeyEvent(downEvent, isShiftPressed: true),
      isFalse,
    );
  });

  test('Shift+Space מורשה לעבור כדי לאפשר גלילה אחורה', () {
    final spaceDown = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.space,
      logicalKey: LogicalKeyboardKey.space,
      timeStamp: Duration.zero,
    );

    // Shift+Space — חריג: מורשה לעבור (גלילה מסך אחד אחורה)
    expect(
      shouldHandlePageShapeNavigationKeyEvent(spaceDown, isShiftPressed: true),
      isTrue,
    );

    // Shift+חץ — עדיין חסום
    final arrowDown = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: LogicalKeyboardKey.arrowDown,
      timeStamp: Duration.zero,
    );
    expect(
      shouldHandlePageShapeNavigationKeyEvent(arrowDown, isShiftPressed: true),
      isFalse,
    );
  });

  group('resolveCommentaryKeyAction', () {
    setUp(() => ShortcutHelper.isMacForTesting = false);
    tearDown(() => ShortcutHelper.isMacForTesting = null);

    KeyDownEvent keyDown(
      PhysicalKeyboardKey physical,
      LogicalKeyboardKey logical,
    ) => KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );

    final addNoteEvent = keyDown(
      PhysicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyN,
    );

    test('קיצור הוסף-הערה במפרש הפעיל עם בחירה ושורה ידועה → addNote', () {
      expect(
        resolveCommentaryKeyAction(
          event: addNoteEvent,
          isActiveCommentary: true,
          hasSelection: true,
          hasSelectedIndex: true,
          addNoteShortcut: 'ctrl+n',
          isControlPressed: true,
        ),
        CommentaryKeyAction.addNote,
      );
    });

    test('הוסף-הערה כשהמפרש אינו הפעיל → none (לא מטפלים מכאן)', () {
      expect(
        resolveCommentaryKeyAction(
          event: addNoteEvent,
          isActiveCommentary: false,
          hasSelection: true,
          hasSelectedIndex: true,
          addNoteShortcut: 'ctrl+n',
          isControlPressed: true,
        ),
        CommentaryKeyAction.none,
      );
    });

    test('הוסף-הערה בלי טקסט מסומן → none', () {
      expect(
        resolveCommentaryKeyAction(
          event: addNoteEvent,
          isActiveCommentary: true,
          hasSelection: false,
          hasSelectedIndex: true,
          addNoteShortcut: 'ctrl+n',
          isControlPressed: true,
        ),
        CommentaryKeyAction.none,
      );
    });

    test('הוסף-הערה בלי שורת מקור ידועה לבחירה → none', () {
      expect(
        resolveCommentaryKeyAction(
          event: addNoteEvent,
          isActiveCommentary: true,
          hasSelection: true,
          hasSelectedIndex: false,
          addNoteShortcut: 'ctrl+n',
          isControlPressed: true,
        ),
        CommentaryKeyAction.none,
      );
    });

    test('Ctrl+C במפרש הפעיל עם בחירה → copy', () {
      expect(
        resolveCommentaryKeyAction(
          event: keyDown(PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC),
          isActiveCommentary: true,
          hasSelection: true,
          hasSelectedIndex: true,
          addNoteShortcut: 'ctrl+n',
          isControlPressed: true,
        ),
        CommentaryKeyAction.copy,
      );
    });

    test('מקש ללא modifier מתאים → none (לא מיירטים מקלדת רגילה)', () {
      expect(
        resolveCommentaryKeyAction(
          event: addNoteEvent,
          isActiveCommentary: true,
          hasSelection: true,
          hasSelectedIndex: true,
          addNoteShortcut: 'ctrl+n',
          isControlPressed: false,
        ),
        CommentaryKeyAction.none,
      );
    });
  });

  testWidgets('פוקוס על MenuItemButton מזוהה כתפריט', (tester) async {
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuItemButton(
            focusNode: focusNode,
            onPressed: () {},
            child: const Text('פריט'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    focusNode.requestFocus();
    await tester.pump();

    expect(isMenuFocusNode(focusNode), isTrue);

    focusNode.dispose();
  });

  testWidgets('פוקוס על SubmenuButton מזוהה כתפריט', (tester) async {
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmenuButton(
            focusNode: focusNode,
            menuChildren: const [],
            child: const Text('תת-תפריט'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    focusNode.requestFocus();
    await tester.pump();

    expect(isMenuFocusNode(focusNode), isTrue);

    focusNode.dispose();
  });

  testWidgets('פוקוס שאינו על תפריט אינו מזוהה כתפריט', (tester) async {
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextButton(
            focusNode: focusNode,
            onPressed: () {},
            child: const Text('כפתור רגיל'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    focusNode.requestFocus();
    await tester.pump();

    expect(isMenuFocusNode(focusNode), isFalse);

    focusNode.dispose();
  });

  testWidgets(
    'פוקוס על תת-תפריט בתפריט הקשר אינו נגנב חזרה לטקסט הראשי בצורת הדף',
    (tester) async {
      final textBookBloc = _TestTextBookBloc(_loadedState());
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
      final menuItemFocusNode = FocusNode(debugLabel: 'TestMenuItem');

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: SimpleTextViewer(
                      content: const ['שורה א'],
                      fontSize: 18,
                      openBookCallback: (_) {},
                      isMainText: true,
                    ),
                  ),
                  MenuItemButton(
                    focusNode: menuItemFocusNode,
                    onPressed: () {},
                    child: const Text('פריט תת-תפריט'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // initState של SimpleTextViewer גורם ל-_requestKeyboardFocus
      // שמציב _shouldPreserveKeyboardFocus = true.
      await tester.pumpAndSettle();

      // המשתמש פותח תת-תפריט (החלף מפרש / קישורים) - הפוקוס עובר אליו.
      menuItemFocusNode.requestFocus();
      await tester.pump();
      // postFrame שלאחר איבוד הפוקוס - לפני התיקון היה גוזל את הפוקוס בחזרה.
      await tester.pump();
      await tester.pump();

      expect(
        menuItemFocusNode.hasFocus,
        isTrue,
        reason:
            'תת-התפריט אמור להישאר פתוח: הטקסט הראשי לא צריך לגנוב פוקוס מתפריט פעיל',
      );

      menuItemFocusNode.dispose();
    },
  );

  testWidgets('אחרי סגירת תת-תפריט הפוקוס חוזר לטקסט הראשי בצורת הדף', (
    tester,
  ) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
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
    final menuItemFocusNode = FocusNode(debugLabel: 'TestMenuItem');

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: SimpleTextViewer(
                    content: const ['שורה א'],
                    fontSize: 18,
                    openBookCallback: (_) {},
                    isMainText: true,
                  ),
                ),
                MenuItemButton(
                  focusNode: menuItemFocusNode,
                  onPressed: () {},
                  child: const Text('פריט תת-תפריט'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // הטקסט הראשי קיבל פוקוס באתחול (autofocus + _requestKeyboardFocus)
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'PageShapeContentFocus',
    );

    // משתמש פותח תת-תפריט - הפוקוס עובר אליו
    menuItemFocusNode.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(menuItemFocusNode.hasFocus, isTrue);

    // משתמש סוגר את התפריט - הפוקוס יוצא ממנו
    menuItemFocusNode.unfocus();
    await tester.pump();
    await tester.pump();

    // הפוקוס צריך לחזור לטקסט הראשי כדי שמקשי החיצים יעבדו
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'PageShapeContentFocus',
      reason: 'אחרי סגירת תפריט, מקשי החיצים צריכים להמשיך לעבוד בטקסט הראשי',
    );

    menuItemFocusNode.dispose();
  });

  testWidgets('"העתק" בתפריט ההקשר מנוטרל כשאין טקסט נבחר בעת פתיחת התפריט', (
    tester,
  ) async {
    // ——————————————————————————————————————————————————————————————————————
    // מבדק זה מוודא שה-capturedText שנלכד ב-_buildLine (ב-savedTextAtBuild)
    // הוא null כשאין בחירה, ולכן "העתק" מנוטרל — גם אחרי שתוקן הבאג שגרם
    // ל-capturedText לקרוא את _savedSelectedText בזמן הקליק ולא בזמן הבנייה.
    // ——————————————————————————————————————————————————————————————————————
    final textBookBloc = _TestTextBookBloc(_loadedState());
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

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SimpleTextViewer(
              content: const ['שורה א'],
              fontSize: 18,
              openBookCallback: (_) {},
              isMainText: true,
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

    // AppContextMenuRegion נמצא בתוך כל item ברשימה — מטרגטים אותו ישירות
    final regionFinder = find.byType(AppContextMenuRegion);
    expect(
      regionFinder,
      findsWidgets,
      reason: 'SimpleTextViewer חייב לרנדר AppContextMenuRegion לכל שורה',
    );

    final regionCenter = tester.getCenter(regionFinder.first);
    await gesture.moveTo(regionCenter);
    await gesture.down(regionCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // בטקסט ראשי "העתק" הוא אייקון בשורה העליונה (כיתוב "העתקה").
    expect(
      find.text('העתקה'),
      findsOneWidget,
      reason: 'שורת האייקונים חייבת להכיל את אייקון ההעתקה',
    );

    final copyInkWell = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('העתקה'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(
      copyInkWell.onTap,
      isNull,
      reason:
          'אייקון ההעתקה חייב להיות מנוטרל כשאין בחירה — '
          'capturedText=null בזמן הבנייה',
    );
  });

  testWidgets('אחרי סגירת תפריט, פוקוס שהמשתמש העביר לכפתור אחר אינו נגנב', (
    tester,
  ) async {
    final textBookBloc = _TestTextBookBloc(_loadedState());
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
    final menuItemFocusNode = FocusNode(debugLabel: 'TestMenuItem');
    final otherButtonFocusNode = FocusNode(debugLabel: 'OtherButton');

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: SimpleTextViewer(
                    content: const ['שורה א'],
                    fontSize: 18,
                    openBookCallback: (_) {},
                    isMainText: true,
                  ),
                ),
                MenuItemButton(
                  focusNode: menuItemFocusNode,
                  onPressed: () {},
                  child: const Text('פריט תת-תפריט'),
                ),
                TextButton(
                  focusNode: otherButtonFocusNode,
                  onPressed: () {},
                  child: const Text('כפתור אחר'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // משתמש פותח תת-תפריט - הפוקוס עובר אליו
    menuItemFocusNode.requestFocus();
    await tester.pump();
    expect(menuItemFocusNode.hasFocus, isTrue);

    // משתמש סוגר את התפריט ומיד מעביר פוקוס לכפתור אחר
    // (למשל ע"י Tab, או לחיצה על widget אחר)
    otherButtonFocusNode.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // הפוקוס צריך להישאר בכפתור שהמשתמש בחר במכוון
    expect(
      otherButtonFocusNode.hasFocus,
      isTrue,
      reason: 'אסור לגנוב פוקוס מ-widget שהמשתמש בחר בו במכוון',
    );

    menuItemFocusNode.dispose();
    otherButtonFocusNode.dispose();
  });

  testWidgets(
    'SelectableRegion לא נבנה מחדש כשאזור חיצוני נעשה פעיל ואין לנו בחירה משלנו '
    '(מונע טעינה מחדש של תוכן בעת בחירה במפרש בצורת הדף)',
    (tester) async {
      // רגרסיה: לפני התיקון, כל הפעלה של אזור חיצוני גרמה לבנייה מחדש של
      // ה-SelectionArea — מה שהשמיד את עץ הצאצאים (ScrollablePositionedList)
      // וגרם לאיפוס מצב פנימי/קפיצות גלילה. אם אין לנו בחירה משלנו אין מה
      // לנקות, ולכן אסור לבנות מחדש.
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);
      final otherOwner = Object();

      final textBookBloc = _TestTextBookBloc(_loadedState());
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

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: SimpleTextViewer(
                content: const ['שורה א'],
                fontSize: 18,
                openBookCallback: (_) {},
                isMainText: true,
                selectionSyncController: controller,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final elementBefore = _findSelectableRegionElement(tester);
      expect(elementBefore, isNotNull);

      controller.activate(otherOwner);
      await tester.pump();

      final elementAfter = _findSelectableRegionElement(tester);
      expect(
        elementAfter,
        same(elementBefore),
        reason:
            'בלי בחירה משלנו, הפעלת אזור חיצוני אסור שתגרום ל-rebuild — '
            'אחרת עץ הצאצאים נהרס לחינם',
      );
    },
  );

  testWidgets(
    'SelectableRegion לא נבנה מחדש כשהבחירה התנקתה (activeOwner הופך ל-null)',
    (tester) async {
      // רגרסיה: לפני התיקון, ניקוי בחירה גרם להחלפת ה-key של ה-SelectionArea
      // ולבנייה מחדש של ה-ScrollablePositionedList — והגלילה קפצה לתחילת הקטע.
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);
      final otherOwner = Object();

      final textBookBloc = _TestTextBookBloc(_loadedState());
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

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: SimpleTextViewer(
                content: const ['שורה א'],
                fontSize: 18,
                openBookCallback: (_) {},
                isMainText: true,
                selectionSyncController: controller,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // האזור החיצוני מפעיל ומיד מנקה — דמוי משתמש שבחר ושחרר את הבחירה.
      controller.activate(otherOwner);
      await tester.pump();
      final elementAfterActivate = _findSelectableRegionElement(tester);

      controller.clear(otherOwner);
      await tester.pump();
      final elementAfterClear = _findSelectableRegionElement(tester);

      expect(
        elementAfterClear,
        same(elementAfterActivate),
        reason:
            'ניקוי בחירה (activeOwner=null) אסור שיגרום ל-rebuild — אחרת הגלילה קופצת',
      );
    },
  );

  testWidgets(
    'SelectableRegion במפרש לא נהרס כשאזור חיצוני (טקסט ראשי) נעשה פעיל — '
    'מונע קפיצת גלילה לתחילת הספר בצורת הדף',
    (tester) async {
      // רגרסיה: כשבחרו טקסט במפרש ואחר כך בטקסט הראשי, ה-SelectionArea של
      // המפרש נבנה מחדש עם מפתח חדש (כדי לנקות בחירה ויזואלית). הבנייה מחדש
      // השמידה את ה-ScrollablePositionedList ואיפסה את מיקום הגלילה לשורה 0.
      // התיקון: שימוש ב-SelectableRegion עם GlobalKey יציב + clearSelection()
      // ישיר — ללא שינוי מפתח ולכן ללא קפיצה.
      final controller = SelectionSyncController();
      addTearDown(controller.dispose);
      final mainTextOwner = Object();

      final textBookBloc = _TestTextBookBloc(_loadedState());
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

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TextBookBloc>.value(value: textBookBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: Scaffold(
              body: SimpleTextViewer(
                content: const ['שורה א', 'שורה ב', 'שורה ג'],
                fontSize: 18,
                openBookCallback: (_) {},
                isMainText: false, // מפרש — כאן התרחש הבאג
                selectionSyncController: controller,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final elementBefore = _findSelectableRegionElement(tester);
      expect(
        elementBefore,
        isNotNull,
        reason: 'SimpleTextViewer חייב לרנדר SelectableRegion',
      );

      // דמוי בחירת טקסט בטקסט הראשי (הפעלת אזור חיצוני) —
      // לפני התיקון זה היה גורם לבנייה מחדש של SelectionArea של המפרש
      controller.activate(mainTextOwner);
      await tester.pump();

      final elementAfter = _findSelectableRegionElement(tester);
      expect(
        elementAfter,
        same(elementBefore),
        reason:
            'SelectableRegion של המפרש לא אמור להיהרס ולהיווצר מחדש — '
            'הרס כזה היה מאפס את ScrollablePositionedList לשורה 0 וגורם לקפיצה',
      );
    },
  );

  testWidgets('פוקוס בתוך עורך Quill מזוהה כשדה קלט', (tester) async {
    final focusNode = FocusNode();
    final scrollController = ScrollController();
    final controller = quill.QuillController(
      document: quill.Document()..insert(0, 'שלום\n'),
      selection: const TextSelection.collapsed(offset: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: quill.QuillEditor(
            controller: controller,
            focusNode: focusNode,
            scrollController: scrollController,
            config: const quill.QuillEditorConfig(
              autoFocus: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(isTextInputFocusNode(focusNode), isTrue);

    scrollController.dispose();
    focusNode.dispose();
  });
}

/// מחזירה את ה-Element של SelectableRegion שנוצר על-ידי SimpleTextViewer.
/// SimpleTextViewer משתמש ב-`GlobalKey<SelectableRegionState>` — מה שמאפשר
/// לזהות אותו בין שאר ה-SelectableRegion שעשויים להימצא בעץ.
Element? _findSelectableRegionElement(WidgetTester tester) {
  for (final element in tester.elementList(find.byType(SelectableRegion))) {
    if ((element.widget as SelectableRegion).key
        is GlobalKey<SelectableRegionState>) {
      return element;
    }
  }
  return null;
}

/// repository מדומה שמתעד את הקריאה ל-addNote בלי לגעת במערכת הקבצים.
class _RecordingNotesRepository extends PersonalNotesRepository {
  String? capturedBookId;
  int? capturedLineNumber;
  String? capturedContentPlain;
  int? capturedCategoryId;
  int? capturedSelectionColumn;
  int addNoteCallCount = 0;

  @override
  Future<List<PersonalNote>> addNote({
    required String bookId,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
    int? selectionColumn,
    int? categoryId,
  }) async {
    addNoteCallCount++;
    capturedBookId = bookId;
    capturedLineNumber = lineNumber;
    capturedContentPlain = contentPlain;
    capturedCategoryId = categoryId;
    capturedSelectionColumn = selectionColumn;
    return const [];
  }
}

PersonalNote _note() {
  final now = DateTime(2026, 3, 15);
  return PersonalNote(
    id: '1',
    bookId: 'ספר בדיקה',
    lineNumber: 1,
    displayTitle: 'שורה א',
    lastKnownLineNumber: 1,
    status: PersonalNoteStatus.located,
    content: 'תוכן',
    contentPlain: 'תוכן',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: true,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
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

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  final List<PersonalNotesEvent> receivedEvents = [];

  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {
      receivedEvents.add(event);
    });
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
