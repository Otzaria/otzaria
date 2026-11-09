import 'package:flutter/widgets.dart';
import 'package:otzaria/core/ui_snack.dart';

abstract final class FixtureMessages {
  static const saved = 'נשמר';
}

void saved() => UiSnack.show(FixtureMessages.saved);
void quick(String message) => UiSnack.showQuick(message);
void either(bool ok, String failed) =>
    UiSnack.show(ok ? FixtureMessages.saved : failed);
void hide() => UiSnack.hide();
Widget label() => const Text('לא UiSnack');
