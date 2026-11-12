import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/toc_expansion_settings.dart';
import 'package:otzaria/text_book/view/toc_navigator_screen.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitState(TextBookState newState) => emit(newState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// שלוש רמות: פרקים, דפים ועמודים. שורה של כל ערך = האינדקס שלו.
List<TocEntry> _toc() {
  var line = 0;
  return [
    for (var c = 0; c < 3; c++)
      () {
        final chapter = TocEntry(text: 'פרק $c', index: line++, level: 1);
        for (var d = 0; d < 2; d++) {
          final daf = TocEntry(
            text: 'דף $c-$d',
            index: line++,
            level: 2,
            parent: chapter,
          );
          for (final amud in ['.', ':']) {
            daf.children.add(
              TocEntry(
                text: 'עמוד $c-$d$amud',
                index: line++,
                level: 3,
                parent: daf,
              ),
            );
          }
          chapter.children.add(daf);
        }
        return chapter;
      }(),
  ];
}

TextBookLoaded _state(List<TocEntry> toc, {required int visible}) =>
    TextBookLoaded(
      book: TextBook(title: 'ספר בדיקה'),
      showLeftPane: true,
      content: List.generate(30, (i) => 'שורה $i'),
      fontSize: 18,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: toc,
      removeNikud: false,
      visibleIndices: [visible],
      pinLeftPane: false,
      searchText: '',
    );

Future<_TestTextBookBloc> _pump(
  WidgetTester tester,
  List<TocEntry> toc, {
  int visible = 0,
}) async {
  final bloc = _TestTextBookBloc(_state(toc, visible: visible));
  addTearDown(bloc.close);
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: BlocProvider<TextBookBloc>.value(
            value: bloc,
            child: SizedBox(
              width: 400,
              height: 800,
              child: TocViewer(
                lines: LineScrollController(),
                closeLeftPaneCallback: () {},
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('הרחבה וכיווץ של הכותרות'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

bool _isSelected(WidgetTester tester, String title) => tester
    .widget<NavTreeTile>(
      find.ancestor(of: find.text(title), matching: find.byType(NavTreeTile)),
    )
    .isSelected;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    TocExpansionSettings.autoExpand.value = true;
  });

  testWidgets('"הצג עד רמה 2" מראה דפים בלי עמודים, ונשמר לספר הבא', (
    tester,
  ) async {
    await _pump(tester, _toc());
    await _choose(tester, 'הצג עד רמה 2');
    expect(find.text('דף 2-1'), findsOneWidget);
    expect(find.text('עמוד 0-0.'), findsNothing);
    expect(TocExpansionSettings.loadLevel(), 2);

    // ספר שנפתח אחר כך מתחיל באותה רמה.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, _toc());
    expect(find.text('דף 2-1'), findsOneWidget);
    expect(find.text('עמוד 0-0.'), findsNothing);
  });

  testWidgets('בלי פתיחה אוטומטית: מיקום הקריאה מסומן על האב הגלוי', (
    tester,
  ) async {
    final bloc = await _pump(tester, _toc());
    await _choose(tester, 'כווץ הכל');
    await _choose(tester, 'פתיחה אוטומטית לפי מיקום הקריאה');
    expect(TocExpansionSettings.autoExpand.value, isFalse);

    // שורה 9 היא "עמוד 1-0." בתוך "פרק 1" הסגור.
    bloc.emitState(_state(bloc.state.tableOfContentsForTest, visible: 9));
    await tester.pumpAndSettle();
    expect(find.text('עמוד 1-0.'), findsNothing, reason: 'הענף לא נפתח לבד');
    expect(_isSelected(tester, 'פרק 1'), isTrue);
  });

  testWidgets('הכותרת הפעילה עוברת מדף לדף בגלילה (#2849)', (tester) async {
    final bloc = await _pump(tester, _toc(), visible: 2);
    expect(_isSelected(tester, 'עמוד 0-0.'), isTrue);

    // מעבר לדף הבא בספר: הסימון והענף הפתוח הולכים אחריו.
    bloc.emitState(_state(bloc.state.tableOfContentsForTest, visible: 5));
    await tester.pumpAndSettle();
    expect(_isSelected(tester, 'עמוד 0-1.'), isTrue);
    expect(_isSelected(tester, 'עמוד 0-0.'), isFalse);

    bloc.emitState(_state(bloc.state.tableOfContentsForTest, visible: 16));
    await tester.pumpAndSettle();
    expect(_isSelected(tester, 'עמוד 2-0.'), isTrue);
  });

  testWidgets('התפריט צף לצד אייקון החיפוש כשהכותרת נגללה החוצה (#4607)', (
    tester,
  ) async {
    final toc = List.generate(60, (c) {
      final chapter = TocEntry(text: 'פרק $c', index: c * 2, level: 1);
      chapter.children.add(
        TocEntry(text: 'סעיף $c', index: c * 2 + 1, level: 2, parent: chapter),
      );
      return chapter;
    });
    await _pump(tester, toc);
    expect(find.byTooltip('הרחבה וכיווץ של הכותרות'), findsOneWidget);

    await tester.drag(find.byType(NavTreeTile).first, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('ספר בדיקה'), findsNothing, reason: 'הכותרת נגללה');
    expect(find.byTooltip('הרחבה וכיווץ של הכותרות'), findsOneWidget);
    expect(find.byTooltip('איתור כותרת...'), findsOneWidget);
    expect(find.byType(NavPanelCollapsibleSearch), findsOneWidget);
  });
}

extension on TextBookState {
  List<TocEntry> get tableOfContentsForTest =>
      (this as TextBookLoaded).tableOfContents;
}
