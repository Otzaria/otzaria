import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// בלי NumLock מקשי הספרון הם מקשי ניווט, אבל ה-engine של Windows גוזר את
/// המקש הלוגי מקוד הסריקה ומדווח numpad8 במקום arrowUp (#5934). המיפוי כאן
/// רץ על כל KeyData לפני HardwareKeyboard, הפוקוס וה-Shortcuts, כך שכל
/// התאמה של arrowUp/home/end באפליקציה חלה גם עליהם. המקש הפיזי לא משתנה,
/// ושחרור/חזרה מקבלים את המקש הלוגי שנבחר בלחיצה גם אם NumLock השתנה בינתיים.
void installNumpadNavigationKeys() {
  if (defaultTargetPlatform != TargetPlatform.windows) return;
  final dispatcher = ui.PlatformDispatcher.instance;
  final inner = dispatcher.onKeyData;
  if (inner == null) return;
  final pressed = <int, int>{};
  dispatcher.onKeyData = (data) => inner(_mapNumpadKey(data, pressed));
}

ui.KeyData _mapNumpadKey(ui.KeyData data, Map<int, int> pressed) {
  final int? logical;
  if (data.type == ui.KeyEventType.down) {
    logical =
        HardwareKeyboard.instance.lockModesEnabled.contains(
          KeyboardLockMode.numLock,
        )
        ? null
        : _navigationKeys[data.logical];
    if (logical != null) pressed[data.physical] = logical;
  } else if (data.type == ui.KeyEventType.up) {
    logical = pressed.remove(data.physical);
  } else {
    logical = pressed[data.physical];
  }
  if (logical == null) return data;
  return ui.KeyData(
    timeStamp: data.timeStamp,
    type: data.type,
    physical: data.physical,
    logical: logical,
    character: data.character,
    synthesized: data.synthesized,
    deviceType: data.deviceType,
  );
}

final Map<int, int> _navigationKeys = {
  LogicalKeyboardKey.numpad7.keyId: LogicalKeyboardKey.home.keyId,
  LogicalKeyboardKey.numpad8.keyId: LogicalKeyboardKey.arrowUp.keyId,
  LogicalKeyboardKey.numpad9.keyId: LogicalKeyboardKey.pageUp.keyId,
  LogicalKeyboardKey.numpad4.keyId: LogicalKeyboardKey.arrowLeft.keyId,
  LogicalKeyboardKey.numpad6.keyId: LogicalKeyboardKey.arrowRight.keyId,
  LogicalKeyboardKey.numpad1.keyId: LogicalKeyboardKey.end.keyId,
  LogicalKeyboardKey.numpad2.keyId: LogicalKeyboardKey.arrowDown.keyId,
  LogicalKeyboardKey.numpad3.keyId: LogicalKeyboardKey.pageDown.keyId,
  LogicalKeyboardKey.numpad0.keyId: LogicalKeyboardKey.insert.keyId,
  LogicalKeyboardKey.numpadDecimal.keyId: LogicalKeyboardKey.delete.keyId,
};
