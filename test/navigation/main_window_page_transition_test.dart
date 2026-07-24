import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';

/// בדיקות ל-slide החוצה בין מסכים לא-סמוכים ב-MainWindowScreen.
///
/// קבוצה 1 בודקת את [MainWindowScreenState.buildTransitionPages] (סדר העמודים).
/// קבוצה 2 מפעילה PageView אמיתי ובודקת שימור State בפועל דרך הרקונסיליאציה —
/// כלומר שמסך stateful שזז בעץ במהלך ה-swap *לא* נבנה מחדש (כשיש לו GlobalKey),
/// וכן מתעדת שבלי GlobalKey הוא כן נבנה מחדש. שתי הקבוצות פועלות על הקוד האמיתי.
void main() {
  group('MainWindowScreenState.buildTransitionPages', () {
    const library = Text('library');
    const reading = Text('reading');
    const more = Text('more'); // מסך הכלים — keep-alive, אסור שיידחק מהעץ
    const settings = Text('settings');
    const canonical = [library, reading, more, settings];

    test('במנוחה (ללא מעבר) מחזיר את הסדר הקנוני כמות שהוא', () {
      final pages = MainWindowScreenState.buildTransitionPages(
        canonical,
        targetIndex: null,
        slotIndex: null,
      );
      expect(pages, same(canonical));
    });

    test('ספריה→כלים (0→2, slot=1): היעד מוצב בשכן, כל המסכים נשמרים', () {
      final pages = MainWindowScreenState.buildTransitionPages(
        canonical,
        targetIndex: 2,
        slotIndex: 1,
      );
      expect(pages[1], same(more), reason: 'מסך היעד מוצג בעמוד-השכן');
      expect(pages[2], same(reading), reason: 'מה שהיה בשכן עבר למיקום היעד');
      expect(pages[0], same(library), reason: 'המקור נשאר במקומו');
      expect(pages, containsAll(canonical), reason: 'אף מסך לא נמחק מהעץ');
    });

    test('הגדרות→ספריה (3→0, slot=2): מסך הכלים נשאר בעץ ואינו נדחק', () {
      // ה-slot נופל בדיוק על מיקום הכלים (2) — המקרה שחשף את הרגרסיה ב-[P1].
      final pages = MainWindowScreenState.buildTransitionPages(
        canonical,
        targetIndex: 0,
        slotIndex: 2,
      );
      expect(pages[2], same(library), reason: 'מסך היעד מוצג בעמוד-השכן');
      expect(
        pages[0],
        same(more),
        reason: 'הכלים זזו למיקום היעד דרך swap — אך נותרו בעץ',
      );
      expect(
        pages,
        contains(more),
        reason: 'מסך הכלים (keep-alive) לא נדחק → ה-WebView אינו נטען מחדש',
      );
      expect(pages, containsAll(canonical));
    });

    test('ספריה→הגדרות (0→3, slot=1): הכלים אינם מעורבים ונשארים במקומם', () {
      final pages = MainWindowScreenState.buildTransitionPages(
        canonical,
        targetIndex: 3,
        slotIndex: 1,
      );
      expect(pages[2], same(more), reason: 'הכלים לא זזו כלל');
      expect(pages[1], same(settings), reason: 'מסך היעד מוצג בעמוד-השכן');
      expect(pages, containsAll(canonical));
    });

    test('כל מעבר חוצה מחזיר תמורה של הסדר הקנוני (אורך ותוכן נשמרים)', () {
      const cases = [
        [2, 1], // 0→2
        [3, 1], // 0→3
        [3, 2], // 1→3
        [0, 1], // 2→0
        [0, 2], // 3→0
        [1, 2], // 3→1
      ];
      for (final c in cases) {
        final pages = MainWindowScreenState.buildTransitionPages(
          canonical,
          targetIndex: c[0],
          slotIndex: c[1],
        );
        expect(pages.length, canonical.length);
        expect(
          pages.toSet(),
          canonical.toSet(),
          reason: 'target=${c[0]} slot=${c[1]} — חייב להיות תמורה ללא אובדן',
        );
      }
    });
  });

  group('שימור State במהלך slide חוצה (PageView אמיתי)', () {
    testWidgets(
      'מסך ממותג (GlobalKey) שזז בעץ דרך swap עובר reparent ולא נבנה מחדש',
      (tester) async {
        _initCount = 0;
        // היעד (index 3) הוא StatefulWidget ממותג. במעבר 0→3 הוא מוצב זמנית
        // בעמוד-השכן (1), ובסיום עובר ל-3 — עם GlobalKey זהו reparent (initState
        // רץ פעם אחת בלבד).
        final pages = <Widget>[
          const Text('library'),
          const Text('reading'),
          const Text('more'),
          _Tracked(key: GlobalKey()),
        ];
        final hk = GlobalKey<_SlideHarnessState>();
        await tester.pumpWidget(
          MaterialApp(
            home: _SlideHarness(key: hk, pages: pages),
          ),
        );
        await tester.pumpAndSettle();

        final slide = hk.currentState!.slide(0, 3);
        await tester.pumpAndSettle();
        await slide;
        await tester.pumpAndSettle();

        expect(hk.currentState!.currentPageIndex, 3);
        expect(
          _initCount,
          1,
          reason: 'עם GlobalKey — המסך עבר reparent ולא נבנה מחדש',
        );
      },
    );

    testWidgets(
      'בלי GlobalKey אותו מסך נבנה מחדש — מאמת שה-key הכרחי לשימור ה-State',
      (tester) async {
        _initCount = 0;
        final pages = <Widget>[
          const Text('library'),
          const Text('reading'),
          const Text('more'),
          const _Tracked(), // ללא key
        ];
        final hk = GlobalKey<_SlideHarnessState>();
        await tester.pumpWidget(
          MaterialApp(
            home: _SlideHarness(key: hk, pages: pages),
          ),
        );
        await tester.pumpAndSettle();

        final slide = hk.currentState!.slide(0, 3);
        await tester.pumpAndSettle();
        await slide;
        await tester.pumpAndSettle();

        expect(
          _initCount,
          greaterThan(1),
          reason: 'בלי GlobalKey — פירוק ובנייה מחדש (זו הרגרסיה ש-key מונע)',
        );
      },
    );
  });
}

