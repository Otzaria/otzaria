import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_build_policy.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// שער הבנייה מחדש של עץ תצוגת הספר.
///
/// המלכוד המרכזי: `buildWhen` על ווידג'ט פנימי אינו מונע בנייה כשההורה
/// נבנה — הוא רק מקפיא את המצב שנמסר. לכן השער חייב לשבת גם בשורש העץ.
void main() {
  group('shouldRebuildReader', () {
    test('תזוזת גלילה בלבד אינה מצדיקה בנייה מחדש', () {
      final before = _loaded();
      final after = before.copyWith(visibleIndices: const [7, 8, 9]);

      expect(shouldRebuildReader(before, after), isFalse);
    });

    test('רשימת שורות גלויות זהה בערכה אינה מצדיקה בנייה', () {
      final before = _loaded();
      final after = before.copyWith(visibleIndices: [...before.visibleIndices]);

      expect(shouldRebuildReader(before, after), isFalse);
    });

    test('קישורי החלון שחושבו מחדש בגלילה אינם מצדיקים בנייה', () {
      // עם חלונית צד פתוחה כל צעד גלילה מחשב visibleLinks מחדש; הקורא נגזר
      // מ-linksByLine, וחלונית הקישורים נבנית מ-BlocBuilder משלה.
      final before = _loaded();
      final after = before.copyWith(
        visibleIndices: const [7, 8, 9],
        visibleLinks: [_link(1, 1), _link(1, 2)],
      );

      expect(shouldRebuildReader(before, after), isFalse);
    });

    test('קישורים שנטענו מחדש מצדיקים בנייה גם כשמספרם זהה', () {
      final before = _loaded();
      final after = before.copyWith(
        linksByLine: {
          1: [_link(1, 2)],
        },
        visibleLinks: [_link(1, 2), _link(1, 3)],
      );

      expect(shouldRebuildReader(before, after), isTrue);
    });

    test('כותרת שהשתנתה עם הגלילה כן מצדיקה בנייה מחדש', () {
      // currentTitle נגזר מהשורה הגלויה ומוצג בפס הכותרת; אילו נחסם יחד עם
      // visibleIndices הוא היה קופא על הכותרת הראשונה.
      final before = _loaded();
      final after = before.copyWith(
        visibleIndices: const [7, 8, 9],
        currentTitle: 'סימן אחר',
      );

      expect(shouldRebuildReader(before, after), isTrue);
    });

    test('עדכון הטקסט המסומן אינו מצדיק בנייה מחדש', () {
      // הסימון מתעדכן בכל תזוזת עכבר בזמן גרירה, ואף חלק מהתצוגה אינו נגזר
      // ממנו — בנייה בגללו מרעידה את כל המפרשים בצורת הדף (issue #976).
      final before = _loaded();
      final after = before.copyWith(
        selectedTextForNote: 'טקסט אחר',
        selectedTextSectionIndex: 2,
        selectedTextStart: 7,
        selectedTextEnd: 11,
      );

      expect(shouldRebuildReader(before, after), isFalse);
    });

    test('ניקוי הטקסט המסומן אינו מצדיק בנייה מחדש', () {
      final before = _loaded();
      final after = before.copyWith(clearSelectedText: true);

      expect(shouldRebuildReader(before, after), isFalse);
    });

    test('בחירת שורה מצדיקה בנייה מחדש', () {
      final before = _loaded();

      expect(
        shouldRebuildReader(
          before,
          before.copyWith(selectedIndex: before.selectedIndex! + 1),
        ),
        isTrue,
      );
    });

    test('מעבר מצב קריאה רציף מצדיק בנייה מחדש', () {
      final before = _loaded();
      final after = before.copyWith(
        continuousReadingMode: !before.continuousReadingMode,
        visibleIndices: const [3],
      );

      expect(shouldRebuildReader(before, after), isTrue);
    });

    test('גרסת תוכן חדשה מצדיקה בנייה גם כשאורך התוכן זהה', () {
      // טעינת חלון מה-DB מחליפה שורות בלי לשנות את האורך; contentVersion
      // הוא מה שמבדיל, ובלעדיו התוכן החדש לא היה מצויר.
      final before = _loaded();
      final after = before.copyWith(
        content: const ['אחר', 'אחר', 'אחר'],
        contentVersion: before.contentVersion + 1,
        visibleIndices: const [5],
      );

      expect(shouldRebuildReader(before, after), isTrue);
    });

    test('סיום טעינת הקישורים מצדיק בנייה מחדש', () {
      final before = _loaded();
      final after = before.copyWith(
        linksLoading: !before.linksLoading,
        visibleIndices: const [9],
      );

      expect(shouldRebuildReader(before, after), isTrue);
    });

    test('מצב שאינו טעון תמיד נבנה', () {
      final loaded = _loaded();
      final initial = TextBookInitial.named(
        TextBook(title: 'ספר'),
        0,
        false,
        const [],
      );

      expect(shouldRebuildReader(initial, loaded), isTrue);
      expect(shouldRebuildReader(loaded, initial), isTrue);
      expect(
        shouldRebuildReader(initial, initial),
        isTrue,
      );
    });

    test('copyWith משמר כל שדה שמשתתף בהשוואה', () {
      // ההשוואה בנויה על כך ש-copyWith משמר כל שדה ב-props. שדה שיתווסף
      // ל-props ולא ל-copyWith יחזור לברירת המחדל, ההשוואה תראה "זהה",
      // ובנייה תיחסם בטעות בדיוק כשהיא נדרשת. הבדיקה תופסת זאת רק אם כל
      // שדה ב-fixture נושא ערך שאינו ברירת המחדל של הבנאי.
      final state = _loaded();

      expect(state.copyWith(), equals(state));
    });

    test('ה-fixture אינו נשען על ברירות המחדל של הבנאי', () {
      // שומר על הבדיקה שמעליה: אם שדה כאן יחזור לברירת מחדל, מוטציה
      // ב-copyWith תעבור בשקט.
      final state = _loaded();

      expect(state.showLeftPane, isTrue);
      expect(state.linksLoading, isTrue);
      expect(state.hasDraft, isTrue);
      expect(state.isEditorOpen, isTrue);
      expect(state.pinLeftPane, isTrue);
      expect(state.removePunctuation, isTrue);
      expect(state.isTanach, isTrue);
      expect(state.continuousReadingMode, isTrue);
      expect(state.searchText, isNotEmpty);
      expect(state.highlightText, isNotEmpty);
      expect(state.searchDistance, isNot(0));
      expect(state.searchMode, isNot(SearchMode.exact));
      expect(state.selectedIndex, isNotNull);
      expect(state.currentTitle, isNotNull);
      expect(state.searchResultLines, isNotNull);
      expect(state.permanentHighlightLine, isNotNull);
      expect(state.selectedIndices, isNotEmpty);
      expect(state.selectedLinkTypes, isNotEmpty);
      expect(state.readingSegments, isNotEmpty);
      expect(state.visibleLinks, isNotEmpty);
    });
  });

  group('שער הבנייה בעץ ווידג\'טים', () {
    testWidgets('שער בשורש מונע בנייה של כל תת-העץ', (tester) async {
      final cubit = _StateCubit(_loaded());
      var rootBuilds = 0;
      var leafBuilds = 0;

      await tester.pumpWidget(
        _tree(
          cubit,
          guardRoot: true,
          onRoot: () {
            rootBuilds++;
          },
          onLeaf: (_) {
            leafBuilds++;
          },
        ),
      );

      final baseline = leafBuilds;
      for (var i = 0; i < 5; i++) {
        cubit.scrollTo([i, i + 1]);
        await tester.pump();
      }

      expect(rootBuilds, 1, reason: 'השורש נבנה רק בפריים הראשון');
      expect(
        leafBuilds,
        baseline,
        reason: 'תזוזת גלילה אינה בונה מחדש את העלה',
      );

      await cubit.close();
    });

    testWidgets('גלילה עם חלונית קישורים פתוחה אינה בונה את העלה', (
      tester,
    ) async {
      final cubit = _StateCubit(_loaded());
      var leafBuilds = 0;

      await tester.pumpWidget(
        _tree(
          cubit,
          guardRoot: true,
          onLeaf: (_) {
            leafBuilds++;
          },
        ),
      );

      final baseline = leafBuilds;
      for (var i = 0; i < 5; i++) {
        cubit.scrollWithLinks(
          [i, i + 1],
          [
            for (var k = 0; k <= i; k++) _link(1, k),
          ],
        );
        await tester.pump();
      }

      expect(leafBuilds, baseline);

      await cubit.close();
    });

    testWidgets('שינוי שאינו גלילה עובר את השער ובונה מחדש', (tester) async {
      final cubit = _StateCubit(_loaded());
      var leafBuilds = 0;

      await tester.pumpWidget(
        _tree(
          cubit,
          guardRoot: true,
          onLeaf: (_) {
            leafBuilds++;
          },
        ),
      );

      final baseline = leafBuilds;
      cubit.retitle('סימן חדש');
      await tester.pump();

      expect(leafBuilds, greaterThan(baseline));

      await cubit.close();
    });

    testWidgets('הסרת השער מהשורש מבטלת גם את השער בעלה', (tester) async {
      // מתעד למה השער חייב לשבת בשורש: `buildWhen` בעלה אינו עוצר בנייה
      // שמגיעה מההורה, ובנוסף מוסר לו מצב ישן.
      final cubit = _StateCubit(_loaded());
      var leafBuilds = 0;
      List<int>? leafSaw;

      await tester.pumpWidget(
        _tree(
          cubit,
          guardRoot: false,
          onLeaf: (state) {
            leafBuilds++;
            leafSaw = state.visibleIndices;
          },
        ),
      );

      final baseline = leafBuilds;
      cubit.scrollTo(const [41, 42]);
      await tester.pump();

      expect(
        leafBuilds,
        greaterThan(baseline),
        reason: 'העלה נבנה למרות buildWhen, כי ההורה נבנה',
      );
      expect(
        leafSaw,
        isNot(const [41, 42]),
        reason: 'ובנוסף הוא מקבל מצב ישן — לכן אין להסתמך על שער בעלה בלבד',
      );

      await cubit.close();
    });

    testWidgets('סימון טקסט אינו בונה מחדש פאנל מפרשים שמאזין ל-bloc בעצמו', (
      tester,
    ) async {
      // מבנה צורת הדף: שער בשורש, וכל פאנל מפרשים הוא BlocBuilder נפרד. שער
      // ההורה אינו מגן עליו, ולכן השער שלו חייב לחסום גם את עדכוני הסימון.
      final cubit = _StateCubit(_loaded());
      var leafBuilds = 0;

      await tester.pumpWidget(
        _tree(
          cubit,
          guardRoot: true,
          onLeaf: (_) {
            leafBuilds++;
          },
        ),
      );

      final baseline = leafBuilds;
      for (var i = 0; i < 5; i++) {
        cubit.selectText('טקסט $i', i);
        await tester.pump();
      }

      expect(
        leafBuilds,
        baseline,
        reason: 'גרירת סימון אינה בונה מחדש את פאנל המפרשים',
      );

      await cubit.close();
    });

    testWidgets('רצף חסימות אינו צובר פער — המצב מתעדכן בשינוי הבא', (
      tester,
    ) async {
      // הפרדיקט טרנזיטיבי, ולכן שרשרת דילוגים לא יכולה להשאיר את העלה
      // עם מצב ישן אחרי ששדה אמיתי משתנה.
      final cubit = _StateCubit(_loaded());
      TextBookLoaded? leafSaw;

      await tester.pumpWidget(
        _tree(
          cubit,
          guardRoot: true,
          onLeaf: (state) {
            leafSaw = state;
          },
        ),
      );

      for (var i = 0; i < 4; i++) {
        cubit.scrollTo([i]);
        await tester.pump();
      }
      cubit.retitle('אחרי הרצף');
      await tester.pump();

      expect(leafSaw!.currentTitle, 'אחרי הרצף');
      expect(leafSaw!.visibleIndices, const [3]);

      await cubit.close();
    });
  });
}

