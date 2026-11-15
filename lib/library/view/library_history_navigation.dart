import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/book_common/view/reading_history_tooltip.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// מרחק אופקי מצטבר של החלקת שתי אצבעות שנחשב לבקשת חזרה/קדימה.
const double kLibrarySwipeDistance = 80;

/// מבקש מעבר בהיסטוריה; היעד נבחר כשה־Bloc מעבד את האירוע.
void travelLibraryHistory(
  BuildContext context, {
  required bool forward,
  required VoidCallback onNavigate,
}) {
  context.read<LibraryBloc>().add(TravelLibraryHistory(forward: forward));
  onNavigate();
}

String _placeOf(String? path) => path == null || path == '/'
    ? ''
    : path.substring(path.lastIndexOf('/') + 1);

ActionButtonData libraryBackAction(
  BuildContext context,
  LibraryNavigationHistory history, {
  required bool compact,
  required VoidCallback onNavigate,
}) => ActionButtonData.simple(
  key: const ValueKey('library-history-back'),
  compact: compact,
  tooltip: historyTooltip(
    context,
    _placeOf(history.previous),
    'חזרה אחורה',
    'חזרה אל {place}',
  ),
  icon: FluentIcons.arrow_left_24_regular,
  actionId: ToolbarActionId.libraryBack,
  onPressed: history.canGoBack
      ? () => travelLibraryHistory(
          context,
          forward: false,
          onNavigate: onNavigate,
        )
      : null,
);

ActionButtonData libraryForwardAction(
  BuildContext context,
  LibraryNavigationHistory history, {
  required bool compact,
  required VoidCallback onNavigate,
}) => ActionButtonData.simple(
  key: const ValueKey('library-history-forward'),
  compact: compact,
  tooltip: historyTooltip(
    context,
    _placeOf(history.next),
    'מעבר קדימה',
    'מעבר קדימה אל {place}',
  ),
  icon: FluentIcons.arrow_right_24_regular,
  actionId: ToolbarActionId.libraryForward,
  onPressed: history.canGoForward
      ? () => travelLibraryHistory(
          context,
          forward: true,
          onNavigate: onNavigate,
        )
      : null,
);

/// מבקש ניווט בלחצני הצד של העכבר ובהחלקה אופקית במשטח המגע.
class LibraryHistoryNavigator extends StatefulWidget {
  const LibraryHistoryNavigator({
    super.key,
    required this.onNavigate,
    required this.child,
  });

  final VoidCallback onNavigate;
  final Widget child;

  @override
  State<LibraryHistoryNavigator> createState() =>
      _LibraryHistoryNavigatorState();
}

class _LibraryHistoryNavigatorState extends State<LibraryHistoryNavigator> {
  bool _swipeHandled = false;

  void _travel({required bool forward}) => travelLibraryHistory(
    context,
    forward: forward,
    onNavigate: widget.onNavigate,
  );

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kBackMouseButton != 0) {
      _travel(forward: false);
    } else if (event.buttons & kForwardMouseButton != 0) {
      _travel(forward: true);
    }
  }

  // כמו בדפדפן: אצבעות שזזות ימינה חוזרות אחורה, בלי תלות בכיוון הממשק.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final pan = event.pan;
    if (_swipeHandled ||
        pan.dx.abs() < kLibrarySwipeDistance ||
        pan.dx.abs() < pan.dy.abs() * 2) {
      return;
    }
    _swipeHandled = true;
    _travel(forward: pan.dx < 0);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    onPointerPanZoomUpdate: _onPanZoomUpdate,
    onPointerPanZoomEnd: (_) => _swipeHandled = false,
    child: widget.child,
  );
}

/// מחווה שמתחילה באזור שנגלל אופקית בעצמו לא מנווטת בהיסטוריה.
class LibrarySwipeExclusion extends StatelessWidget {
  const LibrarySwipeExclusion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerPanZoomStart: (_) =>
        context
                .findAncestorStateOfType<_LibraryHistoryNavigatorState>()
                ?._swipeHandled =
            true,
    child: child,
  );
}
