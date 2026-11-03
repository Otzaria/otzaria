import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

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

    final verified = await showSaferModePasswordDialog(
      context,
      title: 'הזן סיסמה',
      hint: 'הנך במצב סייפר.\nהזן את הסיסמה כדי לגשת להגדרות',
    );

    if (!mounted) return;

    if (verified) {
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
    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsBloc, SettingsState>(
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
        ),
        // מסך ההגדרות נשמר חי (KeepAlive) לכל אורך הסשן, ולכן אימות חד-פעמי
        // ב-initState אינו מספיק: יציאה מהמסך נועלת מחדש, וחזרה מבקשת סיסמה.
        BlocListener<NavigationBloc, NavigationState>(
          listenWhen: (previous, current) =>
              previous.currentScreen != current.currentScreen,
          listener: (context, navState) {
            if (!shouldRequireSaferModePassword(context)) return;
            if (navState.currentScreen != Screen.settings) {
              if (_isVerified) {
                setState(() {
                  _isVerified = false;
                  _dialogShown = false;
                });
              }
            } else if (!_isVerified && !_dialogShown) {
              _dialogShown = true;
              _showPasswordDialog();
            }
          },
        ),
      ],
      child: _buildContent(),
    );
  }

  // המסך המוגן נשאר תמיד בעץ (Offstage בנעילה) כדי שה-State שלו לא ייהרס —
  // הנעילה היא שכבת כיסוי בלבד, ופתיחה מחזירה את המסך כפי שנעזב.
  Widget _buildContent() {
    final locked = _isChecking || !_isVerified;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: locked,
          child: ExcludeFocus(
            excluding: locked,
            child: widget.child,
          ),
        ),
        if (_isChecking)
          const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (!_isVerified)
          _buildLockScreen(),
      ],
    );
  }

  /// מסך הנעילה: OtzariaEmptyState.large על רקע הלוח, בלי AppBar במחשב ועם
  /// AppTopBar בטלפון, והטקסטים דרך settingsText (q10 Q8c, DD-31).
  Widget _buildLockScreen() {
    return Builder(
      builder: (context) {
        final state = OtzariaEmptyState.large(
          icon: FluentIcons.lock_closed_24_regular,
          title: context.settingsText('הנך במצב סייפר'),
          message: context.settingsText('נדרשת סיסמה כדי לגשת להגדרות'),
          actions: [
            ActionButton.recommended(
              icon: FluentIcons.key_24_regular,
              text: context.settingsText('הזן סיסמה'),
              onPressed: () {
                setState(() {
                  _dialogShown = false;
                });
                _showPasswordDialog();
              },
            ),
          ],
        );
        return Scaffold(
          backgroundColor: AppSurfaces.panelBackground(context),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= LayoutBreakpoints.compact) {
                return state;
              }
              return Column(
                children: [
                  AppTopBar(
                    center: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        context.settingsText('הגדרות'),
                        style: AppTopBar.titleStyle(context),
                      ),
                    ),
                  ),
                  Expanded(child: state),
                ],
              );
            },
          ),
        );
      },
    );
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

  return showSaferModePasswordDialog(
    context,
    title: 'אמת סיסמה',
    hint: 'הנך במצב סייפר.\nהזן את הסיסמה כדי לבצע פעולה זו',
  );
}

/// מציג את חלון אימות הסיסמה ומחזיר true רק כשהסיסמה אומתה.
/// [title] ו-[hint] הם מפתחות settingsText, ומתורגמים בשפת הדיאלוג.
Future<bool> showSaferModePasswordDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final repository = context.read<SettingsRepository>();
  final verified = await showDialog<bool>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (ctx) => SaferModePasswordDialog(
        title: ctx.settingsText(title),
        hint: ctx.settingsText(hint),
        onVerify: (password) async =>
            repository.verifyProtectedModePassword(password),
      ),
    ),
  );
  return verified == true;
}
