/// ספר מקרא בשני מסכי הקורא, במצב רציף: פרקים ופסוקים בגליון, בלי כותרות
/// פרק בגוף הטקסט, ומזהי השורות המקוריים נשמרים בלחיצה, בבחירה ובהעתקה.
/// הנתונים סינתטיים, במבנה השורות של המסד.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
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
import 'package:otzaria/text_book/utils/mikra_structure.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const String _pe = '&nbsp;<span class="mam-spi-pe">{פ}</span><br>';

const List<String> _data = [
  '<h1>בראשית</h1>', // 0
  '<h2>פרק א</h2>', // 1
  '(א) ראשונה אבג דהו:', // 2
  '(ב) שניה זחט יכל:', // 3
  '(ג) שלישית מנס עפצ:$_pe', // 4
  '(ד) רביעית קרש תאב:', // 5
  '<h2>פרק ב</h2>', // 6
  '(א) חמישית גדה וזח:', // 7
  '(ב) שישית טיכ למנ:', // 8
];

final List<TocEntry> _toc = [
  TocEntry(text: 'בראשית', index: 0, level: 1),
  TocEntry(text: 'פרק א', index: 1, level: 2),
  TocEntry(text: 'פרק ב', index: 6, level: 2),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final simple in [false, true]) {
    final screen = simple ? 'צורת הדף' : 'עיון';

    testWidgets('$screen: אין כותרות פרק ומספרי פסוק בגוף הטקסט', (
      tester,
    ) async {
      await _pump(tester, simple: simple);
      final text = _paragraphTexts(tester).join('\n');
      expect(text, isNot(contains('(א)')));
      expect(text, isNot(contains('(ב)')));
      expect(text, isNot(contains('פרק')));
      // פרק ב׳ באמצע פסקה: פסוק ד׳ של פרק א׳ ופסוק א׳ של פרק ב׳ באותה פסקה.
      expect(
        _paragraphTexts(tester).any(
          (t) => t.contains('רביעית') && t.contains('חמישית'),
        ),
        isTrue,
      );
    });

    testWidgets('$screen: הפתוחה חותכת את הפסקה', (tester) async {
      await _pump(tester, simple: simple);
      final paragraphs = _paragraphTexts(tester);
      final withPetucha = paragraphs.singleWhere((t) => t.contains('{פ}'));
      expect(withPetucha, contains('שלישית'));
      expect(withPetucha, isNot(contains('רביעית')));
    });

    testWidgets('$screen: ציוני הגליון — פרק ופסוק, פרשה ועלייה', (
      tester,
    ) async {
      await _pump(tester, simple: simple);
      final lines = [
        for (final p in tester.widgetList<ContinuousReadingParagraph>(
          find.byType(ContinuousReadingParagraph),
        ))
          ...p.lines,
      ];
      final byLine = {for (final l in lines) l.lineIndex: l};
      expect(
        byLine[2]!.gutter,
        const MikraGutterLabel(chapter: 'א', verse: 'א'),
      );
      expect(byLine[3]!.gutter, const MikraGutterLabel(verse: 'ב'));
      expect(
        byLine[7]!.gutter,
        const MikraGutterLabel(chapter: 'ב', verse: 'א'),
      );
      // כותרת פרק ב׳ היא שורה במקומה, ריקה בתצוגה.
      expect(byLine[6]!.htmlText, '');
      expect(byLine[6]!.gutter, isNull);
      expect(
        byLine[2]!.division,
        const MikraDivisionLabel(parasha: 'בראשית', aliyah: 'ראשון'),
      );
    });

    testWidgets('$screen: לחיצה בפסוק בוחרת את שורת המקור שלו', (
      tester,
    ) async {
      final h = await _pump(tester, simple: simple);
      await tester.tapAt(
        _textRect(tester, 'חמישית').center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        h.bloc.received.whereType<UpdateSelectedIndex>().last,
        const UpdateSelectedIndex(7),
      );
    });

    testWidgets('$screen: מיקום בפסקה מתורגם לשורה הנכונה גם אחרי כותרת פרק', (
      tester,
    ) async {
      await _pump(tester, simple: simple);
      final render = tester
          .renderObjectList<RenderReaderParagraphLines>(
            find.byType(ReaderParagraphLines),
          )
          .firstWhere((r) => r.rangeForLine(8) != null);
      final hit = render.locate(_textRect(tester, 'שישית').center)!;
      expect(hit.lineIndex, 8);
    });

    testWidgets('$screen: העתקת בחירה שחוצה פסוקים — בלי מספרי פסוק', (
      tester,
    ) async {
      final copied = <String>[];
      debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
      addTearDown(() => debugSelectedTextCopyHandler = null);
      await _pump(tester, simple: simple);
      await _selectRange(
        tester,
        _textRect(tester, 'דהו'),
        _textRect(tester, 'שניה'),
      );
      await _pressCtrlC(tester, copied);
      expect(copied, ['דהו: שניה']);
    });
    testWidgets('$screen: העתקת בחירה שחוצה פתוחה — בלי {פ}', (tester) async {
      final copied = <String>[];
      debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
      addTearDown(() => debugSelectedTextCopyHandler = null);
      await _pump(tester, simple: simple);
      await _selectRange(
        tester,
        _textRect(tester, 'עפצ'),
        _textRect(tester, 'רביעית'),
      );
      await _pressCtrlC(tester, copied);
      expect(copied.single, isNot(contains('{פ}')));
      expect(copied.single, startsWith('עפצ:'));
      expect(copied.single, endsWith('רביעית'));
    });
  }

  testWidgets('עיון: בחירה מזוהה בשורתה, והעמודה — בשורה הרגילה', (
    tester,
  ) async {
    final h = await _pump(tester, simple: false);
    await _selectWord(tester, _textRect(tester, 'יכל'));
    expect(h.selectedText?.trim(), 'יכל');
    expect(h.selectedLine, 3);
    // "(ב) שניה זחט יכל:" — "יכל" מתחיל בעמודה 13 בשורה הרגילה.
    expect(h.selectedColumn, '(ב) שניה זחט '.length);
  });

  testWidgets('עיון: בחירה שחוצה פרק מזוהה בשורת ההתחלה', (tester) async {
    final h = await _pump(tester, simple: false);
    await _selectRange(
      tester,
      _textRect(tester, 'תאב'),
      _textRect(tester, 'חמישית'),
    );
    expect(h.selectedLine, 5);
  });

  for (final simple in [false, true]) {
    final screen = simple ? 'צורת הדף' : 'עיון';

    testWidgets('$screen: תצוגה כנדפס (המתג כבוי) — כמו קודם', (tester) async {
      await _pump(tester, simple: simple, mikraTraditionalLayout: false);
      final text = _paragraphTexts(tester).join('\n');
      expect(text, contains('(ב)'));
      for (final p in tester.widgetList<ContinuousReadingParagraph>(
        find.byType(ContinuousReadingParagraph),
      )) {
        expect(p.gutterStyle, isNull);
      }
    });

    testWidgets('$screen: שורות בודדות (לא ברצף) — בלי שינוי', (tester) async {
      await _pump(tester, simple: simple, continuous: false);
      expect(find.byType(ContinuousReadingParagraph), findsNothing);
    });
  }

  testWidgets('החלפת התצוגה בספר פתוח משנה את הפריסה', (tester) async {
    final h = await _pump(tester, simple: false);
    expect(_paragraphTexts(tester).join('\n'), isNot(contains('(ב)')));
    final loaded = h.bloc.state as TextBookLoaded;
    // ignore: invalid_use_of_protected_member
    h.bloc.emit(loaded.copyWith(mikraTraditionalLayout: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_paragraphTexts(tester).join('\n'), contains('(ב)'));
    // ignore: invalid_use_of_protected_member
    h.bloc.emit(loaded.copyWith(mikraTraditionalLayout: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_paragraphTexts(tester).join('\n'), isNot(contains('(ב)')));
  });

  for (final simple in [false, true]) {
    final screen = simple ? 'צורת הדף' : 'עיון';
    for (final continuous in [true, false]) {
      testWidgets('$screen: העתקה עם ציון מקור אמיתי — רצף=$continuous', (
        tester,
      ) async {
        final copied = <String>[];
        debugSelectedTextCopyHandler = (content) =>
            copied.add(content.plainText);
        addTearDown(() => debugSelectedTextCopyHandler = null);
        await _pump(
          tester,
          simple: simple,
          continuous: continuous,
          settings: SettingsState.initial().copyWith(
            copyWithHeaders: 'book_and_path',
            copyHeaderFormat: 'same_line_after_brackets',
            torahCopyCitation: 'book_parasha_aliyah',
          ),
        );
        await _selectWord(tester, _textRect(tester, 'יכל'));
        await _pressCtrlC(tester, copied);
        expect(copied.single, endsWith('(בראשית, פרשת בראשית, ראשון)'));
      });
    }
  }

  testWidgets('ספר שאינו מקרא — בלי שינוי (מספר הפסוק נשאר בטקסט)', (
    tester,
  ) async {
    await _pump(tester, simple: false, isTanach: false);
    final text = _paragraphTexts(tester).join('\n');
    expect(text, contains('(ב)'));
    for (final p in tester.widgetList<ContinuousReadingParagraph>(
      find.byType(ContinuousReadingParagraph),
    )) {
      expect(p.gutterStyle, isNull);
    }
  });
}

TextBook _book() => _NoTocBook();

class _NoTocBook extends TextBook {
  _NoTocBook() : super(title: 'בראשית');

  @override
  Future<List<TocEntry>> get tableOfContents async => _toc;
}

List<String> _paragraphTexts(WidgetTester tester) => [
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>().where(
    (p) =>
        p.text.toPlainText().contains('ראשונה') ||
        p.text.toPlainText().contains('רביעית') ||
        p.text.toPlainText().contains('שלישית'),
  ))
    p.text.toPlainText(),
];

