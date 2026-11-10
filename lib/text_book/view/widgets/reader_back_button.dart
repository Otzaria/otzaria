import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

/// חזרה למיקום הקודם, וקדימה כשיש לאן — כמו בדפדפן.
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
          final forward = history.forward;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BarButton.icon(
                key: const ValueKey('reader-back-location'),
                tooltip: historyTooltip(
                  context,
                  back == null ? '' : describe?.call(back) ?? '',
                  'חזרה למיקום הקודם',
                  'חזרה אל {place}',
                ),
                icon: FluentIcons.arrow_left_24_regular,
                compact: compact,
                onPressed: back != null
                    ? () => unawaited(lines.goBack())
                    : null,
              ),
              if (forward != null)
                BarButton.icon(
                  key: const ValueKey('reader-forward-location'),
                  tooltip: historyTooltip(
                    context,
                    describe?.call(forward) ?? '',
                    'מעבר קדימה',
                    'מעבר קדימה אל {place}',
                  ),
                  icon: FluentIcons.arrow_right_24_regular,
                  compact: compact,
                  onPressed: () => unawaited(lines.goForward()),
                ),
            ],
          );
        },
      );
}

/// תיאור כפתור היסטוריה: עם שם היעד כשידוע, אחרת הנוסח הכללי.
String historyTooltip(
  BuildContext context,
  String place,
  String generic,
  String withPlace,
) {
  final trimmed = place.trim();
  return trimmed.isEmpty
      ? context.settingsText(generic)
      : context.settingsText(withPlace, args: {'place': trimmed});
}
