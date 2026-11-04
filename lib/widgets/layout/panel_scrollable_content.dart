// lib/widgets/layout/panel_scrollable_content.dart
//
// [PanelScrollableContent] — אזור תוכן גלילה עם פס גלילה צמוד לקצה.
//
// פטרן משותף לדיאלוגים ופאנלים:
//  • הפס ([AppScrollbar]) מתפרס עד לגבול ה-widget (הקורא לא מוסיף padding
//    אופקי כלפי חוץ), בימין הפיזי או בצד [scrollbarSide]
//  • [padding] מוחל בתוך ה-SingleChildScrollView, והרצועה של הפס מצטמצמת
//    בריווח שכבר יש בצד שלו
//
// **שימוש:**
// ```dart
// // ה-Container/Padding החיצוני ללא padding אופקי:
// Expanded(
//   child: PanelScrollableContent(
//     padding: const EdgeInsets.symmetric(horizontal: 16),
//     child: MyContent(),
//   ),
// )
// ```

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/feedback/app_scrollbar.dart';

class PanelScrollableContent extends StatefulWidget {
  /// תוכן הגלילה.
  final Widget child;

  /// padding שיוחל בתוך ה-SingleChildScrollView.
  /// ברירת מחדל: 16px אופקי — שמרחק זה הוא גם המרווח שמפריד בין הגלילה לתוכן.
  final EdgeInsetsGeometry padding;

  /// הצד הפיזי של הפס. שמאל רק בחלונית שמשמאל לתוכן, שהידית שלה בקצה
  /// הימני (ContextOverlayPanel).
  final ScrollbarOrientation scrollbarSide;

  /// משאיר את פס הגלילה גלוי כל עוד יש תוכן לגלול, בלי להמתין לגרירה.
  /// נדרש היכן שהתוכן החתוך אינו נראה לעין (דיאלוג בחלון נמוך).
  final bool thumbVisibility;

  const PanelScrollableContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.scrollbarSide = ScrollbarOrientation.right,
    this.thumbVisibility = false,
  });

  @override
  State<PanelScrollableContent> createState() => _PanelScrollableContentState();
}

class _PanelScrollableContentState extends State<PanelScrollableContent> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding.resolve(Directionality.of(context));
    return AppScrollbar(
      controller: _scrollController,
      side: widget.scrollbarSide,
      thumbVisibility: widget.thumbVisibility,
      contentInset: widget.scrollbarSide == ScrollbarOrientation.right
          ? padding.right
          : padding.left,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}
