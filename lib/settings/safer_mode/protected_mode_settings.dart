import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/bloc/settings_bloc.dart';
import 'package:otzaria/settings/bloc/settings_event.dart';
import 'package:otzaria/settings/bloc/settings_state.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';
import 'package:otzaria/settings/password_verification_dialog.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

/// Widget להגדרות מצב מוגן
class ProtectedModeSettings extends StatelessWidget {
  const ProtectedModeSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = RepositoryProvider.of<SettingsRepository>(context);

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final hasPassword = repository.hasProtectedModePassword();

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      FluentIcons.shield_lock_24_regular,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'מצב מוגן',
                      style: Theme.of(context).textTheme.titleLarge,
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'הגן על ההגדרות שלך עם סיסמה. כאשר מצב מוגן מופעל, תידרש להזין סיסמה לפני כניסה להגדרות.\nבנוסף, מצב זה ינעל את האפשרות לערוך הערות אישיות ולערוך טקסטים של ספרים.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text(
                    'הפעל מצב מוגן',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    hasPassword ? 'סיסמה הוגדרה' : 'יש להגדיר סיסמה תחילה',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: hasPassword
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  value: state.protectedModeEnabled,
                  onChanged: hasPassword
                      ? (value) => _handleToggleProtectedMode(
                            context,
                            repository,
                            value,
                          )
                      : null,
                  secondary: Icon(
                    state.protectedModeEnabled
                        ? FluentIcons.lock_closed_24_filled
                        : FluentIcons.lock_open_24_regular,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(FluentIcons.key_24_regular),
                  title: Text(
                    hasPassword ? 'שנה סיסמה' : 'הגדר סיסמה',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    hasPassword
                        ? 'לחץ לשינוי הסיסמה הקיימת'
                        : 'לחץ להגדרת סיסמה חדשה',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: const Icon(FluentIcons.chevron_left_24_regular),
                  onTap: () =>
                      _handleSetPassword(context, repository, hasPassword),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleToggleProtectedMode(
    BuildContext context,
    SettingsRepository repository,
    bool newValue,
  ) async {
    // אם מנסים לכבות את המצב המוגן, נדרוש אימות סיסמה
    if (!newValue) {
      final verified = await showDialog<bool>(
        context: context,
        builder: (context) => PasswordVerificationDialog(
          title: 'אמת סיסמה',
          hint: 'הזן את הסיסמה כדי להשבית את המצב המוגן',
          onVerify: (password) async {
            return repository.verifyProtectedModePassword(password);
          },
        ),
      );

      if (verified != true) return;
    }

    // מבצעים את השינוי
    if (context.mounted) {
      context.read<SettingsBloc>().add(UpdateProtectedModeEnabled(newValue));
      if (!newValue) {
        UiSnack.show('המצב המוגן הושבת');
      }
    }
  }

  Future<void> _handleSetPassword(
    BuildContext context,
    SettingsRepository repository,
    bool hasExistingPassword,
  ) async {
    // אם יש סיסמה קיימת, נדרוש אימות תחילה
    if (hasExistingPassword) {
      final verified = await showDialog<bool>(
        context: context,
        builder: (context) => PasswordVerificationDialog(
          title: 'אמת סיסמה נוכחית',
          hint: 'הזן את הסיסמה הנוכחית כדי לשנות אותה',
          onVerify: (password) async {
            return repository.verifyProtectedModePassword(password);
          },
        ),
      );

      if (verified != true) return;
    }

    // עכשיו נציג דיאלוג להגדרת סיסמה חדשה
    if (!context.mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SetPasswordDialog(
        onSetPassword: (password) async {
          context
              .read<SettingsBloc>()
              .add(UpdateProtectedModePassword(password));
        },
      ),
    );

    if (result == true && context.mounted) {
      // אם זו סיסמה ראשונה, נפעיל אוטומטית את המצב המוגן
      if (!hasExistingPassword) {
        context
            .read<SettingsBloc>()
            .add(const UpdateProtectedModeEnabled(true));
      }
    }
  }
}
