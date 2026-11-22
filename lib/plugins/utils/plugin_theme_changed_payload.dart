import 'package:flutter/material.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// ה-payload של `theme.changed` מתוך הזרע והבהירות שנבחרו.
///
/// ה-MaterialApp מתעדכן רק ב-frame הבא, ולכן ה-payload נבנה כאן ישירות
/// מההגדרות ולא מ-`Theme.of(context)`.
Map<String, dynamic> buildThemeChangedPayload({
  required Color seed,
  required Brightness brightness,
  required AppDensity density,
}) => buildThemePayloadFromScheme(
  AppThemeData.createColorScheme(seed, brightness),
  isDark: brightness == Brightness.dark,
  density: density,
  variant: AppThemeVariant.ofSeed(seed),
);
