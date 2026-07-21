import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';

class PluginHighlightRevealService extends ChangeNotifier {
  PluginHighlightRevealService._();

  static final PluginHighlightRevealService instance =
      PluginHighlightRevealService._();

  PluginHighlight? _highlight;
  Timer? _clearTimer;

  PluginHighlight? get highlight => _highlight;
  String? get highlightId => _highlight?.highlightId;

  void reveal(PluginHighlight highlight) {
    _clearTimer?.cancel();
    _highlight = highlight;
    notifyListeners();
    _clearTimer = Timer(const Duration(seconds: 3), clear);
  }

  void clear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    if (_highlight == null) return;
    _highlight = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }
}
