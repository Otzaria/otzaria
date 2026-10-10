import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/view/custom_shortcut_dialog.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// פותח את דיאלוג הקיצור הדינמי לעריכת [initial] (או ליצירה כשהוא null).
/// מחזיר את הקיצור שנשמר, או null בביטול.
Future<DynamicShortcut?> showDynamicShortcutDialog(
  BuildContext context, {
  DynamicShortcut? initial,
}) async {
  final draft = ValueNotifier<DynamicShortcut>(
    initial ??
        DynamicShortcut(
          id: DynamicShortcutRegistry.instance.newId(),
          key: '',
          kind: DynamicShortcutKind.setTextDisplay,
          change: const DynamicDisplayChange(nikud: DynamicMarkChange.toggle),
        ),
  );
  final confirmed = await showDialog<bool>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (_) => _DynamicShortcutDialog(draft: draft, isNew: initial == null),
    ),
  );
  final result = confirmed == true ? draft.value : null;
  draft.dispose();
  return result;
}

class _DynamicShortcutDialog extends StatelessWidget {
  final ValueNotifier<DynamicShortcut> draft;
  final bool isNew;

  const _DynamicShortcutDialog({required this.draft, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final t = context.settingsText;
    // דיאלוג עצמאי ולא AppDialog.twoActions: אישור חייב להיעצר כשהוולידציה
    // נכשלת, והרכיב הקנוני סוגר תמיד.
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(isNew ? 'קיצור דינמי חדש' : 'עריכת קיצור דינמי'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Flexible(
              child: ValueListenableBuilder<DynamicShortcut>(
                valueListenable: draft,
                builder: (context, value, _) => _DynamicShortcutForm(
                  value: value,
                  onChanged: (next) => draft.value = next,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ActionButton.ghost(
                  text: t('ביטול'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: AppTokens.spaceSM),
                ActionButton.recommended(
                  text: t('שמור'),
                  onPressed: () {
                    if (_validate(context)) Navigator.of(context).pop(true);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _validate(BuildContext context) {
    final value = draft.value;
    if (value.key.isEmpty) {
      UiSnack.showError(SettingsMessages.dynamicShortcutMissingKey);
      return false;
    }
    if (!value.hasEffect) {
      UiSnack.showError(SettingsMessages.dynamicShortcutMissingChange);
      return false;
    }
    for (final key in ShortcutValidator.shortcutKeys) {
      if (key == value.settingKey) continue;
      if (ShortcutValidator.getShortcutValue(key) == value.key) {
        UiSnack.showError(
          CommonMessages.shortcutAlreadyInUse(
            ShortcutValidator.shortcutNames[key] ?? key,
          ),
        );
        return false;
      }
    }
    return true;
  }
}

class _DynamicShortcutForm extends StatelessWidget {
  final DynamicShortcut value;
  final ValueChanged<DynamicShortcut> onChanged;

  const _DynamicShortcutForm({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.settingsText;
    final change = value.change;
    final markOptions = <SegmentOption<DynamicMarkChange?>>[
      SegmentOption(value: null, label: t('ללא שינוי')),
      SegmentOption(value: DynamicMarkChange.show, label: t('הצג')),
      SegmentOption(value: DynamicMarkChange.hide, label: t('הסתר')),
      SegmentOption(value: DynamicMarkChange.toggle, label: t('החלף')),
    ];
    final isDisplay = value.kind == DynamicShortcutKind.setTextDisplay;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsActionTile.segmentedTile<DynamicShortcutKind>(
              icon: FluentIcons.flash_24_regular,
              title: t('פעולה'),
              options: [
                SegmentOption(
                  value: DynamicShortcutKind.setTextDisplay,
                  label: t('שינוי תצוגה'),
                ),
                SegmentOption(
                  value: DynamicShortcutKind.copySelectionWith,
                  label: t('העתקת בחירה'),
                ),
                SegmentOption(
                  value: DynamicShortcutKind.copyParagraphWith,
                  label: t('העתקת פסקה'),
                ),
              ],
              currentValue: value.kind,
              onChanged: (v) => onChanged(value.copyWith(kind: v)),
            ),
            SettingsActionTile.segmentedTile<TextTarget>(
              icon: FluentIcons.book_open_24_regular,
              title: t('יעד'),
              options: [
                SegmentOption(value: TextTarget.body, label: t('גוף הספר')),
                SegmentOption(
                  value: TextTarget.commentary,
                  label: t('מפרשים'),
                ),
              ],
              currentValue: value.target,
              onChanged: (v) => onChanged(value.copyWith(target: v)),
            ),
            const Divider(),
            SettingsActionTile.segmentedTile<DynamicMarkChange?>(
              icon: OtzariaIcons.alef_niqqud_24_filled,
              title: t('ניקוד'),
              options: markOptions,
              currentValue: change.nikud,
              onChanged: (v) =>
                  onChanged(value.copyWith(change: change.copyWith(nikud: v))),
            ),
            SettingsActionTile.segmentedTile<DynamicTeamimChange?>(
              icon: OtzariaIcons.alef_niqqud_taamim_24_filled,
              title: t('טעמי המקרא'),
              options: [
                SegmentOption(value: null, label: t('ללא שינוי')),
                SegmentOption(value: DynamicTeamimChange.show, label: t('הצג')),
                SegmentOption(
                  value: DynamicTeamimChange.hide,
                  label: t('הסתר'),
                ),
                SegmentOption(
                  value: DynamicTeamimChange.followNikud,
                  label: t('כמו הניקוד'),
                ),
              ],
              currentValue: change.teamim,
              onChanged: (v) => onChanged(
                value.copyWith(change: change.copyWith(teamim: v)),
              ),
            ),
            SettingsActionTile.segmentedTile<DynamicMarkChange?>(
              icon: OtzariaIcons.alef_punctuation_24_filled,
              title: t('סימני פיסוק'),
              options: markOptions,
              currentValue: change.punctuation,
              onChanged: (v) => onChanged(
                value.copyWith(change: change.copyWith(punctuation: v)),
              ),
            ),
            SettingsActionTile.segmentedTile<HolyNameDisplay?>(
              icon: OtzariaIcons.alef_lock_24_filled,
              title: t('שם הוי"ה'),
              options: [
                SegmentOption(value: null, label: t('ללא שינוי')),
                SegmentOption(value: HolyNameDisplay.asIs, label: t('ככתבו')),
                SegmentOption(value: HolyNameDisplay.kufKuf, label: t('יקוק')),
                SegmentOption(
                  value: HolyNameDisplay.hehApostrophe,
                  label: t("ה'"),
                ),
              ],
              currentValue: change.holyName,
              onChanged: (v) => onChanged(
                value.copyWith(change: change.copyWith(holyName: v)),
              ),
            ),
            if (value.target == TextTarget.body && isDisplay)
              SettingsActionTile.segmentedTile<DynamicMarkChange?>(
                icon: OtzariaIcons.alef_1_24_filled,
                title: t('ציוני המפרשים'),
                options: markOptions,
                currentValue: change.anchorMarkers,
                onChanged: (v) => onChanged(
                  value.copyWith(change: change.copyWith(anchorMarkers: v)),
                ),
              ),
            if (!isDisplay)
              SettingsActionTile.switchTile(
                icon: FluentIcons.text_clear_formatting_24_regular,
                title: t('ללא עיצוב'),
                subtitle: t('העתקת טקסט פשוט בלבד, בלי גופן ועיצוב'),
                value: value.plainTextOnly,
                onChanged: (v) => onChanged(value.copyWith(plainTextOnly: v)),
              ),
            if (isDisplay)
              SettingsActionTile.switchTile(
                icon: FluentIcons.save_24_regular,
                title: t('שמור גם לספר'),
                subtitle: t(
                  'פעיל רק כש"שמירת התאמות לכל ספר" מופעלת בהגדרות',
                ),
                value: value.persistToBook,
                onChanged: (v) => onChanged(value.copyWith(persistToBook: v)),
              ),
            const Divider(),
            SettingsActionTile.text(
              icon: FluentIcons.keyboard_24_regular,
              title: t('צירוף המקשים'),
              subtitle: value.key.isEmpty
                  ? t('לא הוגדר')
                  : ShortcutHelper.formatShortcutForDisplay(value.key),
              actions: [
                ActionButton.neutral(
                  text: t('הקלט מקשים'),
                  onPressed: () async {
                    final captured = await showDialog<String>(
                      context: context,
                      builder: settingsDialogBuilder(
                        context,
                        (_) => CustomShortcutDialog(
                          initialShortcut: value.key,
                          actionName: value.describe(),
                        ),
                      ),
                    );
                    if (captured != null && captured.isNotEmpty) {
                      onChanged(value.copyWith(key: captured));
                    }
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceSM),
              child: Text(
                value.describe(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
