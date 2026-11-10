import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:otzaria/utils/file/page_map_builder.dart';
import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

// issue #2468: זבחים כה. בצילום → כפתור הטקסט → הטקסט הרציף הוצג בדף ה.
// שורות הכותרת ועמודי ה-PDF הם של זבחים במסד ובקובץ האמיתיים.
const _amudim = [
  ('ב.', 1),
  ('ב:', 12),
  ('ג.', 32),
  ('ג:', 50),
  ('ד.', 70),
  ('ד:', 98),
  ('ה.', 127),
  ('ה:', 145),
  ('ו.', 165),
  ('ו:', 184),
  ('ז.', 198),
  ('ז:', 217),
  ('ח.', 244),
  ('ח:', 267),
  ('ט.', 285),
  ('ט:', 310),
  ('י.', 339),
  ('י:', 362),
  ('יא.', 397),
  ('יא:', 426),
  ('יב.', 459),
  ('יב:', 479),
  ('יג.', 502),
  ('יג:', 524),
  ('יד.', 547),
  ('יד:', 569),
  ('טו.', 591),
  ('טו:', 610),
  ('טז.', 625),
  ('טז:', 644),
  ('יז.', 663),
  ('יז:', 674),
  ('יח.', 682),
  ('יח:', 694),
  ('יט.', 715),
  ('יט:', 742),
  ('כ.', 766),
  ('כ:', 784),
  ('כא.', 802),
  ('כא:', 813),
  ('כב.', 827),
  ('כב:', 844),
  ('כג.', 861),
  ('כג:', 873),
  ('כד.', 885),
  ('כד:', 903),
  ('כה.', 921),
  ('כה:', 935),
  ('כו.', 956),
  ('כו:', 979),
  ('כז.', 992),
];
const _pdfPageOfDaf25a = 47;
const _daf25aLine = 921;
const _daf25bLine = 935;
const _lineCount = 1010;

final List<String> _lines = () {
  final headings = {for (final (name, line) in _amudim) line: name};
  var daf = '';
  return [
    for (var i = 0; i < _lineCount; i++)
      if (i == 0)
        '<h1>זבחים</h1>'
      else if (headings[i] case final name?)
        '<h2>דף ${daf = name}</h2>'
      else
        'דף $daf שורה $i: גמרא ממקום שאמרו לשחוט ושם תהא שחיטתו '
            'ובמקום שאמרו לזרוק ושם תהא זריקתו',
  ];
}();

List<TocEntry> _toc() {
  final root = TocEntry(text: 'זבחים', index: 0);
  root.children = [
    for (final (name, line) in _amudim)
      TocEntry(text: 'דף $name', index: line, level: 2, parent: root),
  ];
  return [root];
}

TextBookLoaded _state(List<bool> loaded) {
  final content = [
    for (var i = 0; i < _lines.length; i++) loaded[i] ? _lines[i] : '',
  ];
  return TextBookLoaded(
    book: TextBook(title: 'זבחים'),
    showLeftPane: false,
    content: content,
    contentVersion: loaded.where((f) => f).length,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: _toc(),
    removeNikud: false,
    visibleIndices: const [_daf25aLine],
    pinLeftPane: false,
    searchText: '',
    supportsContinuousReadingMode: true,
    continuousReadingMode: true,
    loadedLineFlags: loaded,
  );
}

List<bool> _window(int start, int end) => [
  for (var i = 0; i < _lines.length; i++) i >= start && i <= end,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('עמוד ה-PDF של זבחים כה. ממופה לשורת הכותרת של כה.', () {
    final anchorsPdf = [
      (page: 1, ref: normalizeRef('זבחים')),
      for (var i = 0; i < _amudim.length; i++)
        (page: i + 1, ref: normalizeRef('זבחים/דף ${_amudim[i].$1}')),
    ];
    final map = buildPageMapFromAnchors(
      anchorsPdf,
      collectTextAnchors(_toc()),
    );
    expect(map.pdfToText(_pdfPageOfDaf25a), _daf25aLine);
  });

  testWidgets('מעבר מצילום לטקסט רציף נשאר בדף כה אחרי טעינת הרקע', (
    tester,
  ) async {
    final partial = _state(_window(_daf25aLine - 30, _daf25aLine + 60));
    final textBookBloc = _TestTextBookBloc(partial);
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: partial.book, index: _daf25aLine);
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CombinedView(
              data: partial.content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: true,
              tab: tab,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    textBookBloc.emitForTest(
      partial.copyWith(visibleIndices: [tab.index, tab.index + 1]),
    );
    await tester.pumpAndSettle();
    expect(tab.index, inInclusiveRange(_daf25aLine, _daf25bLine - 1));

    for (final loaded in [
      _window(0, _daf25aLine + 60),
      _window(0, _lines.length - 1),
    ]) {
      textBookBloc.emitForTest(
        _state(loaded).copyWith(visibleIndices: [tab.index, tab.index + 1]),
      );
      await tester.pumpAndSettle();
      expect(
        tab.index,
        inInclusiveRange(_daf25aLine, _daf25bLine - 1),
        reason: 'הטקסט חייב להישאר בזבחים כה.',
      );
    }
    expect(find.textContaining('דף כה. שורה 922'), findsOneWidget);
  });
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }
  void emitForTest(TextBookState state) => emit(state);
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
