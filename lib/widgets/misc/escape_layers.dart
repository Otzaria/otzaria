import 'package:flutter/widgets.dart';

/// שכבות צפות שאינן מחזיקות פוקוס (תפריט הקשר, פאנל צף) ונסגרות ב-ESC.
///
/// Flutter מפעיל את כל ה-early handlers על כל מקש, לכן מטפל משותף יחיד
/// מעביר את המקש מהשכבה האחרונה שנרשמה, והראשונה שמטפלת בו עוצרת.
abstract final class EscapeLayers {
  static final List<OnKeyEventCallback> _layers = [];

  /// [below] - לשכבה שמצוירת תמיד מתחת לתפריטים (פאנל בתוך העץ).
  static void add(OnKeyEventCallback layer, {bool below = false}) {
    final wasEmpty = _layers.isEmpty;
    _layers.remove(layer);
    below ? _layers.insert(0, layer) : _layers.add(layer);
    if (wasEmpty) {
      FocusManager.instance.addEarlyKeyEventHandler(_dispatch);
    }
  }

  static void remove(OnKeyEventCallback layer) {
    if (!_layers.remove(layer)) return;
    if (_layers.isEmpty) {
      FocusManager.instance.removeEarlyKeyEventHandler(_dispatch);
    }
  }

  static KeyEventResult _dispatch(KeyEvent event) {
    for (final layer in _layers.reversed.toList()) {
      final result = layer(event);
      if (result != KeyEventResult.ignored) return result;
    }
    return KeyEventResult.ignored;
  }
}
