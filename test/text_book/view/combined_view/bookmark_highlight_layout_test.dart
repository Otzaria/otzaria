import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _target = 30;
const _farTarget = 3500;
String _lineText(int i) =>
    'פסוק $i: דברי הברית אשר צוה לכרת את בני ישראל בארץ מואב';
final _content = List.generate(80, _lineText);

/// הקורא האמיתי: הטאב נפתח מסימניה, והקורא נפרס רק אחרי 2.2 שניות. עד אז
/// היעד לא נמדד ואסור שזמן ההדגשה יתחיל (סיבת הסגירה של #5692).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    // מטמון הספרייה שומר Future מהשעון המדומה של הבדיקה שיצרה אותו.
    final original = FileSystemData.instance;
    FileSystemData.instance = _FileSystem();
    addTearDown(() => FileSystemData.instance = original);
  });

  testWidgets('שורת הסימניה מודגשת רק כשהקורא פרס ומדד אותה, '
      'וההדגשה נמשכת מרגע ההופעה (issue #4455)', (tester) async {
    final book = TextBook(title: 'ספר', filePath: '/books/ספר.txt');
    final tab = TextBookTab(
      book: book,
      index: _target,
      initialReadingAnchor: const ReadingAnchor(line: _target),
    )..highlightLineWhenVisible(_target);
    addTearDown(tab.dispose);
    final bloc = TextBookBloc(
      repository: _Repository(),
      protectionLoader: (_) async => BookProtection.none,
      bookNotesLoader: (_) async => BookNotes.empty,
      initialState: TextBookInitial.named(
        book,
        _target,
        false,
        const [],
        searchMode: SearchMode.exact,
        showPageShapeView: false,
      ),
      readingPosition: tab.lines.position,
      readingNavigationEpoch: tab.lines.navigationEpoch,
      initialBookmarkHighlight: HighlightLineWhenVisible(
        tab.highlightWhenVisibleLine!,
        navigationEpoch: tab.lines.navigationEpoch.value,
      ),
    );
    addTearDown(bloc.close);
    bloc.add(
      const LoadContent(
        fontSize: 18,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await tester.pump();
    expect(bloc.state, isA<TextBookLoaded>());

    // הספר נטען, אבל הקורא עוד לא נפרס: 2.2 שניות בלי מדידה.
    await tester.pump(const Duration(milliseconds: 2200));
    expect(tab.lines.position.value?.isTarget, isTrue);
    expect((bloc.state as TextBookLoaded).highlightedLine, isNull);

    await _pumpReader(tester, tab, bloc);
    expect(tab.lines.position.value?.isTarget, isFalse);
    expect(tab.lines.position.value?.visibleLines, contains(_target));
    expect((bloc.state as TextBookLoaded).highlightedLine, _target);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      (bloc.state as TextBookLoaded).highlightedLine,
      _target,
      reason: 'זמן ההדגשה נספר מההופעה',
    );
    await tester.pump(const Duration(seconds: 1));
    expect((bloc.state as TextBookLoaded).highlightedLine, isNull);
  });

  testWidgets('לחיצה בזמן טעינת יעד רחוק אינה מתחילה את זמן ההדגשה', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Repository(blockFarTarget: true);
    final book = TextBook(title: 'ספר רחוק', filePath: '/books/far.txt');
    final tab = TextBookTab(book: book, index: 0);
    addTearDown(tab.dispose);
    final bloc = TextBookBloc(
      repository: repository,
      protectionLoader: (_) async => BookProtection.none,
      bookNotesLoader: (_) async => BookNotes.empty,
      initialState: TextBookInitial.named(
        book,
        0,
        false,
        const [],
        searchMode: SearchMode.exact,
        showPageShapeView: false,
      ),
      readingPosition: tab.lines.position,
      readingNavigationEpoch: tab.lines.navigationEpoch,
    );
    addTearDown(bloc.close);
    addTearDown(() {
      if (!repository.farTargetLoaded.isCompleted) {
        repository.farTargetLoaded.complete();
      }
    });
    bloc.add(const SetTabVisibility(true, allowBackgroundWarming: false));
    bloc.add(
      const LoadContent(
        fontSize: 18,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await tester.pump();
    expect(bloc.state, isA<TextBookLoaded>());
    await _pumpReader(tester, tab, bloc);

    final navigation = tab.lines.scrollToLine(
      _farTarget,
      alignment: 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    final epoch = tab.lines.navigationEpoch.value;
    bloc.add(HighlightLineWhenVisible(_farTarget, navigationEpoch: epoch));
    await tester.pumpAndSettle();
    await navigation;
    TextBookLoaded loaded() => bloc.state as TextBookLoaded;
    expect(tab.lines.position.value?.isTarget, isTrue);
    expect(loaded().isContentLineLoaded(_farTarget), isFalse);
    expect(loaded().highlightedLine, isNull);

    final row = find.byWidgetPredicate(
      (widget) => widget is ReaderLineBlock && widget.lineIndex == _farTarget,
    );
    expect(row, findsOneWidget);
    final pointer = await tester.startGesture(tester.getCenter(row));
    await pointer.up();
    await tester.pump();
    expect(tab.lines.navigationEpoch.value, epoch);
    expect(tab.lines.position.value?.isTarget, isFalse);
    expect(tab.lines.position.value?.visibleLines, contains(_farTarget));
    expect(loaded().isContentLineLoaded(_farTarget), isFalse);
    final highlightBeforeLoad = loaded().highlightedLine;
    await tester.pump(const Duration(milliseconds: 2200));
    expect(loaded().highlightedLine, isNull);

    repository.farTargetLoaded.complete();
    await tester.pumpAndSettle();
    expect(loaded().isContentLineLoaded(_farTarget), isTrue);
    expect(tab.lines.position.value?.visibleLines, contains(_farTarget));
    expect(
      [highlightBeforeLoad, loaded().highlightedLine],
      [null, _farTarget],
      reason: 'הטיימר צריך להתחיל אחרי טעינת השורה ולא כשהוצג מציין מקום',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(loaded().highlightedLine, isNull);
  });
}

Future<void> _pumpReader(
  WidgetTester tester,
  TextBookTab tab,
  TextBookBloc bloc,
) async {
  final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  addTearDown(notes.close);
  addTearDown(settings.close);
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
          body: BlocBuilder<TextBookBloc, TextBookState>(
            builder: (_, state) => CombinedView(
              data: (state as TextBookLoaded).content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
              tab: tab,
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

class _FileSystem implements FileSystemData {
  @override
  Future<bool> isTanachBook(
    String title, {
    int? categoryId,
    String? fileType,
  }) async => false;

  @override
  Future<bool> supportsContinuousReadingMode(
    String title, {
    int? categoryId,
    String? fileType,
  }) async => false;

  @override
  Future<Map<String, Map<String, dynamic>>> get metadata async => const {};

  @override
  Future<Map<String, String>> get titleToPath async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository extends TextBookRepository {
  _Repository({this.blockFarTarget = false})
    : _lines = blockFarTarget ? List.generate(5000, _lineText) : _content,
      super(fileSystem: FileSystemData.instance);

  final List<String> _lines;
  final bool blockFarTarget;
  final farTargetLoaded = Completer<void>();

  @override
  Future<String> getBookContent(TextBook book) async => _lines.join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    final start = startLine.clamp(0, _lines.length - 1);
    final end = endLine.clamp(start, _lines.length - 1);
    if (blockFarTarget && start <= _farTarget && _farTarget <= end) {
      await farTargetLoaded.future;
    }
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: _lines.length,
      lines: _lines.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}
