// ווידג'ט RtlIcon — מהפך ב-RTL אייקון כיווני שהגופן אינו מהפך בעצמו.
// ⚠️ אייקון Fluent עם matchTextDirection (chevron_left/right, arrow_left/right,
//    arrow_previous/next, text_align_left/right) מתהפך כבר ב-Icon: כותבים
//    Icon(<הגליף של LTR>) ולא רושמים אותו כאן — היפוך נוסף מבטל את הראשון.
// ⚠️ לא ניתן להשתמש ב-const Map<IconData,...> כי IconData לא מימש ==.
// ⚠️ אייקוני OtzariaIcons אסור להוסיף לכאן — הם מצוירים RTL מלכתחילה.
// ⚠️ _flippableIcons הוא פתרון ביניים: היפוך גאומטרי הופך גם פרטים
//    א-סימטריים. אייקון שנראה רע כך — לצייר ב-otzaria_icons ולהסיר מכאן.

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

  static final Map<IconData, IconData> _fluentMirrorMap = {
    FluentIcons.chevron_double_right_20_regular:
        FluentIcons.chevron_double_left_20_regular,
    FluentIcons.chevron_double_left_20_regular:
        FluentIcons.chevron_double_right_20_regular,
    FluentIcons.chevron_double_right_16_regular:
        FluentIcons.chevron_double_left_16_regular,
    FluentIcons.chevron_double_left_16_regular:
        FluentIcons.chevron_double_right_16_regular,
    FluentIcons.calendar_24_regular: FluentIcons.calendar_rtl_24_regular,
    FluentIcons.calendar_24_filled: FluentIcons.calendar_rtl_24_filled,
    FluentIcons.panel_left_24_regular: FluentIcons.panel_right_24_regular,
    FluentIcons.panel_right_24_regular: FluentIcons.panel_left_24_regular,
    FluentIcons.panel_left_24_filled: FluentIcons.panel_right_24_filled,
    FluentIcons.panel_right_24_filled: FluentIcons.panel_left_24_filled,
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

    // אייקון שמתהפך בעצמו (matchTextDirection) — גם מתוסף, לפי שם.
    if (!isRtl || icon.matchTextDirection) return baseIcon;

    final mirroredIcon = _fluentMirrorMap[icon];
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
