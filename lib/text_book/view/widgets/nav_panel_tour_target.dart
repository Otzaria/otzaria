import 'package:flutter/material.dart';

/// חלונית הניווט של טאב הטקסט הפעיל, כיעד להדגשה בסיור המודרך.
///
/// כל הטאבים הפתוחים חיים בעץ במקביל, ולכן אי-אפשר להצמיד מפתח גלובלי אחד
/// לכולם — הטאב הפעיל מפרסם כאן את המפתח שלו.
GlobalKey? activeTextBookNavPanelTourTargetKey;

/// עוטף את חלונית הניווט של ספר טקסט במפתח יציב, ומפרסם אותו כיעד לסיור
/// המודרך כל עוד [isActiveTab] נכון.
///
/// עטיפה שמתווספת ונעלמת לפי [isActiveTab] הייתה מחליפה את מבנה העץ באותו
/// מקום, ו-Flutter משמיד אז את כל תת-העץ — החיפוש והניווט אובדים בכל מעבר טאב.
class TextBookNavPanelTourTarget extends StatefulWidget {
  /// האם זה הטאב הפעיל, כלומר זו החלונית שהסיור המודרך צריך להדגיש.
  final bool isActiveTab;

  final Widget child;

  const TextBookNavPanelTourTarget({
    super.key,
    required this.isActiveTab,
    required this.child,
  });

  @override
  State<TextBookNavPanelTourTarget> createState() =>
      _TextBookNavPanelTourTargetState();
}

class _TextBookNavPanelTourTargetState
    extends State<TextBookNavPanelTourTarget> {
  final GlobalKey _paneKey = GlobalKey(
    debugLabel: 'text_book_nav_panel_tour_target',
  );

  @override
  void initState() {
    super.initState();
    _syncTourTarget();
  }

  @override
  void didUpdateWidget(covariant TextBookNavPanelTourTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTourTarget();
  }

  @override
  void dispose() {
    if (activeTextBookNavPanelTourTargetKey == _paneKey) {
      activeTextBookNavPanelTourTargetKey = null;
    }
    super.dispose();
  }

  /// הניקוי מותנה בבעלות על הפרסום, כדי שלא יימחק פרסום של טאב אחר — הטאב
  /// הנכנס והיוצא מתעדכנים באותו frame ובסדר לא מובטח.
  void _syncTourTarget() {
    if (widget.isActiveTab) {
      activeTextBookNavPanelTourTargetKey = _paneKey;
    } else if (activeTextBookNavPanelTourTargetKey == _paneKey) {
      activeTextBookNavPanelTourTargetKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _paneKey, child: widget.child);
  }
}
