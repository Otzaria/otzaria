import 'package:flutter/widgets.dart';

/// קורא ל-[onChanged] כשהמערכת מחליפה בין בהיר לכהה
/// (`didChangePlatformBrightness`), פעם אחת לכל החלפה. בבנייה הראשונה אין קריאה.
///
/// כש"עקוב אחר המערכת" פעיל, ה-MaterialApp מתחלף מעצמו אבל ההגדרות לא
/// משתנות, ולכן האירוע `theme.changed` לתוספים לא היה נשלח.
class PlatformBrightnessListener extends StatefulWidget {
  const PlatformBrightnessListener({
    super.key,
    required this.onChanged,
    required this.child,
  });

  final ValueChanged<Brightness> onChanged;
  final Widget child;

  @override
  State<PlatformBrightnessListener> createState() =>
      _PlatformBrightnessListenerState();
}

class _PlatformBrightnessListenerState extends State<PlatformBrightnessListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    widget.onChanged(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
