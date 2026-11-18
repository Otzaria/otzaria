import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/view/widgets/book_source_banner.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_dispatcher.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
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
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _title = 'ספר בדיקה';

// כמו סוף מסכת: פסקאות ואחריהן שורת סיום גבוהה.
final _content = <String>[
  for (var i = 0; i < 20; i++) 'פסקה$i ${List.filled(30, 'מילה$i').join(' ')}',
  for (var i = 20; i < 23; i++) 'פסקה$i ${List.filled(6, 'מילה$i').join(' ')}',
  '<big><strong>${List.filled(3, 'הדרן עלך המגרש וסליקא לה מסכת גיטין').join('<br>')}</strong></big>',
];

final _lastIndex = _content.length - 1;

// שורת סיום נמוכה: הכרטיס שנפתח מעליה דוחף אותה אל מתחת לקו ה-90%.
final _shortEndContent = <String>[
  ..._content.take(_lastIndex),
  'פסקה$_lastIndex ${List.filled(6, 'מילה$_lastIndex').join(' ')}',
];

// פסקה 5 גבוהה מהמסך.
final _tallContent = <String>[
  for (var i = 0; i < 12; i++)
    'פסקה$i ${List.filled(i == 5 ? 900 : 30, 'מילה$i').join(' ')}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  /// פותח את התצוגה המשולבת (מפרשים מתחת לטקסט) ב-[jumpIndex] (ברירת מחדל:
  /// סוף הספר), לוחץ על [paragraph] ומחזיר את המיקומים לפני הלחיצה ואחריה.
  Future<
    ({
      Map<int, ItemPosition> before,
      Map<int, ItemPosition> after,
      Rect card,
      TextBookTab tab,
    })
  >
  tapParagraph(
    WidgetTester tester,
    int paragraph, {
    int? jumpIndex,
    double alignment = 0,
    List<String>? content,
    Offset Function(Rect paragraph)? tapPoint,
    Future<String>? commentaryContent,
    Future<void> Function(TextBookTab tab)? afterOpening,
    Size surfaceSize = const Size(620, 880),
    String searchText = '',
    int? expectedParagraph,
    ReadingAnchor? initialAnchor,
    BookProtection protection = BookProtection.none,
    void Function(TextBookTab tab)? afterFirstFrame,
  }) async {
    final lines = content ?? _content;
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final links = [
      for (var line = 1; line <= lines.length; line++)
        _FixtureLink(line, commentaryContent),
    ];
    final bloc = _TextBookBloc(
      TextBookLoaded(
        book: TextBook(title: _title),
        showLeftPane: false,
        content: lines,
        fontSize: 25,
        showSplitView: false,
        showPageShapeView: false,
        activeCommentators: const ['רש"י'],
        commentatorGroups: const [
          CommentatorGroup(title: 'ראשונים', commentators: ['רש"י']),
        ],
        availableCommentators: const ['רש"י'],
        links: links,
        visibleLinks: const [],
        linksByLine: {
          for (final link in links) link.index1: [link],
        },
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: List.generate(lines.length, (i) => i),
        selectedIndex: null,
        pinLeftPane: false,
        searchText: searchText,
        protection: protection,
      ),
    );
    final notesBloc = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(
      book: TextBook(title: _title),
      index: 0,
      initialReadingAnchor: initialAnchor,
    );
    addTearDown(bloc.close);
    addTearDown(notesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

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
            body: CombinedView(
              data: lines,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 25,
              showCommentaryAsExpansionTiles: true,
              tab: tab,
            ),
          ),
        ),
      ),
    );
    afterFirstFrame?.call(tab);
    await tester.pump();
    // כמו ה-bloc האמיתי: המצב הטעון נפלט פעם אחת, והגלילה הראשונית רצה לפני
    // הקפיצה של הבדיקה.
    bloc.emitForTest(
      (bloc.state as TextBookLoaded).copyWith(
        visibleIndices: [jumpIndex ?? _lastIndex],
      ),
    );
    await tester.pumpAndSettle();

    // ברירת המחדל כמו Ctrl+End: הרשימה נעצרת בסוף הספר.
    tab.lines.itemController.jumpTo(
      index: jumpIndex ?? _lastIndex,
      alignment: alignment,
    );
    await tester.pumpAndSettle();

    Map<int, ItemPosition> positions() => {
      for (final p in tab.lines.positionsListener.itemPositions.value)
        p.index: p,
    };
    final before = positions();
    if (jumpIndex == null) {
      expect(
        before[_lastIndex]!.itemTrailingEdge,
        moreOrLessEquals(1.0, epsilon: 1e-3),
      );
    }

    final target = find.byKey(ValueKey('html_${_title}_$paragraph'));
    final rect = tester.getRect(target);
    await tester.tapAt(
      tapPoint?.call(rect) ?? rect.bottomCenter - const Offset(0, 10),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    await tester.pump();
    await afterOpening?.call(tab);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final selectedParagraph = expectedParagraph ?? paragraph;
    expect((bloc.state as TextBookLoaded).selectedIndex, selectedParagraph);
    final card = tester.getRect(
      find.byKey(ValueKey('commentary_card_$selectedParagraph')),
    );
    return (before: before, after: positions(), card: card, tab: tab);
  }

  for (final restored in [false, true]) {
    testWidgets('באנר בפריים הראשון: עוגן אפס מפורש=$restored', (tester) async {
      await tapParagraph(
        tester,
        2,
        jumpIndex: 2,
        initialAnchor: restored
            ? const ReadingAnchor(line: 0, alignment: 0)
            : null,
        protection: BookProtection(bannerText: 'קרדיט למקור הספר ' * 80),
        afterFirstFrame: (tab) {
          final list = tester.widget<ScrollablePositionedList>(
            find.byType(ScrollablePositionedList),
          );
          if (restored) {
            expect(list.initialTargetRectResolver, isNotNull);
            final box = tab.lines.itemBoxes.boxForItem(0)!;
            final source = tab.lines.itemBoxes.lineExtent(0, 0)!;
            expect(
              box.localToGlobal(Offset(0, source.top * box.size.height)).dy,
              closeTo(0, .1),
            );
          } else {
            expect(list.initialTargetRectResolver, isNull);
            expect(
              tester.getTopLeft(find.byType(BookSourceBanner)).dy,
              greaterThanOrEqualTo(0),
            );
          }
        },
      );
    });
  }

  testWidgets('החלפת ספר ו־Bloc שומרת State ומעבירה את כל החיבורים', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(620, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final settings = StubSettingsBloc(SettingsState.initial());
    final oldBook = TextBook(title: 'ספר ישן');
    final newBook = TextBook(title: 'ספר חדש');
    final oldTab = TextBookTab(book: oldBook, index: 0);
    final newTab = TextBookTab(book: newBook, index: 12);
    final oldBloc = _TextBookBloc(_loadedBook(oldBook, _content));
    final newBloc = _TextBookBloc(_loadedBook(newBook, _content));
    addTearDown(notes.close);
    addTearDown(settings.close);
    addTearDown(oldBloc.close);
    addTearDown(newBloc.close);
    addTearDown(oldTab.dispose);
    addTearDown(newTab.dispose);
    const key = ValueKey('retained-reader');
    Widget reader(TextBookTab tab, TextBookBloc bloc) => MaterialApp(
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
            key: key,
            data: _content,
            openBookCallback: (_) {},
            openLeftPaneTab: (_, {searchText}) {},
            textSize: 25,
            showCommentaryAsExpansionTiles: true,
            tab: tab,
          ),
        ),
      ),
    );
    await tester.pumpWidget(reader(oldTab, oldBloc));
    await tester.pumpAndSettle();
    final retained = tester.state(find.byKey(key));
    PageStorageBucket readerStorage() => tester
        .widget<PageStorage>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(PageStorage),
          ),
        )
        .bucket;
    final oldStorage = readerStorage();
    expect(oldTab.lines.isAttached, isTrue);
    await tester.pumpWidget(reader(newTab, newBloc));
    await tester.pumpAndSettle();
    expect(tester.state(find.byKey(key)), same(retained));
    expect(readerStorage(), isNot(same(oldStorage)));
    final newStorage = readerStorage();
    expect(oldTab.lines.isAttached, isFalse);
    expect(newTab.lines.isAttached, isTrue);
    expect(FocusRepository().requestTabContentFocus(oldTab), isFalse);
    FocusRepository().cancelPendingTabContentFocus();
    expect(FocusRepository().requestTabContentFocus(newTab), isTrue);
    const request = DynamicCopyRequest(
      kind: DynamicShortcutKind.setTextDisplay,
      target: TextTarget.body,
      profile: TextDisplayProfile(),
    );
    oldTab.dynamicCopyRequestNotifier.value = request;
    expect(oldTab.dynamicCopyRequestNotifier.value, same(request));
    newTab.dynamicCopyRequestNotifier.value = request;
    expect(newTab.dynamicCopyRequestNotifier.value, isNull);
    expect(find.byKey(const ValueKey('html_ספר חדש_12')), findsOneWidget);
    oldBloc.emitForTest(
      (oldBloc.state as TextBookLoaded).copyWith(
        selectedIndex: 1,
        selectedIndices: const {1},
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('html_ספר ישן_1')), findsNothing);
    final navigation = newTab.lines.scrollToLine(3, duration: Duration.zero);
    await tester.pumpAndSettle();
    await navigation;
    expect(find.byKey(const ValueKey('html_ספר חדש_3')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('html_ספר חדש_3')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect((newBloc.state as TextBookLoaded).selectedIndex, 3);
    expect((oldBloc.state as TextBookLoaded).selectedIndex, 1);
    final refreshedBloc = _TextBookBloc(_loadedBook(newBook, _content));
    addTearDown(refreshedBloc.close);
    final move = newTab.lines.scrollToLine(4, duration: Duration.zero);
    await tester.pumpAndSettle();
    await move;
    await tester.tap(
      find.byKey(const ValueKey('html_ספר חדש_4')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(reader(newTab, refreshedBloc));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.state(find.byKey(key)), same(retained));
    expect(readerStorage(), isNot(same(newStorage)));
    expect((refreshedBloc.state as TextBookLoaded).selectedIndex, isNull);
    expect((newBloc.state as TextBookLoaded).selectedIndex, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(newTab.lines.isAttached, isFalse);
    expect(FocusRepository().requestTabContentFocus(newTab), isFalse);
    FocusRepository().cancelPendingTabContentFocus();
  });

  group('בחירת פסקה בסוף הספר לא מקפיצה את הרשימה אחורה (issue #1798)', () {
    testWidgets('כרטיס לפני שורת סיום גבוהה מקבל עדיפות בתוך המסך', (
      tester,
    ) async {
      final paragraph = _lastIndex - 1;
      final result = await tapParagraph(tester, paragraph);
      expect(
        result.after[paragraph]!.itemLeadingEdge,
        lessThanOrEqualTo(result.before[paragraph]!.itemLeadingEdge + 1e-3),
      );
      expect(result.card.top, greaterThanOrEqualTo(0));
      expect(result.card.bottom, lessThanOrEqualTo(880));
      expect(result.after[_lastIndex]!.itemTrailingEdge, greaterThan(1));
    });

    // תחילת המקור יכולה לצאת מהמסך כדי להשאיר את הכרטיס וסוף הספר גלויים.
    testWidgets('הפסקה האחרונה — סוף הספר נשאר בתחתית', (tester) async {
      final result = await tapParagraph(tester, _lastIndex);
      final last = result.after[_lastIndex]!;
      expect(last.itemTrailingEdge, moreOrLessEquals(1.0, epsilon: 1e-3));
      expect(result.card.top, greaterThanOrEqualTo(0));
      expect(result.card.bottom, lessThanOrEqualTo(880));
    });

    // פסקה שתחילתה מעל המסך אינה ניתנת לעיגון; הגלילה עדיין חושפת את הכרטיס.
    testWidgets('פסקה שחלקה מעל המסך — הכרטיס נחשף', (tester) async {
      final result = await tapParagraph(
        tester,
        4,
        jumpIndex: 5,
        alignment: 0.2,
      );
      expect(result.before[4]!.itemLeadingEdge, lessThan(0));
      expect(result.card.top, greaterThanOrEqualTo(0));
      expect(result.card.bottom, lessThanOrEqualTo(880));
    });

    // הכרטיס כבר נפתח בבדיקה שאחרי 300ms ודחף את הפסקה הבאה אל מתחת לקו
    // ה-90% — כמו במכשיר. סוף הספר עדיין חוזר לתחתית.
    testWidgets('כרטיס שדחף את הפסקה הבאה מתחת לקו ה-90% — סוף הספר בתחתית', (
      tester,
    ) async {
      final paragraph = _lastIndex - 1;
      final result = await tapParagraph(
        tester,
        paragraph,
        content: _shortEndContent,
      );
      double height(ItemPosition p) => p.itemTrailingEdge - p.itemLeadingEdge;
      final card =
          height(result.after[paragraph]!) - height(result.before[paragraph]!);
      final nextLeading = result.before[_lastIndex]!.itemLeadingEdge;
      expect(nextLeading, lessThan(0.9));
      expect(nextLeading + card, greaterThan(0.9));
      expect(
        result.after[_lastIndex]!.itemTrailingEdge,
        moreOrLessEquals(1.0, epsilon: 1e-3),
      );
    });

    testWidgets('פסקה גבוהה מהמסך — הכרטיס מוצג מיד', (tester) async {
      const paragraph = 5;
      final result = await tapParagraph(
        tester,
        paragraph,
        jumpIndex: paragraph,
        alignment: 0.3,
        content: _tallContent,
        tapPoint: (rect) => rect.topCenter + const Offset(0, 40),
        afterOpening: (_) async {
          final card = tester.getRect(
            find.byKey(
              const ValueKey('commentary_card_5'),
            ),
          );
          expect(card.top, greaterThanOrEqualTo(0));
          expect(card.bottom, lessThanOrEqualTo(880));
        },
      );
      expect(result.after[paragraph]!.itemLeadingEdge, lessThan(0));
      expect(result.card.top, greaterThanOrEqualTo(0));
      expect(result.card.bottom, lessThanOrEqualTo(880));
      final sourceExtent = result.tab.lines.itemBoxes.lineExtent(
        paragraph,
        paragraph,
      );
      expect(sourceExtent, isNotNull);
      final item = result.tab.lines.itemBoxes.boxForItem(paragraph)!;
      final measuredHeight =
          (sourceExtent!.bottom - sourceExtent.top) * item.size.height;
      final textRect = tester.getRect(
        find.byKey(const ValueKey('html_ספר בדיקה_5')),
      );
      expect(measuredHeight, closeTo(textRect.height, 4));
      expect(sourceExtent.bottom, lessThan(1));
      expect(result.tab.lines.history.value.back, isNotNull);
      final back = result.tab.lines.goBack();
      await tester.pumpAndSettle();
      await back;
      final restored = result.tab.lines.positionsListener.itemPositions.value
          .firstWhere((item) => item.index == paragraph);
      expect(
        restored.itemLeadingEdge,
        closeTo(result.before[paragraph]!.itemLeadingEdge, .01),
      );
    });

    testWidgets('תוכן שמגיע אחרי 900ms שומר את סוף הספר בתחתית', (
      tester,
    ) async {
      final result = await tapParagraph(
        tester,
        _lastIndex - 1,
        content: _shortEndContent,
        commentaryContent: Future.delayed(
          const Duration(milliseconds: 900),
          () => 'תוכן מאוחר ${'מילה ' * 300}',
        ),
      );
      expect(result.card.top, greaterThanOrEqualTo(0));
      expect(result.card.bottom, lessThanOrEqualTo(880));
      expect(
        result.tab.lines.itemController.scrollController!.position.extentAfter,
        closeTo(0, 0.1),
      );
    });

    testWidgets('כרטיס עם סרגל חיפוש וסיום סמוך לרבע מסך נשאר גלוי', (
      tester,
    ) async {
      final result = await tapParagraph(
        tester,
        _lastIndex - 1,
        content: [
          ..._shortEndContent.take(_lastIndex),
          'שורת סיום<br>שורת סיום',
        ],
        surfaceSize: const Size(620, 400),
        searchText: 'מילה',
        commentaryContent: Future.value('מפרש גבוה ${'מילה ' * 400}'),
      );
      expect(result.card.top, greaterThanOrEqualTo(0));
      expect(result.card.bottom, lessThanOrEqualTo(400));
      expect(result.card.height, lessThanOrEqualTo(300.1));
      final tail = result.after[_lastIndex]!;
      expect(
        tail.itemTrailingEdge - tail.itemLeadingEdge,
        inInclusiveRange(0.15, 0.26),
      );
    });

    testWidgets('בחירה חדשה גוברת על כרטיס קודם שתוכנו עדיין נטען', (
      tester,
    ) async {
      final result = await tapParagraph(
        tester,
        _lastIndex - 1,
        content: _shortEndContent,
        expectedParagraph: _lastIndex,
        commentaryContent: Future.delayed(
          const Duration(milliseconds: 1500),
          () => 'תוכן מאוחר ${'מילה ' * 300}',
        ),
        afterOpening: (tab) async {
          await tester.tap(
            find.byKey(ValueKey('html_${_title}_$_lastIndex')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump(const Duration(milliseconds: 301));
          await tester.pump();
          await tester.pump();
          final card = tester.getRect(
            find.byKey(ValueKey('commentary_card_$_lastIndex')),
          );
          expect(card.top, greaterThanOrEqualTo(0));
          expect(card.bottom, lessThanOrEqualTo(880));
        },
      );
      expect(result.card.top, greaterThanOrEqualTo(0));
      expect(result.card.bottom, lessThanOrEqualTo(880));
      expect(
        find.byKey(ValueKey('commentary_card_${_lastIndex - 1}')),
        findsNothing,
      );
    });

    testWidgets('גלילה ידנית מבטלת את העיגון לפני הגעת תוכן מאוחר', (
      tester,
    ) async {
      ItemPosition? userAnchor;
      final result = await tapParagraph(
        tester,
        _lastIndex - 1,
        content: _shortEndContent,
        commentaryContent: Future.delayed(
          const Duration(milliseconds: 900),
          () => 'תוכן מאוחר ${'מילה ' * 300}',
        ),
        afterOpening: (tab) async {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.sendEventToBinding(
            const PointerScrollEvent(
              position: Offset(300, 50),
              scrollDelta: Offset(0, -160),
            ),
          );
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(
            tab
                .lines
                .itemController
                .scrollController!
                .position
                .isScrollingNotifier
                .value,
            isFalse,
          );
          userAnchor = tab.lines.positionsListener.itemPositions.value
              .where(
                (item) => item.itemTrailingEdge > 0 && item.itemLeadingEdge < 1,
              )
              .reduce((a, b) => a.index < b.index ? a : b);
        },
      );
      expect(
        result.tab.lines.itemController.listController!.stickTarget,
        isNull,
      );
      expect(
        result.after[userAnchor!.index]!.itemLeadingEdge,
        closeTo(userAnchor!.itemLeadingEdge, 0.001),
      );
    });
  });
}

TextBookLoaded _loadedBook(TextBook book, List<String> content) =>
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: content,
      fontSize: 25,
      showSplitView: false,
      showPageShapeView: false,
      activeCommentators: const [],
      availableCommentators: const [],
      commentatorGroups: const [],
      searchText: '',
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: List.generate(content.length, (i) => i),
      selectedIndex: null,
      pinLeftPane: false,
    );

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<UpdateSelectedIndex>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(
          selectedIndex: event.index,
          clearSelectedIndex: event.index == null,
          selectedIndices: {?event.index},
          clearSelectedIndices: event.index == null,
        ),
      ),
    );
    on<TextBookEvent>((event, emit) {});
  }

  void emitForTest(TextBookState state) => emit(state);

  @override
  late final TextBookRepository repository = _TextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureLink extends Link {
  _FixtureLink(int line, Future<String>? delayed)
    : _content = delayed ?? Future.value('מפרש לדוגמה ${'מילה ' * 80}'),
      super(
        heRef: 'רש"י $line',
        index1: line,
        path2: 'רש"י',
        index2: line,
        connectionType: 'commentary',
      ) {
    _content.then((text) => _loaded = text);
  }

  final Future<String> _content;
  String? _loaded;
  @override
  Future<String> get content => _content;
  @override
  String? get loadedContent => _loaded;
  @override
  Future<String> get displayReference => Future.value(heRef);
}
