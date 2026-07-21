// בדיקת רגרסיה לבאג מפורום https://otzaria.org/forum/topic/1488:
// פס גלילה בהגדרות/TOC לא הגיב ללחיצה כי ידית הגרירה (ResizableDragHandle)
// חפפה אותו. תוקן בקומיט c8950aa81 ע"י צמצום שטח הלחיצה של הידית
// (48/36 -> 24/18), שממנו נגזר ה-overhang החודר לתוך הפאנל.

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
  test('טוקני שטח הלחיצה של ידית הגרירה קטנים מהערכים הישנים שגרמו לחפיפה',
      () {
    // הערכים הישנים (48/36) יצרו overhang של 24/18 פנימה לתוך הפאנל, שכיסה
    // את פס הגלילה. אם הערכים יגדלו בחזרה, הבאג יחזור.
    expect(AppTokens.dragHandleRegularHitSize, 24);
    expect(AppTokens.dragHandleCompactHitSize, 18);
    expect(AppTokens.dragHandleRegularHitSize, lessThan(48));
    expect(AppTokens.dragHandleCompactHitSize, lessThan(36));
  });

  testWidgets(
      'handleHitOverhang במצב רגיל שווה למחצית dragHandleRegularHitSize',
      (tester) async {
    late double overhang;
    await tester.pumpWidget(
      _wrap(
        Builder(builder: (context) {
          overhang = handleHitOverhang(context);
          return const SizedBox();
        }),
      ),
    );

    expect(overhang, AppTokens.dragHandleRegularHitSize / 2);
  });

  testWidgets(
      'handleHitOverhang במצב קומפקטי שווה למחצית dragHandleCompactHitSize',
      (tester) async {
    late double overhang;
    await tester.pumpWidget(
      _wrap(
        Builder(builder: (context) {
          overhang = handleHitOverhang(context);
          return const SizedBox();
        }),
        compactMenuMode: true,
      ),
    );

    expect(overhang, AppTokens.dragHandleCompactHitSize / 2);
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
  });
}
