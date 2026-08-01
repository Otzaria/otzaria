import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// מסמן את החלונית שנלחצה כחלונית הפעילה של הטאב.
///
/// [HitTestBehavior.translucent] כדי שהתוכן עצמו יקבל את הלחיצה כרגיל — הסימון
/// הוא תופעת לוואי של הלחיצה ולא במקומה.
///
/// ה-[Listener] נשאר בעץ גם כשאין מה לסמן, ורק המאזין מתנטרל: החלפתו בילד
/// עצמו הייתה משנה את סוג הווידג'ט בפיצול ובפירוק, ובונה מחדש את הספר.
class ActivePaneMarker extends StatelessWidget {
  /// החלונית שהמסמן עוטף.
  final OpenedTab pane;

  /// בטאב שאינו מפוצל יש חלונית אחת, ואין מה לסמן.
  final bool enabled;

  final Widget child;

  const ActivePaneMarker({
    super.key,
    required this.pane,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: enabled
          ? (_) => context.read<TabsBloc>().add(SetActivePane(pane))
          : null,
      child: child,
    );
  }
}
