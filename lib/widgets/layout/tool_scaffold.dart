import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

/// מעטפת למסכי כלים שנבנים סביב שדה חיפוש (מילונים, ביוגרפיות, גימטריה,
/// שמור וזכור): סרגל עליון, [filters] מתחתיו, גוף ו-[footer].
///
/// הסרגל נשאר גם בטעינה ובשגיאת טעינה: [loading] מחליף את הגוף בספינר,
/// ו-[loadError] בהודעת שגיאה עם "נסה שוב" ([onRetry]).
class ToolScaffold extends StatelessWidget {
  const ToolScaffold({
    super.key,
    required this.topBar,
    required this.body,
    this.filters,
    this.footer,
    this.loading = false,
    this.loadError,
    this.onRetry,
    this.onSearchShortcut,
    this.searchShortcut,
    this.centerContent = true,
  }) : assert(
         onSearchShortcut == null || searchShortcut != null,
         'onSearchShortcut צריך searchShortcut',
       );

  /// בדרך כלל `AppTopBar` עם `OtzariaSearchField`.
  final Widget topBar;

  final Widget body;

  /// שורות מסננים ברוחב המסך, מתחת לסרגל. מוסתרות בטעינה ובשגיאה.
  final Widget? filters;

  /// שורה בתחתית המסך (למשל קרדיט). מוסתרת בטעינה ובשגיאה.
  final Widget? footer;

  final bool loading;

  /// כותרת הודעת השגיאה כשטעינת נתוני הכלי נכשלה.
  final String? loadError;

  final VoidCallback? onRetry;

  /// נקרא ב-[searchShortcut] (בדרך כלל "חפש בחלון" מההגדרות,
  /// `currentWindowSearchActivator`). null: המסך מטפל בקיצור בעצמו.
  final VoidCallback? onSearchShortcut;
  final ShortcutActivator? searchShortcut;

  /// מרכוז הגוף והגבלת רוחבו ([ToolPanelWrapper]).
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    final ready = !loading && loadError == null;
    final Widget content = loading
        ? const LoadingIndicator()
        : loadError != null
        ? OtzariaErrorState(
            title: loadError!,
            actions: onRetry == null
                ? null
                : [
                    ActionButton.recommended(
                      text: 'נסה שוב',
                      icon: FluentIcons.arrow_clockwise_24_regular,
                      onPressed: onRetry,
                    ),
                  ],
          )
        : body;

    final column = Column(
      children: [
        topBar,
        if (ready && filters != null) filters!,
        Expanded(
          child: ToolPanelWrapper(
            centerContent: centerContent || !ready,
            child: content,
          ),
        ),
        if (ready && footer != null) footer!,
      ],
    );

    final shortcut = onSearchShortcut;
    final activator = searchShortcut;
    if (shortcut == null || activator == null) return column;
    return CallbackShortcuts(
      bindings: {activator: shortcut},
      child: column,
    );
  }
}
