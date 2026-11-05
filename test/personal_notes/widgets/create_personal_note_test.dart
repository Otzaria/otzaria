import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/utils/create_personal_note.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _bookId = 'ספר בדיקה|user';
const _categoryId = 37;
const _lineNumber = 4;
const _anchor = PdfNoteAnchor(pageNumber: 4, x: .25, y: .75);

void main() {
  late _FailingCache cache;
  late _NotesRepository repository;
  late _RecordingNotesBloc bloc;
  var blocCreated = false;
  late int panelOpenCalls;
  final drafts = PersonalNoteDraftService();

  setUp(() async {
    cache = _FailingCache();
    await Settings.init(cacheProvider: cache);
    repository = _NotesRepository();
    blocCreated = false;
    panelOpenCalls = 0;
  });

  tearDown(() async {
    if (blocCreated) await bloc.close();
  });

  Future<void> saveDraft(String content, {PdfNoteAnchor? anchor}) =>
      drafts.saveDraft(
        bookId: _bookId,
        categoryId: _categoryId,
        lineNumber: _lineNumber,
        draft: PersonalNoteDraft(
          content: content,
          contentPlain: content,
          contentFormat: PersonalNoteContentFormat.plain,
          updatedAt: DateTime.utc(2026, 1, 1),
          pdfAnchor: anchor,
        ),
      );

  Future<void> open(
    WidgetTester tester, {
    bool panelOpen = false,
    PdfNoteAnchor? anchor,
    bool retargetSidebar = false,
  }) async {
    if (!blocCreated) {
      // הזרמים האסינכרוניים צריכים להירשם באזור הזמן של testWidgets.
      bloc = _RecordingNotesBloc(repository);
      blocCreated = true;
    }
    var sidebarBook = 'ספר אחר';
    bloc.add(LoadPersonalNotes(sidebarBook, categoryId: 99));
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) => SettingsRepository(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PersonalNotesBloc>.value(value: bloc),
            BlocProvider(
              create: (context) => SettingsBloc(
                repository: context.read<SettingsRepository>(),
              ),
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => Row(
                    children: [
                      TextButton(
                        onPressed: () => createPersonalNote(
                          context,
                          isNotesPanelOpen: panelOpen,
                          bookId: _bookId,
                          categoryId: _categoryId,
                          lineNumber: _lineNumber,
                          referenceText: 'מקור בדיקה',
                          selectedText: 'בחירה',
                          selectionColumn: 8,
                          sourceSelectedText: 'בְּחִירָה',
                          sourceSelectionOffset: 12,
                          punctuationHidden: true,
                          pdfAnchor: anchor,
                          repository: repository,
                          openNotesPanel: () {
                            panelOpenCalls++;
                            if (retargetSidebar) {
                              setState(() => sidebarBook = _bookId);
                            }
                          },
                        ),
                        child: const Text('צור הערה'),
                      ),
                      if (retargetSidebar)
                        Expanded(
                          child: PersonalNotesSidebar(
                            bookId: sidebarBook,
                            repository: repository,
                            isPdf: anchor != null,
                            pdfDocumentId: anchor?.documentId,
                            includeUnidentifiedPdfAnchors: true,
                            categoryId: sidebarBook == _bookId
                                ? _categoryId
                                : 99,
                            onNavigateToLine: (_, {note}) {},
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    bloc.received.clear();
    await tester.tap(find.text('צור הערה'));
    await tester.pumpAndSettle();
  }

  quill.QuillEditor editor(WidgetTester tester) =>
      tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor));

  Future<void> type(WidgetTester tester, String content) async {
    editor(tester).controller.replaceText(
      0,
      0,
      content,
      TextSelection.collapsed(offset: content.length),
    );
    await tester.pump();
  }

  Future<void> pressAction(WidgetTester tester, String text) async {
    await tester.tap(find.widgetWithText(ActionButton, text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('פאנל סגור פותח דיאלוג בלי לשנות יעד או מצב חלונית', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
    expect(bloc.received.whereType<StartCreatingPersonalNote>(), isEmpty);
    expect(bloc.state.bookId, 'ספר אחר');
    expect(panelOpenCalls, 0);
    await pressAction(tester, 'ביטול');
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(repository.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('שמירה בחלון צף משמרת ספר, קטגוריה, מקור בחירה ועוגן', (
    tester,
  ) async {
    await open(tester, anchor: _anchor);
    await type(tester, 'הערת בדיקה');
    await pressAction(tester, 'שמור');
    final saved = repository.writes.single;
    expect(saved.bookId, _bookId);
    expect(saved.categoryId, _categoryId);
    expect(saved.lineNumber, _lineNumber);
    expect(saved.contentPlain, 'הערת בדיקה');
    expect(saved.contentFormat, PersonalNoteContentFormat.quillDelta);
    expect(saved.selectedText, 'בחירה');
    expect(saved.selectionColumn, 8);
    expect(saved.sourceSelectedText, 'בְּחִירָה');
    expect(saved.sourceSelectionOffset, 12);
    expect(saved.punctuationHidden, isTrue);
    expect(saved.pdfAnchor, _anchor);
    expect(panelOpenCalls, 0);
    expect(bloc.state.bookId, 'ספר אחר');
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('פאנל פתוח משחזר טיוטה בתוך החלונית ולא פותח דיאלוג', (
    tester,
  ) async {
    await saveDraft('תוכן טיוטה', anchor: _anchor);
    await open(tester, panelOpen: true, anchor: _anchor);
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(panelOpenCalls, 1);
    final event = bloc.received.whereType<StartCreatingPersonalNote>().single;
    expect(event.bookId, _bookId);
    expect(event.initialContent, 'תוכן טיוטה');
    expect(event.pdfAnchor, _anchor);
    expect(event.sourceSelectionOffset, 12);
    expect(bloc.state.bookId, _bookId);
    expect(bloc.state.categoryId, _categoryId);
    expect(bloc.state.isCreatingNewNote, isTrue);
    expect(repository.writes, isEmpty);
  });

  testWidgets('Alt+Enter מתוך החלון הצף שומר פעם אחת בלי לשנות את התוכן', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'שורה ראשונה\nשורה שנייה');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(repository.attempts, 1);
    expect(repository.writes.single.contentPlain, 'שורה ראשונה\nשורה שנייה');
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('מעבר מהערות ספר אחר אינו מבטל את היצירה החדשה', (tester) async {
    await open(tester, panelOpen: true, retargetSidebar: true);
    expect(bloc.state.newNoteBookId, _bookId);
    expect(bloc.state.isCreatingNewNote, isTrue);
    expect(find.byType(InlineNoteEditor), findsOneWidget);
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('נקודה חדשה באותו עמוד אינה טוענת או מוחקת טיוטה בנקודה אחרת', (
    tester,
  ) async {
    await saveDraft('טיוטה בנקודה א', anchor: _anchor);
    const second = PdfNoteAnchor(pageNumber: 4, x: .8, y: .2);
    await open(tester, anchor: second);
    expect(editor(tester).controller.document.toPlainText().trim(), isEmpty);
    await type(tester, 'הערה בנקודה ב');
    await pressAction(tester, 'שמור');
    expect(repository.writes.single.pdfAnchor, second);
    expect(
      (await drafts.loadDraft(
        bookId: _bookId,
        categoryId: _categoryId,
        lineNumber: _lineNumber,
        pdfAnchor: _anchor,
      ))?.contentPlain,
      'טיוטה בנקודה א',
    );
  });

  testWidgets('החלפת נקודה בחלונית שומרת טיוטה ומתחילה עורך חדש', (
    tester,
  ) async {
    await open(tester, panelOpen: true, retargetSidebar: true, anchor: _anchor);
    await type(tester, 'טיוטה בנקודה א');
    const second = PdfNoteAnchor(pageNumber: 4, x: .8, y: .2);
    bloc.add(
      const StartCreatingPersonalNote(
        bookId: _bookId,
        lineNumber: _lineNumber,
        pdfAnchor: second,
      ),
    );
    await tester.pumpAndSettle();
    expect(editor(tester).controller.document.toPlainText().trim(), isEmpty);
    expect(
      (await drafts.loadDraft(
        bookId: _bookId,
        categoryId: _categoryId,
        lineNumber: _lineNumber,
        pdfAnchor: _anchor,
      ))?.contentPlain,
      'טיוטה בנקודה א',
    );
    await type(tester, 'תוכן בנקודה ב');
    await pressAction(tester, 'שמור');
    expect(repository.writes.single.pdfAnchor, second);
    expect(repository.writes.single.contentPlain, 'תוכן בנקודה ב');
    expect(
      (await drafts.loadDraft(
        bookId: _bookId,
        categoryId: _categoryId,
        lineNumber: _lineNumber,
        pdfAnchor: _anchor,
      ))?.contentPlain,
      'טיוטה בנקודה א',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('כשל שמירה משאיר תוכן לעריכה וחוסם שמירה כפולה בזמן ההמתנה', (
    tester,
  ) async {
    final pending = Completer<void>();
    repository.onAdd = () => pending.future;
    await open(tester);
    await type(tester, 'תוכן לשמירה חוזרת');
    editor(tester).controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      quill.ChangeSource.local,
    );
    final pendingContent = editor(
      tester,
    ).controller.document.toDelta().toJson();
    await pressAction(tester, 'שמור');
    expect(editor(tester).controller.readOnly, isTrue);
    expect(repository.attempts, 1);
    final boldIcon = find
        .descendant(
          of: find.byTooltip('מודגש'),
          matching: find.byType(Icon),
        )
        .first;
    Focus.of(tester.element(boldIcon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      editor(tester).controller.document.toDelta().toJson(),
      pendingContent,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(repository.attempts, 1);
    expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
    repository.onAdd = null;
    pending.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(editor(tester).controller.readOnly, isFalse);
    expect(editor(tester).focusNode.hasFocus, isTrue);
    expect(
      editor(tester).controller.document.toPlainText().trim(),
      'תוכן לשמירה חוזרת',
    );
    expect(repository.writes, isEmpty);
    await pressAction(tester, 'שמור');
    expect(repository.attempts, 2);
    expect(repository.writes, hasLength(1));
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('כשל מחיקת טיוטה לאחר שמירה אינו מאפשר יצירת עותק נוסף', (
    tester,
  ) async {
    await saveDraft('טיוטה קיימת');
    await open(tester);
    cache.failRemove = true;
    await pressAction(tester, 'שמור');
    expect(repository.writes, hasLength(1));
    expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('כשל כתיבה בחלונית שומר טיוטה גם אחרי סגירה ופתיחה מחדש', (
    tester,
  ) async {
    final pending = Completer<void>();
    repository.onAdd = () => pending.future;
    await open(tester, panelOpen: true, retargetSidebar: true);
    await type(tester, 'תוכן שנשמר אחרי ניסיון חוזר');
    await pressAction(tester, 'שמור');
    expect(editor(tester).controller.readOnly, isTrue);
    expect(repository.attempts, 1);
    expect(
      tester
          .widget<ActionButton>(find.widgetWithText(ActionButton, 'שמור'))
          .onPressed,
      isNull,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(repository.attempts, 1);
    pending.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(bloc.state.isCreatingNewNote, isTrue);
    expect(editor(tester).controller.readOnly, isFalse);
    expect(repository.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(
      (await drafts.loadDraft(
        bookId: _bookId,
        categoryId: _categoryId,
        lineNumber: _lineNumber,
      ))?.contentPlain,
      'תוכן שנשמר אחרי ניסיון חוזר',
    );
    repository.onAdd = null;
    await open(tester, panelOpen: true, retargetSidebar: true);
    expect(
      editor(tester).controller.document.toPlainText().trim(),
      'תוכן שנשמר אחרי ניסיון חוזר',
    );
    await pressAction(tester, 'שמור');
    expect(repository.attempts, 2);
    expect(
      repository.writes.single.contentPlain,
      'תוכן שנשמר אחרי ניסיון חוזר',
    );
    expect(bloc.state.isCreatingNewNote, isFalse);
    expect(
      await drafts.loadDraft(
        bookId: _bookId,
        categoryId: _categoryId,
        lineNumber: _lineNumber,
      ),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final discard in [false, true]) {
    testWidgets(
      'כשל ${discard ? 'מחיקת' : 'שמירת'} טיוטה בסגירה משאיר את העורך',
      (tester) async {
        if (discard) await saveDraft('טיוטה קיימת');
        await open(tester, anchor: discard ? null : _anchor);
        await type(tester, 'תוכן חדש ');
        cache.failWrite = !discard;
        cache.failRemove = discard;
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await pressAction(tester, discard ? 'סגור בלי לשמור' : 'שמור טיוטה');
        expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
        expect(
          editor(tester).controller.document.toPlainText(),
          contains('תוכן חדש'),
        );
        expect(tester.takeException(), isNull);
        cache.failWrite = false;
        cache.failRemove = false;
        await pressAction(tester, 'ביטול');
        await pressAction(tester, discard ? 'סגור בלי לשמור' : 'שמור טיוטה');
        expect(find.byType(PersonalNoteEditorDialog), findsNothing);
        final draft = await drafts.loadDraft(
          bookId: _bookId,
          categoryId: _categoryId,
          lineNumber: _lineNumber,
          pdfAnchor: discard ? null : _anchor,
        );
        if (discard) {
          expect(draft, isNull);
        } else {
          expect(draft?.contentPlain, 'תוכן חדש');
          expect(draft?.pdfAnchor, _anchor);
          expect(draft?.referenceText, 'מקור בדיקה');
        }
      },
    );
  }

  testWidgets('שינוי עיצוב בלבד מבקש החלטה גם כש-Escape מגיע מתוך העורך', (
    tester,
  ) async {
    await saveDraft('תוכן מעוצב');
    await open(tester);
    editor(tester).controller.formatText(0, 4, quill.Attribute.bold);
    await tester.pump();
    editor(tester).focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('ההערה לא נשמרה. לשמור טיוטה?'), findsOneWidget);
    await pressAction(tester, 'שמור טיוטה');
    final draft = await drafts.loadDraft(
      bookId: _bookId,
      categoryId: _categoryId,
      lineNumber: _lineNumber,
    );
    expect(draft?.content, contains('"bold":true'));
    expect(draft?.contentPlain, 'תוכן מעוצב');
  });
}

class _FailingCache extends MemoryCacheProvider {
  bool failWrite = false;
  bool failRemove = false;

  @override
  Future<void> setObject<T>(String key, T? value) {
    if (failWrite && key.startsWith(PersonalNoteDraftService.keyPrefix)) {
      throw StateError('draft storage unavailable');
    }
    return super.setObject<T>(key, value);
  }

  @override
  Future<void> remove(String key) {
    if (failRemove && key.startsWith(PersonalNoteDraftService.keyPrefix)) {
      throw StateError('draft storage unavailable');
    }
    return super.remove(key);
  }
}

class _RecordingNotesBloc extends PersonalNotesBloc {
  _RecordingNotesBloc(PersonalNotesRepository repository)
    : super(repository: repository);
  final received = <PersonalNotesEvent>[];

  @override
  void onEvent(PersonalNotesEvent event) {
    received.add(event);
    super.onEvent(event);
  }
}

class _NotesRepository extends PersonalNotesRepository {
  int attempts = 0;
  Future<void> Function()? onAdd;
  final writes = <AddPersonalNote>[];

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => [];

  @override
  Future<PersonalNote> createNote({
    required String bookId,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
    int? selectionColumn,
    String? sourceSelectedText,
    int? sourceSelectionOffset,
    bool punctuationHidden = false,
    PdfNoteAnchor? pdfAnchor,
    int? categoryId,
  }) async {
    attempts++;
    await onAdd?.call();
    writes.add(
      AddPersonalNote(
        bookId: bookId,
        lineNumber: lineNumber,
        content: content,
        contentPlain: contentPlain,
        contentFormat: contentFormat,
        selectedText: selectedText,
        selectionColumn: selectionColumn,
        sourceSelectedText: sourceSelectedText,
        sourceSelectionOffset: sourceSelectionOffset,
        punctuationHidden: punctuationHidden,
        pdfAnchor: pdfAnchor,
        categoryId: categoryId,
      ),
    );
    final now = DateTime.utc(2026, 1, 1);
    return PersonalNote(
      id: 'created-${writes.length}',
      bookId: bookId,
      lineNumber: lineNumber,
      lastKnownLineNumber: lineNumber,
      status: PersonalNoteStatus.located,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
      anchorText: selectedText,
      pdfAnchor: pdfAnchor,
      createdAt: now,
      updatedAt: now,
    );
  }
}
