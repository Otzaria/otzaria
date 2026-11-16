import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

/// הגבלת קובצי ההורדות בלבד, לצד בחירת מצב הרשת הכללית.
class DownloadNetworkSettingsTile extends StatelessWidget {
  const DownloadNetworkSettingsTile({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocSelector<SettingsBloc, SettingsState, bool>(
    selector: (state) => state.downloadsWifiOnly,
    builder: (context, wifiOnly) => SettingsSegmentedTile<bool>(
      title: context.settingsText('רשת להורדת קבצים'),
      subtitle: context.settingsText(
        'חל על הורדת קבצים, גם מתוספים; לא על גלישה בתוספים או עדכוני Google Play.',
      ),
      options: [
        SegmentOption(
          value: false,
          label: context.settingsText('כל רשת'),
          subtitle: context.settingsText('WiFi או אינטרנט סלולרי'),
        ),
        SegmentOption(
          value: true,
          label: context.settingsText('WiFi בלבד'),
          subtitle: context.settingsText('הורדות ממתינות לחיבור WiFi'),
        ),
      ],
      currentValue: wifiOnly,
      onChanged: (value) => context.read<SettingsBloc>().add(
        UpdateDownloadsWifiOnly(value),
      ),
    ),
  );
}
