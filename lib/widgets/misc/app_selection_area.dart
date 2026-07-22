import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

/// אזור בחירת טקסט שמציג בלחיצה ימנית את תפריט ההקשר של אוצריא
/// (במקום תפריט ברירת המחדל של Flutter). לתוכן קריא כללי —
/// דיאלוגים, חלוניות וכותרות.
class AppSelectionArea extends StatefulWidget {
  const AppSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  State<AppSelectionArea> createState() => _AppSelectionAreaState();
}

class _AppSelectionAreaState extends State<AppSelectionArea> {
  String? _selectedText;

  bool get _hasSelection =>
      _selectedText != null && _selectedText!.trim().isNotEmpty;

  Future<void> _copySelection() async {
    if (!_hasSelection) return;
    await Clipboard.setData(ClipboardData(text: _selectedText!));
    UiSnack.show(CommonMessages.textCopiedShort);
  }

  @override
  Widget build(BuildContext context) {
    return RtlSelectionShortcuts(
      child: SelectionArea(
        contextMenuBuilder: (context, _) => const SizedBox.shrink(),
        onSelectionChanged: (selection) {
          trackRtlSelection(selection?.plainText);
          // שינוי בחירה זמני בזמן priming (קיצורי RTL) — לא לעבד.
          if (rtlSelectionPriming) return;
          _selectedText = selection?.plainText;
        },
        child: AppContextMenuRegion(
          // לחיצה ימנית על הטקסט המסומן לא תשחרר את הבחירה (ברירת המחדל של
          // SelectableRegion ב-Windows); לחיצה מחוץ לבחירה מבטלת כרגיל.
          shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
            if (!_hasSelection) return false;
            final root = context.findRenderObject();
            if (root == null) return true;
            return clickIsOnSelectionWithinArea(
                  root: root,
                  globalPosition: globalPosition,
                  selectedText: _selectedText!,
                ) ??
                true;
          },
          menuBuilder: (menuContext, _) => [
            AppContextMenuEntry(
              label: 'העתק',
              icon: FluentIcons.copy_24_regular,
              enabled: _hasSelection,
              onTap: _copySelection,
            ),
          ],
          child: widget.child,
        ),
      ),
    );
  }
}
