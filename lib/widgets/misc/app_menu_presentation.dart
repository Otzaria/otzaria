import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_icon.dart';

/// מחבר את תשתית התפריטים העצמאית לעיצוב ולאייקונים של האפליקציה.
MenuPresentation createAppMenuPresentation(
  BuildContext context, {
  AppMenuMetrics? metrics,
}) => MenuPresentation(
  metrics:
      metrics ??
      Theme.of(context).extension<AppMenuMetrics>() ??
      AppMenuMetrics.create(compactMenus: false),
  borderRadius: AppTokens.borderRadiusAll,
  iconBuilder: (context, icon, size, color, mirrorForRtl) => AppMenuIcon(
    icon,
    size: size,
    color: color,
    mirrorForRtl: mirrorForRtl,
  ),
  selectedMarkBuilder: (context, size, color) => Icon(
    FluentIcons.checkmark_circle_24_filled,
    size: size,
    color: color,
  ),
  // הכיוון פיזי לפי מיקום החלונית; Fluent משקף אייקונים בעצמו ב-RTL.
  submenuArrowBuilder: (context, openToRight, size, color) => Directionality(
    textDirection: TextDirection.ltr,
    child: Icon(
      openToRight
          ? FluentIcons.chevron_right_16_regular
          : FluentIcons.chevron_left_16_regular,
      size: size,
      color: color,
    ),
  ),
  downArrowBuilder: (context, size, color) => Icon(
    FluentIcons.chevron_down_12_regular,
    size: size,
    color: color,
  ),
);
