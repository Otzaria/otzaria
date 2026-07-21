// lib/widgets/layout/panel_scrollable_content.dart
//
// [PanelScrollableContent] — אזור תוכן גלילה עם Scrollbar מצמוד לקצה.
//
// פטרן משותף לדיאלוגים ופאנלים:
//  • Scrollbar מתפרס עד לגבול ה-widget (הקורא לא מוסיף padding אופקי כלפי חוץ)
//  • crossAxisMargin: 2 — זהה ל-adaptive_side_pane, מרחק מקסימלי מהתוכן
//  • [padding] מוחל בתוך ה-SingleChildScrollView — כולל המרווח לצד הגלילה
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

class PanelScrollableContent extends StatefulWidget {
  /// תוכן הגלילה.
  final Widget child;

  /// padding שיוחל בתוך ה-SingleChildScrollView.
  /// ברירת מחדל: 16px אופקי — שמרחק זה הוא גם המרווח שמפריד בין הגלילה לתוכן.
  final EdgeInsetsGeometry padding;

  /// מציג את פס הגלילה בצד ההפוך לכיוון הקריאה (ימין ב-RTL).
  /// נדרש כשהקצה הטבעי של הגלילה מתנגש עם ידית שינוי-גודל של הפאנל.
  final bool scrollbarOnOppositeSide;

  const PanelScrollableContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.scrollbarOnOppositeSide = false,
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
    // מכבים את ה-Scrollbar האוטומטי של ScrollBehavior כדי שיישאר רק המפורש,
    // אחרת בהיפוך הצד מתקבל פס כפול (מפורש בצד אחד, אוטומטי בשני).
    final scrollView = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: widget.padding,
        child: widget.child,
      ),
    );

    // crossAxisMargin:2 — זהה ל-adaptive_side_pane; צמוד לגבול עם רווח קל.
    return ScrollbarTheme(
      data: const ScrollbarThemeData(crossAxisMargin: 2),
      child: widget.scrollbarOnOppositeSide
          ? _buildOppositeSideScrollbar(context, scrollView)
          : Scrollbar(controller: _scrollController, child: scrollView),
    );
  }

  /// היפוך כיוון ה-Scrollbar בלבד כדי להצמידו לצד השני, תוך שמירת כיוון התוכן.
  Widget _buildOppositeSideScrollbar(BuildContext context, Widget scrollView) {
    final contentDirection = Directionality.of(context);
    final scrollbarDirection = contentDirection == TextDirection.rtl
        ? TextDirection.ltr
        : TextDirection.rtl;
    return Directionality(
      textDirection: scrollbarDirection,
      child: Scrollbar(
        controller: _scrollController,
        child: Directionality(
          textDirection: contentDirection,
          child: scrollView,
        ),
      ),
    );
  }
}
