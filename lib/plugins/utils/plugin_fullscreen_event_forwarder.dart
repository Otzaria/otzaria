import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';

/// שולח לתוספים את האירוע `ui.fullscreenChanged` בכל שינוי של מצב המסך המלא
/// של החלון: כפתור, F11, Escape, או יציאה אוטומטית במעבר מסך. בלי האירוע
/// תוסף שמחליף תווית כפתור לפי המצב נתקע כשהמשתמש יוצא ב-Escape.
///
/// המצב הוא של חלון אחד, ולכן האירוע מכוון לתוספים שמוצגים בחלון הזה בלבד.
/// בבנייה הראשונה אין אירוע (זה אינו שינוי).
class PluginFullscreenEventForwarder extends StatelessWidget {
  const PluginFullscreenEventForwarder({
    super.key,
    required this.dispatch,
    required this.child,
  });

  /// נושא האירוע ל-`PluginRuntimeDispatcher.dispatchEvent`.
  static const topic = 'ui.fullscreenChanged';

  final Future<void> Function(
    String topic,
    Map<String, dynamic> payload, {
    int? viewId,
  })
  dispatch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<WindowFullscreenCubit, bool>(
      listener: (context, isFullscreen) => dispatch(
        topic,
        {'fullscreen': isFullscreen},
        viewId: View.maybeOf(context)?.viewId,
      ),
      child: child,
    );
  }
}
