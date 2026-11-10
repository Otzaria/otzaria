import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_shortcut_bindings.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  setUp(() => Settings.init(cacheProvider: MemorySettingsCache()));

  testWidgets(
    'קיצור התאמת PDF מפעיל את פעולת ההתאמה בלי לשנות את קיצור איפוס הזום',
    (tester) async {
      var fits = 0;
      var resets = 0;
      await tester.pumpWidget(
        _scope(onFit: () => fits++, onReset: () => resets++),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(fits, 1);
      expect(resets, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(resets, 1);
    },
  );

  testWidgets('הגדרה אישית של קיצור ההתאמה מחליפה את ברירת המחדל', (
    tester,
  ) async {
    await Settings.setValue(ShortcutValidator.fitPdfViewKey, 'f4');
    var fits = 0;
    await tester.pumpWidget(_scope(onFit: () => fits++));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    expect(fits, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(fits, 1);
  });

  testWidgets('Alt+Left חוזר למיקום הקודם וניתן להגדרה אישית', (tester) async {
    var backs = 0;
    await tester.pumpWidget(_scope(onFit: () {}, onBack: () => backs++));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(backs, 1);
    await Settings.setValue(ShortcutValidator.previousPdfLocationKey, 'f7');
    await tester.pumpWidget(_scope(onFit: () {}, onBack: () => backs++));
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    expect(backs, 2);
  });

  testWidgets('Alt+Right מתקדם למיקום הבא בלי להפעיל חזרה (issue #4769)', (
    tester,
  ) async {
    var backs = 0;
    var forwards = 0;
    await tester.pumpWidget(
      _scope(
        onFit: () {},
        onBack: () => backs++,
        onForward: () => forwards++,
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(forwards, 1);
    expect(backs, 0);
  });
}

Widget _scope({
  required VoidCallback onFit,
  VoidCallback? onReset,
  VoidCallback? onBack,
  VoidCallback? onForward,
}) => Directionality(
  textDirection: TextDirection.rtl,
  child: CallbackShortcuts(
    bindings: pdfReadingShortcutBindings(
      zoomIn: () {},
      zoomOut: () {},
      resetZoom: onReset ?? () {},
      fitView: onFit,
      previousLocation: onBack ?? () {},
      nextLocation: onForward ?? () {},
      nextMatch: () {},
      previousMatch: () {},
    ),
    child: const Focus(autofocus: true, child: SizedBox()),
  ),
);
