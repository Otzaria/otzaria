import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/second_test_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('הנעיצה אינה עוקפת מסך צר', () {
    setUp(() async {
      await Settings.setValue('key-pin-sidebar', true);
      await Settings.setValue('key-default-sidebar-open', true);
    });

    test('shouldAutoOpenReadingLeftPane — סגור בטלפון, פתוח בשולחני', () {
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 411), isFalse);
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 1400), isTrue);
    });

    test('resolveInitialReadingLeftPaneVisibility — סגור בטלפון', () {
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: false,
          screenWidth: 411,
        ),
        isFalse,
      );
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: false,
          screenWidth: 1400,
        ),
        isTrue,
      );
    });

    test('בקשה מפורשת פותחת גם בטלפון', () {
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: true,
          screenWidth: 411,
        ),
        isTrue,
      );
    });

    test('מצב שמור ב-JSON גובר על הנעיצה', () {
      expect(
        resolveRestoredReadingLeftPaneState(
          {'showLeftPane': true},
          screenWidth: 411,
        ),
        isTrue,
      );
      expect(
        resolveRestoredReadingLeftPaneState(const {}, screenWidth: 411),
        isFalse,
      );
    });
  });

  test('בלי נעיצה ובלי "פתוח כברירת מחדל" — סגור בכל רוחב', () async {
    await Settings.setValue('key-pin-sidebar', false);
    await Settings.setValue('key-default-sidebar-open', false);

    expect(shouldAutoOpenReadingLeftPane(screenWidth: 1400), isFalse);
    expect(shouldAutoOpenReadingLeftPane(screenWidth: 411), isFalse);
  });

  test('"פתוח כברירת מחדל" בלבד — פתוח רק בשולחני', () async {
    await Settings.setValue('key-pin-sidebar', false);
    await Settings.setValue('key-default-sidebar-open', true);

    expect(shouldAutoOpenReadingLeftPane(screenWidth: 1400), isTrue);
    expect(shouldAutoOpenReadingLeftPane(screenWidth: 411), isFalse);
  });

  group('רוחב לפי התצוגה של ההקשר', () {
    late BuildContext wide;
    late BuildContext narrow;
    late SecondTestView second;

    Future<void> pumpTwoViews(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(2800, 1800)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      second = SecondTestView(tester.view)
        ..physicalSize = const Size(1233, 2400)
        ..devicePixelRatio = 3;
      await tester.pumpWidget(
        wrapWithView: false,
        ViewCollection(
          views: [
            View(
              view: tester.view,
              child: Builder(
                builder: (c) {
                  wide = c;
                  return const SizedBox();
                },
              ),
            ),
            View(
              view: second,
              child: Builder(
                builder: (c) {
                  narrow = c;
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      );
    }

    testWidgets('כל הקשר מקבל את רוחב התצוגה שלו', (tester) async {
      await pumpTwoViews(tester);
      expect(readingLayoutWidthOf(wide), 1400);
      expect(readingLayoutWidthOf(narrow), closeTo(411, 0.001));

      await Settings.setValue('key-default-sidebar-open', true);
      expect(
        shouldAutoOpenReadingLeftPane(screenWidth: readingLayoutWidthOf(wide)),
        isTrue,
      );
      expect(
        shouldAutoOpenReadingLeftPane(
          screenWidth: readingLayoutWidthOf(narrow),
        ),
        isFalse,
      );
    });

    testWidgets('ה-resolver נמדד מחדש אחרי שינוי גודל', (tester) async {
      await pumpTwoViews(tester);
      final resolve = readingLayoutWidthResolverOf(narrow);
      expect(resolve(), closeTo(411, 0.001));
      second.physicalSize = const Size(4200, 2400);
      expect(resolve(), 1400);
    });
  });
}
