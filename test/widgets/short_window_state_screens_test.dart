import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
import 'package:otzaria/library/view/library_empty_state_widget.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

// מסכי מצב (ריק/שגיאה/הגדרה) נחתכים בחלון נמוך — טלפון לרוחב, מסך מפוצל,
// מקלדת פתוחה או חלון דסקטופ נמוך — ואז כפתור הפעולה יוצא מחוץ למסך.
// הגדלים לכל מסך נבחרו מתחת לגובה שהוא צורך: 438px למסך הגדרת הספרייה,
// 304px למצב הריק של הספרייה, 244px למצב הריק של הכלים.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// מרנדר [child] בחלון בגודל [size] ומחזיר את חריגות הפריסה שנתפסו.
Future<List<String>> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget child,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.toString());
  await tester.pumpWidget(_wrap(child));
  await tester.pump();
  FlutterError.onError = previous;
  return errors.where((e) => e.contains('overflow')).toList();
}

/// בודק שהיעד נגיש בכל אחד מ-[sizes]: בלי חריגת פריסה, ולחיץ אחרי גלילה.
void _reachableIn(
  String label,
  List<Size> sizes,
  Widget Function() build,
  Finder Function() target,
) {
  for (final size in sizes) {
    testWidgets(
      '$label — ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        final overflows = await _pumpAt(tester, size, build());
        expect(overflows, isEmpty, reason: 'התוכן חורג מהחלון: $overflows');

        final finder = target();
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        expect(finder.hitTestable(), findsOneWidget);
      },
    );
  }
}

/// מוודא שבחלון מרווח המסך אינו גליל — המרכוז נשמר ולא הפך לגלילה תמידית.
void _notScrollableWhenRoomy(String label, Widget Function() build) {
  testWidgets('$label — 1200x900 אינו גליל', (tester) async {
    final overflows = await _pumpAt(tester, const Size(1200, 900), build());
    expect(overflows, isEmpty);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, 0);
  });
}

LibraryEmptyStateWidget _libraryEmpty({VoidCallback? onOpenLink}) =>
    LibraryEmptyStateWidget(
      message: 'לא נמצאו תוצאות',
      onBack: () {},
      onHome: () {},
      onOpenSearch: () {},
      onOpenLink: onOpenLink,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibrarySetupView', () {
    const sizes = [Size(640, 360), Size(800, 300), Size(360, 420)];
    _reachableIn(
      'כפתור הגדרת הספרייה',
      sizes,
      () => LibrarySetupView(onLibraryLoaded: () async {}),
      () => find.byWidgetPredicate(
        (w) => w is ActionButton && w.text == 'בחר מיקום או הורד ספרייה',
      ),
    );
    _notScrollableWhenRoomy(
      'LibrarySetupView',
      () => LibrarySetupView(onLibraryLoaded: () async {}),
    );

    testWidgets('הכותרת וההסבר נשארים בחלון נמוך', (tester) async {
      await _pumpAt(
        tester,
        const Size(640, 360),
        LibrarySetupView(onLibraryLoaded: () async {}),
      );
      expect(find.text('לא נמצאה ספריית ספרים'), findsOneWidget);
      expect(find.textContaining('ניתן להוריד את הספרייה'), findsOneWidget);
    });
  });

  group('LibraryEmptyStateWidget', () {
    const sizes = [Size(640, 260), Size(800, 240), Size(360, 300)];
    _reachableIn(
      'כפתור פתיחת חיפוש',
      sizes,
      _libraryEmpty,
      () => find.text('פתח חיפוש טקסט'),
    );
    _reachableIn(
      'כפתור "בית"',
      sizes,
      _libraryEmpty,
      () => find.text('בית'),
    );
    _reachableIn(
      'כפתור פתיחת קישור ישיר',
      sizes,
      () => _libraryEmpty(onOpenLink: () {}),
      () => find.text('פתיחת קישור'),
    );
    _notScrollableWhenRoomy('LibraryEmptyStateWidget', _libraryEmpty);

    testWidgets('לחיצה על הכפתור אחרי גלילה מפעילה את ה-callback', (
      tester,
    ) async {
      var opened = false;
      await _pumpAt(
        tester,
        const Size(640, 260),
        LibraryEmptyStateWidget(
          message: 'לא נמצאו תוצאות',
          onBack: () {},
          onHome: () {},
          onOpenSearch: () => opened = true,
        ),
      );
      await tester.ensureVisible(find.text('פתח חיפוש טקסט'));
      await tester.tap(find.text('פתח חיפוש טקסט'));
      await tester.pump();
      expect(opened, isTrue);
    });
  });

  group('OtzariaEmptyState (כלים)', () {
    const sizes = [Size(640, 200), Size(800, 180)];
    OtzariaEmptyState build() => const OtzariaEmptyState(
      icon: OtzariaIcons.search_24_regular,
      title: 'לא נמצאו תוצאות עבור החיפוש שהוזן',
      message: 'ניתן לנסות ניסוח אחר או להרחיב את טווח החיפוש',
    );

    _reachableIn(
      'תת-הכותרת',
      sizes,
      build,
      () => find.text('ניתן לנסות ניסוח אחר או להרחיב את טווח החיפוש'),
    );
    _notScrollableWhenRoomy('OtzariaEmptyState (כלים)', build);

    testWidgets('בלי תת-כותרת ההודעה עדיין נגישה בחלון נמוך', (tester) async {
      final overflows = await _pumpAt(
        tester,
        const Size(640, 180),
        const OtzariaEmptyState(
          icon: OtzariaIcons.search_24_regular,
          title: 'לא נמצאו תוצאות עבור החיפוש שהוזן',
        ),
      );
      expect(overflows, isEmpty);
      await tester.ensureVisible(
        find.text('לא נמצאו תוצאות עבור החיפוש שהוזן'),
      );
      expect(
        find.text('לא נמצאו תוצאות עבור החיפוש שהוזן').hitTestable(),
        findsOneWidget,
      );
    });
  });
}
