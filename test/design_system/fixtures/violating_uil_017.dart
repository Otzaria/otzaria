import 'package:flutter/material.dart';

const TextStyle small = TextStyle(fontSize: 13); // LINT
TextStyle copy(TextStyle base) => base.copyWith(fontSize: 12.5); // LINT
TextStyle plain(Color color) => TextStyle(color: color, fontSize: 14); // LINT
TextStyle token() => const TextStyle(fontSize: AppTokens.fontMD); // LINT
TextStyle smaller() => const TextStyle(fontSize: AppTokens.fontSM - 1); // LINT

class AppTokens {
  static const double fontSM = 12;
  static const double fontMD = 14;
}

TextStyle? bigger(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.apply(fontSizeDelta: 2); // LINT
TextTheme scaledTheme(TextTheme theme) =>
    theme.apply(fontSizeFactor: 1.1); // LINT
