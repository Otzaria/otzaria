import 'package:flutter/foundation.dart';

/// היסטוריית הביקורים בתיקיות הספרייה, כמו בדפדפן; התיקיות נשמרות לפי נתיב
/// כדי לשרוד טעינה מחדש של עץ הספרייה.
class LibraryNavigationHistory extends ChangeNotifier {
  LibraryNavigationHistory({this.maxDepth = 50});

  final int maxDepth;
  final List<String> _back = [];
  final List<String> _forward = [];
  String? _current;

  String? get previous => _back.lastOrNull;
  String? get next => _forward.lastOrNull;
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  /// התיקייה [path] מוצגת. ביקור חדש מבטל את מסלול הקדימה; הגעה ליעד של
  /// [back] או [forward] אינה ביקור חדש.
  void visit(String path) {
    final current = _current;
    _current = path;
    if (current == null || current == path) return;
    _push(_back, current);
    _forward.clear();
    notifyListeners();
  }

  /// היעד הקודם שקיים עדיין, או null כשאין.
  String? back({bool Function(String)? isAvailable}) =>
      _travel(_back, _forward, isAvailable);

  /// היעד הבא שקיים עדיין, או null כשאין.
  String? forward({bool Function(String)? isAvailable}) =>
      _travel(_forward, _back, isAvailable);

  String? _travel(
    List<String> from,
    List<String> to,
    bool Function(String)? isAvailable,
  ) {
    if (from.isEmpty) return null;
    while (from.isNotEmpty) {
      final target = from.removeLast();
      if (target == _current || !(isAvailable?.call(target) ?? true)) continue;
      final current = _current;
      if (current != null) _push(to, current);
      _current = target;
      notifyListeners();
      return target;
    }
    notifyListeners();
    return null;
  }

  void _push(List<String> stack, String path) {
    if (stack.lastOrNull == path) return;
    stack.add(path);
    if (stack.length > maxDepth) stack.removeAt(0);
  }
}
