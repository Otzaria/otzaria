import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/book_common/view/reading_history_tooltip.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

/// חזרה למיקום הקודם בהיסטוריית הקורא.
class ReaderBackButton extends StatelessWidget {
  const ReaderBackButton({
    super.key,
    required this.lines,
    this.describe,
    this.compact = false,
  });

  final LineScrollController lines;

  /// שם המיקום לתיאור הכפתור, למשל "ביצה ג"; ריק כשאין כותרת.
  final String Function(ReadingAnchor anchor)? describe;
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ReadingHistoryEnds>(
        valueListenable: lines.history,
        builder: (context, history, _) {
          final back = history.back;
          return BarButton.icon(
            key: const ValueKey('reader-back-location'),
            tooltip: historyTooltip(
              context,
              back == null ? '' : describe?.call(back) ?? '',
              'חזרה למיקום הקודם',
              'חזרה אל {place}',
            ),
            icon: FluentIcons.arrow_left_24_regular,
            compact: compact,
            onPressed: back != null ? () => unawaited(lines.goBack()) : null,
          );
        },
      );
}
