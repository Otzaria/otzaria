import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// מזהה חזרות רק אחרי שהמקש טופל באותו קורא ובאותו רצף פוקוס.
class NavigationKeyTracker with WidgetsBindingObserver {
  NavigationKeyTracker({required this.hasNavigationFocus});

  final bool Function() hasNavigationFocus;
  final Set<LogicalKeyboardKey> _keys = {};

  bool isRepeat(KeyEvent event) {
    if (_keys.isEmpty) {
      FocusManager.instance.addListener(_onFocusChange);
      WidgetsBinding.instance.addObserver(this);
    }
    _keys.retainAll(HardwareKeyboard.instance.logicalKeysPressed);
    return !_keys.add(event.logicalKey) && event is KeyRepeatEvent;
  }

  void release(KeyEvent event) {
    if (event is KeyUpEvent &&
        _keys.remove(event.logicalKey) &&
        _keys.isEmpty) {
      clear();
    }
  }

  void _onFocusChange() {
    if (!hasNavigationFocus()) clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) clear();
  }

  void clear() {
    _keys.clear();
    FocusManager.instance.removeListener(_onFocusChange);
    WidgetsBinding.instance.removeObserver(this);
  }
}
