import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_notes_column.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:path/path.dart' as path;
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _title = 'חברותא על ברכות';
const _inlineTitle = 'חברותא על שבת';
const _lines = ['<h2>פרק ראשון</h2>', 'גוף החברותא על המשנה הראשונה'];
const _noteSelection = 'הגירסה בכתב יד';
const _noteBody = 'הערת העורך על $_noteSelection';

/// הערה מ-line_note על שורה 1, שגופה אינו בשורה עצמה.
final _notes = (BookNotesBuilder()..add(1, 0, 'א', _noteBody)).build();

/// הערת inline (מסד בלי line_note): גוף ההערה הוא חלק מהשורה עצמה.
const _inlineLines = [
  '<h2>פרק ראשון</h2>',
  'גוף החברותא<sup class="footnote-marker">א</sup><i class="footnote">$_noteBody</i>',
];

/// דיווח מהערה נשען על השורה הגולמית שב-seforim.db: רק מול מסד אמיתי נבנית
/// הצעת תיקון, וממנו היא נבנתה בטעות לשורת האב (issue #3509).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('note-error-report-');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data'));
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      await _seedLibrary(tempDir),
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ה-handle של ה-worker ב-Windows אינו משתחרר מיד; ה-temp אינו הנבדק.
    }
  });

  Future<TabbedReportDialog> openedDialog(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      if (find.byType(TabbedReportDialog).evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(_tick));
      await tester.pump(_tick);
    }
    return tester.widget<TabbedReportDialog>(find.byType(TabbedReportDialog));
  }

  Future<void> closeDialog(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(TabbedReportDialog))).pop();
    await tester.pumpAndSettle();
  }

  /// סימון טקסט בהערה בחלונית המפרשים ודיווח מתפריט ההקשר שלה.
  Future<TabbedReportDialog> reportFromNotesPanel(
    WidgetTester tester,
    TextBookLoaded state,
  ) async {
    await _pumpWithBlocs(
      tester,
      state,
      CommentaryListBase(
        openBookCallback: (_) {},
        fontSize: 18,
        showSearch: false,
      ),
    );
    final note = find.textContaining(_noteSelection, findRichText: true).first;
    tester
        .widget<SelectionArea>(
          find.ancestor(of: note, matching: find.byType(SelectionArea)).first,
        )
        .onSelectionChanged!(const SelectedContent(plainText: _noteSelection));
    await tester.pump();
    tester
        .widget<AppContextMenuRegion>(
          find
              .ancestor(of: note, matching: find.byType(AppContextMenuRegion))
              .first,
        )
        .menuBuilder(tester.element(note), Offset.zero)
        .singleWhere((entry) => entry.label == 'דווח על טעות בספר')
        .onTap!();
    return openedDialog(tester);
  }

  /// דיווח מתפריט ההקשר של ההערה בטור ההערות של צורת הדף.
  Future<TabbedReportDialog> reportFromNotesColumn(
    WidgetTester tester,
    TextBookLoaded state,
  ) async {
    final column = buildPageShapeNotesColumn(state.content, state.bookNotes);
    await _pumpWithBlocs(
      tester,
      state,
      SimpleTextViewer(
        content: column.content,
        fontSize: 18,
        openBookCallback: (_) {},
        bookTitle: kNotesCommentatorTitle,
        isBookNotesColumn: true,
        sourceIndexForIndex: (index) => column.links[index].index1 - 1,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.textContaining(_noteSelection, findRichText: true).first,
      ),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('דווח על טעות בספר'));
    return openedDialog(tester);
  }

  testWidgets(
    'הערה במפרשים: דיווח חופשי עם גוף ההערה, ולשורת הספר הצעת תיקון (issue #3509)',
    (tester) async {
      final launcher = _RecordingUrlLauncher();
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      final dialog = await reportFromNotesPanel(tester, _state);
      expect(dialog.correctionTemplate, isNull);
      expect(dialog.selectedText, _noteSelection);
      expect(dialog.currentLineNumber, 2);

      await tester.enterText(
        find.byKey(const ValueKey('report-details-field')),
        'טעות בהערה',
      );
      await tester.pump();
      await tester.tap(find.text('שלח בדוא"ל'));
      for (var i = 0; i < 100 && launcher.urls.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(_tick));
        await tester.pump(_tick);
      }
      final body = Uri.parse(launcher.urls.single).queryParameters['body']!;
      expect(body, contains('שם הספר: $_title'));
      expect(body, contains('מספר שורה: 2'));
      expect(body, contains(_noteBody));
      expect(body, isNot(contains('גוף החברותא')));
      await tester.pumpAndSettle();

      unawaited(
        ErrorReportHelper.showErrorReportDialog(
          context: tester.element(find.byType(CommentaryListBase)),
          selectedText: 'המשנה',
          state: _state,
          fontSize: 18,
          bookTitle: _title,
          savedSelectedIndex: 1,
        ),
      );
      final lineTemplate = (await openedDialog(tester)).correctionTemplate;
      expect(lineTemplate?.originalLine, _lines[1]);
      expect(lineTemplate?.hasSelection, isTrue);
    },
  );

  testWidgets(
    'צורת הדף, טור ההערות: דיווח על הערה הוא דיווח חופשי על גוף ההערה (issue #3509)',
    (tester) async {
      final dialog = await reportFromNotesColumn(tester, _state);
      expect(dialog.correctionTemplate, isNull);
      expect(dialog.selectedText, endsWith(_noteBody));
      expect(dialog.currentLineNumber, 2);
    },
  );

  testWidgets(
    'הערת inline שבתוך השורה: הדיווח עליה נשאר הצעת תיקון לשורה (issue #3509)',
    (tester) async {
      final panel = await reportFromNotesPanel(tester, _inlineState);
      expect(panel.correctionTemplate?.originalLine, _inlineLines[1]);
      expect(panel.correctionTemplate?.hasSelection, isTrue);
      await closeDialog(tester);

      final column = await reportFromNotesColumn(tester, _inlineState);
      expect(column.correctionTemplate?.originalLine, _inlineLines[1]);
      expect(column.currentLineNumber, 2);
    },
  );
}

