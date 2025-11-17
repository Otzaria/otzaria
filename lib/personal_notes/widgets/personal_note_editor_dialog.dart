import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PersonalNoteEditorDialog extends StatefulWidget {
  final TextEditingController controller;
  final String title;

  PersonalNoteEditorDialog({
    super.key,
    TextEditingController? controller,
    this.title = 'הערה חדשה',
  }) : controller = controller ?? TextEditingController();

  @override
  State<PersonalNoteEditorDialog> createState() =>
      _PersonalNoteEditorDialogState();
}

class _PersonalNoteEditorDialogState extends State<PersonalNoteEditorDialog> {
  int _focusedButtonIndex = 1; // 0 = ביטול, 1 = שמור (ברירת מחדל)
  final FocusNode _textFieldFocusNode = FocusNode();
  String _initialText = '';
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _initialText = widget.controller.text;
    widget.controller.addListener(_checkForChanges);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFieldFocusNode.requestFocus();
    });
  }

  void _checkForChanges() {
    final hasChanges = widget.controller.text.trim() != _initialText.trim() &&
        widget.controller.text.trim().isNotEmpty;
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_checkForChanges);
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  Future<bool> _confirmClose() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('אזהרה'),
        content: const Text('ההערה לא נשמרה, לסגור?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('סגור'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _handleCancel() async {
    if (await _confirmClose()) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }

        // Alt + Enter - שליחת הטופס מכל מקום
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isAltPressed) {
          _submit();
          return KeyEventResult.handled;
        }

        // אם הפוקוס בשדה הטקסט, אנטר רגיל עושה ירידת שורה
        if (_textFieldFocusNode.hasFocus) {
          return KeyEventResult.ignored;
        }

        // אם הפוקוס בכפתורים - חיצים ואנטר
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _focusedButtonIndex = _focusedButtonIndex == 0 ? 1 : 0;
          });
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (_focusedButtonIndex == 1) {
            _submit();
          } else {
            _handleCancel();
          }
          return KeyEventResult.handled;
        }

        // Escape - ביטול
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _handleCancel();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleCancel();
        },
        child: AlertDialog(
          title: Text(widget.title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: TextField(
              controller: widget.controller,
              focusNode: _textFieldFocusNode,
              minLines: 5,
              maxLines: 12,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'כתבו כאן את ההערה האישית\n(Alt+Enter לשמירה)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            _buildButton(
              text: 'ביטול',
              isFocused: _focusedButtonIndex == 0,
              onPressed: _handleCancel,
            ),
            _buildButton(
              text: 'שמור',
              isFocused: _focusedButtonIndex == 1,
              isConfirm: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required bool isFocused,
    required VoidCallback onPressed,
    bool isConfirm = false,
  }) {
    final showHover = isFocused && !_textFieldFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.9)
              : null,
        ),
        child: Text(text),
      );
    } else {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
              : null,
        ),
        child: Text(text),
      );
    }
  }
}
