import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/android_update_bloc.dart';
import '../bloc/android_update_event.dart';
import '../bloc/android_update_state.dart';
import '../models/android_update.dart';
import 'android_update_host.dart';

Future<void> showAndroidUpdateDialog(
  BuildContext context,
  AndroidUpdateBloc bloc,
) => showDialog<void>(
  context: context,
  builder: settingsDialogBuilder(
    context,
    (context) => AppDialog.singleAction(
      title: context.settingsText('עדכון אוצריא'),
      icon: FluentIcons.arrow_download_24_regular,
      confirmText: context.settingsText('סגור'),
      customContent: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: AndroidUpdatePanel(bloc: bloc),
        ),
      ),
    ),
  ),
);

class AndroidUpdateSettingsTile extends StatelessWidget {
  const AndroidUpdateSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = AndroidUpdateScope.maybeOf(context);
    if (bloc == null) return const SizedBox.shrink();
    return BlocBuilder<AndroidUpdateBloc, AndroidUpdateState>(
      bloc: bloc,
      builder: (context, state) => SettingsActionTile.text(
        icon: FluentIcons.arrow_download_24_regular,
        title: context.settingsText('עדכון תוכנה'),
        subtitle: _statusText(context, state),
        actions: [
          ActionButton.recommended(
            text: context.settingsText('בדוק ועדכן'),
            onPressed: () {
              if (!state.busy &&
                  state.prepared == null &&
                  state.release == null &&
                  state.phase != AndroidUpdatePhase.ready &&
                  state.phase != AndroidUpdatePhase.confirmation) {
                bloc.add(const AndroidUpdateCheck());
              }
              showAndroidUpdateDialog(context, bloc);
            },
          ),
        ],
      ),
    );
  }
}

class AndroidUpdateIndicator extends StatelessWidget {
  const AndroidUpdateIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = AndroidUpdateScope.maybeOf(context);
    if (bloc == null) return const SizedBox.shrink();
    return BlocBuilder<AndroidUpdateBloc, AndroidUpdateState>(
      bloc: bloc,
      builder: (context, state) => state.showIndicator
          ? ActionButton.ghost(
              text: context.settingsText('עדכון'),
              icon: FluentIcons.arrow_download_24_regular,
              tooltip: context.settingsText('עדכון תוכנה'),
              onPressed: () => showAndroidUpdateDialog(context, bloc),
            )
          : const SizedBox.shrink(),
    );
  }
}

