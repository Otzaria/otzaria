import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/view/reader/marker_reader_selection.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// הבחירה של הקורא ברגע הלחיצה, כפי שמסך הספר שומר אותה.
typedef MarkerReaderSelection = ({String? text, int? lineIndex, int? column});

/// מה שהכפתור תלוי בו, כדי שהסרגל ייבנה מחדש כשהסימונים בספר משתנים.
Listenable markerToolbarListenable(TextBookLoaded state) =>
    MarkerBookCache.instance.listenable(state.book.title);

/// כפתור המרקר בסרגל הקורא. טקסט נבחר מסומן בצבע ברירת המחדל, ובלי בחירה
/// הלחיצה מסתירה ומציגה את הסימונים שבספר. ההסבר והאייקון לפי המצב: סימונים
/// מוצגים — אייקון מלא.
ActionButtonData? buildMarkerToolbarAction({
  required BuildContext context,
  required TextBookLoaded state,
  required bool compact,
  required MarkerReaderSelection Function() selection,
}) {
  final settings = MarkerSettings.instance;
  if (!settings.showToolbarButton) return null;
  final palette = settings.palette;
  final title = state.book.title;
  final hasMarks =
      MarkerBookCache.instance
          .marksOf(title, markerBookUidOf(state.book))
          ?.isNotEmpty ??
      false;
  final shown = settings.showHighlights && !settings.isBookHidden(title);

  void mark() {
    final current = selection();
    markReaderSelection(
      context: context,
      state: state,
      selectedText: current.text,
      lineIndex: current.lineIndex,
      column: current.column,
      color: palette.defaultColor,
    );
  }

  // סימונים מוסתרים מוצגים קודם; אחר כך טקסט נבחר מסומן, ובלי בחירה הלחיצה
  // מסתירה את הסימונים.
  void press() {
    final selected = selection().text?.trim().isNotEmpty ?? false;
    if (!shown || (hasMarks && !selected)) {
      MarkerActions.instance.toggleBookVisible(title);
    } else {
      mark();
    }
  }

  return ActionButtonData.simple(
    icon: shown && hasMarks
        ? FluentIcons.highlight_24_filled
        : FluentIcons.highlight_24_regular,
    tooltip: markerToolbarTooltip(
      hasMarks: hasMarks,
      shown: shown,
      color: palette.defaultColor,
    ),
    compact: compact,
    actionId: ToolbarActionId.marker,
    onPressed: press,
  );
}

/// ההסבר של כפתור הסרגל, לפי מה שהלחיצה תעשה בלי בחירה.
String markerToolbarTooltip({
  required bool hasMarks,
  required bool shown,
  required MarkerColor color,
}) {
  if (!shown) return 'הצגת הסימונים בספר';
  if (hasMarks) return 'הסתרת הסימונים בספר';
  return 'סימון הטקסט שנבחר ב${color.label}';
}
