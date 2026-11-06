import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/utils/pdf_personal_note_anchor.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../test_helpers/memory_cache_provider.dart';

class _NotesRepository extends PersonalNotesRepository {
  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) =>
      PersonalNotesDatabase.instance.loadNotes(bookId);
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final database = PersonalNotesDatabase.instance;
  final originalModulePath = Pdfrx.pdfiumModulePath;
  late Directory directory;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await database.close();
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-notes-');
    AppPaths.debugOverrideDataRootPath(directory.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${directory.path}/databases',
    );
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() async {
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, int rounds) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await settle(tester, 1);
    }
    expect(condition(), isTrue);
  }

  testWidgets('PDF אמיתי: ניווט, זהות, זום, מצב יד ובחירת נקודה בפאנל צר', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final file = File('${directory.path}/book.pdf');
    final book = PdfBook(
      id: 12,
      title: 'ספר בדיקה',
      path: file.path,
      source: BookSource.user,
    );
    final other = PdfBook(
      id: 12,
      title: book.title,
      path: '${directory.path}/another/book.pdf',
      source: BookSource.user,
    );
    final anchor = PdfNoteAnchor(
      pageNumber: 2,
      x: .35,
      y: .65,
      documentId: pdfPersonalNoteDocumentId(book),
    );
    final otherAnchor = PdfNoteAnchor(
      pageNumber: 2,
      x: .6,
      y: .5,
      documentId: pdfPersonalNoteDocumentId(other),
    );
    final key = personalNotesBookKey(book);
    PersonalNote note(String id, PdfNoteAnchor point) => PersonalNote(
      id: id,
      bookId: key,
      lineNumber: point.pageNumber,
      lastKnownLineNumber: null,
      pdfAnchor: point,
      status: PersonalNoteStatus.located,
      content: 'תוכן $id',
      contentPlain: 'תוכן $id',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 3; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(400, 500),
            build: (_) => pw.Text('${i + 1}'),
          ),
        );
      }
      await file.writeAsBytes(await pdf.save());
      await database.insertNote(note('current', anchor));
      await database.insertNote(note('other-document', otherAnchor));
    });
    final tab = PdfBookTab(
      book: book,
      pageNumber: 1,
      requiresStableLayout: true,
    )..requestPersonalNoteNavigation(anchor);
    final slowSettings = Completer<void>();
    unawaited(
      PerBookSettings.runLockedForKey(
        PerBookSettings.bookKey(book),
        () => slowSettings.future,
      ),
    );
    final tabs = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = _SettingsBloc();
    final notes = PersonalNotesBloc(repository: _NotesRepository());
    final tour = TourCubit();
    addTearDown(tabs.close);
    addTearDown(settings.close);
    addTearDown(notes.close);
    addTearDown(tour.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
            BlocProvider<TourCubit>.value(value: tour),
          ],
          child: PdfBookScreen(tab: tab),
        ),
      ),
    );
    final controller = tab.pdfViewerController;
    await pumpUntil(tester, () => controller.isReady);
    await settle(tester, 5);
    final params = tester.widget<PdfViewer>(find.byType(PdfViewer)).params;
    // הסשן הראשון מחכה להגדרות כאשר מתקבל document-change. ההמשך הישן
    // אינו רשאי לפתוח פאנל או לצרוך את הבקשה השמורה עבור הסשן הבא.
    params.onDocumentChanged!(null);
    slowSettings.complete();
    await settle(tester, 30);
    expect(notes.state.expandRequestPdfAnchor, isNull);
    expect(tab.takePersonalNoteNavigationRequest(), anchor);
    tab.requestPersonalNoteNavigation(anchor);
    params.onViewerReady!(controller.document, controller);
    await pumpUntil(
      tester,
      () =>
          find.byType(PersonalNotesSidebar).evaluate().isNotEmpty &&
          notes.state.expandRequestPdfAnchor == anchor,
    );
    await settle(tester, 40);

    final pdfBloc = tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();
    expect((pdfBloc.state as PdfBookLoaded).showRightPane, isTrue);
    final marker = find.byKey(const ValueKey('pdf-note-current'));
    expect(marker, findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-note-other-document')), findsNothing);
    final tile = tester.widget<NoteTile>(find.byKey(const ValueKey('current')));
    expect(tile.expandToken, notes.state.expandRequestToken);
    expect(find.byKey(const ValueKey('other-document')), findsNothing);

    Offset documentPoint() => pdfNoteAnchorDocumentPosition(
      anchor,
      page: controller.pages[anchor.pageNumber - 1],
      pageRect: controller.layout.pageLayouts[anchor.pageNumber - 1],
    );
    void expectMarkerAtAnchor() {
      final global = controller.documentToGlobal(documentPoint())!;
      final center = tester.getCenter(marker);
      expect(center.dx, closeTo(global.dx, 1));
      expect(center.dy, closeTo(global.dy, 1));
      expect(controller.visibleRect.contains(documentPoint()), isTrue);
    }

    expectMarkerAtAnchor();
    final oldZoom = controller.currentZoom;
    final zoom = controller.goTo(
      controller.calcMatrixFor(documentPoint(), zoom: oldZoom * 1.5),
      duration: Duration.zero,
    );
    await settle(tester, 15);
    await tester.runAsync(() => zoom);
    expect(controller.currentZoom, greaterThan(oldZoom));
    expectMarkerAtAnchor();

    // בודקים את הפרמטרים שמקבל הצפיין בפועל אחרי פעולות במסך.
    // כך שינוי ניסוח או פורמט בקוד המקור אינו משנה את הכיסוי של מצב היד.
    void expectTextSelectionEnabled(bool enabled, {required String reason}) {
      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(
        viewer.params.textSelectionParams?.enabled,
        enabled,
        reason: reason,
      );
    }

    expectTextSelectionEnabled(
      true,
      reason: 'סימון טקסט זמין כשמצב היד ובחירת נקודה כבויים',
    );
    await tester.tap(find.byTooltip('מצב יד — גלילה בגרירת העכבר'));
    await settle(tester, 5);
    expectTextSelectionEnabled(
      false,
      reason: 'הפעלת מצב היד מפנה את גרירת העכבר לגלילה',
    );
    final sidebar = tester.widget<PersonalNotesSidebar>(
      find.byType(PersonalNotesSidebar),
    );
    await sidebar.onReanchorNote!(note('current', anchor));
    await settle(tester, 15);
    expect(find.text(NotesMessages.choosePdfNotePoint), findsOneWidget);
    expectTextSelectionEnabled(
      false,
      reason: 'בחירת נקודת הערה אינה מפעילה סימון טקסט במצב יד',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 15);
    expect(find.text(NotesMessages.choosePdfNotePoint), findsNothing);
    expectTextSelectionEnabled(
      false,
      reason: 'ביטול בחירת נקודה משאיר את מצב היד פעיל',
    );
    await tester.tap(find.byTooltip('מצב יד פעיל — לחץ לחזרה לסימון טקסט'));
    await settle(tester, 5);
    expectTextSelectionEnabled(
      true,
      reason: 'כיבוי מצב היד מחזיר את סימון הטקסט',
    );

    await tester.binding.setSurfaceSize(const Size(420, 800));
    await settle(tester, 20);
    AdaptiveSidePane notesPane() => tester.widget<AdaptiveSidePane>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AdaptiveSidePane &&
            widget.alignment == AlignmentDirectional.centerStart,
      ),
    );
    Future<void> beginReanchor() async {
      final sidebar = tester.widget<PersonalNotesSidebar>(
        find.byType(PersonalNotesSidebar),
      );
      await sidebar.onReanchorNote!(note('current', anchor));
      await settle(tester, 15);
      // ההסתרה זמנית לתצוגה: ההחלטה על עורך inline נשארת לפי המצב הלוגי.
      expect((pdfBloc.state as PdfBookLoaded).showRightPane, isTrue);
      expect(notesPane().isOpen, isFalse);
      expectTextSelectionEnabled(
        false,
        reason: 'בחירת נקודת הערה מנטרלת סימון טקסט גם כשמצב היד כבוי',
      );
    }

    await beginReanchor();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 15);
    expect(notesPane().isOpen, isTrue);
    expectTextSelectionEnabled(
      true,
      reason: 'ביטול בחירת נקודה מחזיר סימון טקסט כשמצב היד כבוי',
    );
    await beginReanchor();
    final newAnchor = PdfNoteAnchor(
      pageNumber: 2,
      x: .45,
      y: .6,
      documentId: anchor.documentId,
    );
    final newPosition = pdfNoteAnchorDocumentPosition(
      newAnchor,
      page: controller.pages[1],
      pageRect: controller.layout.pageLayouts[1],
    );
    final reposition = controller.goTo(
      controller.calcMatrixFor(newPosition),
      duration: Duration.zero,
    );
    await settle(tester, 5);
    await tester.runAsync(() => reposition);
    await tester.tapAt(controller.documentToGlobal(newPosition)!);
    await settle(tester, 30);
    final stored = await tester.runAsync(() => database.loadNotes(key));
    final moved = stored!.singleWhere((note) => note.id == 'current');
    expect(moved.content, 'תוכן current');
    expect(moved.pdfAnchor!.documentId, anchor.documentId);
    expect(moved.pdfAnchor!.pageNumber, 2);
    expect(moved.pdfAnchor!.x, closeTo(.45, .00001));
    expect(moved.pdfAnchor!.y, closeTo(.6, .00001));
    expect(notesPane().isOpen, isTrue);
    expectTextSelectionEnabled(
      true,
      reason: 'שמירת נקודת ההערה מחזירה סימון טקסט כשמצב היד כבוי',
    );
    await beginReanchor();
    tester.widget<PdfViewer>(find.byType(PdfViewer)).params.onDocumentChanged!(
      null,
    );
    await settle(tester, 15);
    expect(
      notesPane().isOpen,
      isTrue,
      reason: 'החלפת מסמך מבטלת בחירת נקודה ומחזירה את הפאנל',
    );
    expectTextSelectionEnabled(
      true,
      reason: 'החלפת מסמך מבטלת את חסימת סימון הטקסט של בחירת נקודה',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, 10);
  });
}
