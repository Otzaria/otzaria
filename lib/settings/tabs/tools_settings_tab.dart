import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/settings/panels/settings_panels_exports.dart';
import 'package:otzaria/settings/panels/tools_management_panel.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';
import 'package:otzaria/settings/widgets/settings_tab_scroll_view.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// טאב כלים — לוח שנה, גימטריות, עורך.
///
/// [calendarCubit] — העברה מפורשת של CalendarCubit כדי לתקן את הבאג שבו
/// הגדרות לוח השנה לא נשמרות כאשר ההגדרות נפתחות כ-route חדש (ה-context
/// של המסך החדש לא מכיל את ה-CalendarCubit ממסך הניווט).
class ToolsSettingsTab extends StatefulWidget {
  /// CalendarCubit שמגיע מה-context של המסך שפתח את ההגדרות.
  /// אם null, מנסה לקרוא מה-context (תואמות לאחור).
  final CalendarCubit? calendarCubit;

  const ToolsSettingsTab({super.key, this.calendarCubit});

  @override
  State<ToolsSettingsTab> createState() => _ToolsSettingsTabState();
}

class _ToolsSettingsTabState extends State<ToolsSettingsTab> {
  /// בחירת התוספים. מוחזקת כאן כדי שהסרגל יישב מחוץ לאזור הגלילה.
  final _selection = PluginSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calendarCubit = widget.calendarCubit;
    final content = Column(
      children: [
        PluginSelectionBar(selection: _selection),
        Expanded(
          child: SettingsTabScrollView(
            child: ToolPanelWrapper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ToolsManagementPanel(selection: _selection),
                  const CalendarSettingsTab(),
                  const GematriaSettingsTab(),
                  const TikkunKorimSettingsTab(),
                  const SizedBox(height: AppTokens.spaceMD),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    // אם קיבלנו CalendarCubit במפורש — עטוף כדי להבטיח שהשינויים יישמרו
    if (calendarCubit != null) {
      return BlocProvider<CalendarCubit>.value(
        value: calendarCubit,
        child: content,
      );
    }

    return content;
  }
}
