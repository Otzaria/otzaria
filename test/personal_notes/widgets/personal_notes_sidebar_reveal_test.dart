import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:hive_ce/hive.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/utils/open_personal_notes_target.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _bookId = 'ספר בדיקה';

class _NotesRepository extends PersonalNotesRepository {
  final notes = List.generate(
    40,
    (index) => PersonalNote(
      id: 'note-${index + 1}',
      bookId: _bookId,
      lineNumber: index + 1,
      displayTitle: 'הערה ${index + 1}',
      lastKnownLineNumber: index + 1,
      status: PersonalNoteStatus.located,
      content: 'תוכן ${index + 1}',
      contentPlain: 'תוכן ${index + 1}',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => notes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<PersonalNotesBloc> pumpSidebar(
    WidgetTester tester, {
    int? focusLineNumber,
    PersonalNotesBloc? notesBloc,
    bool isPdf = false,
    String? pdfDocumentId,
  }) async {
    final bloc = notesBloc ?? PersonalNotesBloc(repository: _NotesRepository());
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 400,
              height: 400,
              child: BlocProvider<PersonalNotesBloc>.value(
                value: bloc,
                child: PersonalNotesSidebar(
                  bookId: _bookId,
                  isPdf: isPdf,
                  pdfDocumentId: pdfDocumentId,
                  focusLineNumber: focusLineNumber,
                  onNavigateToLine: (_, {note}) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  ItemScrollController controller(WidgetTester tester) => tester
      .widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList))
      .itemScrollController!;

  void expectVisible(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    final viewport = tester.getRect(find.byType(ScrollablePositionedList));
    expect(tester.getRect(finder).overlaps(viewport), isTrue);
  }

  testWidgets('פתיחה ראשונה גוללת להערה רחוקה ומרחיבה אותה לאחר הטעינה', (
    tester,
  ) async {
    await pumpSidebar(tester, focusLineNumber: 35);

    expectVisible(tester, find.text('תוכן 35'));
    expect(controller(tester).scrollController!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('עוגן PDF חסר נחשף אחרי כותרת וטופס, גם כשיש הערה באותו עמוד', (
    tester,
  ) async {
    const anchor = PdfNoteAnchor(
      pageNumber: 5,
      x: .2,
      y: .7,
      documentId: 'user|pdf-book',
    );
    final repository = _NotesRepository();
    repository.notes.add(
      PersonalNote(
        id: 'missing-pdf-point',
        bookId: _bookId,
        lineNumber: null,
        displayTitle: '',
        lastKnownLineNumber: 5,
        status: PersonalNoteStatus.missing,
        content: 'תוכן עוגן חסר',
        contentPlain: 'תוכן עוגן חסר',
        contentFormat: PersonalNoteContentFormat.plain,
        pdfAnchor: anchor,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    final notesBloc = PersonalNotesBloc(repository: repository);
    notesBloc.add(const LoadPersonalNotes(_bookId));
    await notesBloc.stream.firstWhere((state) => !state.isLoading);
    notesBloc.add(
      const StartCreatingPersonalNote(
        bookId: _bookId,
        lineNumber: 2,
        pdfAnchor: PdfNoteAnchor(
          pageNumber: 2,
          x: .1,
          y: .3,
          documentId: 'user|pdf-book',
        ),
      ),
    );
    await notesBloc.stream.firstWhere((state) => state.isCreatingNewNote);
    final bloc = await pumpSidebar(
      tester,
      notesBloc: notesBloc,
      isPdf: true,
      pdfDocumentId: anchor.documentId,
    );

    openPersonalNotesTarget(
      bloc,
      bookId: _bookId,
      lineNumber: 5,
      pdfAnchor: anchor,
    );
    await tester.pumpAndSettle();

    expectVisible(tester, find.text('תוכן עוגן חסר'));
    final tile = tester.widget<NoteTile>(
      find.byKey(const ValueKey('missing-pdf-point')),
    );
    expect(tile.expandToken, bloc.state.expandRequestToken);
    expect(bloc.state.isCreatingNewNote, isTrue);

    // בקשת שורה רגילה מסירה את הזהות הקודמת, גם אם המספר זהה.
    bloc.add(const RequestExpandNotesForLine(5));
    await tester.pumpAndSettle();
    expect(bloc.state.expandRequestPdfAnchor, isNull);
    expectVisible(tester, find.text('תוכן 5'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('לחיצה חוזרת גוללת שוב ליעד שנגלל החוצה ונפתח אחרי כיווץ', (
    tester,
  ) async {
    final bloc = await pumpSidebar(tester, focusLineNumber: 35);
    final target = find.byWidgetPredicate(
      (widget) => widget is NoteTile && widget.note.id == 'note-35',
    );
    await tester.tap(
      find.descendant(of: target, matching: find.byTooltip('סגור')),
    );
    await tester.pumpAndSettle();
    controller(tester).jumpTo(index: 0);
    await tester.pumpAndSettle();

    bloc.add(const RequestExpandNotesForLine(35));
    await tester.pumpAndSettle();

    expectVisible(tester, find.text('תוכן 35'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('יצירת הערה אחרי גלילה חושפת את העורך בראש הרשימה', (
    tester,
  ) async {
    final bloc = await pumpSidebar(tester);
    controller(tester).jumpTo(index: 30);
    await tester.pumpAndSettle();
    expect(controller(tester).scrollController!.offset, greaterThan(0));

    bloc.add(const StartCreatingPersonalNote(bookId: _bookId, lineNumber: 36));
    await tester.pumpAndSettle();

    expectVisible(tester, find.byType(InlineNoteEditor));
    // הכרטיס גבוה מהחלונית; הפוקוס עשוי לגלול שוב כדי לחשוף את אזור ההקלדה.
    // נדרשת נראות מלאה של הקלט ופוקוס פעיל, ולא היסט פיקסלים פנימי מסוים.
    final input = find.descendant(
      of: find.byType(InlineNoteEditor),
      matching: find.byType(quill.QuillEditor),
    );
    final viewport = tester.getRect(find.byType(ScrollablePositionedList));
    final inputRect = tester.getRect(input);
    expect(inputRect.top, greaterThanOrEqualTo(viewport.top - 1));
    expect(inputRect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    expect(tester.widget<quill.QuillEditor>(input).focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('רענון רגיל אינו מחזיר את המשתמש ליעד שכבר נחשף', (
    tester,
  ) async {
    final bloc = await pumpSidebar(tester, focusLineNumber: 35);
    controller(tester).jumpTo(index: 0);
    await tester.pumpAndSettle();

    bloc.add(const LoadPersonalNotes(_bookId));
    await tester.pumpAndSettle();

    expect(controller(tester).scrollController!.offset, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ניווט אחרון גובר על טיוטה פעילה גם בבנייה ראשונה של החלונית', (
    tester,
  ) async {
    final notesBloc = PersonalNotesBloc(repository: _NotesRepository());
    notesBloc.add(const LoadPersonalNotes(_bookId));
    await notesBloc.stream.firstWhere((state) => !state.isLoading);
    notesBloc.add(
      const StartCreatingPersonalNote(bookId: _bookId, lineNumber: 2),
    );
    notesBloc.add(const RequestExpandNotesForLine(35));
    await notesBloc.stream.firstWhere(
      (state) => state.expandRequestLineNumber == 35,
    );
    final bloc = await pumpSidebar(tester, notesBloc: notesBloc);

    expectVisible(tester, find.text('תוכן 35'));
    expect(bloc.state.isCreatingNewNote, isTrue);
    bloc.add(const LoadPersonalNotes(_bookId));
    await tester.pumpAndSettle();
    expectVisible(tester, find.text('תוכן 35'));

    bloc.add(
      const StartCreatingPersonalNote(bookId: _bookId, lineNumber: 2),
    );
    await tester.pumpAndSettle();
    expectVisible(tester, find.byType(InlineNoteEditor));
    expect(bloc.state.expandRequestLineNumber, isNull);
    expect(controller(tester).scrollController!.offset, closeTo(0, 0.01));
    await tester.pumpWidget(const SizedBox());
  });

  for (final (selection, cancelFirst) in [
    ('בחירה שנייה', false),
    ('בחירה ראשונה', false),
    ('בחירה ראשונה', true),
  ]) {
    testWidgets(
      'בקשת יצירה חוזרת חושפת עורך שנגלל החוצה: $selection, ביטול קודם=$cancelFirst',
      (tester) async {
        final bloc = await pumpSidebar(tester);
        bloc.add(
          const StartCreatingPersonalNote(
            bookId: _bookId,
            lineNumber: 2,
            selectedText: 'בחירה ראשונה',
          ),
        );
        await tester.pumpAndSettle();
        final originalController = tester
            .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
            .controller;
        controller(tester).jumpTo(index: 30);
        await tester.pumpAndSettle();

        if (cancelFirst) bloc.add(const CancelCreatingPersonalNote());
        bloc.add(
          StartCreatingPersonalNote(
            bookId: _bookId,
            lineNumber: 2,
            selectedText: selection,
          ),
        );
        await tester.pumpAndSettle();

        expectVisible(tester, find.byType(InlineNoteEditor));
        final input = find.descendant(
          of: find.byType(InlineNoteEditor),
          matching: find.byType(quill.QuillEditor),
        );
        final editor = tester.widget<quill.QuillEditor>(input);
        expect(identical(editor.controller, originalController), !cancelFirst);
        if (cancelFirst) {
          // יצירה חדשה מבקשת פוקוס וגוללת את הקלט לתצוגה גם בכרטיס גבוה.
          final viewport = tester.getRect(
            find.byType(ScrollablePositionedList),
          );
          final inputRect = tester.getRect(input);
          expect(inputRect.top, greaterThanOrEqualTo(viewport.top - 1));
          expect(inputRect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
          expect(editor.focusNode.hasFocus, isTrue);
        } else {
          expect(controller(tester).scrollController!.offset, closeTo(0, 0.01));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('נקודת PDF חדשה מחליפה עורך מחוץ למסך ובקשה זהה משמרת אותו', (
    tester,
  ) async {
    const documentId = 'user|pdf-points';
    const first = PdfNoteAnchor(
      pageNumber: 2,
      x: .2,
      y: .3,
      documentId: documentId,
    );
    const second = PdfNoteAnchor(
      pageNumber: 2,
      x: .8,
      y: .7,
      documentId: documentId,
    );
    final bloc = await pumpSidebar(
      tester,
      isPdf: true,
      pdfDocumentId: documentId,
    );
    void request(PdfNoteAnchor anchor, {bool staleDraft = false}) => bloc.add(
      StartCreatingPersonalNote(
        bookId: _bookId,
        lineNumber: 2,
        initialContent: staleDraft
            ? '[{"insert":"טיוטה ישנה\\n"}]'
            : 'תוכן התחלתי',
        initialFormat: staleDraft
            ? PersonalNoteContentFormat.quillDelta
            : PersonalNoteContentFormat.plain,
        pdfAnchor: anchor,
      ),
    );
    quill.QuillEditor editor() => tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );

    request(first);
    await tester.pumpAndSettle();
    final firstController = editor().controller;
    firstController.document.insert(0, 'נקודה א ');
    await tester.pumpAndSettle();
    controller(tester).jumpTo(index: 30);
    await tester.pumpAndSettle();

    request(second);
    await tester.pumpAndSettle();
    final secondController = editor().controller;
    expect(identical(firstController, secondController), isFalse);
    expect(secondController.document.toPlainText().trim(), 'תוכן התחלתי');
    expectVisible(tester, find.byType(quill.QuillEditor));
    expect(
      (await PersonalNoteDraftService().loadDraft(
        bookId: _bookId,
        lineNumber: 2,
        pdfAnchor: first,
      ))?.contentPlain,
      'נקודה א תוכן התחלתי',
    );
    expect(tester.takeException(), isNull);

    secondController.document.insert(0, 'נקודה ב ');
    await tester.pumpAndSettle();
    controller(tester).jumpTo(index: 30);
    await tester.pumpAndSettle();
    request(second, staleDraft: true);
    await tester.pumpAndSettle();
    expect(identical(editor().controller, secondController), isTrue);
    expect(
      editor().controller.document.toPlainText().trim(),
      'נקודה ב תוכן התחלתי',
    );
    expectVisible(tester, find.byType(InlineNoteEditor));
    expect(controller(tester).scrollController!.offset, closeTo(0, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  group('שחזור טיוטה שמורה', () {
    final drafts = PersonalNoteDraftService();

    setUp(() async {
      // Hive אמיתי נדרש לסריקת box.keys; backend בזיכרון מאפשר גם לשמירה
      // מתוך dispose להסתיים ב-fakeAsync, בלי כתיבת קובץ שממשיכה לאחר הבדיקה.
      await Hive.openBox<dynamic>(
        HiveCache.keyName,
        bytes: Uint8List(0),
      );
      await Settings.init(cacheProvider: HiveCache());
      await drafts.saveDraft(
        bookId: _bookId,
        lineNumber: 2,
        draft: PersonalNoteDraft(
          content: 'טיוטה שנשמרה',
          contentPlain: 'טיוטה שנשמרה',
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime(2026),
          lineNumber: 2,
        ),
      );
    });

    tearDown(() async {
      await Hive.close();
    });

    testWidgets('פתיחת חלונית רגילה עדיין משחזרת את הטיוטה', (tester) async {
      final bloc = await pumpSidebar(tester);

      expect(bloc.state.newNoteLineNumber, 2);
      expect(bloc.state.newNoteInitialContent, 'טיוטה שנשמרה');
      expectVisible(tester, find.byType(InlineNoteEditor));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(
        (await drafts.loadDraft(bookId: _bookId, lineNumber: 2))?.contentPlain,
        'טיוטה שנשמרה',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ניווט מפורש אינו נגנב על ידי טיוטה שמורה בשורה אחרת', (
      tester,
    ) async {
      final bloc = await pumpSidebar(tester, focusLineNumber: 35);

      expectVisible(tester, find.text('תוכן 35'));
      expect(bloc.state.isCreatingNewNote, isFalse);
      expect(
        (await drafts.loadDraft(bookId: _bookId, lineNumber: 2))?.content,
        'טיוטה שנשמרה',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('יצירה מפורשת אינה מוחלפת בטיוטה שמורה של שורה אחרת', (
      tester,
    ) async {
      final notesBloc = PersonalNotesBloc(repository: _NotesRepository());
      notesBloc.add(
        const StartCreatingPersonalNote(
          bookId: _bookId,
          lineNumber: 36,
          initialContent: 'טיוטה נוכחית',
        ),
      );
      await notesBloc.stream.firstWhere((state) => state.isCreatingNewNote);
      final bloc = await pumpSidebar(tester, notesBloc: notesBloc);

      expect(bloc.state.newNoteLineNumber, 36);
      expect(bloc.state.newNoteInitialContent, 'טיוטה נוכחית');
      expectVisible(tester, find.byType(InlineNoteEditor));
      expect(
        (await drafts.loadDraft(bookId: _bookId, lineNumber: 2))?.content,
        'טיוטה שנשמרה',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(
        (await drafts.loadDraft(bookId: _bookId, lineNumber: 36))?.contentPlain,
        'טיוטה נוכחית',
      );
      expect(
        (await drafts.loadDraft(bookId: _bookId, lineNumber: 2))?.contentPlain,
        'טיוטה שנשמרה',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
