import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כפתור פתיחה בתוכנה חיצונית שפתיחתה איטית (בר אילן: 3–25 שניות).
///
/// הכפתור ננעל בזמן הפתיחה ומציג מצב טעינה. אין כאן "ביטול": הוא ייווסף
/// רק כשהוא באמת יעצור את הפעולה, ולא כדי להסתיר את מחוון הטעינה.
///
/// משותף לדיאלוג פרטי הספר ולתצוגה המקדימה. בתצוגה המקדימה היה קודם
/// כפתור "פתח בעיון" שקרא למסלול הפתיחה המקומי, ולכן **לא עשה דבר**
/// לספר חיצוני.
class ExternalOpenButton extends StatefulWidget {
  final ExternalLibraryBook book;

  /// מחזיר `null` בהצלחה, או הודעת שגיאה מלאה למשתמש.
  final Future<String?> Function(ExternalLibraryBook book) onOpen;

  /// הכיתוב על הכפתור, מהספק. "פתח בבר אילן" אומר למשתמש מה יקרה;
  /// "פתח בתוכנה" משאיר אותו לנחש איזו.
  final String label;

  /// נקרא אחרי פתיחה מוצלחת — בדיאלוג זו סגירתו.
  final VoidCallback? onOpened;

  const ExternalOpenButton({
    super.key,
    required this.book,
    required this.onOpen,
    required this.label,
    this.onOpened,
  });

  @override
  State<ExternalOpenButton> createState() => _ExternalOpenButtonState();
}

class _ExternalOpenButtonState extends State<ExternalOpenButton> {
  bool _isOpening = false;

  @override
  Widget build(BuildContext context) {
    return ActionButton.recommended(
      text: _isOpening ? 'פותח...' : widget.label,
      icon: FluentIcons.desktop_24_regular,
      isLoading: _isOpening,
      onPressed: _isOpening ? null : _open,
    );
  }

  Future<void> _open() async {
    setState(() => _isOpening = true);
    String? error;
    try {
      error = await widget.onOpen(widget.book);
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
    if (!mounted) return;
    if (error == null) {
      widget.onOpened?.call();
    } else {
      UiSnack.showError(error);
    }
  }
}
