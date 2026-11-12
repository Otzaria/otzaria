import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_headings_builder.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

/// פסקה אחת עם שורה ממורכזת וכותרת נושא ארוכה בתוכה: הערכה לפי אורך הטקסט
/// מחמיצה את הגובה של שתיהן, ולכן מיקום שורה אחריהן נמדד מהרינדור.
const _blockLine = 20;
const _headingLine = 23;
const _target = 26;
final _content = [
  for (var i = 0; i < 45; i++)
    i == _blockLine
        ? '<center>שורה ממורכזת</center>'
        : i == _target
        ? 'יעדמדויק דברי הברית אשר צוה לכרת את בני ישראל בארץ מואב'
        : 'פסוק $i: דברי הברית אשר צוה לכרת את בני ישראל בארץ מואב מלבד '
              'הברית אשר כרת אתם בחרב',
];
final _heading = List.filled(12, 'כותרת נושא ארוכה מאוד').join(' ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_measured_line');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    final db = MyDatabase.withPath(await AppPaths.resolveUserBooksDbPath());
    final raw = await db.database;
    raw.execute("INSERT INTO source (name) VALUES ('external')");
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, filePath, fileType) '
      "VALUES (7, 1, 'ספר', '/books/ספר.txt', 'txt')",
    );
    await UserContentRepository(db).replaceBookHeadings(raw.lastInsertRowId, [
      UserAltTocStructureData(
        key: 'Topic',
        heTitle: 'נושאים',
        entries: [
          UserAltTocEntryData(
            level: 1,
            text: _heading,
            lineIndex: _headingLine,
            parentIndex: null,
            hasChildren: false,
            isLastChild: true,
          ),
        ],
      ),
    ], source: 'test');
    db.close();
    await UserBooksDatabaseHolder.instance.repository;
  });

  tearDown(() async {
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  testWidgets('שורה אחרי בלוק ממורכז וכותרת בפסקה: נחיתה ומיקום מדויקים', (
    tester,
  ) async {
    final tab = await _pump(tester);
    final paragraphs = tester.widgetList<ContinuousReadingParagraph>(
      find.byType(ContinuousReadingParagraph),
    );
    expect(
      paragraphs
          .expand((p) => p.lines)
          .singleWhere((line) => line.lineIndex == _headingLine)
          .heading,
      isNotNull,
      reason: 'הכותרת מוצגת בתוך הפסקה',
    );
    expect(
      tester.widget<ReaderLineBlock>(find.byType(ReaderLineBlock)).lineIndex,
      _blockLine,
    );

    final navigation = tab.lines.scrollToLine(_target);
    await tester.pumpAndSettle();
    await navigation;

    final list = tester.getRect(find.byType(ScrollablePositionedList));
    final anchor = list.top + kReadingAnchorAlignment * list.height;
    expect(_rowTopOf(tester, 'יעדמדויק'), closeTo(anchor, 1.5));
    expect(tab.index, _target);
    expect(tab.lines.position.value?.topLine, _target);
    expect(tab.lines.position.value?.intraLineFraction, closeTo(0, 0.05));
  });
}

/// ראש שורת התצוגה שבה מתחיל [text], בקואורדינטות גלובליות.
double _rowTopOf(WidgetTester tester, String text) {
  final paragraph = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere((p) => p.text.toPlainText().contains(text));
  final offset = paragraph.text.toPlainText().indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
        boxHeightStyle: ui.BoxHeightStyle.max,
      )
      .first;
  return paragraph.localToGlobal(Offset(0, box.top)).dy;
}

Future<TextBookTab> _pump(WidgetTester tester) async {
  final book = TextBook(
    title: 'ספר',
    categoryId: 7,
    filePath: '/books/ספר.txt',
    source: BookSource.user,
  );
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: _content,
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
      pinLeftPane: false,
      searchText: '',
      continuousReadingMode: true,
    ),
  );
  final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  final tab = TextBookTab(book: book, index: 0);
  addTearDown(bloc.close);
  addTearDown(notes.close);
  addTearDown(settings.close);
  addTearDown(tab.dispose);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: Scaffold(
          body: CombinedView(
            data: _content,
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
  // טעינת הכותרות קוראת את user_books.db — I/O אמיתי.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return tab;
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _Repository();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
