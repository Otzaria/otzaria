import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';

import '../golden_harness.dart';

Widget _states() => SizedBox(
  width: 640,
  height: 320,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: OtzariaEmptyState(
          icon: FluentIcons.search_24_regular,
          title: 'אין תוצאות',
          message: 'נסה מילה אחרת',
          action: ActionButton.neutral(text: 'נקה סינון', onPressed: () {}),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: OtzariaErrorState(
          title: 'טעינת הספר נכשלה',
          details: 'הקובץ לא נמצא',
          actions: [
            ActionButton.recommended(text: 'נסה שוב', onPressed: () {}),
          ],
        ),
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('מצב ריק ומצב שגיאה, ${brightness.name}', (tester) async {
      await pumpGolden(tester, _states(), brightness: brightness);
      await expectGolden('feedback_states.${brightness.name}');
    });
  }
}