/// Harness מינימלי המפעיל את [MainWindowScreenState.buildTransitionPages] האמיתי
/// בתוך PageView, ומדמה את זרימת ה-slide (סידור זמני → animateToPage לשכן →
/// שחזור קנוני + jumpToPage ליעד).
class _SlideHarness extends StatefulWidget {
  const _SlideHarness({super.key, required this.pages});
  final List<Widget> pages;
  @override
  State<_SlideHarness> createState() => _SlideHarnessState();
}

class _SlideHarnessState extends State<_SlideHarness> {
  final PageController controller = PageController();
  int currentPageIndex = 0;
  int? _target;
  int? _slot;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> slide(int from, int to) async {
    final slot = from + (to > from ? 1 : -1);
    setState(() {
      _target = to;
      _slot = slot;
    });
    await WidgetsBinding.instance.endOfFrame;
    await controller.animateToPage(
      slot,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() {
      currentPageIndex = to;
      _target = null;
      _slot = null;
    });
    controller.jumpToPage(to);
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: controller,
      physics: const NeverScrollableScrollPhysics(),
      children: MainWindowScreenState.buildTransitionPages(
        widget.pages,
        targetIndex: _target,
        slotIndex: _slot,
      ),
    );
  }
}

/// מונה גלובלי של קריאות initState עבור [_Tracked].
int _initCount = 0;

/// StatefulWidget שסופר כמה פעמים אותחל — לזיהוי reparent מול בנייה מחדש.
class _Tracked extends StatefulWidget {
  const _Tracked({super.key});
  @override
  State<_Tracked> createState() => _TrackedState();
}

class _TrackedState extends State<_Tracked> {
  @override
  void initState() {
    super.initState();
    _initCount++;
  }

  @override
  Widget build(BuildContext context) => const Text('tracked');
}