class AndroidUpdatePanel extends StatelessWidget {
  const AndroidUpdatePanel({super.key, required this.bloc});
  final AndroidUpdateBloc bloc;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AndroidUpdateBloc, AndroidUpdateState>(
    bloc: bloc,
    builder: (context, state) {
      final version =
          state.release?.displayVersion ?? state.prepared?.versionName;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_statusText(context, state)),
          if (version != null) ...[
            const SizedBox(height: 8),
            Text(version, textDirection: TextDirection.ltr),
          ],
          if (state.phase == AndroidUpdatePhase.downloading ||
              state.phase == AndroidUpdatePhase.cancelling) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: state.progress),
            if (state.totalBytes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.settingsText(
                    'הורדו {percent}%',
                    args: {'percent': (100 * state.progress!).floor()},
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _primaryAction(context, state),
              if (!state.isPlay &&
                  state.phase == AndroidUpdatePhase.downloading)
                ActionButton.neutral(
                  text: context.settingsText('בטל הורדה'),
                  onPressed: () => bloc.add(const AndroidUpdateCancel()),
                ),
              if (!state.busy &&
                  state.prepared == null &&
                  state.release != null)
                ActionButton.ghost(
                  text: context.settingsText('בדוק שוב'),
                  onPressed: () => bloc.add(const AndroidUpdateCheck()),
                ),
              if (state.failure == AndroidUpdateFailure.metadataMissing ||
                  state.failure == AndroidUpdateFailure.playUnavailable)
                ActionButton.ghost(
                  text: state.isPlay
                      ? context.settingsText('פתח את Google Play')
                      : context.settingsText('פתח את דף ההורדה'),
                  onPressed: () => launchUrl(
                    Uri.parse(
                      state.isPlay
                          ? 'https://play.google.com/store/apps/details?id=org.otzaria.otzaria'
                          : 'https://github.com/Otzaria/otzaria/releases/latest',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );

  Widget _primaryAction(BuildContext context, AndroidUpdateState state) {
    if (state.busy) {
      return ActionButton.recommended(
        text: context.settingsText('המתן'),
        isLoading: true,
        onPressed: null,
      );
    }
    if (state.prepared != null ||
        state.phase == AndroidUpdatePhase.ready ||
        (!state.isPlay &&
            (state.phase == AndroidUpdatePhase.confirmation ||
                state.failure == AndroidUpdateFailure.interrupted))) {
      return ActionButton.recommended(
        text: context.settingsText('התקן עדכון'),
        onPressed: () => bloc.add(const AndroidUpdateInstall()),
      );
    }
    if (state.release != null ||
        (state.isPlay &&
            (state.phase == AndroidUpdatePhase.available ||
                state.phase == AndroidUpdatePhase.cancelled ||
                state.phase == AndroidUpdatePhase.confirmation))) {
      return ActionButton.recommended(
        text: context.settingsText('הורד עדכון'),
        onPressed: () => bloc.add(const AndroidUpdateDownload()),
      );
    }
    return ActionButton.recommended(
      text: context.settingsText('בדוק עדכונים'),
      onPressed: () => bloc.add(const AndroidUpdateCheck()),
    );
  }
}

String _statusText(BuildContext context, AndroidUpdateState state) {
  if (state.failure case final failure?) return _failureText(context, failure);
  return switch (state.phase) {
    AndroidUpdatePhase.idle => context.settingsText(
      'בדוק אם קיימת גרסה חדשה של אוצריא.',
    ),
    AndroidUpdatePhase.initializing ||
    AndroidUpdatePhase.checking => context.settingsText('בודק עדכונים...'),
    AndroidUpdatePhase.upToDate || AndroidUpdatePhase.completed =>
      context.settingsText('גרסת אוצריא מעודכנת.'),
    AndroidUpdatePhase.available =>
      state.isPlay
          ? context.settingsText('גרסה חדשה זמינה ב-Google Play.')
          : context.settingsText('גרסה חדשה של אוצריא זמינה להורדה.'),
    AndroidUpdatePhase.downloading =>
      state.isPlay
          ? context.settingsText(
              'העדכון יורד באמצעות Google Play. אפשר להמשיך להשתמש באוצריא.',
            )
          : context.settingsText('מוריד ומאמת את עדכון התוכנה...'),
    AndroidUpdatePhase.cancelling => context.settingsText('מבטל את ההורדה...'),
    AndroidUpdatePhase.ready =>
      state.isPlay
          ? context.settingsText('העדכון מוכן. ההתקנה תפעיל את אוצריא מחדש.')
          : context.settingsText('העדכון מוכן להתקנה. Android יבקש את אישורך.'),
    AndroidUpdatePhase.awaitingPermission =>
      (state.environment?.sdkInt ?? 26) < 26
          ? context.settingsText(
              'אפשר התקנה ממקורות לא מוכרים בהגדרות האבטחה של Android, ואז חזור לכאן.',
            )
          : context.settingsText(
              'אפשר לאוצריא להתקין עדכונים במסך Android, ואז חזור לכאן.',
            ),
    AndroidUpdatePhase.confirmation =>
      state.isPlay
          ? context.settingsText('אשר את העדכון בחלון Google Play.')
          : context.settingsText(
              'אשר את העדכון בחלון Android. אם סגרת אותו, אפשר לנסות שוב.',
            ),
    AndroidUpdatePhase.installing => context.settingsText(
      'ממתין לתוצאת ההתקנה...',
    ),
    AndroidUpdatePhase.cancelled => context.settingsText(
      'העדכון בוטל. אפשר לנסות שוב.',
    ),
    AndroidUpdatePhase.failed => context.settingsText(
      'העדכון לא הותקן. אפשר לנסות שוב.',
    ),
  };
}

String _failureText(
  BuildContext context,
  AndroidUpdateFailure failure,
) => switch (failure) {
  AndroidUpdateFailure.network => context.settingsText(
    'לא ניתן להוריד את העדכון. בדוק את החיבור ונסה שוב.',
  ),
  AndroidUpdateFailure.metadataMissing => context.settingsText(
    'הגרסה אינה כוללת פרטי אימות לעדכון אוטומטי. ניתן להוריד אותה מדף ההורדה.',
  ),
  AndroidUpdateFailure.invalidMetadata => context.settingsText(
    'פרטי העדכון אינם תקינים. לא בוצעה התקנה.',
  ),
  AndroidUpdateFailure.packageMismatch => context.settingsText(
    'קובץ העדכון אינו מיועד לאפליקציה המותקנת.',
  ),
  AndroidUpdateFailure.signatureMismatch => context.settingsText(
    'חתימת העדכון שונה מהחתימה של אוצריא המותקנת. לא בוצעה התקנה.',
  ),
  AndroidUpdateFailure.incompatibleDevice => context.settingsText(
    'גרסה זו אינה תואמת למכשיר שלך.',
  ),
  AndroidUpdateFailure.notNewer => context.settingsText(
    'קובץ העדכון אינו חדש יותר מהגרסה המותקנת.',
  ),
  AndroidUpdateFailure.sizeMismatch ||
  AndroidUpdateFailure.hashMismatch => context.settingsText(
    'קובץ העדכון אינו שלם או לא עבר אימות. הורד אותו שוב.',
  ),
  AndroidUpdateFailure.storage => context.settingsText(
    'אין אפשרות לשמור את העדכון. בדוק שיש מקום פנוי במכשיר.',
  ),
  AndroidUpdateFailure.permissionDenied => context.settingsText(
    'לא ניתנה הרשאה להתקנה. אפשר לנסות שוב ולאשר אותה במסך Android.',
  ),
  AndroidUpdateFailure.installerFailed => context.settingsText(
    'Android לא השלים את ההתקנה. אפשר לנסות שוב.',
  ),
  AndroidUpdateFailure.interrupted => context.settingsText(
    'ההתקנה נקטעה. אפשר להתחיל אותה שוב מהקובץ שכבר הורד.',
  ),
  AndroidUpdateFailure.playUnavailable => context.settingsText(
    'Google Play אינו זמין לעדכון כרגע. נסה שוב או פתח את החנות.',
  ),
  AndroidUpdateFailure.disabled => context.settingsText(
    'בדיקת העדכונים כבויה או שמצב מנותק פעיל.',
  ),
  AndroidUpdateFailure.busy => context.settingsText(
    'עדכון אחר עדיין מתבצע. המתן לסיומו.',
  ),
};
