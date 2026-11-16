import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/utils/tab_content_vertical_drag_recognizer.dart';
import 'package:otzaria/tabs/utils/tab_swipe_direction.dart';
import 'package:otzaria/tabs/utils/tab_swipe_log.dart';
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
    required this.onActiveChanged,
    required this.child,
  });

  final PageController? controller;

  /// `true` מתחילת הגרירה ו-`false` בסוף ההתיישבות, כדי שסנכרון ה-PageView
  /// מה-bloc לא יקפיץ את התצוגה באמצע.
  final ValueChanged<bool> onActiveChanged;

  final Widget child;

  @override
  State<TabSwipeDetector> createState() => _TabSwipeDetectorState();
}

class _TabSwipeDetectorState extends State<TabSwipeDetector> {
  bool _dragging = false;
  double _startPage = 0;
  int _anchorIndex = 0;
  double _draggedDx = 0;
  double _draggedPages = 0;
  PointerDeviceKind? _kind;
  int? _expectedIndex;
  List<OpenedTab> _gestureTabs = const [];

  /// מחווה חדשה מחליפה את ההתיישבות הקודמת; רק האחרונה משחררת את הדיכוי.
  int _generation = 0;

  @override
  void dispose() {
    // dispose של המזהים לא קורא ל-onEnd/onCancel; בלי זה הסנכרון נשאר חסום.
    if (_expectedIndex != null) {
      _dragging = false;
      _generation++;
      widget.onActiveChanged(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listener: (_, state) => _onTabsChanged(state),
      child: RawGestureDetector(
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
      ),
    );
  }

  void _onTabsChanged(TabsState state) {
    if (_expectedIndex == null ||
        (_expectedIndex == state.currentTabIndex &&
            listEquals(_gestureTabs, state.tabs))) {
      return;
    }
    // בחירה או שינוי מבנה מבחוץ מחליפים את המחווה, כולל אנימציה שעדיין רצה.
    _dragging = false;
    _generation++;
    _expectedIndex = null;
    _gestureTabs = const [];
    final controller = widget.controller;
    if (state.hasOpenTabs && controller != null && controller.hasClients) {
      controller.jumpToPage(
        state.currentTabIndex.clamp(0, state.tabs.length - 1),
      );
    }
    widget.onActiveChanged(false);
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
    _generation++;
    widget.onActiveChanged(true);
    _startPage = controller.page ?? 0;
    final state = context.read<TabsBloc>().state;
    _anchorIndex = state.currentTabIndex;
    _expectedIndex = _anchorIndex;
    _gestureTabs = List.of(state.tabs);
    _draggedDx = 0;
    _draggedPages = 0;
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
    final before = position.pixels;
    position.jumpTo(
      (position.pixels + offsetDelta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _draggedPages += (position.pixels - before) / position.viewportDimension;
  }

  Future<void> _settle(double velocityDx) async {
    if (!_dragging) return;
    _onTabsChanged(context.read<TabsBloc>().state);
    if (!_dragging) return;
    _dragging = false;
    final generation = _generation;
    try {
      await _settleOnTarget(velocityDx);
    } finally {
      if (generation == _generation) {
        _expectedIndex = null;
        _gestureTabs = const [];
        widget.onActiveChanged(false);
      }
    }
  }

  Future<void> _settleOnTarget(double velocityDx) async {
    final controller = widget.controller;
    if (controller == null || !controller.hasClients) return;
    final bloc = context.read<TabsBloc>();
    final state = bloc.state;
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
      anchorIndex: _anchorIndex,
      draggedPages: _draggedPages,
      pageVelocity: pageVelocity,
      tabCount: state.tabs.length,
    );
    TabSwipeLog.add(bloc, {
      'kind': _kind?.name,
      'tab': state.currentTab?.runtimeType.toString(),
      'from': _anchorIndex,
      'to': target,
      'tabs': state.tabs.length,
      'dx': _draggedDx.round(),
      'velocity': velocityDx.round(),
      'startPage': _rounded(_startPage),
      'page': _rounded(page),
    });
    // עדכון ה-bloc קודם כדי שההדגשה בשורת הטאבים תגיב מיד.
    _expectedIndex = target;
    if (target != state.currentTabIndex) bloc.add(SetCurrentTab(target));
    final duration = AppMotion.duration(
      context,
      const Duration(milliseconds: 220),
    );
    if (duration == Duration.zero) {
      controller.jumpToPage(target);
    } else {
      await controller.animateToPage(
        target,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  static double _rounded(double value) =>
      double.parse(value.toStringAsFixed(2));
}
