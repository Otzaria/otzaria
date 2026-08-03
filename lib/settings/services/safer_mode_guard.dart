import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';

/// Wrapper שבודק סיסמה לפני כניסה למסך מוגן במצב סייפר
class SaferModeGuard extends StatefulWidget {
  final Widget child;

  const SaferModeGuard({
    super.key,
    required this.child,
  });

  @override
  State<SaferModeGuard> createState() => _SaferModeGuardState();
}

class _SaferModeGuardState extends State<SaferModeGuard> {
  bool _isVerified = false;
  bool _isChecking = true;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // נשתמש ב-postFrameCallback כדי לוודא שה-context מוכן
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkProtection();
      }
    });
  }

  void _checkProtection() {
    // נבדוק אם מצב סייפר מופעל
    final state = context.read<SettingsBloc>().state;
    final repository = context.read<SettingsRepository>();

    if (!state.protectedModeEnabled || !repository.hasProtectedModePassword()) {
      // אין הגנה - נאפשר גישה ישירה
      if (mounted) {
        setState(() {
          _isVerified = true;
          _isChecking = false;
        });
      }
    } else {
      // יש הגנה - נדרוש אימות
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
        if (!_dialogShown) {
          _dialogShown = true;
          _showPasswordDialog();
        }
      }
    }
  }

  Future<void> _showPasswordDialog() async {
    if (!mounted) return;

    final repository = context.read<SettingsRepository>();

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => SaferModePasswordDialog(
        title: context.settingsText('הזן סיסמה'),
        hint: context.settingsText(
          'הנך במצב סייפר.\nהזן את הסיסמה כדי לגשת להגדרות',
        ),
        onVerify: (password) async {
          return repository.verifyProtectedModePassword(password);
        },
      ),
    );

    if (!mounted) return;

    if (verified == true) {
      setState(() {
        _isVerified = true;
      });
    } else {
      // המשתמש ביטל - נחזור למסך הקודם בצורה בטוחה
      // נבדוק אם ה-Navigator יכול לעשות pop
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (previous, current) =>
          previous.protectedModeEnabled != current.protectedModeEnabled,
      listener: (context, state) {
        // אם המצב המוגן הופעל והמשתמש עדיין לא אומת
        if (state.protectedModeEnabled && !_isVerified) {
          final repository = context.read<SettingsRepository>();
          if (repository.hasProtectedModePassword()) {
            // נאפס את הסטטוס ונבקש אימות מחדש
            setState(() {
              _isVerified = false;
              _isChecking = false;
              _dialogShown = false;
            });
            // נציג את הדיאלוג
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_dialogShown) {
                _dialogShown = true;
                _showPasswordDialog();
              }
            });
          }
        }
      },
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isVerified) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'הגדרות',
          ),
          automaticallyImplyLeading: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  FluentIcons.lock_closed_24_regular,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'הנך במצב סייפר',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'נדרשת סיסמה כדי לגשת להגדרות',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _dialogShown = false;
                    });
                    _showPasswordDialog();
                  },
                  icon: const Icon(FluentIcons.key_24_regular),
                  label: const Text('הזן סיסמה'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}

/// פונקציה עוזרת לבדיקה האם צריך אימות סיסמה במצב סייפר
bool shouldRequireSaferModePassword(BuildContext context) {
  final state = context.read<SettingsBloc>().state;
  final repository = context.read<SettingsRepository>();
  return state.protectedModeEnabled && repository.hasProtectedModePassword();
}

/// פונקציה עוזרת לאימות סיסמה לפני ביצוע פעולה מוגנת במצב סייפר
Future<bool> verifySaferModePassword(BuildContext context) async {
  if (!shouldRequireSaferModePassword(context)) {
    return true; // אין הגנה - מאושר
  }

  final repository = context.read<SettingsRepository>();

  final verified = await showDialog<bool>(
    context: context,
    builder: (context) => SaferModePasswordDialog(
      title: context.settingsText('אמת סיסמה'),
      hint: context.settingsText(
        'הנך במצב סייפר.\nהזן את הסיסמה כדי לבצע פעולה זו',
      ),
      onVerify: (password) async {
        return repository.verifyProtectedModePassword(password);
      },
    ),
  );

  return verified == true;
}
