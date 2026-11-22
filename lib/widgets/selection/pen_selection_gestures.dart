import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// מתייחס לעט כמו לעכבר בבחירת טקסט: גרירה בוחרת טקסט (ולא גוללת).
///
/// ‏`SelectableRegion` של Flutter מתייחס לעט כמו לאצבע: גרירה אופקית לא בוחרת
/// ואנכית גוללת, כי "גרירה לבחירה" שמורה לעכבר בלבד. כאן מזהים גרירה של עט
/// בעצמנו, כמעט מיד (כמו בעכבר), ושולחים את אותם אירועי בחירה שהאזור שולח
/// לעכבר. הנגיעות, הלחיצה הארוכה והלחיצות הכפולות של העט נשארות בידי האזור.
///
/// חייב לשבת בתוך `SelectionArea`/`SelectableRegion`. [onSelectionChanged]
/// נקרא בסיום הגרירה עם התוכן הנבחר, כי האזור עצמו לא מעדכן את
/// `onSelectionChanged` שלו על בחירה שלא עברה דרכו.
class PenSelectionGestures extends StatefulWidget {
  const PenSelectionGestures({
    super.key,
    required this.child,
    this.onSelectionChanged,
  });

  final Widget child;
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  @override
  State<PenSelectionGestures> createState() => _PenSelectionGesturesState();
}

class _PenSelectionGesturesState extends State<PenSelectionGestures> {
  SelectionHandler? _handler;

  // מרחק התזוזה שממנו עט נחשב גורר: כמו בעכבר, כמעט מיד, כדי שהגרירה תקדים
  // את הגלילה של הרשימה שמתחת (שדורשת 18).
  static const _penDragSlop = DeviceGestureSettings(touchSlop: 1);

  void _start(DragStartDetails details) {
    // המאחה שמעל (delegate של SelectableRegion) הוא גם SelectionHandler.
    final Object? registrar = SelectionContainer.maybeOf(context);
    _handler = registrar is SelectionHandler ? registrar : null;
    _handler?.dispatchSelectionEvent(
      SelectionEdgeUpdateEvent.forStart(globalPosition: details.globalPosition),
    );
  }

  void _update(DragUpdateDetails details) {
    _handler?.dispatchSelectionEvent(
      SelectionEdgeUpdateEvent.forEnd(globalPosition: details.globalPosition),
    );
  }

  void _finish() {
    final handler = _handler;
    _handler = null;
    if (handler == null) return;
    widget.onSelectionChanged?.call(handler.getSelectedContent());
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(
                debugOwner: this,
                supportedDevices: const {
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                },
              ),
              (instance) {
                instance
                  ..gestureSettings = _penDragSlop
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = _start
                  ..onUpdate = _update
                  ..onEnd = ((_) => _finish())
                  ..onCancel = _finish;
              },
            ),
      },
      child: widget.child,
    );
  }
}
