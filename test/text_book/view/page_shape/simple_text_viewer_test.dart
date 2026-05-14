import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/text_book/view/selection/selection_persistence.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('display mode change keeps the visible source line', () {
    expect(
      resolveDisplayModeRestoreLineIndex(
        visibleIndices: const [42, 43, 44],
        selectedIndex: 7,
        contentLength: 100,
      ),
      42,
    );

    expect(
      resolveDisplayModeRestoreLineIndex(
        visibleIndices: const [],
        selectedIndex: 7,
        contentLength: 100,
      ),
      7,
    );

    expect(
      resolveDisplayModeRestoreLineIndex(
        visibleIndices: const [150],
        selectedIndex: 7,
        contentLength: 100,
      ),
      isNull,
    );
  });

  testWidgets('לחיצה על אינדיקטור הערה פותחת את טאב ההערות הפנימי',
      (tester) async {
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
    await tester.tap(find.byIcon(FluentIcons.note_24_filled));
    await tester.pumpAndSettle();

    expect(openedTab, 1);
  });

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
  });

  testWidgets(
      'אחרי סגירת תת-תפריט הפוקוס חוזר לטקסט הראשי בצורת הדף',
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

  testWidgets('"העתק" בתפריט ההקשר מנוטרל כשאין טקסט נבחר בעת פתיחת התפריט',
      (tester) async {
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
    expect(regionFinder, findsWidgets,
        reason: 'SimpleTextViewer חייב לרנדר AppContextMenuRegion לכל שורה');

    final regionCenter = tester.getCenter(regionFinder.first);
    await gesture.moveTo(regionCenter);
    await gesture.down(regionCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('העתק'), findsOneWidget,
        reason: 'תפריט הקשר חייב להכיל פריט "העתק"');

    final copyButton = tester.widget<MenuItemButton>(
      find
          .ancestor(
            of: find.text('העתק'),
            matching: find.byType(MenuItemButton),
          )
          .first,
    );
    expect(
      copyButton.onPressed,
      isNull,
      reason:
          '"העתק" חייב להיות מנוטרל כשאין בחירה — capturedText=null בזמן הבנייה',
    );
  });

  testWidgets(
      'אחרי סגירת תפריט, פוקוס שהמשתמש העביר לכפתור אחר אינו נגנב',
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
  test('מצב טקסט רציף מעבד הערות אינלייניות במקום להציג HTML גולמי', () {
    const rawText = 'פסוק <i class="footnote">*(בספרי תימן בסמ״ך גדולה)</i>';
    final processed = TextRendererService.processText(
      rawText,
      const RenderSettings(fontSize: 20),
    );
    final spans = buildInlineHtmlSpans(
      processed,
      const TextStyle(fontSize: 20),
    );
    final flattened = _flattenText(spans);
    final styledNote = _flattenTextSpans(spans).firstWhere(
      (span) => span.text?.contains('בספרי תימן') ?? false,
    );

    expect(flattened, contains('בספרי תימן'));
    expect(flattened, isNot(contains('<i')));
    expect(styledNote.style?.fontStyle, FontStyle.italic);
    expect(styledNote.style?.fontSize, lessThan(20));
  });

  test('מצב טקסט רציף משמר big בתוך הערה אינליינית', () {
    const rawText = 'text <i class="footnote">*(small <big>large</big>)</i>';
    final processed = TextRendererService.processText(
      rawText,
      const RenderSettings(fontSize: 20),
    );
    final spans = buildInlineHtmlSpans(
      processed,
      const TextStyle(fontSize: 20),
    );
    final textSpans = _flattenTextSpans(spans);
    final regularNote = textSpans.firstWhere(
      (span) => span.text?.contains('small') ?? false,
    );
    final enlargedNote = textSpans.firstWhere(
      (span) => span.text?.contains('large') ?? false,
    );
    final regularFontSize = regularNote.style!.fontSize!;
    final enlargedFontSize = enlargedNote.style!.fontSize!;

    expect(enlargedFontSize, greaterThan(regularFontSize));
    expect(enlargedNote.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('מצב טקסט רציף לא מיישר מקטע קצר לשני הצדדים', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: ContinuousReadingParagraph(
              lines: [
                ContinuousReadingParagraphLine(
                  lineIndex: 0,
                  text: 'מקטע קצר',
                  style: TextStyle(fontSize: 20),
                ),
              ],
              baseStyle: TextStyle(fontSize: 20),
              onLineTap: _noopLineTap,
            ),
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));

    expect(richText.textAlign, TextAlign.start);
  });

  testWidgets('מצב טקסט רציף משאיר justify למקטע שנשבר לכמה שורות',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: ContinuousReadingParagraph(
              lines: [
                ContinuousReadingParagraphLine(
                  lineIndex: 0,
                  text: 'זהו מקטע ארוך מספיק כדי להישבר לכמה שורות בתצוגה צרה',
                  style: TextStyle(fontSize: 20),
                ),
              ],
              baseStyle: TextStyle(fontSize: 20),
              onLineTap: _noopLineTap,
            ),
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));

    expect(richText.textAlign, TextAlign.justify);
  });
}

void _noopLineTap(int lineIndex) {}

String _flattenText(List<InlineSpan> spans) {
  final buffer = StringBuffer();
  for (final span in _flattenTextSpans(spans)) {
    buffer.write(span.text);
  }
  return buffer.toString();
}

List<TextSpan> _flattenTextSpans(List<InlineSpan> spans) {
  final result = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is! TextSpan) return;
    result.add(span);
    span.children?.forEach(visit);
  }

  spans.forEach(visit);
  return result;
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
