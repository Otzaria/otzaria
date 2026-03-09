import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/mixins/dialog_navigation_mixin.dart';

/// דיאלוג לאימות סיסמה למצב מוגן
class PasswordVerificationDialog extends StatefulWidget {
  final Future<bool> Function(String password) onVerify;
  final String title;
  final String? hint;

  const PasswordVerificationDialog({
    super.key,
    required this.onVerify,
    this.title = 'הזן סיסמה',
    this.hint,
  });

  @override
  State<PasswordVerificationDialog> createState() =>
      _PasswordVerificationDialogState();
}

class _PasswordVerificationDialogState extends State<PasswordVerificationDialog>
    with DialogNavigationMixin {
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  bool _isObscured = true;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();

    // תן פוקוס לשדה הטקסט אחרי שהדיאלוג נפתח
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (_passwordController.text.isEmpty) {
      UiSnack.showError('נא להזין סיסמה');
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      final isValid = await widget.onVerify(_passwordController.text);

      if (!mounted) return;

      if (isValid) {
        Navigator.of(context).pop(true);
      } else {
        UiSnack.showError('סיסמה שגויה');
        _passwordController.clear();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildKeyboardNavigator(
      onConfirm: _handleVerify,
      onCancel: () => Navigator.of(context).pop(false),
      textFieldFocusNode: _textFieldFocusNode,
      child: AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              widget.title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            const Icon(FluentIcons.lock_closed_24_regular),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.hint != null) ...[
                Text(
                  widget.hint!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              RtlTextField(
                controller: _passwordController,
                focusNode: _textFieldFocusNode,
                obscureText: _isObscured,
                enabled: !_isVerifying,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'סיסמה',
                  hintText: 'הזן את הסיסמה',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.key_24_regular),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscured
                          ? FluentIcons.eye_24_regular
                          : FluentIcons.eye_off_24_regular,
                    ),
                    onPressed: () {
                      setState(() {
                        _isObscured = !_isObscured;
                      });
                    },
                  ),
                ),
                onSubmitted: (_) => _handleVerify(),
              ),
            ],
          ),
        ),
        actions: [
          _buildButton(
            text: 'ביטול',
            isFocused: focusedButtonIndex == 0,
            onPressed: () => Navigator.of(context).pop(false),
            enabled: !_isVerifying,
          ),
          _buildButton(
            text: 'אישור',
            isFocused: focusedButtonIndex == 1,
            isConfirm: true,
            onPressed: _handleVerify,
            enabled: !_isVerifying,
            isLoading: _isVerifying,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required bool isFocused,
    required VoidCallback onPressed,
    required bool enabled,
    bool isConfirm = false,
    bool isLoading = false,
  }) {
    final showHover = isFocused && !_textFieldFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.9)
              : null,
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(text),
      );
    } else {
      return TextButton(
        onPressed: enabled ? onPressed : null,
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

/// דיאלוג להגדרת סיסמה חדשה
class SetPasswordDialog extends StatefulWidget {
  final Future<void> Function(String password) onSetPassword;

  const SetPasswordDialog({
    super.key,
    required this.onSetPassword,
  });

  @override
  State<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<SetPasswordDialog>
    with DialogNavigationMixin {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();
  bool _isObscured1 = true;
  bool _isObscured2 = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // תן פוקוס לשדה הראשון אחרי שהדיאלוג נפתח
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passwordFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_passwordController.text.isEmpty) {
      UiSnack.showError('נא להזין סיסמה');
      return;
    }

    if (_passwordController.text.length < 4) {
      UiSnack.showError('הסיסמה חייבת להכיל לפחות 4 תווים');
      return;
    }

    if (_passwordController.text != _confirmController.text) {
      UiSnack.showError('הסיסמאות אינן תואמות');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onSetPassword(_passwordController.text);

      if (!mounted) return;

      UiSnack.show('הסיסמה נשמרה בהצלחה');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError('שגיאה בשמירת הסיסמה: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildKeyboardNavigator(
      onConfirm: _handleSave,
      onCancel: () => Navigator.of(context).pop(false),
      textFieldFocusNode: _passwordFocusNode,
      child: AlertDialog(
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'הגדרת סיסמה',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(width: 8),
            Icon(FluentIcons.lock_closed_24_regular),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'הגדר סיסמה להגנה על ההגדרות',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              RtlTextField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: _isObscured1,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: 'סיסמה חדשה',
                  hintText: 'לפחות 4 תווים',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.key_24_regular),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscured1
                          ? FluentIcons.eye_24_regular
                          : FluentIcons.eye_off_24_regular,
                    ),
                    onPressed: () {
                      setState(() {
                        _isObscured1 = !_isObscured1;
                      });
                    },
                  ),
                ),
                onSubmitted: (_) => _confirmFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              RtlTextField(
                controller: _confirmController,
                focusNode: _confirmFocusNode,
                obscureText: _isObscured2,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: 'אימות סיסמה',
                  hintText: 'הזן שוב את הסיסמה',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(FluentIcons.checkmark_lock_24_regular),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscured2
                          ? FluentIcons.eye_24_regular
                          : FluentIcons.eye_off_24_regular,
                    ),
                    onPressed: () {
                      setState(() {
                        _isObscured2 = !_isObscured2;
                      });
                    },
                  ),
                ),
                onSubmitted: (_) => _handleSave(),
              ),
            ],
          ),
        ),
        actions: [
          _buildButton(
            text: 'ביטול',
            isFocused: focusedButtonIndex == 0,
            onPressed: () => Navigator.of(context).pop(false),
            enabled: !_isSaving,
          ),
          _buildButton(
            text: 'שמור',
            isFocused: focusedButtonIndex == 1,
            isConfirm: true,
            onPressed: _handleSave,
            enabled: !_isSaving,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required bool isFocused,
    required VoidCallback onPressed,
    required bool enabled,
    bool isConfirm = false,
    bool isLoading = false,
  }) {
    final showHover = isFocused &&
        !_passwordFocusNode.hasFocus &&
        !_confirmFocusNode.hasFocus;

    if (isConfirm) {
      return FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: showHover
              ? Theme.of(context).primaryColor.withValues(alpha: 0.9)
              : null,
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(text),
      );
    } else {
      return TextButton(
        onPressed: enabled ? onPressed : null,
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
