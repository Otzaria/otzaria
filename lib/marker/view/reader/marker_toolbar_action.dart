import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// מה שהכפתור תלוי בו, כדי שהסרגל ייבנה מחדש כשהסימונים בספר משתנים.
Listenable markerToolbarListenable(String bookTitle) =>
    MarkerBookCache.instance.listenable(bookTitle);

/// כפתור המרקר בסרגל הקורא: מסתיר ומציג את הסימונים שבספר. מופיע רק בספר
/// שיש בו סימונים, כשהם כבר נטענו; האייקון מלא כשהם מוצגים.
ActionButtonData? buildMarkerToolbarAction({
  required String bookTitle,
  required String? bookUid,
  required bool compact,
  bool pdf = false,
}) {
  final settings = MarkerSettings.instance;
  if (!settings.showToolbarButton) return null;
  final hasMarks =
      MarkerBookCache.instance
          .marksOf(bookTitle, bookUid, pdf: pdf)
          ?.isNotEmpty ??
      false;
  if (!hasMarks) return null;
  final shown =
      settings.showHighlights && !settings.isBookHidden(bookTitle, pdf: pdf);
  return ActionButtonData.simple(
    icon: shown
        ? FluentIcons.highlight_24_filled
        : FluentIcons.highlight_24_regular,
    tooltip: markerToolbarTooltip(shown: shown),
    compact: compact,
    actionId: ToolbarActionId.marker,
    onPressed: () =>
        MarkerActions.instance.toggleBookVisible(bookTitle, pdf: pdf),
  );
}

String markerToolbarTooltip({required bool shown}) =>
    shown ? 'הסתרת הסימונים בספר' : 'הצגת הסימונים בספר';
