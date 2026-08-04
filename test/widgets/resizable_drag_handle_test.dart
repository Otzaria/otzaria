// בדיקת רגרסיה לבאג מפורום https://otzaria.org/forum/topic/1488:
// פס גלילה בהגדרות/TOC לא הגיב ללחיצה כי ידית הגרירה (ResizableDragHandle)
// חפפה אותו. הצמצום ב-c8950aa81 (48/36 -> 24/18) רק חצה את החדירה פנימה,
// ובחלונית המפרשים היא עדיין כיסתה את המסילה במלואה. כעת החדירה מנותקת
// משטח המגע וקבועה ב-kPaneHandleInnerReach.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(super.initialState) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _wrap(Widget child, {bool? compactMenuMode}) {
  final content = SizedBox(height: 300, child: child);
  if (compactMenuMode == null) {
    return MaterialApp(home: Scaffold(body: content));
  }
  return MaterialApp(
    home: BlocProvider<SettingsBloc>.value(
      value: _FakeSettingsBloc(
        SettingsState.initial().copyWith(compactMenuMode: compactMenuMode),
      ),
      child: Scaffold(body: content),
    ),
  );
}

void main() {
  test('טוקני שטח הלחיצה של ידית הגרירה קטנים מהערכים הישנים שגרמו לחפיפה', () {
    // הערכים הישנים (48/36) יצרו overhang של 24/18 פנימה לתוך הפאנל, שכיסה
    // את פס הגלילה. אם הערכים יגדלו בחזרה, הבאג יחזור.
    expect(AppTokens.dragHandleRegularHitSize, 24);
    expect(AppTokens.dragHandleCompactHitSize, 18);
    expect(AppTokens.dragHandleRegularHitSize, lessThan(48));
    expect(AppTokens.dragHandleCompactHitSize, lessThan(36));
  });

  test('החדירה לתוך הפאנל משאירה את אגודל פס הגלילה תפיס', () {
    // המסילה 12px והאגודל מרוּוח 2px מכל צד, כלומר תופס [2, 10] מהקצה.
    // חדירה של 6px ומעלה בולעת את מרכזו — שם המשתמש מכוון.
    expect(kPaneHandleInnerReach, lessThan(6));
  });

  testWidgets('הכניסה פנימה והגלישה החוצה מרכיבות יחד את שטח המגע המלא', (
    tester,
  ) async {
    late double outreach;
    late double hitSize;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            outreach = handleHitOutreach(context);
            hitSize = handleHitSize(context);
            return const SizedBox();
          },
        ),
      ),
    );

    // החדירה קבועה ואינה נגזרת מ-hitSize; הגדלת שטח המגע מוסיפה רק החוצה.
    expect(hitSize, AppTokens.dragHandleRegularHitSize);
    expect(kPaneHandleInnerReach + outreach, hitSize);
  });

  testWidgets('הקו הנראה מוזז אל דופן הפאנל ולא נשאר במרכז שטח המגע', (
    tester,
  ) async {
    late double offsetLeftPane;
    late double offsetRightPane;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            offsetLeftPane = paneHandleGripOffset(context, paneOnRight: false);
            offsetRightPane = paneHandleGripOffset(context, paneOnRight: true);
            return const SizedBox();
          },
        ),
      ),
    );

    final expected =
        AppTokens.dragHandleRegularHitSize / 2 - kPaneHandleInnerReach;
    expect(offsetLeftPane, -expected);
    expect(offsetRightPane, expected);
  });

  testWidgets(
    'שטח הלחיצה בפועל של ResizableDragHandle תואם לטוקן dragHandleRegularHitSize',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ResizableDragHandle(
            isVertical: true,
            onDragDelta: (_) {},
          ),
        ),
      );

      final size = tester.getSize(find.byType(ResizableDragHandle));
      expect(size.width, AppTokens.dragHandleRegularHitSize);
    },
  );
}
