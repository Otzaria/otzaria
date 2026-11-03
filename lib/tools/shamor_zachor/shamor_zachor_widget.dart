import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'screens/shamor_zachor_main_screen.dart';

/// בקר פוקוס חיצוני למסכי שמור וזכור.
class ShamorZachorFocusController {
  VoidCallback? _requestKeyboardFocus;

  void requestKeyboardFocus() {
    _requestKeyboardFocus?.call();
  }

  void bind(VoidCallback callback) {
    _requestKeyboardFocus = callback;
  }

  void unbind(VoidCallback callback) {
    if (_requestKeyboardFocus == callback) {
      _requestKeyboardFocus = null;
    }
  }
}

/// כלי שמור וזכור. ה-providers שלו (נתונים והתקדמות) ברמת האפליקציה.
///
/// אין לכלי Navigator משלו (DD-29): הספר נפתח בתוך המסך הראשי (מצב, לא route),
/// ודיאלוגים, tooltips ואנימציית הסיום עולים בשכבות של החלון.
class ShamorZachorWidget extends StatefulWidget {
  /// Callback when the screen changes, providing the new title
  final ValueChanged<String>? onTitleChanged;

  /// בקר חיצוני להחזרת פוקוס למסך הראשי של הכלי.
  final ShamorZachorFocusController? focusController;

  const ShamorZachorWidget({
    super.key,
    this.onTitleChanged,
    this.focusController,
  });

  @override
  State<ShamorZachorWidget> createState() => _ShamorZachorWidgetState();
}

class _ShamorZachorWidgetState extends State<ShamorZachorWidget>
    with AutomaticKeepAliveClientMixin {
  static final Logger _logger = Logger('ShamorZachorWidget');

  @override
  bool get wantKeepAlive => true;

  final ShamorZachorFocusController _mainScreenFocusController =
      ShamorZachorFocusController();

  void _requestKeyboardFocus() {
    _mainScreenFocusController.requestKeyboardFocus();
  }

  @override
  void initState() {
    super.initState();
    _logger.info('Initializing ShamorZachorWidget');
    widget.focusController?.bind(_requestKeyboardFocus);
  }

  @override
  void didUpdateWidget(covariant ShamorZachorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusController != widget.focusController) {
      oldWidget.focusController?.unbind(_requestKeyboardFocus);
      widget.focusController?.bind(_requestKeyboardFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return ShamorZachorMainScreen(focusController: _mainScreenFocusController);
  }

  @override
  void dispose() {
    widget.focusController?.unbind(_requestKeyboardFocus);
    _logger.fine('Disposing ShamorZachorWidget');
    super.dispose();
  }
}
