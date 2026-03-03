import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/calendar/ulits/calendar_cubit.dart';
import 'package:otzaria/settings/panels/settings_panels_exports.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          CalendarSettingsTab(),
          GematriaSettingsTab(),
          EditorSettingsTab(),
        ],
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
