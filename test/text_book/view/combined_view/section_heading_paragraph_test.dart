import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
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
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_headings_builder.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const _content = [
  '(ח) ונח מצא חן בעיני ה׳',
  '(ט) אלה תולדת נח נח איש צדיק',
  '(י) ויולד נח שלשה בנים',
];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_heading_para');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    final db = MyDatabase.withPath(await AppPaths.resolveUserBooksDbPath());
    final raw = await db.database;
    raw.execute("INSERT INTO source (name) VALUES ('external')");
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, filePath, fileType) '
      "VALUES (7, 1, 'ספר', '/books/ספר.txt', 'txt')",
    );
    await UserContentRepository(db).replaceBookHeadings(raw.lastInsertRowId, [
      const UserAltTocStructureData(
        key: 'Topic',
        heTitle: 'נושאים',
        entries: [
          UserAltTocEntryData(
            level: 1,
            text: 'פרשת נח',
            lineIndex: 1,
            parentIndex: null,
            hasChildren: false,
            isLastChild: true,
          ),
        ],
      ),
    ], source: 'test');
    db.close();
  });

  tearDown(() async {
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpBook(
    WidgetTester tester, {
    bool preview = false,
    ValueChanged<String?>? onSelectionChanged,
  }) async {
    final book = TextBook(
      title: 'ספר',
      categoryId: 7,
      filePath: '/books/ספר.txt',
      source: BookSource.user,
    );
    final textBookBloc = _TestTextBookBloc(
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
        selectedIndex: 1,
        selectedIndices: const {1},
        pinLeftPane: false,
        searchText: '',
        scrollController: ItemScrollController(),
        positionsListener: ItemPositionsListener.create(),
      ),
    );
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: book, index: 0);
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(
              value: personalNotesBloc,
            ),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CombinedView(
              data: _content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
              tab: tab,
              isPreviewMode: preview,
              onSelectedTextChanged: (text, _, _) =>
                  onSelectionChanged?.call(text),
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
  }

  testWidgets(
    'כותרת מוזרקת היא פסקה נפרדת — מחוץ לרקע השורה הנבחרת (issue #1945)',
    (tester) async {
      await pumpBook(tester);
      final heading = find.textContaining('פרשת נח', findRichText: true);
      expect(heading, findsOneWidget);
      final selectedBackground = find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            (w.decoration as BoxDecoration?)?.color != null,
      );
      expect(
        find.ancestor(
          of: find.textContaining('אלה תולדת נח', findRichText: true),
          matching: selectedBackground,
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: heading, matching: selectedBackground),
        findsNothing,
      );
    },
  );

  for (final preview in [false, true]) {
    for (final cross in <bool?>[null, false, true]) {
      testWidgets(
        'right click heading offers copy preview=$preview cross=$cross',
        (tester) async {
          String? selectedText;
          await pumpBook(
            tester,
            preview: preview,
            onSelectionChanged: (text) => selectedText = text,
          );

          final heading = find.textContaining('פרשת נח', findRichText: true);
          expect(heading, findsOneWidget);
          Rect textRect(String text) {
            final paragraph = tester.allRenderObjects
                .whereType<RenderParagraph>()
                .firstWhere((p) => p.text.toPlainText().contains(text));
            final offset = paragraph.text.toPlainText().indexOf(text);
            final box = paragraph
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: offset,
                    extentOffset: offset + text.length,
                  ),
                )
                .first
                .toRect();
            return Rect.fromPoints(
              paragraph.localToGlobal(box.topLeft),
              paragraph.localToGlobal(box.bottomRight),
            );
          }

          if (cross != null) {
            final rect = textRect('פרשת נח');
            final gesture = await tester.startGesture(
              Offset(rect.right - 1, rect.center.dy),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump();
            final end = cross ? textRect('אלה תולדת נח') : rect;
            await gesture.moveTo(Offset(end.left + 1, end.center.dy));
            await tester.pump();
            await gesture.up();
            await tester.pump();
            expect(selectedText, contains('פרשת נח'));
            if (cross) {
              expect(selectedText, contains('אלה תולדת נח'));
            }
          }
          await tester.tapAt(
            textRect('פרשת נח').center,
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('העתק כ...'), findsOneWidget);
          if (cross == null) {
            expect(selectedText, isNull);
          } else {
            expect(selectedText, contains('פרשת נח'));
            if (cross) expect(selectedText, contains('אלה תולדת נח'));
          }
          final regionFinder = find.ancestor(
            of: heading,
            matching: find.byType(AppContextMenuRegion),
          );
          expect(regionFinder, findsOneWidget);
          final region = tester.widget<AppContextMenuRegion>(regionFinder);
          final entries = region.menuBuilder(
            tester.element(regionFinder),
            textRect('פרשת נח').center,
          );
          final copyAs = entries.singleWhere((e) => e.label == 'העתק כ...');
          expect(copyAs.enabled, cross != null);
          expect(copyAs.children, isNotEmpty);
          expect(
            copyAs.children!.every((e) => e.enabled == (cross != null)),
            isTrue,
          );
          expect(copyAs.children!.map((e) => e.label), contains('כמו בתצוגה'));
        },
      );
    }
  }
}
