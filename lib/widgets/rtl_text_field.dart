import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// TextField מותאם אישית עם תמיכה מלאה ב-RTL
///
/// מתקן שתי בעיות ידועות ב-Flutter Desktop עם RTL:
/// 1. מקשי החיצים פועלים הפוך
/// 2. תפריט ההקשר המובנה לא מתאים
/// 3. בעיית autofocus באנדרואיד (המקלדת קופצת ונעלמת)
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
  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final effectiveController = widget.controller ?? TextEditingController();
    final bool isRtl = Directionality.of(context) == TextDirection.rtl;

    // באנדרואיד, לא משתמשים ב-autofocus ישירות אלא דרך requestFocus ב-initState
    final shouldUseAutofocus =
        widget.autofocus && (widget.focusNode == null || !Platform.isAndroid);

    Widget textField = TextField(
      controller: effectiveController,
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
        // השבתת תפריט ההקשר המובנה
        return const SizedBox.shrink();
      },
    );

    // עטיפה בתיקון חיצים אם RTL
    if (isRtl) {
      textField = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            _moveCursor(effectiveController, 1);
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            _moveCursor(effectiveController, -1);
          },
        },
        child: textField,
      );
    }

    // עטיפה בטיפול בתפריט הקשר
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 2) {
          _showContextMenu(context, event.position, effectiveController);
        }
      },
      child: textField,
    );
  }

  void _moveCursor(TextEditingController controller, int offsetChange) {
    final text = controller.text;
    final selection = controller.selection;
    final newOffset =
        (selection.baseOffset + offsetChange).clamp(0, text.length);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newOffset),
    );
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

      switch (value) {
        case 'cut':
          final text = controller.text;
          final selectedText = text.substring(selection.start, selection.end);
          await Clipboard.setData(ClipboardData(text: selectedText));
          controller.text = text.substring(0, selection.start) +
              text.substring(selection.end);
          controller.selection =
              TextSelection.collapsed(offset: selection.start);
          break;
        case 'copy':
          final text = controller.text;
          final selectedText = text.substring(selection.start, selection.end);
          await Clipboard.setData(ClipboardData(text: selectedText));
          break;
        case 'paste':
          final data = await Clipboard.getData('text/plain');
          if (data?.text != null) {
            final text = controller.text;
            final newText = text.substring(0, selection.start) +
                data!.text! +
                text.substring(selection.end);
            controller.text = newText;
            controller.selection = TextSelection.collapsed(
                offset: selection.start + data.text!.length);
          }
          break;
        case 'selectAll':
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
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
