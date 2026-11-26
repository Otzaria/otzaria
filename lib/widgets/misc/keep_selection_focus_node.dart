import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// צומת פוקוס לאזור בחירה בקורא: שומר את הבחירה כשהחלון מאבד פוקוס.
///
/// ב-Windows אובדן פוקוס החלון מעביר את הפוקוס ל-rootScope כשה-lifecycle עדיין
/// resumed; בלי זה SelectableRegion מנקה את הבחירה. מעבר פוקוס לרכיב אחר
/// בתוך האפליקציה ממשיך לנקות כרגיל.
class KeepSelectionOnWindowBlurFocusNode extends FocusNode {
  KeepSelectionOnWindowBlurFocusNode({super.debugLabel});

  @override
  void notifyListeners() {
    if (SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        FocusManager.instance.primaryFocus == FocusManager.instance.rootScope) {
      return;
    }
    super.notifyListeners();
  }
}

/// מחזיק [KeepSelectionOnWindowBlurFocusNode] למקומות שבונים אזור בחירה לכל
/// פריט, ואין להם State יחיד שיחזיק צומת לכל אחד.
class KeepSelectionOnWindowBlurFocus extends StatefulWidget {
  const KeepSelectionOnWindowBlurFocus({super.key, required this.builder});

  final Widget Function(FocusNode focusNode) builder;

  @override
  State<KeepSelectionOnWindowBlurFocus> createState() =>
      _KeepSelectionOnWindowBlurFocusState();
}

class _KeepSelectionOnWindowBlurFocusState
    extends State<KeepSelectionOnWindowBlurFocus> {
  final _focusNode = KeepSelectionOnWindowBlurFocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_focusNode);
}