Widget _tree(
  _StateCubit cubit, {
  required bool guardRoot,
  VoidCallback? onRoot,
  required void Function(TextBookLoaded state) onLeaf,
}) {
  return MaterialApp(
    home: BlocProvider.value(
      value: cubit,
      child: BlocBuilder<_StateCubit, TextBookState>(
        buildWhen: guardRoot ? shouldRebuildReader : null,
        builder: (context, _) {
          onRoot?.call();
          return BlocBuilder<_StateCubit, TextBookState>(
            buildWhen: shouldRebuildReader,
            builder: (context, state) {
              onLeaf(state as TextBookLoaded);
              return const SizedBox();
            },
          );
        },
      ),
    ),
  );
}

class _StateCubit extends Cubit<TextBookState> {
  _StateCubit(super.initialState);

  void scrollTo(List<int> visibleIndices) {
    emit((state as TextBookLoaded).copyWith(visibleIndices: visibleIndices));
  }

  void scrollWithLinks(List<int> visibleIndices, List<Link> visibleLinks) {
    emit(
      (state as TextBookLoaded).copyWith(
        visibleIndices: visibleIndices,
        visibleLinks: visibleLinks,
      ),
    );
  }

  void retitle(String title) {
    emit((state as TextBookLoaded).copyWith(currentTitle: title));
  }

