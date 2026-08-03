import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// דיאלוג לאימות סיסמה במצב סייפר
class SaferModePasswordDialog extends StatefulWidget {
  final Future<bool> Function(String password) onVerify;
  final String title;
  final String? hint;

  const SaferModePasswordDialog({
    super.key,
    required this.onVerify,
    this.title = 'הזן סיסמה',
    this.hint,
  });

  @override
  State<SaferModePasswordDialog> createState() =>
      _SaferModePasswordDialogState();
}

class _SaferModePasswordDialogState extends State<SaferModePasswordDialog>
    with
        DialogNavigationMixin,
        DialogFocusRestorerMixin<SaferModePasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();
  bool _isObscured = true;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    registerDialogFocusRestorer(_textFieldFocusNode);
    // תן פוקוס לשדה הטקסט אחרי שהדיאלוג נפתח
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFieldFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _textFieldFocusNode.dispose();
    _cancelFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (_passwordController.text.isEmpty) {
      UiSnack.showError(SettingsMessages.passwordRequired);
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
        UiSnack.showError(SettingsMessages.wrongPassword);
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
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const Icon(FluentIcons.lock_closed_24_regular),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 20),
            ),
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
                  labelText: context.settingsText('סיסמה'),
                  hintText: context.settingsText('הזן את הסיסמה'),
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
          ActionButton.neutral(
            text: context.settingsText('ביטול'),
            focusNode: _cancelFocusNode,
            onPressed: !_isVerifying
                ? () => Navigator.of(context).pop(false)
                : null,
          ),
          ActionButton.recommended(
            text: context.settingsText('אישור'),
            focusNode: _confirmFocusNode,
            onPressed: !_isVerifying ? _handleVerify : null,
            isLoading: _isVerifying,
          ),
        ],
      ),
    );
  }
}

/// דיאלוג להגדרת סיסמה למצב סייפר — הגדרה, שינוי, או הסרה
class SaferModeSetPasswordDialog extends StatefulWidget {
  final Future<void> Function(String password) onSetPassword;
  final Future<void> Function()? onClearPassword;

  /// כשמצב הסייפר פעיל אי אפשר להסיר את הסיסמה - יש להשבית אותו קודם.
  final bool isSaferModeEnabled;

  const SaferModeSetPasswordDialog({
    super.key,
    required this.onSetPassword,
    this.onClearPassword,
    this.isSaferModeEnabled = false,
  });

  @override
  State<SaferModeSetPasswordDialog> createState() =>
      _SaferModeSetPasswordDialogState();
}

class _SaferModeSetPasswordDialogState extends State<SaferModeSetPasswordDialog>
    with
        DialogNavigationMixin,
        DialogFocusRestorerMixin<SaferModeSetPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();
  final FocusNode _saveButtonFocusNode = FocusNode();
  bool _isObscured1 = true;
  bool _isObscured2 = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    registerDialogFocusRestorer(_passwordFocusNode);
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
    _cancelButtonFocusNode.dispose();
    _saveButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_passwordController.text.isEmpty) {
      UiSnack.showError(SettingsMessages.passwordRequired);
      return;
    }

    if (_passwordController.text.length < 4) {
      UiSnack.showError(SettingsMessages.passwordTooShort);
      return;
    }

    if (_passwordController.text != _confirmController.text) {
      UiSnack.showError(SettingsMessages.passwordsDoNotMatch);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onSetPassword(_passwordController.text);

      if (!mounted) return;

      UiSnack.show(SettingsMessages.passwordSaved);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.passwordSaveError(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _handleClear() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('הסרת סיסמה'),
      content: context.settingsText('לא תידרש עוד סיסמה לגישה להגדרות.'),
      confirmText: context.settingsText('הסר סיסמה'),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onClearPassword!();
      if (!mounted) return;
      UiSnack.show(SettingsMessages.passwordRemoved);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.passwordRemoveError(e));
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
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              context.settingsText('הגדרת סיסמה'),
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
              Text(
                context.settingsText('הגדר סיסמה להגנה על ההגדרות'),
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
                  labelText: context.settingsText('סיסמה חדשה'),
                  hintText: context.settingsText('לפחות 4 תווים'),
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
                  labelText: context.settingsText('אימות סיסמה'),
                  hintText: context.settingsText('הזן שוב את הסיסמה'),
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
              if (widget.onClearPassword != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ActionButton.ghost(
                    text: widget.isSaferModeEnabled
                        ? context.settingsText(
                            'לא ניתן למחוק את הסיסמה כשמצב סייפר פעיל',
                          )
                        : context.settingsText('מחיקת סיסמה'),
                    onPressed: (!_isSaving && !widget.isSaferModeEnabled)
                        ? _handleClear
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          ActionButton.neutral(
            text: 'ביטול',
            focusNode: _cancelButtonFocusNode,
            onPressed: !_isSaving
                ? () => Navigator.of(context).pop(false)
                : null,
          ),
          ActionButton.recommended(
            text: context.settingsText('שמור'),
            focusNode: _saveButtonFocusNode,
            onPressed: !_isSaving ? _handleSave : null,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }
}
