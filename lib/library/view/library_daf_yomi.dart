import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

/// ווידג'ט תאריך עברי + דף יומי — 2 כפתורי [ToolbarGhostButton]:
/// כפתור התאריך (עם אייקון לוח שנה) פותח את לוח השנה,
/// וכפתור הדף היומי פותח את הדף.
///
/// **אחריות:**
/// • מציג תאריך עברי + דף יומי, ומנווט ללוח השנה בלחיצה.
/// • פתיחת הדף היומי מטופלת דרך [onDafYomiTap].
class LibraryDafYomi extends StatefulWidget {
  final Function(String tractate, String daf) onDafYomiTap;

  /// כשאין ספרייה אין דף לפתוח — כפתור הדף היומי מוצג מושבת (התאריך נשאר פעיל).
  final bool dafEnabled;

  const LibraryDafYomi({
    super.key,
    required this.onDafYomiTap,
    this.dafEnabled = true,
  });

  @override
  State<LibraryDafYomi> createState() => _LibraryDafYomiState();
}

class _LibraryDafYomiState extends State<LibraryDafYomi> {
  void _openCalendar() {
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.more));
    // ToolsScreen נבנה lazy ב-PageView, ולכן בלחיצה הראשונה ייתכן ש-
    // moreScreenKey.currentState עדיין null. ניסיונות חוזרים עם hop קצר
    // מבטיחים שהלוח ייפתח גם בפעם הראשונה שנכנסים למסך הכלים.
    _resetCalendarWhenAvailable();
  }

  void _resetCalendarWhenAvailable({int attemptsLeft = 6}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final toolsState = moreScreenKey.currentState;
      if (toolsState != null) {
        toolsState.resetToCalendar();
        return;
      }
      if (attemptsLeft <= 0) return;
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        _resetCalendarWhenAvailable(attemptsLeft: attemptsLeft - 1);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final Daf dafYomi = getDafYomi(DateTime.now());
    final tractate = dafYomi.getMasechta();
    final dafAmud = dafYomi.getDaf();
    final dafText = '$tractate ${formatAmud(dafAmud)}';
    final dateText = getHebrewDateFormattedAsString(DateTime.now());

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'פתח לוח שנה',
          child: ToolbarGhostButton(
            text: dateText,
            icon: FluentIcons.calendar_24_regular,
            onPressed: _openCalendar,
          ),
        ),
        Tooltip(
          message: 'פתח דף יומי: $dafText',
          child: ToolbarGhostButton(
            text: dafText,
            icon: FluentIcons.book_24_regular,
            onPressed: widget.dafEnabled
                ? () => widget.onDafYomiTap(tractate, formatAmud(dafAmud))
                : null,
          ),
        ),
      ],
    );

    return content;
  }
}
