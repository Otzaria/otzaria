import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/bloc/settings_bloc.dart';
import 'package:otzaria/settings/bloc/settings_event.dart';
import 'package:otzaria/settings/bloc/settings_state.dart';
import 'package:otzaria/settings/bloc/settings_repository.dart';
import 'package:otzaria/settings/password_verification_dialog.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

/// מסך הגדרות מצב מוגן
class ProtectedSettingsScreen extends StatelessWidget {
  const ProtectedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('מתקדם > מצב מוגן', textDirection: TextDirection.rtl),
        leading: IconButton(
          icon: const Icon(FluentIcons.arrow_right_24_regular),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProtectedModeCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProtectedModeCard(BuildContext context) {
    final repository = RepositoryProvider.of<SettingsRepository>(context);

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final hasPassword = repository.hasProtectedModePassword();

        return SettingsCard(
          title: 'מצב מוגן',
          subtitle:
              'הגן על ההגדרות שלך עם סיסמה. כאשר מצב מוגן מופעל, תידרש להזין סיסמה לפני כניסה להגדרות. בנוסף, מצב זה ינעל את האפשרות לערוך הערות אישיות ולערוך טקסטים של ספרים.',
          children: [
            SwitchListTile(
              secondary: Icon(
                state.protectedModeEnabled
                    ? FluentIcons.lock_closed_24_filled
                    : FluentIcons.lock_open_24_regular,
              ),
              title:
                  const Text('הפעל מצב מוגן', style: TextStyle(fontSize: 16)),
              subtitle: Text(
                hasPassword ? 'סיסמה הוגדרה' : 'יש להגדיר סיסמה תחילה',
                style: TextStyle(
                  fontSize: 13,
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
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(FluentIcons.key_24_regular),
              title: Text(
                hasPassword ? 'שנה סיסמה' : 'הגדר סיסמה',
                style: const TextStyle(fontSize: 16),
              ),
              subtitle: Text(
                hasPassword
                    ? 'לחץ לשינוי הסיסמה הקיימת'
                    : 'לחץ להגדרת סיסמה חדשה',
                style: const TextStyle(fontSize: 13),
              ),
              trailing: const Icon(FluentIcons.chevron_left_24_regular),
              onTap: () => _handleSetPassword(context, repository, hasPassword),
            ),
          ],
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