class _Harness {
  _Harness(this.bloc);

  final _TextBookBloc bloc;
  String? selectedText;
  int? selectedLine;
  int? selectedColumn;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required bool simple,
  TextBook? book,
  bool isTanach = true,
  bool mikraTraditionalLayout = true,
  bool continuous = true,
  SettingsState? settings,
}) async {
  book ??= _book();
  final state = TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: _data,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const <int, List<Link>>{},
    tableOfContents: _toc,
    removeNikud: false,
    visibleIndices: List.generate(_data.length, (i) => i),
    pinLeftPane: false,
    searchText: '',
    isTanach: isTanach,
    continuousReadingMode: continuous,
    mikraTraditionalLayout: mikraTraditionalLayout,
  );
  final bloc = _TextBookBloc(state);
  final settingsBloc = _SettingsBloc(settings ?? SettingsState.initial());
  final notes = _PersonalNotesBloc(const PersonalNotesState.initial());
  final bookmarks = _BookmarkBloc();
  final h = _Harness(bloc);
  final tab = TextBookTab(book: book, index: 0);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    tab.dispose();
    await bloc.close();
    await settingsBloc.close();
    await notes.close();
    await bookmarks.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<BookmarkBloc>.value(value: bookmarks),
        ],
        child: Scaffold(
          body: simple
              ? SimpleTextViewer(
                  content: _data,
                  fontSize: 18,
                  isMainText: true,
                  openBookCallback: (_) {},
                )
              : CombinedView(
                  data: _data,
                  openBookCallback: (_) {},
                  openLeftPaneTab: (_, {searchText}) {},
                  textSize: 18,
                  showCommentaryAsExpansionTiles: false,
                  onOpenPersonalNotes: () {},
                  onSelectedTextChanged: (text, line, column) {
                    h.selectedText = text;
                    h.selectedLine = line;
                    h.selectedColumn = column;
                  },
                  tab: tab,
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  await _pumpUntil(
    tester,
    () => !SqliteDataProvider.instance.debugIsInitializing,
  );
  return h;
}

Rect _textRect(WidgetTester tester, String text) {
  final paragraph = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere((p) => p.text.toPlainText().contains(text));
  final plain = paragraph.text.toPlainText();
  final offset = plain.indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + text.length),
      )
      .first
      .toRect();
  return Rect.fromPoints(
    paragraph.localToGlobal(box.topLeft),
    paragraph.localToGlobal(box.bottomRight),
  );
}

Future<void> _selectWord(WidgetTester tester, Rect word) async {
  final gesture = await tester.startGesture(
    Offset(word.right - 1, word.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(Offset(word.left + 1, word.center.dy));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<void> _selectRange(WidgetTester tester, Rect from, Rect to) async {
  final gesture = await tester.startGesture(
    Offset(from.right - 1, from.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(Offset(to.left + 1, to.center.dy));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<void> _pressCtrlC(WidgetTester tester, List<String> copied) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _pumpUntil(tester, () => copied.isNotEmpty);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 10),
}) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
}

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }

  final List<TextBookEvent> received = [];

  @override
  final TextBookRepository repository = _TextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
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

class _PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _PersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
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

class _BookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _BookmarkBloc() : super(BookmarkState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
