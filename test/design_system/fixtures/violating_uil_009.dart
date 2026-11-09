import 'package:flutter/foundation.dart';
import 'package:otzaria/core/ui_snack.dart';

void saved() => UiSnack.show('נשמר'); // LINT
void failed(int code) => UiSnack.showError('נכשל: $code'); // LINT
void multiline() => UiSnack.showWarning(
  'אזהרה', // LINT
);
void withAction(String message, VoidCallback undo) => UiSnack.showWithAction(
  message: message,
  actionLabel: 'בטל', // LINT
  onAction: undo,
);
void either(bool ok) => UiSnack.show(
  ok
      ? 'נשמר' // LINT
      : 'נכשל', // LINT
);
