import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// מתג הסדר האישי באיתור, ולידו איפוס שמוצג רק כשיש מה לאפס.
class FindRefPersonalOrderTile extends StatefulWidget {
  const FindRefPersonalOrderTile({super.key});

  @override
  State<FindRefPersonalOrderTile> createState() =>
      _FindRefPersonalOrderTileState();
}

class _FindRefPersonalOrderTileState extends State<FindRefPersonalOrderTile> {
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    // עמוד ההגדרות נשמר חי: פתיחה מהאיתור או חלון אחר משנים את המצב מתחתיו.
    _changes = Settings.changes
        .where(
          (key) =>
              key == FindRefPreferenceStore.scoresKey ||
              key == FindRefPreferenceStore.enabledKey,
        )
        .listen((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _setEnabled(bool value) async {
    await FindRefPreferenceStore.setEnabled(value);
    if (mounted) setState(() {});
  }

  Future<void> _reset() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('איפוס הסדר האישי באיתור'),
      content: context.settingsText(
        'האיתור ישכח אילו ספרים פתחת, והתוצאות יוצגו בסדר הרגיל.',
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('איפוס'),
    );
    if (confirmed != true || !mounted) return;
    FindRefPreferenceStore.clear();
    setState(() {});
    UiSnack.show(SettingsMessages.findRefPersonalOrderReset);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = FindRefPreferenceStore.isEnabled;
    return SettingsSwitchTile(
      icon: FluentIcons.person_star_24_regular,
      title: context.settingsText('איתור מותאם אישית'),
      subtitle: context.settingsText(
        enabled
            ? 'ספרים שפתחת לאחרונה מהאיתור יוקדמו בתוצאות'
            : 'תוצאות האיתור יוצגו בסדר הרגיל',
      ),
      value: enabled,
      onChanged: _setEnabled,
      extraActions: [
        if (FindRefPreferenceStore.hasData)
          AppIconButton(
            key: const ValueKey('find-ref-personal-order-reset'),
            icon: const Icon(FluentIcons.arrow_reset_24_regular),
            size: AppIconButtonSize.small,
            tooltip: context.settingsText('איפוס הסדר האישי באיתור'),
            onPressed: _reset,
          ),
      ],
    );
  }
}
