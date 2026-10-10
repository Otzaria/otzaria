import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
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
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../test_helpers/memory_cache_provider.dart';

const _title = 'ספר בדיקה';
String _note(String content) =>
    '$content <sup class="footnote-marker">א</sup><i class="footnote">${'תוכן המפרש מופיע כאן. ' * 80}</i>';

List<String> _content() => [
  for (var i = 0; i < 24; i++)
    _note('פסקה$i ${List.filled(i < 20 ? 30 : 6, 'מילה$i').join(' ')}'),
];

Future<({_TextBookBloc bloc, TextBookTab tab})> _pumpView(
  WidgetTester tester,
  List<String> data, {
  bool withSegments = false,
  bool below = true,
  bool notes = true,
  bool preview = false,
  bool duplicateView = false,
}) async {
  tester.view.physicalSize = const Size(620, 880);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final book = TextBook(title: _title);
  final bloc = _TextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: data,
      fontSize: 25,
      showSplitView: !below,
      showPageShapeView: false,
      activeCommentators: notes ? const [kNotesCommentatorTitle] : const [],
      commentatorGroups: const [
        CommentatorGroup(
          title: 'הערות',
          commentators: [kNotesCommentatorTitle],
        ),
      ],
      availableCommentators: const [kNotesCommentatorTitle],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: List.generate(data.length, (i) => i),
      selectedIndex: null,
      pinLeftPane: false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
      readingSegments: withSegments
          ? buildReadingSegments(data, continuous: false)
          : const [],
    ),
  );
  final notesBloc = _PersonalNotesBloc(const PersonalNotesState.initial());
  final settingsBloc = _SettingsBloc(SettingsState.initial());
  final tab = TextBookTab(book: book, index: 0);
  addTearDown(bloc.close);
  addTearDown(notesBloc.close);
  addTearDown(settingsBloc.close);
  addTearDown(tab.dispose);
  final secondTab = duplicateView ? TextBookTab(book: book, index: 0) : null;
  if (secondTab != null) addTearDown(secondTab.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: BlocBuilder<TextBookBloc, TextBookState>(
            builder: (context, state) {
              CombinedView view(TextBookTab viewTab) => CombinedView(
                data: (state as TextBookLoaded).content,
                openBookCallback: (_) {},
                openLeftPaneTab: (_, {searchText}) {},
                textSize: 25,
                showCommentaryAsExpansionTiles: below,
                tab: viewTab,
                isPreviewMode: preview,
              );
              if (secondTab == null) return view(tab);
              return Row(
                children: [
                  Expanded(child: view(tab)),
                  Expanded(child: view(secondTab)),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  bloc.replace(bloc.loaded.copyWith(contentVersion: 1));
  await tester.pumpAndSettle();
  await _frames(tester, 8);
  return (bloc: bloc, tab: tab);
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Map<int, ItemPosition> _positions(TextBookTab tab) => {
  for (final p in tab.positionsListener.itemPositions.value) p.index: p,
};

Future<void> _tap(WidgetTester tester, int index) async {
  final target = find.byKey(ValueKey('html_${_title}_$index'));
  final r = tester.getRect(target);
  final y = r.bottom.clamp(30.0, 850.0) - 10;
  await tester.tapAt(Offset(r.center.dx, y), kind: PointerDeviceKind.mouse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => Settings.init(cacheProvider: MemoryCacheProvider()));

  testWidgets(
    'פתיחת מפרשים שומרת details ואת אותו HtmlWidget בסוף הספר',
    (tester) async {
      final data = _content();
      data[22] = _note(
        '<div>פסקה22 <details><summary>הצג טקסט מוסתר</summary>PAYLOAD_VISIBLE</details> המשך הפסקה</div>',
      );
      final h = await _pumpView(tester, data);
      h.tab.scrollController.jumpTo(index: 23);
      await tester.pumpAndSettle();
      final summary = find.textContaining('הצג טקסט מוסתר', findRichText: true);
      final payload = find.textContaining(
        'PAYLOAD_VISIBLE',
        findRichText: true,
      );
      expect(summary, findsOneWidget);
      expect(payload, findsNothing);
      final html = find.byKey(ValueKey('html_${_title}_22'));
      final htmlState = tester.state(html);
      await tester.tap(summary, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(payload, findsOneWidget);
      await _frames(tester, 20);
      expect(tester.state(html), same(htmlState));
      expect(h.bloc.loaded.selectedIndex, 22);
      expect(find.byKey(const ValueKey('commentary_card_22')), findsOneWidget);
      expect(
        payload,
        findsOneWidget,
        reason: 'בחירת מפרשים לא סוגרת details פתוח',
      );
    },
  );

  testWidgets('details זהים בפסקה הנבחרת ובשכנתה נשמרים בהחלפת עוגן', (
    tester,
  ) async {
    final data = _content();
    for (final index in [21, 22]) {
      data[index] = _note(
        '<div><DETAILS><SUMMARY>טקסט מוסתר</SUMMARY>'
        'תוכן פתוח</DETAILS> המשך</div>',
      );
    }
    final h = await _pumpView(tester, data);
    h.tab.scrollController.jumpTo(index: 23);
    await tester.pumpAndSettle();
    Finder paragraph(int index) =>
        find.byKey(ValueKey('html_${_title}_$index'), skipOffstage: false);
    for (final index in [21, 22]) {
      await tester.tap(
        find.descendant(
          of: paragraph(index),
          matching: find.textContaining('טקסט מוסתר', findRichText: true),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await _frames(tester, 20);
      h.bloc.replace(
        h.bloc.loaded.copyWith(
          clearSelectedIndex: true,
          clearSelectedIndices: true,
        ),
      );
      await _frames(tester, 20);
    }
    expect(
      find.textContaining('תוכן פתוח', findRichText: true, skipOffstage: false),
      findsNWidgets(2),
      reason: 'שני הפרטים פתוחים לפני בחירת שורה',
    );
    final before = [
      for (final index in [21, 22]) tester.state(paragraph(index)),
    ];
    h.bloc.replace(
      h.bloc.loaded.copyWith(
        clearSelectedIndex: true,
        clearSelectedIndices: true,
      ),
    );
    await _frames(tester, 5);
    await _tap(tester, 22);
    await _frames(tester, 20);
    expect(find.byKey(const ValueKey('commentary_card_22')), findsOneWidget);
    expect(
      find.textContaining('תוכן פתוח', findRichText: true, skipOffstage: false),
      findsNWidgets(2),
    );
    for (var i = 0; i < 2; i++) {
      expect(
        tester.state(paragraph(21 + i)),
        same(before[i]),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('גלילה רחוקה מבודדת עותקים מקבילים ומשחררת מצב שיצא מהמטמון', (
    tester,
  ) async {
    final data = [
      for (var i = 0; i < 80; i++)
        _note(
          '<div>פסקה$i ${'מילה ' * 30}'
          '<details><summary>טקסט מוסתר</summary>תוכן$i</details></div>',
        ),
    ];
    final h = await _pumpView(tester, data, notes: false);
    h.tab.scrollController.jumpTo(index: 23);
    await tester.pumpAndSettle();
    final key =
        tester
                .widget<Column>(
                  find
                      .ancestor(
                        of: find.byKey(ValueKey('html_${_title}_23')),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is Column && widget.key is GlobalKey,
                        ),
                      )
                      .first,
                )
                .key!
            as GlobalKey;
    expect(key.currentContext, isNotNull);
    var sawOverlap = false;
    for (final index in [12, 60, 0, 79]) {
      final scrolling = h.tab.scrollController.scrollTo(
        index: index,
        duration: const Duration(seconds: 1),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        sawOverlap |=
            find
                .byKey(ValueKey('html_${_title}_17'), skipOffstage: false)
                .evaluate()
                .length >
            1;
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      await scrolling;
    }
    expect(
      sawOverlap,
      isTrue,
      reason: 'הבדיקה מכסה פריט שבנוי בשני עותקי הרשימה יחד',
    );
    expect(
      key.currentContext,
      isNull,
      reason: 'אין מאגר שמחזיק פסקאות מחוץ למטמון',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('פסקה גבוהה עם details וכרטיס מלא חושפת את תחתית המפרשים', (
    tester,
  ) async {
    final data = _content();
    data[22] = _note(
      '<div>פסקה22 <details><summary>טקסט מוסתר ארוך</summary>'
      '${List.filled(12, 'תוכן פתוח ארוך').join('<br>')}</details> סוף</div>',
    );
    final h = await _pumpView(tester, data);
    h.tab.scrollController.jumpTo(index: 23);
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining('טקסט מוסתר ארוך', findRichText: true),
      kind: PointerDeviceKind.mouse,
    );
    await _frames(tester, 20);
    final html = find.byKey(ValueKey('html_${_title}_22'));
    expect(tester.getSize(html).height, greaterThan(880 * .25));
    expect(
      find.textContaining('תוכן פתוח ארוך', findRichText: true),
      findsOneWidget,
    );
    final card = find.byKey(const ValueKey('commentary_card_22'));
    expect(card, findsOneWidget);
    expect(tester.getRect(card).bottom, lessThanOrEqualTo(880));
    expect(tester.takeException(), isNull);
  });

  testWidgets('תצוגה מקדימה מבודדת עותקי פסקאות בזמן גלילה רחוקה', (
    tester,
  ) async {
    final data = [
      for (var i = 0; i < 80; i++)
        '<div>פסקה$i ${'מילה ' * 30}'
            '<details><summary>טקסט מוסתר</summary>תוכן$i</details></div>',
    ];
    final h = await _pumpView(tester, data, notes: false, preview: true);
    for (final index in [23, 10, 60, 0]) {
      final scrolling = h.tab.scrollController.scrollTo(
        index: index,
        duration: const Duration(seconds: 1),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      await scrolling;
    }
  });

  testWidgets('שתי תצוגות של אותו ספר מחזיקות מצב תוכן נפרד', (tester) async {
    final data = ['<details><summary>טקסט מוסתר</summary>תוכן פתוח</details>'];
    await _pumpView(tester, data, notes: false, duplicateView: true);
    expect(find.byKey(ValueKey('html_${_title}_0')), findsNWidgets(2));
    await tester.tap(
      find.textContaining('טקסט מוסתר', findRichText: true).first,
      kind: PointerDeviceKind.mouse,
    );
    await _frames(tester, 20);
    expect(
      find.textContaining('תוכן פתוח', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('סגירה ופתיחה מחדש משחררות מצב ומתחילות details סגור', (
    tester,
  ) async {
    final data = ['<details><summary>טקסט מוסתר</summary>תוכן פתוח</details>'];
    await _pumpView(tester, data, notes: false);
    final original = tester.state(find.byKey(ValueKey('html_${_title}_0')));
    await tester.tap(
      find.textContaining('טקסט מוסתר', findRichText: true),
      kind: PointerDeviceKind.mouse,
    );
    await _frames(tester, 20);
    expect(
      find.textContaining('תוכן פתוח', findRichText: true),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(original.mounted, isFalse);
    await _pumpView(tester, data, notes: false);
    expect(find.textContaining('תוכן פתוח', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('כרטיס מלא בפסקה האחרונה נשאר גלוי עד תחתיתו', (
    tester,
  ) async {
    final h = await _pumpView(tester, _content());
    h.tab.scrollController.jumpTo(index: 23);
    await tester.pumpAndSettle();
    await _tap(tester, 23);
    await _frames(tester, 20);
    final p = _positions(h.tab)[23]!;
    expect(p.itemTrailingEdge, moreOrLessEquals(1, epsilon: .002));
    expect(p.itemLeadingEdge, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'גלילה במהלך השהיית הלחיצה אינה יוצרת עיגון לא תקין',
    (tester) async {
      final h = await _pumpView(tester, _content());
      h.tab.scrollController.jumpTo(index: 10, alignment: .2);
      await tester.pumpAndSettle();
      await _tap(tester, 10);
      final outer = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      outer.position.jumpTo(outer.position.pixels - 800);
      await tester.pump(const Duration(milliseconds: 100));
      await _frames(tester, 20);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('הסרת מסנן במהלך השהיית הגלילה אינה גורמת שגיאה', (
    tester,
  ) async {
    final h = await _pumpView(tester, _content());
    h.tab.scrollController.jumpTo(index: 23);
    await tester.pumpAndSettle();
    await _tap(tester, 22);
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump();
    expect(h.bloc.loaded.selectedIndex, 22);
    h.bloc.replace(h.bloc.loaded.copyWith(activeCommentators: const []));
    await _frames(tester, 20);
    expect(find.byKey(const ValueKey('commentary_card_22')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'מעבר לקריאה רציפה במהלך ההשהיה שומר אינדקסים תקינים',
    (tester) async {
      final data = [
        for (var i = 0; i < 24; i++)
          _note(
            '<div>פסקה$i <details><summary>פרטים</summary>תוכן</details></div>',
          ),
      ];
      final h = await _pumpView(tester, data, withSegments: true);
      h.tab.scrollController.jumpTo(index: 23);
      await tester.pumpAndSettle();
      await _tap(tester, 22);
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      expect(h.bloc.loaded.selectedIndex, 22);
      h.bloc.replace(
        h.bloc.loaded.copyWith(
          continuousReadingMode: true,
          readingSegments: buildReadingSegments(data, continuous: true),
        ),
      );
      await _frames(tester, 20);
      expect(tester.takeException(), isNull);
      expect(
        _positions(
          h.tab,
        ).keys.every((i) => i >= 0 && i < h.bloc.loaded.readingSegments.length),
        isTrue,
      );
    },
  );

  testWidgets(
    'קיצור תוכן במהלך ההשהיה שומר אינדקסים תקינים',
    (tester) async {
      final h = await _pumpView(tester, _content());
      h.tab.scrollController.jumpTo(index: 23);
      await tester.pumpAndSettle();
      await _tap(tester, 22);
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      final short = h.bloc.loaded.content.take(3).toList();
      h.bloc.replace(
        h.bloc.loaded.copyWith(
          content: short,
          clearSelectedIndex: true,
          clearSelectedIndices: true,
        ),
      );
      await _frames(tester, 20);
      expect(tester.takeException(), isNull);
      expect(_positions(h.tab).keys.every((i) => i >= 0 && i < 3), isTrue);
    },
  );

  testWidgets('ללא מפרשים לחיצה אינה גוללת', (
    tester,
  ) async {
    final h = await _pumpView(tester, _content(), notes: false);
    h.tab.scrollController.jumpTo(index: 23);
    await tester.pumpAndSettle();
    final before = _positions(h.tab)[22]!.itemLeadingEdge;
    await _tap(tester, 22);
    await _frames(tester, 20);
    expect(
      _positions(h.tab)[22]!.itemLeadingEdge,
      moreOrLessEquals(before, epsilon: .002),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('סגירת התצוגה במהלך ההשהיה בטוחה', (
    tester,
  ) async {
    final h = await _pumpView(tester, _content());
    h.tab.scrollController.jumpTo(index: 23);
    await tester.pumpAndSettle();
    await _tap(tester, 22);
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester, 10);
    expect(tester.takeException(), isNull);
  });
}

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<UpdateSelectedIndex>(
      (event, emit) => emit(
        loaded.copyWith(
          selectedIndex: event.index,
          clearSelectedIndex: event.index == null,
          selectedIndices: {?event.index},
          clearSelectedIndices: event.index == null,
        ),
      ),
    );
    on<TextBookEvent>((event, emit) {});
  }
  TextBookLoaded get loaded => state as TextBookLoaded;
  void replace(TextBookLoaded next) => emit(next);
  @override
  late final TextBookRepository repository = _TextBookRepository();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
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
