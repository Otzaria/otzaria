import 'package:flutter/widgets.dart';

/// שוליי תוכן הקריאה של כל חלונית בתצוגת "זה לצד זה", בצד הדופן החיצוני בלבד —
/// כך ידית הפתיחה (Positioned(left:0)) בחלונית הצמודה לדופן צפה מעל השוליים.
class SplitPaneContentInset extends InheritedWidget {
  final EdgeInsetsGeometry contentInset;

  const SplitPaneContentInset({
    super.key,
    required this.contentInset,
    required super.child,
  });

  /// השוליים הפעילים, או [EdgeInsets.zero] בתצוגת חלונית יחידה (ללא פיצול).
  static EdgeInsetsGeometry of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<SplitPaneContentInset>();
    return inherited?.contentInset ?? EdgeInsets.zero;
  }

  @override
  bool updateShouldNotify(SplitPaneContentInset oldWidget) =>
      contentInset != oldWidget.contentInset;
}
