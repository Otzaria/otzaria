// lib/widgets/rtl_icon.dart
//
// ווידג'ט RtlIcon — אייקון RTL-מודע שמהפך אוטומטית חיצי ניווט בסביבת RTL.
//
// **בעיה:** Flutter לא מהפך אייקוני כיוון (chevron, arrow) אוטומטית ב-RTL.
// **פתרון:** RtlIcon בודק את Directionality ומחזיר את הצד ההפוך.
//
// **שימוש:**
// ```dart
// // במקום: const Icon(Icons.chevron_left)
// const RtlIcon(Icons.chevron_left)
//
// // במקום: const Icon(FluentIcons.chevron_right_24_regular)
// const RtlIcon(FluentIcons.chevron_right_24_regular)
// ```
//
// **אייקוני Fluent UI** — הוסף ל-_fluentMirrorMap כנדרש.

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// אייקון RTL-מודע שמהפך חיצי ניווט אוטומטית בסביבת RTL.
///
/// תומך ב:
/// - [Icons] Material icons — ראה [_materialMirrorMap]
/// - [FluentIcons] — ראה [_fluentMirrorMap]
///
/// אייקונים שאינם ברשימות לא משתנים.
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

  // ── Material Icons mirror map ────────────────────────────────────────────
  // הסרת const כי IconData לא יכול להיות מפתח ב-const map
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

  // ── FluentIcons mirror map ───────────────────────────────────────────────
  // הסרת const כי IconData לא יכול להיות מפתח ב-const map
  static final Map<IconData, IconData> _fluentMirrorMap = {
    FluentIcons.chevron_right_24_regular: FluentIcons.chevron_left_24_regular,
    FluentIcons.chevron_left_24_regular: FluentIcons.chevron_right_24_regular,
    FluentIcons.chevron_right_20_regular: FluentIcons.chevron_left_20_regular,
    FluentIcons.chevron_left_20_regular: FluentIcons.chevron_right_20_regular,
    FluentIcons.chevron_right_16_regular: FluentIcons.chevron_left_16_regular,
    FluentIcons.chevron_left_16_regular: FluentIcons.chevron_right_16_regular,
    FluentIcons.arrow_right_24_regular: FluentIcons.arrow_left_24_regular,
    FluentIcons.arrow_left_24_regular: FluentIcons.arrow_right_24_regular,
  };

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    IconData resolvedIcon = icon;
    if (isRtl) {
      resolvedIcon = _materialMirrorMap[icon] ?? _fluentMirrorMap[icon] ?? icon;
    }

    return Icon(
      resolvedIcon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );
  }
}
