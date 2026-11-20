import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';

/// סעיף 3: באצבע ב-Windows אין ריחוף, ולכן הפעולות שמופיעות רק בריחוף היו
/// בלתי נגישות. לחיצה ארוכה (או לחיצה ימנית) על הכרטיס פותחת תפריט עם אותן
/// פעולות, והכפתורים בריחוף נשארים.
void main() {
  const searchInHebrew = 'חפש בעברית';
  const copyMeaning = 'העתק פירוש';
  const copyWithResult = 'העתק את הערך עם התוצאה';
  const copyEntry = 'העתק את הערך';
  const hebrew = 'פירוש ראשון ארוך מאוד שממשיך לכמה מילים *** פירוש שני';

  // Windows עם מסך מגע: אין ריחוף, והאפליקציה מתייחסת אליו כמחשב.
  void windowsTest(String name, WidgetTesterCallback body) => testWidgets(
    name,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  final searches = <(String, bool)>[];
  String? clipboardText;

  setUp(() {
    searches.clear();
    clipboardText = null;
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    required bool queryIsAramaic,
  }) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: AramaicResultCard(
                aramaic: 'מילה',
                hebrew: hebrew,
                query: queryIsAramaic ? 'מילה' : 'פירוש',
                queryIsAramaic: queryIsAramaic,
                onSearch: (text, {required hebrewToAramaic}) =>
                    searches.add((text, hebrewToAramaic)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> longPressWithFinger(WidgetTester tester, Finder target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Finder menuItem(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(MenuItemButton),
  );

  windowsTest('לחיצה ארוכה באצבע על פירוש: פעולות הפירוש ופעולות הכותרת', (
    tester,
  ) async {
    await pumpCard(tester, queryIsAramaic: true);
    expect(menuItem(copyEntry), findsNothing);

    await longPressWithFinger(tester, find.textContaining('פירוש ראשון'));

    expect(menuItem(searchInHebrew), findsOneWidget);
    expect(menuItem(copyMeaning), findsOneWidget);
    expect(menuItem(copyWithResult), findsOneWidget);
    expect(menuItem(copyEntry), findsOneWidget);

    await tester.tap(find.text(searchInHebrew));
    await tester.pumpAndSettle();
    expect(searches, [('פירוש ראשון ארוך מאוד שממשיך לכמה מילים', true)]);
    expect(tester.takeException(), isNull);
  });

  windowsTest('"העתק פירוש" מעתיק את הפירוש שנלחץ, לא את הראשון', (
    tester,
  ) async {
    await pumpCard(tester, queryIsAramaic: true);

    await longPressWithFinger(tester, find.textContaining('פירוש שני'));
    await tester.tap(find.text(copyMeaning));
    await tester.pumpAndSettle();

    expect(clipboardText, contains('פירוש שני'));
    expect(clipboardText, isNot(contains('ראשון')));
    expect(tester.takeException(), isNull);
  });

  windowsTest('לחיצה ארוכה על הכותרת: פעולות הערך בלבד', (tester) async {
    await pumpCard(tester, queryIsAramaic: false);

    await longPressWithFinger(tester, find.textContaining('מילה').first);

    expect(menuItem('חפש "מילה" בארמית'), findsOneWidget);
    expect(menuItem(copyEntry), findsOneWidget);
    expect(menuItem(copyMeaning), findsNothing);

    await tester.tap(find.text('חפש "מילה" בארמית'));
    await tester.pumpAndSettle();
    expect(searches, [('מילה', false)]);
  });

  windowsTest('לחיצה ימנית בעכבר פותחת את אותו תפריט', (tester) async {
    await pumpCard(tester, queryIsAramaic: true);

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(mouse.removePointer);
    final at = tester.getCenter(find.textContaining('פירוש ראשון'));
    await mouse.addPointer(location: at);
    await mouse.down(at);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(menuItem(copyMeaning), findsOneWidget);
    expect(menuItem(copyEntry), findsOneWidget);
  });

  windowsTest('הכפתורים בריחוף נשארים כמו היום', (tester) async {
    await pumpCard(tester, queryIsAramaic: true);

    expect(find.byTooltip(copyEntry), findsOneWidget);
    expect(find.byTooltip(copyMeaning), findsNWidgets(2));
  });
}
