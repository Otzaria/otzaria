import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/book_common/view/reading_history_tooltip.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// מרחק אופקי מצטבר של החלקת שתי אצבעות שנחשב לבקשת חזרה/קדימה.
const double kLibrarySwipeDistance = 80;

/// התיקייה שנתיבה [path] בעץ [library], או null כשאינה קיימת עוד.
Category? libraryCategoryAtPath(Category library, String path) {
  Category category = library;
  for (final title in path.split('/').where((part) => part.isNotEmpty)) {
    final child = category.subCategories
        .where((sub) => sub.title == title)
        .firstOrNull;
    if (child == null) return null;
    category = child;
  }
  return category;
}

/// מעבר בהיסטוריה אחורה, או קדימה כש-[forward].
void travelLibraryHistory(
  BuildContext context,
  LibraryNavigationHistory history, {
  required bool forward,
  required ValueChanged<Category> onOpen,
}) {
  final library = context.read<LibraryBloc>().state.library;
  if (library == null) return;
  String? travel() => forward ? history.forward() : history.back();
  // תיקייה שנמחקה מאז מדולגת, אחרת הלחיצה לא הייתה עושה דבר.
  for (var path = travel(); path != null; path = travel()) {
    final category = libraryCategoryAtPath(library, path);
    if (category == null) continue;
    onOpen(category);
    return;
  }
}

String _placeOf(String? path) => path == null || path == '/'
    ? ''
    : path.substring(path.lastIndexOf('/') + 1);

ActionButtonData libraryBackAction(
  BuildContext context,
  LibraryNavigationHistory history, {
  required bool compact,
  required ValueChanged<Category> onOpen,
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
          history,
          forward: false,
          onOpen: onOpen,
        )
      : null,
);

ActionButtonData libraryForwardAction(
  BuildContext context,
  LibraryNavigationHistory history, {
  required bool compact,
  required ValueChanged<Category> onOpen,
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
          history,
          forward: true,
          onOpen: onOpen,
        )
      : null,
);

/// רושם את ביקורי התיקיות ב-[history], ומנווט בו בלחצני הצד של העכבר
/// ובהחלקה אופקית של שתי אצבעות במשטח המגע.
class LibraryHistoryNavigator extends StatefulWidget {
  const LibraryHistoryNavigator({
    super.key,
    required this.history,
    required this.onOpen,
    required this.child,
  });

  final LibraryNavigationHistory history;
  final ValueChanged<Category> onOpen;
  final Widget child;

  @override
  State<LibraryHistoryNavigator> createState() =>
      _LibraryHistoryNavigatorState();
}

class _LibraryHistoryNavigatorState extends State<LibraryHistoryNavigator> {
  bool _swipeHandled = false;

  @override
  void initState() {
    super.initState();
    _visit(context.read<LibraryBloc>().state);
  }

  void _visit(LibraryState state) {
    final path = state.currentCategory?.path;
    if (path != null) widget.history.visit(path);
  }

  void _travel({required bool forward}) => travelLibraryHistory(
    context,
    widget.history,
    forward: forward,
    onOpen: widget.onOpen,
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
  Widget build(BuildContext context) => BlocListener<LibraryBloc, LibraryState>(
    listenWhen: (previous, current) =>
        previous.currentCategory?.path != current.currentCategory?.path,
    listener: (context, state) => _visit(state),
    child: Listener(
      onPointerDown: _onPointerDown,
      onPointerPanZoomStart: (_) => _swipeHandled = false,
      onPointerPanZoomUpdate: _onPanZoomUpdate,
      child: widget.child,
    ),
  );
}
