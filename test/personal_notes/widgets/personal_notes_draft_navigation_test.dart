import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';

const _bookId = 'draft-navigation-book';
const _categoryId = 17;
const _lineNumber = 4;

class _DraftCache extends HiveCache {
  Completer<void>? removeGate;
  bool failRemove = false;
  int draftRemovals = 0;

  @override
  Future<void> remove(String key) async {
    if (!key.startsWith(PersonalNoteDraftService.keyPrefix)) {
      return super.remove(key);
    }
    draftRemovals++;
    if (failRemove) throw StateError('draft cleanup failed');
    final removal = super.remove(key);
    await removeGate?.future;
    await removal;
  }
}

class _PendingRepository extends PersonalNotesRepository {
  final notes = <PersonalNote>[];
  Completer<void>? pendingCreate;
  int creates = 0;

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => notes.where((note) => note.bookId == bookId).toList();

  @override
  Future<List<PersonalNote>> loadStoredNotes(String bookId) =>
      loadNotes(bookId);

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
    creates++;
    await pendingCreate?.future;
    final now = DateTime.utc(2026, 1, 1);
    final note = PersonalNote(
      id: 'saved-${notes.length + 1}',
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
    notes.add(note);
    PersonalNotesChanges.notify(bookId);
    return note;
  }
}

class _NotesBloc extends PersonalNotesBloc {
  _NotesBloc({required super.repository});

  VoidCallback? beforeCancel;

