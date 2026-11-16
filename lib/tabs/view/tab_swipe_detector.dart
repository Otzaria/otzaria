import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/utils/tab_content_vertical_drag_recognizer.dart';
import 'package:otzaria/tabs/utils/tab_swipe_direction.dart';
import 'package:otzaria/tabs/utils/tab_swipe_settle.dart';
import 'package:otzaria/tabs/utils/touch_tab_swipe_recognizer.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מזהה החלקה בין טאבים בדסקטופ, בלוח מגע ובמסך מגע.
///
/// הגרירה מזיזה את ה-PageView של [controller] באופן הדרגתי, ובשחרור
/// מתיישבים על הטאב הקרוב (או הסמוך, בהנפה מהירה).
class TabSwipeDetector extends StatefulWidget {
  const TabSwipeDetector({
    super.key,
    required this.controller,
    required this.onSettlingChanged,
    required this.child,
  });

  final PageController? controller;

  /// נקרא עם `true` בתחילת אנימציית ההתיישבות ועם `false` בסופה, כדי
  /// שסנכרון ה-PageView מה-bloc לא יקטע אותה.
  final ValueChanged<bool> onSettlingChanged;

  final Widget child;

  /// ההחלקות האחרונות, לדיווח על התוכנה.
  static List<Map<String, Object?>> get recentSwipes =>
      List.unmodifiable(_recentSwipes);
  static final List<Map<String, Object?>> _recentSwipes = [];
  static const int _maxRecentSwipes = 5;

  @visibleForTesting
  static void debugClearRecentSwipes() => _recentSwipes.clear();

  @override
  State<TabSwipeDetector> createState() => _TabSwipeDetectorState();
}

class _TabSwipeDetectorState extends State<TabSwipeDetector> {
  bool _dragging = false;
  double _startPage = 0;
  int _anchorIndex = 0;
  double _draggedDx = 0;
  PointerDeviceKind? _kind;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        // מעל WebView אין מזהה גלילה פנימי שימנע מעבר טאב בגלילה אנכית.
        TabContentVerticalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
              TabContentVerticalDragRecognizer
            >(
              TabContentVerticalDragRecognizer.new,
              (recognizer) => recognizer.onStart = (_) {},
            ),
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer
            >(
              () => HorizontalDragGestureRecognizer(
                supportedDevices: const {PointerDeviceKind.trackpad},
              ),
              _configure,
            ),
        TouchTabSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<TouchTabSwipeRecognizer>(
              () => TouchTabSwipeRecognizer(
                singleFingerPansContent: () {
                  final tab = context.read<TabsBloc>().state.currentTab;
                  return tab is PdfBookTab && tab.canPanHorizontally;
                },
              ),
              _configure,
            ),
      },
      child: widget.child,
    );
  }

  void _configure(HorizontalDragGestureRecognizer recognizer) {
    recognizer
      // הזכייה בזירה מגיעה רק אחרי סף — down מוסר את הדלתא
      // שנצברה עד אז במקום לבלוע אותה (רציפות הגרירה).
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = _onStart
      ..onUpdate = _onUpdate
      ..onEnd = (details) {
        _settle(details.velocity.pixelsPerSecond.dx);
      }
      ..onCancel = () {
        _settle(0);
      };
  }

  void _onStart(DragStartDetails details) {
    final controller = widget.controller;
    if (controller == null || !controller.hasClients) return;
    _dragging = true;
    _startPage = controller.page ?? 0;
    _anchorIndex = context.read<TabsBloc>().state.currentTabIndex;
    _draggedDx = 0;
    _kind = details.kind;
  }

  void _onUpdate(DragUpdateDetails details) {
    final controller = widget.controller;
    if (!_dragging || controller == null || !controller.hasClients) return;
    _draggedDx += details.delta.dx;
    final position = controller.position;
    final offsetDelta =
        details.delta.dx.abs() *
        tabSwipeDirection(
          accumulatedDx: details.delta.dx,
          textDirection: Directionality.of(context),
        );
    position.jumpTo(
      (position.pixels + offsetDelta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Future<void> _settle(double velocityDx) async {
    if (!_dragging) return;
    _dragging = false;
    final controller = widget.controller;
    if (controller == null || !controller.hasClients) return;
    final state = context.read<TabsBloc>().state;
    if (!state.hasOpenTabs) return;
    final page = controller.page ?? _startPage;
    final pageVelocity =
        velocityDx.abs() *
        tabSwipeDirection(
          accumulatedDx: velocityDx,
          textDirection: Directionality.of(context),
        );
    final target = tabSwipeSettleIndex(
      page: page,
      startPage: _startPage,
      anchorIndex: _anchorIndex,
      pageVelocity: pageVelocity,
      tabCount: state.tabs.length,
    );
    _record(page: page, velocityDx: velocityDx, target: target, state: state);
    // עדכון ה-bloc קודם כדי שההדגשה בשורת הטאבים תגיב מיד.
    if (target != state.currentTabIndex) {
      context.read<TabsBloc>().add(SetCurrentTab(target));
    }
    final duration = AppMotion.duration(
      context,
      const Duration(milliseconds: 220),
    );
    widget.onSettlingChanged(true);
    try {
      if (duration == Duration.zero) {
        controller.jumpToPage(target);
      } else {
        await controller.animateToPage(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      widget.onSettlingChanged(false);
    }
  }

  void _record({
    required double page,
    required double velocityDx,
    required int target,
    required TabsState state,
  }) {
    final swipes = TabSwipeDetector._recentSwipes;
    if (swipes.length == TabSwipeDetector._maxRecentSwipes) {
      swipes.removeAt(0);
    }
    swipes.add({
      'kind': _kind?.name,
      'tab': state.currentTab?.runtimeType.toString(),
      'from': _anchorIndex,
      'to': target,
      'tabs': state.tabs.length,
      'dx': _draggedDx.round(),
      'velocity': velocityDx.round(),
      'startPage': double.parse(_startPage.toStringAsFixed(2)),
      'page': double.parse(page.toStringAsFixed(2)),
    });
  }
}
