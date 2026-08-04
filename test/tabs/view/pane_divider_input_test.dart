import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

Finder _dividerWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

final Finder _horizontalDivider = _dividerWithLabel(
  'מפריד בין חלוניות — גרירה או חצים לצדדים, Home לאיפוס',
);

/// המפריד נבדק כאן משלוש זוויות קלט שאינן גרירת עכבר: מקלדת, מגע, וקורא מסך.
void main() {
  Widget host(
    OpenedTab root, {
    ValueChanged<double>? onRatioChanged,
    TargetPlatform platform = TargetPlatform.windows,
    TextDirection textDirection = TextDirection.rtl,
  }) {
    return MaterialApp(
      theme: ThemeData(platform: platform),
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: SplitPaneView(
            root: root,
            paneBuilder: (pane) => Text(pane.title),
            onRatioChanged: onRatioChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  CombinedTab horizontal({double ratio = 0.5}) => CombinedTab(
    rightTab: _LeafTab('ימין'),
    leftTab: _LeafTab('שמאל'),
    splitRatio: ratio,
  );

  /// ממקדת את המפריד ושולחת הקשה.
  Future<void> pressKey(
    WidgetTester tester,
    Finder divider,
    LogicalKeyboardKey key,
  ) async {
    final focus = find
        .ancestor(of: divider, matching: find.byType(Focus))
        .first;
    tester.widget<Focus>(focus).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(key);
    // השמירה מושהית כדי שהקשה ממושכת לא תסרל את כל הטאבים בכל אירוע.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  group('שינוי גודל מהמקלדת', () {
    testWidgets('חץ שמאלה ב-RTL מגדיל את החלונית הימנית', (tester) async {
      final root = horizontal();
      double? reported;
      await tester.pumpWidget(
        host(root, onRatioChanged: (ratio) => reported = ratio),
      );
      final widthBefore = tester.getSize(find.text('ימין')).width;

      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.arrowLeft);

      expect(reported, greaterThan(0.5));
      expect(root.splitRatio, reported);
      expect(tester.getSize(find.text('ימין')).width, greaterThan(widthBefore));
    });

    testWidgets('חץ ימינה ב-RTL מקטין את החלונית הימנית', (tester) async {
      final root = horizontal();
      double? reported;
      await tester.pumpWidget(
        host(root, onRatioChanged: (ratio) => reported = ratio),
      );

      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.arrowRight);

      expect(reported, lessThan(0.5));
    });

    testWidgets('ב-LTR הכיוון מתהפך', (tester) async {
      final root = horizontal();
      double? reported;
      await tester.pumpWidget(
        host(
          root,
          onRatioChanged: (ratio) => reported = ratio,
          textDirection: TextDirection.ltr,
        ),
      );

      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.arrowLeft);

      expect(reported, lessThan(0.5));
    });

    testWidgets('חצים אנכיים אינם מזיזים את המפריד', (tester) async {
      final root = horizontal();
      var reports = 0;
      await tester.pumpWidget(host(root, onRatioChanged: (_) => reports++));

      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.arrowUp);
      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.arrowDown);

      expect(reports, 0);
      expect(root.splitRatio, 0.5);
    });

    testWidgets('Home מאפס את היחס', (tester) async {
      final root = horizontal(ratio: 0.8);
      double? reported;
      await tester.pumpWidget(
        host(root, onRatioChanged: (ratio) => reported = ratio),
      );

      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.home);

      expect(reported, 0.5);
    });

    testWidgets('הזזות חוזרות אינן חורגות מהמינימום', (tester) async {
      final root = horizontal();
      final reported = <double>[];
      await tester.pumpWidget(
        host(root, onRatioChanged: (ratio) => reported.add(ratio)),
      );

      for (var i = 0; i < 60; i++) {
        await pressKey(
          tester,
          _horizontalDivider,
          LogicalKeyboardKey.arrowLeft,
        );
      }

      expect(reported.last, lessThan(1.0));
      expect(tester.getSize(find.text('שמאל')).width, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('עובי לפי אמצעי הקלט', () {
    testWidgets('בדסקטופ רצועת המפריד צרה', (tester) async {
      await tester.pumpWidget(host(horizontal()));

      final size = tester.getSize(_horizontalDivider);
      expect(size.width, kPaneDividerThickness);
    });

    testWidgets('במגע רצועת המפריד רחבה יותר', (tester) async {
      await tester.pumpWidget(
        host(horizontal(), platform: TargetPlatform.android),
      );

      final size = tester.getSize(_horizontalDivider);
      expect(size.width, kPaneDividerThicknessTouch);
      expect(kPaneDividerThicknessTouch, greaterThan(kPaneDividerThickness));
    });

    testWidgets('שוליי התוכן מפצים על העובי בפועל', (tester) async {
      await tester.pumpWidget(
        host(horizontal(), platform: TargetPlatform.android),
      );

      // ההשלמה נמדדת מול הרוחב האמיתי של החלונית: החלונית הימנית מקבלת
      // שוליים בצד ההתחלה בגודל המפריד שנוגע בה.
      final rightWidth = tester.getSize(find.text('ימין')).width;
      final leftWidth = tester.getSize(find.text('שמאל')).width;
      expect(rightWidth, closeTo(leftWidth, 1.0));
    });

    testWidgets('בחירת העובי לפי פלטפורמה', (tester) async {
      expect(
        paneDividerThicknessFor(TargetPlatform.windows),
        kPaneDividerThickness,
      );
      expect(
        paneDividerThicknessFor(TargetPlatform.linux),
        kPaneDividerThickness,
      );
      expect(
        paneDividerThicknessFor(TargetPlatform.macOS),
        kPaneDividerThickness,
      );
      expect(
        paneDividerThicknessFor(TargetPlatform.android),
        kPaneDividerThicknessTouch,
      );
      expect(
        paneDividerThicknessFor(TargetPlatform.iOS),
        kPaneDividerThicknessTouch,
      );
    });
  });

  group('מקשי צירוף וקיצורים', () {
    testWidgets('Alt+חץ אינו נלקח בידי המפריד', (tester) async {
      final root = horizontal();
      var reports = 0;
      await tester.pumpWidget(host(root, onRatioChanged: (_) => reports++));

      final focus = find
          .ancestor(of: _horizontalDivider, matching: find.byType(Focus))
          .first;
      tester.widget<Focus>(focus).focusNode!.requestFocus();
      await tester.pump();

      // Alt+חץ הוא קיצור מסך ("הקטע הבא"); המפריד חייב להעביר אותו הלאה.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump(const Duration(milliseconds: 300));

      expect(reports, 0);
      expect(root.splitRatio, 0.5);
    });

    testWidgets('Ctrl+Home אינו מאפס את המפריד', (tester) async {
      final root = horizontal(ratio: 0.8);
      var reports = 0;
      await tester.pumpWidget(
        host(root, onRatioChanged: (_) => reports++),
      );

      final focus = find
          .ancestor(of: _horizontalDivider, matching: find.byType(Focus))
          .first;
      tester.widget<Focus>(focus).focusNode!.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 300));

      expect(reports, 0);
      expect(root.splitRatio, 0.8);
    });

    testWidgets('הקשות רצופות נשמרות פעם אחת', (tester) async {
      final root = horizontal();
      var saves = 0;
      await tester.pumpWidget(
        host(root, onRatioChanged: (_) => saves++),
      );

      final focus = find
          .ancestor(of: _horizontalDivider, matching: find.byType(Focus))
          .first;
      tester.widget<Focus>(focus).focusNode!.requestFocus();
      await tester.pump();

      // חמש הקשות בתוך חלון ההשהיה — שמירה אחת. בלי זה כל הקשה סרלה את כל
      // עץ הטאבים לדיסק.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(saves, 1);
      expect(root.splitRatio, greaterThan(0.5));
    });

    testWidgets('הקשה בקצה החסימה אינה שומרת כלל', (tester) async {
      final root = horizontal();
      var saves = 0;
      await tester.pumpWidget(
        host(root, onRatioChanged: (_) => saves++),
      );

      // הגעה לקצה, ואז הקשות נוספות שאינן מזיזות דבר.
      for (var i = 0; i < 40; i++) {
        await pressKey(
          tester,
          _horizontalDivider,
          LogicalKeyboardKey.arrowLeft,
        );
      }
      final savesAtEdge = saves;

      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.arrowLeft);
      await pressKey(tester, _horizontalDivider, LogicalKeyboardKey.arrowLeft);

      expect(saves, savesAtEdge, reason: 'היחס לא זז, ואין מה לשמור');
    });
  });

  group('מגע', () {
    testWidgets('לחיצה ארוכה מאפסת את היחס', (tester) async {
      final root = horizontal(ratio: 0.75);
      double? reported;
      await tester.pumpWidget(
        host(
          root,
          onRatioChanged: (ratio) => reported = ratio,
          platform: TargetPlatform.android,
        ),
      );

      await tester.longPress(_horizontalDivider, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(reported, 0.5, reason: 'במגע אין לחיצה כפולה נוחה');
    });

    testWidgets('בדסקטופ לחיצה ארוכה אינה מאפסת ואינה הורגת את הגרירה', (
      tester,
    ) async {
      final root = horizontal(ratio: 0.75);
      double? reported;
      await tester.pumpWidget(
        host(root, onRatioChanged: (ratio) => reported = ratio),
      );

      // היסוס על הרצועה לפני גרירה: מזהה לחיצה ארוכה היה זוכה בזירה, מאפס
      // את הפריסה ודוחה את מזהי הגרירה.
      final gesture = await tester.startGesture(
        tester.getCenter(_horizontalDivider),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(reported, isNull, reason: 'הלחיצה הארוכה אינה מאפסת בעכבר');

      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(reported, isNotNull, reason: 'הגרירה עדיין עובדת אחרי ההיסוס');
      expect(reported, greaterThan(0.75));
    });
  });

  group('נגישות', () {
    testWidgets('המפריד מדווח כמחוון עם אחוז הרוחב', (tester) async {
      await tester.pumpWidget(host(horizontal(ratio: 0.4)));

      final semantics = tester.widget<Semantics>(_horizontalDivider);
      expect(semantics.properties.slider, isTrue);
      expect(semantics.properties.value, '40%');
      expect(semantics.properties.onIncrease, isNotNull);
      expect(semantics.properties.onDecrease, isNotNull);
    });

    testWidgets('onIncrease ו-onDecrease מזיזים את המפריד', (tester) async {
      final root = horizontal();
      final reported = <double>[];
      await tester.pumpWidget(
        host(root, onRatioChanged: (ratio) => reported.add(ratio)),
      );

      tester.widget<Semantics>(_horizontalDivider).properties.onIncrease!();
      await tester.pump(const Duration(milliseconds: 300));
      expect(reported.last, greaterThan(0.5));

      tester.widget<Semantics>(_horizontalDivider).properties.onDecrease!();
      await tester.pump(const Duration(milliseconds: 300));
      expect(reported.last, closeTo(0.5, 0.001));
    });
  });
}
