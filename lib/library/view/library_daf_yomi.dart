import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/open_tool_tab.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// ווידג'ט תאריך עברי + דף יומי — 2 כפתורי [BarButton.text]:
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
    openToolTabById(context, 'builtin.calendar');
    // הכרטיסיה עשויה להיות פתוחה כבר על תאריך אחר; "הדף היומי" תמיד מתכוון
    // להיום, ולכן מאפסים אותה אחרי שהיא מוצגת.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CalendarCubit>().jumpToToday();
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
          child: BarButton.text(
            text: dateText,
            icon: FluentIcons.calendar_24_regular,
            onPressed: _openCalendar,
          ),
        ),
        Tooltip(
          message: 'פתח דף יומי: $dafText',
          child: BarButton.text(
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
