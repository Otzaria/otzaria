import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/settings/panels/settings_panels_exports.dart';
import 'package:otzaria/settings/panels/tools_management_panel.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

/// טאב כלים — לוח שנה, גימטריות, עורך.
///
/// [calendarCubit] — העברה מפורשת של CalendarCubit כדי לתקן את הבאג שבו
/// הגדרות לוח השנה לא נשמרות כאשר ההגדרות נפתחות כ-route חדש (ה-context
/// של המסך החדש לא מכיל את ה-CalendarCubit ממסך הניווט).
class ToolsSettingsTab extends StatelessWidget {
  /// CalendarCubit שמגיע מה-context של המסך שפתח את ההגדרות.
  /// אם null, מנסה לקרוא מה-context (תואמות לאחור).
  final CalendarCubit? calendarCubit;

  const ToolsSettingsTab({super.key, this.calendarCubit});

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.all(16.0),
      child: ToolPanelWrapper(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ToolsManagementPanel(),
            SizedBox(height: 16),
            CalendarSettingsTab(),
            GematriaSettingsTab(),
            SizedBox(height: 16),
            TikkunKorimSettingsTab(),
            // [EDITING DISABLED] EditorSettingsTab(),
            SizedBox(height: 16),
          ],
        ),
      ),
    );

    // אם קיבלנו CalendarCubit במפורש — עטוף כדי להבטיח שהשינויים יישמרו
    if (calendarCubit != null) {
      return BlocProvider<CalendarCubit>.value(
        value: calendarCubit!,
        child: content,
      );
    }

    return content;
  }
}
