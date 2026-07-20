// ווידג'ט RtlIcon — אייקון RTL-מודע שמהפך חיצי ניווט אוטומטית.
// ⚠️ לא ניתן להשתמש ב-const Map<IconData,...> כי IconData לא מימש ==.
//    מפות הנגד מוגדרות כ-static final.

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class RtlIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  const RtlIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  static final Map<IconData, IconData> _materialMirrorMap = {
    Icons.arrow_forward: Icons.arrow_back,
    Icons.arrow_back: Icons.arrow_forward,
    Icons.arrow_forward_ios: Icons.arrow_back_ios,
    Icons.arrow_back_ios: Icons.arrow_forward_ios,
    Icons.arrow_right: Icons.arrow_left,
    Icons.arrow_left: Icons.arrow_right,
    Icons.chevron_right: Icons.chevron_left,
    Icons.chevron_left: Icons.chevron_right,
    Icons.navigate_next: Icons.navigate_before,
    Icons.navigate_before: Icons.navigate_next,
    Icons.keyboard_arrow_right: Icons.keyboard_arrow_left,
    Icons.keyboard_arrow_left: Icons.keyboard_arrow_right,
    Icons.first_page: Icons.last_page,
    Icons.last_page: Icons.first_page,
    Icons.skip_next: Icons.skip_previous,
    Icons.skip_previous: Icons.skip_next,
  };

  static final Map<IconData, IconData> _fluentMirrorMap = {
    FluentIcons.chevron_right_24_regular: FluentIcons.chevron_left_24_regular,
    FluentIcons.chevron_left_24_regular: FluentIcons.chevron_right_24_regular,
    FluentIcons.chevron_right_20_regular: FluentIcons.chevron_left_20_regular,
    FluentIcons.chevron_left_20_regular: FluentIcons.chevron_right_20_regular,
    FluentIcons.chevron_right_16_regular: FluentIcons.chevron_left_16_regular,
    FluentIcons.chevron_left_16_regular: FluentIcons.chevron_right_16_regular,
    FluentIcons.arrow_right_24_regular: FluentIcons.arrow_left_24_regular,
    FluentIcons.arrow_left_24_regular: FluentIcons.arrow_right_24_regular,
    FluentIcons.arrow_right_24_filled: FluentIcons.arrow_left_24_filled,
    FluentIcons.arrow_left_24_filled: FluentIcons.arrow_right_24_filled,
    FluentIcons.calendar_24_regular: FluentIcons.calendar_rtl_24_regular,
    FluentIcons.calendar_24_filled: FluentIcons.calendar_rtl_24_filled,
    FluentIcons.panel_left_24_regular: FluentIcons.panel_right_24_regular,
    FluentIcons.panel_right_24_regular: FluentIcons.panel_left_24_regular,
    FluentIcons.panel_left_24_filled: FluentIcons.panel_right_24_filled,
    FluentIcons.panel_right_24_filled: FluentIcons.panel_left_24_filled,
    FluentIcons.text_align_right_24_regular:
        FluentIcons.text_align_left_24_regular,
    FluentIcons.text_align_left_24_regular:
        FluentIcons.text_align_right_24_regular,
  };

  // אייקונים ללא גרסת RTL בספריה — מותר להפוך גאומטרית.
  // bookmark סימטרי ולא נכלל. אין להוסיף לכאן אייקונים שאינם כיווניים.
  static final Set<IconData> _flippableIcons = {
    FluentIcons.book_24_regular,
    FluentIcons.book_24_filled,
    FluentIcons.book_information_24_regular,
    FluentIcons.text_align_distributed_24_regular,
    FluentIcons.list_24_regular,
    FluentIcons.calendar_week_start_24_regular,
    FluentIcons.calendar_week_start_24_filled,
    FluentIcons.calendar_month_24_regular,
    FluentIcons.calendar_month_24_filled,
  };

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final baseIcon = Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );

    if (!isRtl) return baseIcon;

    final mirroredIcon = _materialMirrorMap[icon] ?? _fluentMirrorMap[icon];
    if (mirroredIcon != null) {
      return Icon(
        mirroredIcon,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
    }

    if (_flippableIcons.contains(icon)) {
      return Transform.flip(flipX: true, child: baseIcon);
    }

    return baseIcon;
  }
}
