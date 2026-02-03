import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// TextField מותאם אישית עם תמיכה מלאה ב-RTL
///
/// מתקן בעיות ידועות ב-Flutter Desktop עם RTL:
/// 1. מקשי החיצים פועלים הפוך (כולל Shift+חיצים)
/// 2. Collapse של Selection בכיוון הנכון
/// 3. נראות מיידית של הסמן בניווט
/// 4. תפריט ההקשר המובנה לא מתאים
/// 5. בעיית autofocus באנדרואיד (המקלדת קופצת ונעלמת)
class RtlTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final TextStyle? style;
  final TextAlign textAlign;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;

  const RtlTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.style,
    this.textAlign = TextAlign.start,
    this.inputFormatters,
    this.obscureText = false,
  });

  @override
  State<RtlTextField> createState() => _RtlTextFieldState();
}

class _RtlTextFieldState extends State<RtlTextField> {
  Timer? _blinkIdleTimer;
  EditableTextState? _editableTextState;
  late TextEditingController _effectiveController;

  // משך הזמן עד הפסקת הבהוב (כמו ב-Word)
  static const Duration _blinkIdleTimeout = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();

    // יצירת controller פנימי אם לא סופק
    _effectiveController = widget.controller ?? TextEditingController();

    // תיקון לבעיית autofocus באנדרואיד
    // במקום להשתמש ב-autofocus: true ישירות, נבקש פוקוס אחרי שהמסך נבנה
    if (widget.autofocus && widget.focusNode != null && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.focusNode != null) {
          widget.focusNode!.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(RtlTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון controller אם השתנה
    if (widget.controller != oldWidget.controller) {
      _effectiveController = widget.controller ?? TextEditingController();
    }
  }

  @override
  void dispose() {
    _blinkIdleTimer?.cancel();
    // נקה controller רק אם יצרנו אותו
    if (widget.controller == null) {
      _effectiveController.dispose();
    }
    super.dispose();
  }

  /// מאפס את הבהוב הסמן ומציג אותו מיד
  void _resetCaretBlink() {
    if (_editableTextState != null && _editableTextState!.mounted) {
      try {
        // מציג את הסמן מיד
        _editableTextState!.renderEditable.showCursor.value = true;

        // מאפס את טיימר ה-idle
        _blinkIdleTimer?.cancel();
        _blinkIdleTimer = Timer(_blinkIdleTimeout, () {
          if (_editableTextState != null && _editableTextState!.mounted) {
            // עוצר את ההבהוב על ידי שמירת הסמן גלוי קבוע
            // אין לנו גישה ישירה ל-blink timer, אז נשתמש בגישה אחרת:
            // נשמור reference ל-ValueNotifier ונעדכן אותו כל הזמן
            _keepCursorVisible();
          }
        });
      } catch (e) {
        // אם יש שגיאה, פשוט נמשיך
      }
    }
  }

  /// שומר את הסמן גלוי קבוע (מפסיק הבהוב)
  void _keepCursorVisible() {
    if (_editableTextState != null && _editableTextState!.mounted) {
      final showCursor = _editableTextState!.renderEditable.showCursor;

      // מוסיף listener שמוודא שהסמן תמיד גלוי
      void keepVisible() {
        if (showCursor.value == false) {
          showCursor.value = true;
        }
      }

      // מוסיף את ה-listener
      showCursor.addListener(keepVisible);

      // מוודא שהסמן גלוי עכשיו
      showCursor.value = true;

      // מסיר את ה-listener אחרי 100ms (כדי לא להשאיר אותו לנצח)
      // זה מספיק כדי לעצור את ההבהוב הנוכחי
      Future.delayed(const Duration(milliseconds: 100), () {
        showCursor.removeListener(keepVisible);
        // מוודא שהסמן נשאר גלוי
        if (_editableTextState != null && _editableTextState!.mounted) {
          showCursor.value = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRtl = Directionality.of(context) == TextDirection.rtl;

    // באנדרואיד, לא משתמשים ב-autofocus ישירות אלא דרך requestFocus ב-initState
    final shouldUseAutofocus =
        widget.autofocus && (widget.focusNode == null || !Platform.isAndroid);

    Widget textField = TextField(
      controller: _effectiveController,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: shouldUseAutofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      enabled: widget.enabled,
      style: widget.style,
      textAlign: widget.textAlign,
      inputFormatters: widget.inputFormatters,
      obscureText: widget.obscureText,
      contextMenuBuilder: (context, editableTextState) {
        // שמירת reference ל-EditableTextState לצורך reset blink
        _editableTextState = editableTextState;
        // השבתת תפריט ההקשר המובנה
        return const SizedBox.shrink();
      },
    );

    // עטיפה בתיקון חיצים אם RTL
    // שימוש ב-CallbackShortcuts כדי להבטיח קדימות על פני ה-TextField
    if (isRtl) {
      textField = CallbackShortcuts(
        bindings: {
          // חיצים רגילים (ללא Shift)
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _handleArrowKey(isVisualRight: false, extendSelection: false),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _handleArrowKey(isVisualRight: true, extendSelection: false),

          // Shift+חיצים
          const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
              () =>
                  _handleArrowKey(isVisualRight: false, extendSelection: true),
          const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
              () => _handleArrowKey(isVisualRight: true, extendSelection: true),
        },
        child: textField,
      );
    }

    // עטיפה בטיפול בתפריט הקשר
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 2) {
          _showContextMenu(context, event.position, _effectiveController);
        }
      },
      child: textField,
    );
  }

  /// מטפל בלחיצת חץ עם תמיכה מלאה ב-RTL
  ///
  /// [isVisualRight] - האם המקש שנלחץ הוא חץ ימין (ויזואלית)
  /// [extendSelection] - האם להרחיב בחירה (Shift לחוץ)
  void _handleArrowKey({
    required bool isVisualRight,
    required bool extendSelection,
  }) {
    final text = _effectiveController.text;
    final selection = _effectiveController.selection;

    // מאפס את הבהוב ומציג את הסמן מיד
    _resetCaretBlink();

    // לוגיקה ל-RTL:
    // אינדקס 0 נמצא בצד ימין (תחילת הטקסט). אינדקס מקסימלי בצד שמאל (סוף הטקסט).
    // חץ ימינה (Visual Right) -> מקטין אינדקס (נע לקראת ההתחלה, offset נמוך יותר).
    // חץ שמאלה (Visual Left) -> מגדיל אינדקס (נע לקראת הסוף, offset גבוה יותר).

    // טיפול ב-Selection Collapse (ללא Shift)
    if (!extendSelection && selection.isValid && !selection.isCollapsed) {
      final int targetOffset;
      if (isVisualRight) {
        // חץ ימינה -> רוצים להגיע לקצה הימני של הבחירה
        // ב-RTL הקצה הימני הוא ה-Index הנמוך יותר (start)
        targetOffset = selection.start;
      } else {
        // חץ שמאלה -> רוצים להגיע לקצה השמאלי של הבחירה
        // ב-RTL הקצה השמאלי הוא ה-Index הגבוה יותר (end)
        targetOffset = selection.end;
      }
      _effectiveController.selection =
          TextSelection.collapsed(offset: targetOffset);
      return;
    }

    // חישוב תזוזה רגילה
    final int currentOffset =
        extendSelection ? selection.extentOffset : selection.baseOffset;

    // ב-RTL: ימינה = הקטנת אינדקס (-1), שמאלה = הגדלת אינדקס (+1)
    final int offsetChange = isVisualRight ? -1 : 1;
    final int newOffset = (currentOffset + offsetChange).clamp(0, text.length);

    if (extendSelection) {
      // מרחיבים/מצמצמים את הבחירה
      // base נשאר קבוע, extent זז
      _effectiveController.selection = TextSelection(
        baseOffset: selection.baseOffset,
        extentOffset: newOffset,
      );
    } else {
      // ניווט רגיל - collapsed selection
      _effectiveController.selection =
          TextSelection.collapsed(offset: newOffset);
    }
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    TextEditingController controller,
  ) {
    final selection = controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    List<PopupMenuEntry<String>> menuItems = [];

    if (hasSelection) {
      menuItems.addAll([
        _buildMenuItem(
          context,
          'cut',
          'גזור',
          FluentIcons.cut_24_regular,
        ),
        _buildMenuItem(
          context,
          'copy',
          'העתק',
          FluentIcons.copy_24_regular,
        ),
      ]);
    }

    menuItems.add(_buildMenuItem(
      context,
      'paste',
      'הדבק',
      FluentIcons.clipboard_paste_24_regular,
    ));

    if (controller.text.isNotEmpty) {
      menuItems.addAll([
        const PopupMenuDivider(height: 8),
        _buildMenuItem(
          context,
          'selectAll',
          'בחר הכל',
          FluentIcons.select_all_on_24_regular,
        ),
      ]);
    }

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: menuItems,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: Theme.of(context).colorScheme.surface,
    ).then((value) async {
      if (value == null) return;

      // שיפור: טיפול במצב שבו הטקסט השתנה בזמן שהתפריט היה פתוח
      final currentText = controller.text;
      final currentSelection = controller.selection;

      // ודא שהבחירה עדיין חוקית
      if (currentSelection.end > currentText.length) return;

      switch (value) {
        case 'cut':
          final selectedText = currentText.substring(
              currentSelection.start, currentSelection.end);
          await Clipboard.setData(ClipboardData(text: selectedText));
          controller.text = currentText.substring(0, currentSelection.start) +
              currentText.substring(currentSelection.end);
          controller.selection =
              TextSelection.collapsed(offset: currentSelection.start);
          break;
        case 'copy':
          final selectedText = currentText.substring(
              currentSelection.start, currentSelection.end);
          await Clipboard.setData(ClipboardData(text: selectedText));
          break;
        case 'paste':
          final data = await Clipboard.getData('text/plain');
          if (data?.text != null) {
            final newText = currentText.substring(0, currentSelection.start) +
                data!.text! +
                currentText.substring(currentSelection.end);
            controller.text = newText;
            controller.selection = TextSelection.collapsed(
                offset: currentSelection.start + data.text!.length);
          }
          break;
        case 'selectAll':
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: currentText.length,
          );
          break;
      }
    });
  }

  PopupMenuItem<String> _buildMenuItem(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