const _tick = Duration(milliseconds: 20);

TextBookLoaded _bookState(
  String title,
  List<String> content,
  BookNotes bookNotes,
) => TextBookLoaded(
  book: TextBook(title: title, categoryId: 7),
  showLeftPane: false,
  content: content,
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [kNotesCommentatorTitle],
  commentatorGroups: const [],
  availableCommentators: const [kNotesCommentatorTitle],
  links: const [],
  linksByLine: const {},
  tableOfContents: const [],
  visibleIndices: const [1],
  selectedIndex: 1,
  pinLeftPane: false,
  searchText: '',
  bookNotes: bookNotes,
);

final _state = _bookState(_title, _lines, _notes);
final _inlineState = _bookState(_inlineTitle, _inlineLines, BookNotes.empty);

Future<void> _pumpWithBlocs(
  WidgetTester tester,
  TextBookLoaded state,
  Widget child,
) async {
  final textBook = _TextBookBloc(state);
  final settings = _SettingsBloc(SettingsState.initial());
  final notes = _PersonalNotesBloc(const PersonalNotesState.initial());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await textBook.close();
    await settings.close();
    await notes.close();
  });
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TextBookBloc>.value(value: textBook),
        BlocProvider<SettingsBloc>.value(value: settings),
        BlocProvider<PersonalNotesBloc>.value(value: notes),
      ],
      child: MaterialApp(
        home: Scaffold(body: SizedBox(width: 600, height: 500, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<String> _seedLibrary(Directory dir) async {
  final dbPath = path.join(dir.path, 'seforim.db');
  final database = MyDatabase.withPath(dbPath);
  try {
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (7, 'בבלי', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    for (final (id, title, lines) in [
      (1, _title, _lines),
      (2, _inlineTitle, _inlineLines),
    ]) {
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, orderIndex, '
        'totalLines) VALUES (?, 7, 1, ?, ?, ?)',
        [id, title, id, lines.length],
      );
      for (var i = 0; i < lines.length; i++) {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content) VALUES (?, ?, ?, ?)',
          [id * 100 + i, id, i, lines[i]],
        );
      }
    }
  } finally {
    database.close();
  }
  return dbPath;
}

class _RecordingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final urls = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _PersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
