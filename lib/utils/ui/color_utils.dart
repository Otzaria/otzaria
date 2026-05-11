import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

class ColorUtils {
  static Color colorFromString(String? colorString) {
    if (colorString == null) {
      return AppSeedColors.defaultLight;
    }
    if (colorString.startsWith('#')) {
      colorString = colorString.substring(1);
    }
    if (colorString.length == 6) {
      colorString = 'ff$colorString';
    }
    return Color(int.parse(colorString, radix: 16));
  }

  static String colorToString(Color color) {
    return color.toARGB32().toRadixString(16);
  }
}
