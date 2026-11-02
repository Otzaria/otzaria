import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class AppMenuMetrics extends ThemeExtension<AppMenuMetrics> {
  final bool compactMenus;
  final double itemHeight;
  final EdgeInsets itemPadding;
  final EdgeInsets menuPadding;
  final VisualDensity visualDensity;
  final double dividerHeight;
  final double fontSize;
  final double iconSize;
  final double menuMinWidth;
  final FontWeight itemFontWeight;

  const AppMenuMetrics({
    required this.compactMenus,
    required this.itemHeight,
    required this.itemPadding,
    required this.menuPadding,
    required this.visualDensity,
    required this.dividerHeight,
    required this.fontSize,
    required this.iconSize,
    required this.menuMinWidth,
    required this.itemFontWeight,
  });

  /// במצב קומפקטי: הפרש ה-dense של M3 (גובה פחות 8, ריפוד 8 במקום 12).
  factory AppMenuMetrics.create({required bool compactMenus}) {
    return AppMenuMetrics(
      compactMenus: compactMenus,
      itemHeight: compactMenus ? 28 : 36,
      itemPadding: EdgeInsets.symmetric(
        horizontal: compactMenus ? 8 : 12,
        vertical: 0,
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      visualDensity: VisualDensity.standard,
      dividerHeight: 8,
      fontSize: 14,
      iconSize: 18,
      menuMinWidth: 150,
      itemFontWeight: FontWeight.w400,
    );
  }

  @override
  AppMenuMetrics copyWith({
    bool? compactMenus,
    double? itemHeight,
    EdgeInsets? itemPadding,
    EdgeInsets? menuPadding,
    VisualDensity? visualDensity,
    double? dividerHeight,
    double? fontSize,
    double? iconSize,
    double? menuMinWidth,
    FontWeight? itemFontWeight,
  }) {
    return AppMenuMetrics(
      compactMenus: compactMenus ?? this.compactMenus,
      itemHeight: itemHeight ?? this.itemHeight,
      itemPadding: itemPadding ?? this.itemPadding,
      menuPadding: menuPadding ?? this.menuPadding,
      visualDensity: visualDensity ?? this.visualDensity,
      dividerHeight: dividerHeight ?? this.dividerHeight,
      fontSize: fontSize ?? this.fontSize,
      iconSize: iconSize ?? this.iconSize,
      menuMinWidth: menuMinWidth ?? this.menuMinWidth,
      itemFontWeight: itemFontWeight ?? this.itemFontWeight,
    );
  }

  @override
  AppMenuMetrics lerp(ThemeExtension<AppMenuMetrics>? other, double t) {
    if (other is! AppMenuMetrics) return this;

    return AppMenuMetrics(
      compactMenus: t < 0.5 ? compactMenus : other.compactMenus,
      itemHeight: lerpDouble(itemHeight, other.itemHeight, t) ?? itemHeight,
      itemPadding:
          EdgeInsets.lerp(itemPadding, other.itemPadding, t) ?? itemPadding,
      menuPadding:
          EdgeInsets.lerp(menuPadding, other.menuPadding, t) ?? menuPadding,
      visualDensity: t < 0.5 ? visualDensity : other.visualDensity,
      dividerHeight:
          lerpDouble(dividerHeight, other.dividerHeight, t) ?? dividerHeight,
      fontSize: lerpDouble(fontSize, other.fontSize, t) ?? fontSize,
      iconSize: lerpDouble(iconSize, other.iconSize, t) ?? iconSize,
      menuMinWidth:
          lerpDouble(menuMinWidth, other.menuMinWidth, t) ?? menuMinWidth,
      itemFontWeight: t < 0.5 ? itemFontWeight : other.itemFontWeight,
    );
  }
}
