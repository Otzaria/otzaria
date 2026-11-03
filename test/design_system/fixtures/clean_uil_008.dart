import 'package:flutter/material.dart';

class UiSnack {
  static void show(String message) {}
}

class Messages {
  static const saved = 'נשמר';
}

void show() => UiSnack.show(Messages.saved);

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey();

SnackBarThemeData theme(ColorScheme cs) =>
    SnackBarThemeData(backgroundColor: cs.inverseSurface);