  void selectText(String text, int start) {
    emit(
      (state as TextBookLoaded).copyWith(
        selectedTextForNote: text,
        selectedTextStart: start,
        selectedTextEnd: start + text.length,
      ),
    );
  }
}

Link _link(int index1, int index2) => Link(
  heRef: 'ref',
  index1: index1,
  path2: 'commentary.txt',
  index2: index2,
  connectionType: 'commentary',
);

/// מצב שבו **כל** שדה שמשתתף בהשוואה נושא ערך שאינו ברירת המחדל של הבנאי,
/// כדי ששער הסחיפה מעל יתפוס שדה שנשמט מ-`copyWith`.
TextBookLoaded _loaded() => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  content: const ['שורה א', 'שורה ב', 'שורה ג'],
  contentVersion: 3,
  fontSize: 22,
  showLeftPane: true,
  showSplitView: true,
  showTzuratHadafView: true,
  showPageShapeView: true,
  activeCommentators: const ['רש"י'],
  commentatorGroups: const [],
  availableCommentators: const ['רש"י', 'רמב"ן'],
  rareCommentators: const {'אור החיים'},
  links: [_link(1, 1)],
  linksByLine: {
    1: [_link(1, 1)],
  },
  visibleLinks: [_link(1, 1)],
  selectedLinkTypes: const {'COMMENTARY'},
  tableOfContents: [TocEntry(text: 'סימן א', index: 0, level: 1)],
  removeNikud: true,
  removePunctuation: true,
  isTanach: true,
  nikudExemptByTanach: true,
  punctuationExemptByTanach: true,
  commentaryRemoveNikudOverride: true,
  commentaryRemovePunctuationOverride: true,
  supportsContinuousReadingMode: true,
  continuousReadingMode: true,
  readingSegments: const [
    ReadingSegment(
      text: 'שורה א',
      sourceLineIndices: [0],
      lineRanges: [ReadingLineRange(lineIndex: 0, start: 0, end: 6)],
      isHeader: false,
    ),
  ],
  visibleIndices: const [1, 2],
  selectedIndex: 1,
  selectedIndices: const {1},
  pinLeftPane: true,
  searchText: 'חיפוש',
  searchOptions: const {
    'חיפוש_0': {'סיומות': true},
  },
  alternativeWords: const {
    0: ['חלופה'],
  },
  spacingValues: const {'0-1': '1'},
  searchMode: SearchMode.advanced,
  searchDistance: 4,
  matchPolicy: const SearchMatchPolicy(
    proximityScope: SearchScope.sameParagraph,
  ),
  searchResultLines: const {2},
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
  currentTitle: 'סימן א',
  selectedTextForNote: 'טקסט',
  selectedTextSectionIndex: 1,
  selectedTextStart: 2,
  selectedTextEnd: 5,
  highlightedLine: 2,
  linksLoading: true,
  pinpointHighlightIndex: 1,
  pinpointHighlightText: 'מודגש',
  isEditorOpen: true,
  editorIndex: 1,
  editorSectionId: 'section',
  editorText: 'עריכה',
  hasDraft: true,
  hasLinksFile: true,
  highlightText: 'הדגשה',
  permanentHighlightLine: 2,
);
