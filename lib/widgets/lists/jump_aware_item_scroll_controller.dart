import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// [ItemScrollController] שמודיע למאזינים לפני כל קפיצה לאינדקס.
class JumpAwareItemScrollController extends ItemScrollController {
  final _beforeJumpListeners = ObserverList<VoidCallback>();
  int _navigationGeneration = 0;
  int get navigationGeneration => _navigationGeneration;
  Future<void> Function(int index, {int? sourceLineIndex})? externalScroll;

  bool get isNativeAttached => externalScroll == null && super.isAttached;

  @override
  bool get isAttached => externalScroll != null || super.isAttached;

  void addBeforeJumpListener(VoidCallback listener) =>
      _beforeJumpListeners.add(listener);

  void removeBeforeJumpListener(VoidCallback listener) =>
      _beforeJumpListeners.remove(listener);

  void _notifyBeforeJump() {
    for (final listener in _beforeJumpListeners.toList()) {
      listener();
    }
  }

  /// מודיע על ניווט בלי להפעיל ניקוי בחירה ששייך רק לקפיצה.
  void beginNavigation() => _navigationGeneration++;

  @override
  void jumpTo({required int index, double alignment = 0}) {
    _notifyBeforeJump();
    if (externalScroll case final navigate?) {
      navigate(index);
      return;
    }
    super.jumpTo(index: index, alignment: alignment);
  }

  @override
  Future<void> scrollTo({
    required int index,
    int? sourceLineIndex,
    double alignment = 0,
    required Duration duration,
    Curve curve = Curves.linear,
    List<double> opacityAnimationWeights = const [40, 20, 40],
  }) {
    _notifyBeforeJump();
    if (externalScroll case final navigate?) {
      return navigate(index, sourceLineIndex: sourceLineIndex);
    }
    return super.scrollTo(
      index: index,
      alignment: alignment,
      duration: duration,
      curve: curve,
      opacityAnimationWeights: opacityAnimationWeights,
    );
  }
}