  @override
  void onEvent(PersonalNotesEvent event) {
    super.onEvent(event);
    if (event is CancelCreatingPersonalNote) {
      final callback = beforeCancel;
      beforeCancel = null;
      callback?.call();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final drafts = PersonalNoteDraftService();
  late _DraftCache cache;

  setUp(() async {
    // סריקת טיוטות משתמשת ב-box.keys, ולכן שירות הטיוטות ו-Hive אמיתיים.
    await Hive.openBox<dynamic>(HiveCache.keyName, bytes: Uint8List(0));
    cache = _DraftCache();
    await Settings.init(cacheProvider: cache);
  });

  tearDown(Hive.close);

  Future<
    ({
      _NotesBloc bloc,
      _PendingRepository repository,
      ValueNotifier<bool> visible,
    })
  >
  open(
    WidgetTester tester, {
    bool adaptivePane = false,
    PdfNoteAnchor? pdfAnchor,
  }) async {
    await drafts.saveDraft(
      bookId: _bookId,
      categoryId: _categoryId,
      lineNumber: _lineNumber,
      draft: PersonalNoteDraft(
        content: 'טיוטה מקורית',
        contentPlain: 'טיוטה מקורית',
        contentFormat: PersonalNoteContentFormat.plain,
        updatedAt: DateTime.utc(2026),
        pdfAnchor: pdfAnchor,
      ),
    );
    final repository = _PendingRepository();
    // הרשמת זרמי BLoC באזור הזמן של testWidgets, לא ב-setUp.
    final bloc = _NotesBloc(repository: repository);
    final visible = ValueNotifier(true);
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() async {
      if (cache.removeGate case final gate? when !gate.isCompleted) {
        gate.complete();
      }
      if (repository.pendingCreate case final pending?
          when !pending.isCompleted && repository.creates > 0) {
        pending.completeError(StateError('test cleanup'));
        await tester.pump();
      }
      UiSnack.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (!bloc.isClosed) await bloc.close();
      visible.dispose();
      await tester.binding.setSurfaceSize(null);
    });
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
            navigatorKey: navigatorKey,
            locale: const Locale('he'),
            supportedLocales: const [Locale('he'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              quill.FlutterQuillLocalizations.delegate,
            ],
            home: DefaultTabController(
              length: 2,
              child: Scaffold(
                body: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'הערות לבדיקה'),
                        Tab(text: 'חלונית אחרת'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          ValueListenableBuilder<bool>(
                            valueListenable: visible,
                            builder: (context, show, _) {
                              final sidebar = PersonalNotesSidebar(
                                bookId: _bookId,
                                categoryId: _categoryId,
                                isPdf: pdfAnchor != null,
                                pdfDocumentId: pdfAnchor?.documentId,
                                repository: repository,
                                onNavigateToLine: (_, {note}) {},
                              );
                              if (adaptivePane) {
                                return AdaptiveSidePane(
                                  isOpen: show,
                                  paneWidth: 600,
                                  minMainContentWidth: 200,
                                  onClose: () => visible.value = false,
                                  mainContent: const SizedBox.expand(),
                                  paneContent: sidebar,
                                );
                              }
                              return show ? sidebar : const SizedBox.shrink();
                            },
                          ),
                          const Center(child: Text('תוכן חלונית אחרת')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InlineNoteEditor), findsOneWidget);
    return (bloc: bloc, repository: repository, visible: visible);
  }

  quill.QuillController controller(WidgetTester tester) => tester
      .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
      .controller;

  Future<void> replace(WidgetTester tester, String text) async {
    final editor = controller(tester);
    editor.replaceText(
      0,
      editor.document.length - 1,
      text,
      TextSelection.collapsed(offset: text.length),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<PersonalNoteDraft?> readDraft({PdfNoteAnchor? pdfAnchor}) =>
      drafts.loadDraft(
        bookId: _bookId,
        categoryId: _categoryId,
        lineNumber: _lineNumber,
        pdfAnchor: pdfAnchor,
      );

  Iterable<dynamic> draftKeys() =>
      Hive.box<dynamic>(HiveCache.keyName).keys.where(
        (key) => key.toString().startsWith(PersonalNoteDraftService.keyPrefix),
      );

  testWidgets('tab navigation without Save keeps one live draft', (
    tester,
  ) async {
    final host = await open(tester);
    await replace(tester, 'טקסט שנערך בלי שמירה');
    final originalController = controller(tester);
    final token = host.bloc.state.newNoteRequestToken;

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('חלונית אחרת'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הערות לבדיקה'));
      await tester.pumpAndSettle();
    }

    expect(identical(controller(tester), originalController), isTrue);
    expect(
      controller(tester).document.toPlainText().trim(),
      'טקסט שנערך בלי שמירה',
    );
    expect(host.bloc.state.newNoteRequestToken, token);
    expect(host.repository.creates, 0);
    expect(host.repository.notes, isEmpty);
    expect(draftKeys(), hasLength(1));
    expect((await readDraft())?.contentPlain, 'טקסט שנערך בלי שמירה');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'save completed after panel removal does not reopen a duplicate',
    (
      tester,
    ) async {
      final host = await open(tester);
      final pending = host.repository.pendingCreate = Completer<void>();
      await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
      await tester.pump();
      expect(host.repository.creates, 1);
      host.visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      pending.complete();
      await tester.pumpAndSettle();
      host.visible.value = true;
      await tester.pumpAndSettle();

      expect(host.repository.notes, hasLength(1));
      expect(host.repository.notes.single.contentPlain, 'טיוטה מקורית');
      expect(await readDraft(), isNull);
      expect(host.bloc.state.isCreatingNewNote, isFalse);
      expect(find.byType(InlineNoteEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('adaptive pane hide and show without Save keeps one live draft', (
    tester,
  ) async {
    final host = await open(tester, adaptivePane: true);
    await replace(tester, 'טיוטה בזמן סגירת חלונית');
    final originalController = controller(tester);
    final token = host.bloc.state.newNoteRequestToken;
    for (var i = 0; i < 3; i++) {
      host.visible.value = false;
      await tester.pumpAndSettle();
      host.visible.value = true;
      await tester.pumpAndSettle();
    }

    expect(identical(controller(tester), originalController), isTrue);
    expect(host.bloc.state.newNoteRequestToken, token);
    expect(host.repository.creates, 0);
    expect(host.repository.notes, isEmpty);
    expect((await readDraft())?.contentPlain, 'טיוטה בזמן סגירת חלונית');
    expect(draftKeys(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('late save keeps a newer draft at the same location', (
    tester,
  ) async {
    final host = await open(tester);
    final pending = host.repository.pendingCreate = Completer<void>();
    await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
    await tester.pump();
    expect(host.repository.creates, 1);
    host.visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    host.bloc.add(const CancelCreatingPersonalNote());
    host.bloc.add(
      const StartCreatingPersonalNote(
        bookId: _bookId,
        lineNumber: _lineNumber,
        initialContent: 'בקשה חדשה',
      ),
    );
    await tester.pump();
    final newToken = host.bloc.state.newNoteRequestToken;
    host.visible.value = true;
    await tester.pump();
    await replace(tester, 'טיוטה חדשה באותה שורה');
    expect((await readDraft())?.contentPlain, 'טיוטה חדשה באותה שורה');
    pending.complete();
    await tester.pumpAndSettle();

    expect(host.repository.notes, hasLength(1));
    expect(host.bloc.state.newNoteRequestToken, newToken);
    expect(host.bloc.state.isCreatingNewNote, isTrue);
    expect(
      controller(tester).document.toPlainText().trim(),
      'טיוטה חדשה באותה שורה',
    );
    expect((await readDraft())?.contentPlain, 'טיוטה חדשה באותה שורה');
    expect(draftKeys(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restoring the panel while save is pending does not revive the draft',
    (
      tester,
    ) async {
      final host = await open(tester);
      final oldController = controller(tester);
      final pending = host.repository.pendingCreate = Completer<void>();
      await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
      await tester.pump();
      expect(host.repository.creates, 1);
      host.visible.value = false;
      await tester.pump();
      host.visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(identical(controller(tester), oldController), isFalse);
      pending.complete();
      await tester.pumpAndSettle();

      expect(host.repository.notes, hasLength(1));
      expect(host.bloc.state.isCreatingNewNote, isFalse);
      expect(find.byType(InlineNoteEditor), findsNothing);
      expect(await readDraft(), isNull);
      expect(draftKeys(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restored editor preserves new typing before its debounce', (
    tester,
  ) async {
    final host = await open(tester);
    final pending = host.repository.pendingCreate = Completer<void>();
    await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
    await tester.pump();
    expect(host.repository.creates, 1);
    host.visible.value = false;
    await tester.pump();
    host.visible.value = true;
    await tester.pump();
    final editor = controller(tester);
    editor.replaceText(
      0,
      editor.document.length - 1,
      'תוספת שטרם נשמרה בטיוטה',
      const TextSelection.collapsed(offset: 0),
    );
    pending.complete();
    await tester.pumpAndSettle();

    expect(host.repository.notes.single.contentPlain, 'טיוטה מקורית');
    expect((await readDraft())?.contentPlain, 'תוספת שטרם נשמרה בטיוטה');
    expect(draftKeys(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mounted save confirms success after delayed draft cleanup', (
    tester,
  ) async {
    final host = await open(tester);
    final gate = cache.removeGate = Completer<void>();
    await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
    await tester.pump();
    expect(host.repository.notes, hasLength(1));
    expect(cache.draftRemovals, 1);
    expect(host.bloc.state.isCreatingNewNote, isTrue);
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text(NotesMessages.noteSaved), findsOneWidget);
    expect(host.bloc.state.isCreatingNewNote, isFalse);
    expect(find.byType(InlineNoteEditor), findsNothing);
    UiSnack.hide();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mounted save reports cleanup failure and completes its request',
    (
      tester,
    ) async {
      final host = await open(tester);
      cache.failRemove = true;
      await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
      await tester.pumpAndSettle();

      expect(host.repository.notes, hasLength(1));
      expect(
        find.text(NotesMessages.noteSavedDraftCleanupFailed),
        findsOneWidget,
      );
      expect(host.bloc.state.isCreatingNewNote, isFalse);
      expect(find.byType(InlineNoteEditor), findsNothing);
      expect((await readDraft())?.contentPlain, 'טיוטה מקורית');
      UiSnack.hide();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restoring the panel during draft cleanup does not revive the draft',
    (
      tester,
    ) async {
      final host = await open(tester);
      final gate = cache.removeGate = Completer<void>();
      await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
      await tester.pump();
      expect(host.repository.notes, hasLength(1));
      expect(cache.draftRemovals, 1);
      host.visible.value = false;
      await tester.pump();
      host.visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(InlineNoteEditor), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();

      expect(host.repository.notes, hasLength(1));
      expect(host.bloc.state.isCreatingNewNote, isFalse);
      expect(find.byType(InlineNoteEditor), findsNothing);
      expect(await readDraft(), isNull);
      expect(draftKeys(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('queued creation survives completion of the preceding save', (
    tester,
  ) async {
    final host = await open(tester);
    final pending = host.repository.pendingCreate = Completer<void>();
    await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
    await tester.pump();
    expect(host.repository.creates, 1);
    host.bloc.beforeCancel = () => host.bloc.add(
      const StartCreatingPersonalNote(
        bookId: _bookId,
        lineNumber: 8,
        initialContent: 'יצירה שהמתינה בתור',
      ),
    );
    pending.complete();
    await tester.pumpAndSettle();

    expect(host.repository.notes, hasLength(1));
    expect(host.bloc.state.isCreatingNewNote, isTrue);
    expect(host.bloc.state.newNoteLineNumber, 8);
    expect(
      controller(tester).document.toPlainText().trim(),
      'יצירה שהמתינה בתור',
    );
    UiSnack.hide();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure after removal preserves its recoverable draft', (
    tester,
  ) async {
    final host = await open(tester);
    final pending = host.repository.pendingCreate = Completer<void>();
    await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
    await tester.pump();
    expect(host.repository.creates, 1);
    host.visible.value = false;
    await tester.pump();
    pending.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();

    expect(host.repository.notes, isEmpty);
    expect((await readDraft())?.contentPlain, 'טיוטה מקורית');
    expect(draftKeys(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('save can finish after its notes bloc has closed', (
    tester,
  ) async {
    final host = await open(tester);
    final pending = host.repository.pendingCreate = Completer<void>();
    await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
    await tester.pump();
    expect(host.repository.creates, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    var closeCompleted = false;
    unawaited(
      host.bloc.close().then<void>((_) {
        closeCompleted = true;
      }),
    );
    // Stream cancellation crosses the real and fake async zones. Drain both
    // while keeping the actual note write suspended throughout closure.
    for (var i = 0; i < 100 && !closeCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(closeCompleted, isTrue);
    expect(host.bloc.isClosed, isTrue);
    expect(pending.isCompleted, isFalse);
    pending.complete();
    await tester.pumpAndSettle();

    expect(host.repository.notes, hasLength(1));
    expect(await readDraft(), isNull);
    expect(tester.takeException(), isNull);
  });

  group('creation session', () {
    for (final pdfAnchor in <PdfNoteAnchor?>[
      null,
      const PdfNoteAnchor(
        pageNumber: _lineNumber,
        x: .2,
        y: .7,
        documentId: 'user|draft-navigation-pdf',
      ),
    ]) {
      testWidgets(
        'repeated ${pdfAnchor == null ? 'text' : 'PDF'} request during save closes the saved editor',
        (tester) async {
          final host = await open(tester, pdfAnchor: pdfAnchor);
          await replace(tester, 'תוכן שנערך לפני השמירה');
          final originalController = controller(tester);
          final token = host.bloc.state.newNoteRequestToken;
          final pending = host.repository.pendingCreate = Completer<void>();
          await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
          await tester.pump();
          expect(host.repository.creates, 1);
          expect(originalController.readOnly, isTrue);

          host.bloc.add(
            StartCreatingPersonalNote(
              bookId: _bookId,
              lineNumber: _lineNumber,
              initialContent: 'בקשה חוזרת עם תוכן ישן',
              pdfAnchor: pdfAnchor == null
                  ? null
                  : PdfNoteAnchor(
                      pageNumber: pdfAnchor.pageNumber,
                      x: pdfAnchor.x,
                      y: pdfAnchor.y,
                      documentId: pdfAnchor.documentId,
                    ),
            ),
          );
          await tester.pumpAndSettle();
          expect(host.bloc.state.newNoteRequestToken, greaterThan(token));
          expect(identical(controller(tester), originalController), isTrue);
          expect(
            controller(tester).document.toPlainText().trim(),
            'תוכן שנערך לפני השמירה',
          );

          pending.complete();
          await tester.pumpAndSettle();

          expect(host.repository.notes, hasLength(1));
          expect(
            host.repository.notes.single.contentPlain,
            'תוכן שנערך לפני השמירה',
          );
          expect(host.repository.notes.single.pdfAnchor, pdfAnchor);
          expect(host.bloc.state.isCreatingNewNote, isFalse);
          expect(find.byType(InlineNoteEditor), findsNothing);
          expect(await readDraft(pdfAnchor: pdfAnchor), isNull);
          expect(draftKeys(), isEmpty);
          UiSnack.hide();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('queued same-location request closes the saved editor', (
      tester,
    ) async {
      final host = await open(tester);
      final pending = host.repository.pendingCreate = Completer<void>();
      await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
      await tester.pump();
      expect(host.repository.creates, 1);
      host.bloc.beforeCancel = () => host.bloc.add(
        const StartCreatingPersonalNote(
          bookId: _bookId,
          lineNumber: _lineNumber,
          initialContent: 'בקשה חוזרת שהמתינה בתור',
        ),
      );

      pending.complete();
      await tester.pumpAndSettle();

      expect(host.repository.notes, hasLength(1));
      expect(host.bloc.state.isCreatingNewNote, isFalse);
      expect(find.byType(InlineNoteEditor), findsNothing);
      expect(await readDraft(), isNull);
      expect(draftKeys(), isEmpty);
      UiSnack.hide();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    for (final processRequest in [false, true]) {
      testWidgets(
        'save before rebuild ${processRequest ? 'after' : 'before'} the repeated request reaches the bloc',
        (tester) async {
          final host = await open(tester);
          final originalController = controller(tester);
          final token = host.bloc.state.newNoteRequestToken;
          final save = tester
              .widget<ActionButton>(
                find.widgetWithText(ActionButton, 'שמור'),
              )
              .onPressed!;
          final pending = host.repository.pendingCreate = Completer<void>();
          host.bloc.add(
            const StartCreatingPersonalNote(
              bookId: _bookId,
              lineNumber: _lineNumber,
              initialContent: 'בקשה חוזרת לפני הבנייה',
            ),
          );
          if (processRequest) await tester.idle();
          expect(
            host.bloc.state.newNoteRequestToken,
            processRequest ? greaterThan(token) : token,
          );
          expect(identical(controller(tester), originalController), isTrue);

          // מפעילים את הכפתור הקיים בלי לבנות מחדש את ה-callback שלו.
          save();
          await tester.pump();
          expect(host.repository.creates, 1);
          pending.complete();
          await tester.pumpAndSettle();

          expect(host.repository.notes, hasLength(1));
          expect(host.repository.notes.single.contentPlain, 'טיוטה מקורית');
          expect(host.bloc.state.isCreatingNewNote, isFalse);
          expect(find.byType(InlineNoteEditor), findsNothing);
          expect(await readDraft(), isNull);
          UiSnack.hide();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final typeBeforeClosing in [false, true]) {
      testWidgets(
        'cancel and restart in one frame preserves ${typeBeforeClosing ? 'typing before debounce' : 'new initial content'} after the old save',
        (tester) async {
          final host = await open(tester);
          final originalController = controller(tester);
          final pending = host.repository.pendingCreate = Completer<void>();
          await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
          await tester.pump();
          expect(host.repository.creates, 1);

          // בקשת יצירה משחזרת initialContent משירות הטיוטות.
          await drafts.saveDraft(
            bookId: _bookId,
            categoryId: _categoryId,
            lineNumber: _lineNumber,
            draft: PersonalNoteDraft(
              content: 'תוכן של יצירה חדשה',
              contentPlain: 'תוכן של יצירה חדשה',
              contentFormat: PersonalNoteContentFormat.plain,
              updatedAt: DateTime.utc(2026, 1, 2),
            ),
          );
          host.bloc.add(const CancelCreatingPersonalNote());
          host.bloc.add(
            const StartCreatingPersonalNote(
              bookId: _bookId,
              lineNumber: _lineNumber,
              initialContent: 'תוכן של יצירה חדשה',
            ),
          );
          await tester.pump();
          final newController = controller(tester);
          expect(identical(newController, originalController), isFalse);
          expect(newController.readOnly, isFalse);
          expect(
            newController.document.toPlainText().trim(),
            'תוכן של יצירה חדשה',
          );

          final expectedDraft = typeBeforeClosing
              ? 'תוכן חדש שטרם עבר השהיה'
              : 'תוכן של יצירה חדשה';
          if (typeBeforeClosing) {
            newController.replaceText(
              0,
              newController.document.length - 1,
              expectedDraft,
              TextSelection.collapsed(offset: expectedDraft.length),
            );
          }
          pending.complete();
          await tester.pump();
          await tester.idle();
          expect(host.repository.notes, hasLength(1));
          expect(host.repository.notes.single.contentPlain, 'טיוטה מקורית');
          expect(host.bloc.state.isCreatingNewNote, isTrue);
          expect(identical(controller(tester), newController), isTrue);
          expect(newController.readOnly, isFalse);
          expect(
            tester
                .widget<ActionButton>(find.widgetWithText(ActionButton, 'שמור'))
                .onPressed,
            isNotNull,
          );

          host.visible.value = false;
          await tester.pump();
          await tester.idle();

          expect((await readDraft())?.contentPlain, expectedDraft);
          expect(draftKeys(), hasLength(1));
          // חושפים את הטיוטה שנכתבה, בלי להישען על תוכן בקשת היצירה הקודמת.
          host.bloc.add(const CancelCreatingPersonalNote());
          await tester.pump();
          host.visible.value = true;
          await tester.pumpAndSettle();
          expect(controller(tester).readOnly, isFalse);
          expect(
            controller(tester).document.toPlainText().trim(),
            expectedDraft,
          );
          await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
          await tester.pumpAndSettle();

          expect(host.repository.notes.map((note) => note.contentPlain), [
            'טיוטה מקורית',
            expectedDraft,
          ]);
          expect(host.bloc.state.isCreatingNewNote, isFalse);
          expect(find.byType(InlineNoteEditor), findsNothing);
          expect(await readDraft(), isNull);
          UiSnack.hide();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('repeated request keeps a failed save editable for retry', (
      tester,
    ) async {
      final host = await open(tester);
      await replace(tester, 'תוכן לניסיון חוזר');
      final originalController = controller(tester);
      final pending = host.repository.pendingCreate = Completer<void>();
      await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
      await tester.pump();
      host.bloc.add(
        const StartCreatingPersonalNote(
          bookId: _bookId,
          lineNumber: _lineNumber,
          initialContent: 'בקשה חוזרת בזמן שמירה',
        ),
      );
      await tester.pump();
      pending.completeError(StateError('storage unavailable'));
      await tester.pumpAndSettle();

      expect(host.repository.notes, isEmpty);
      expect(host.bloc.state.isCreatingNewNote, isTrue);
      expect(identical(controller(tester), originalController), isTrue);
      expect(originalController.readOnly, isFalse);
      expect((await readDraft())?.contentPlain, 'תוכן לניסיון חוזר');
      expect(
        tester
            .widget<ActionButton>(find.widgetWithText(ActionButton, 'שמור'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<ActionButton>(find.widgetWithText(ActionButton, 'ביטול'))
            .onPressed,
        isNotNull,
      );

      host.repository.pendingCreate = null;
      UiSnack.hide();
      await tester.pump();
      await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
      await tester.pumpAndSettle();

      expect(host.repository.creates, 2);
      expect(host.repository.notes, hasLength(1));
      expect(host.repository.notes.single.contentPlain, 'תוכן לניסיון חוזר');
      expect(host.bloc.state.isCreatingNewNote, isFalse);
      expect(find.byType(InlineNoteEditor), findsNothing);
      expect(await readDraft(), isNull);
      UiSnack.hide();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
