// CommentatorsListView הוא מסלול בחירת המפרשים כשאין ניהול בחירה חיצוני
// (תצוגה משולבת / צורת דף). עד לתיקון הוא לא העביר את צ׳יפי הסוג הלאה, ולכן
// הסינון לא הוצג שם כלל.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('בלי מפתחות סוג — ציר הסוגים אינו מוצג', (tester) async {
    await _pump(tester);

    expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
    expect(find.byKey(commentatorEraChipsGroupKey), findsOneWidget);
  });

  testWidgets('המפתחות מוצגים עם התוויות העבריות של LinkTypes', (tester) async {
    await _pump(
      tester,
      typeChipKeys: const [LinkTypes.targum, LinkTypes.midrash],
    );

    expect(find.byKey(commentatorTypeChipsGroupKey), findsOneWidget);
    expect(find.widgetWithText(Chip, 'תרגום'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'מדרש'), findsOneWidget);
  });

  testWidgets('לחיצה על צ׳יפ מדווחת את המפתח להורה', (tester) async {
    Set<String>? reported;
    await _pump(
      tester,
      typeChipKeys: const [LinkTypes.targum, LinkTypes.midrash],
      onTypeChipsChanged: (types) => reported = types,
    );

    await tester.tap(find.widgetWithText(Chip, 'מדרש'));
    await tester.pumpAndSettle();

    expect(reported, {LinkTypes.midrash});
  });

  testWidgets('בחירה שנכנסת מבחוץ מסמנת את הצ׳יפ', (tester) async {
    await _pump(
      tester,
      typeChipKeys: const [LinkTypes.targum, LinkTypes.midrash],
      selectedTypeChips: const {LinkTypes.targum},
    );

    final selected = tester.widget<Chip>(find.widgetWithText(Chip, 'תרגום'));
    final unselected = tester.widget<Chip>(find.widgetWithText(Chip, 'מדרש'));
    expect(selected.backgroundColor, isNotNull);
    expect(unselected.backgroundColor, isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  List<String> typeChipKeys = const [],
  Set<String> selectedTypeChips = const {},
  ValueChanged<Set<String>>? onTypeChipsChanged,
}) async {
  final bloc = _TestTextBookBloc(_state());
  addTearDown(() async => bloc.close());

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: BlocProvider<TextBookBloc>.value(
          value: bloc,
          child: Scaffold(
            body: CommentatorsListView(
              typeChipKeys: typeChipKeys,
              selectedTypeChips: selectedTypeChips,
              onTypeChipsChanged: onTypeChipsChanged,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TextBookLoaded _state() => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const ['רש"י'],
  commentatorGroups: const [
    CommentatorGroup(title: 'ראשונים', commentators: ['רש"י']),
  ],
  availableCommentators: const ['רש"י'],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
