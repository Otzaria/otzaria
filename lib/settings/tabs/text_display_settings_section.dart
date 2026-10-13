import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_profile_editor.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// כרטיס "תצוגת הטקסט": השורש (גוף הספר, תצוגה רגילה, ערוץ התצוגה) גלוי
/// תמיד; שאר 11 החריצים ושכבת התנ"ך מקופלים תחת "התאמות נוספות", שבה
/// בוחרים צירוף ומחליטים אם הוא יורש או מקבל הגדרות נפרדות. "צירוף" הוא
/// המונח שנחשף למשתמש עבור [TextDisplaySlot] — ארבעת הבוררים שמעליו *הם*
/// הצירוף, ולכן המילה מתארת בדיוק את מה שנראה על המסך.
class TextDisplaySettingsCard extends StatefulWidget {
  const TextDisplaySettingsCard({super.key});

  @override
  State<TextDisplaySettingsCard> createState() =>
      _TextDisplaySettingsCardState();
}

class _TextDisplaySettingsCardState extends State<TextDisplaySettingsCard> {
  bool _advancedOpen = false;
  TextDisplayBookClass _bookClass = TextDisplayBookClass.general;
  TextTarget _target = TextTarget.body;
  TextView _view = TextView.regular;
  TextChannel _channel = TextChannel.display;

  TextDisplaySlot get _slot =>
      TextDisplaySlot(target: _target, view: _view, channel: _channel);

  bool get _isTanach => _bookClass == TextDisplayBookClass.tanach;

  void _update(TextDisplayPolicy policy) {
    context.read<SettingsBloc>().add(UpdateTextDisplayPolicy(policy));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.settingsText;
    final policy = context.select(
      (SettingsBloc bloc) => bloc.state.textDisplayPolicy,
    );
    final rootProfile = policy.resolve(TextDisplaySlot.root);

    return SettingsCard(
      cardId: 'text.nikud',
      title: t('תצוגת הטקסט'),
      subtitle: t('מה מוצג בטקסט, וכיצד הוא מועתק ומיוצא'),
      children: [
        ...TextDisplayProfileEditor.tiles(
          context,
          profile: rootProfile,
          onChanged: (profile) => _update(
            policy.withSlot(
              TextDisplayBookClass.general,
              TextDisplaySlot.root,
              profile.toPatch(),
            ),
          ),
        ),
        ExpandableSection(
          icon: FluentIcons.options_24_regular,
          title: t('התאמות נוספות'),
          subtitle: t('מפרשים, העתקה, ייצוא והדפסה, צורת הדף ותנ"ך'),
          isExpanded: _advancedOpen,
          onTap: () => setState(() => _advancedOpen = !_advancedOpen),
          children: [_buildAdvanced(context, policy)],
        ),
      ],
    );
  }

  Widget _buildAdvanced(BuildContext context, TextDisplayPolicy policy) {
    final t = context.settingsText;
    final slot = _slot;
    final layer = policy.layer(_bookClass);
    final isSeparate = layer.patchFor(slot).isNotEmpty;
    // השורש הכללי נערך למעלה; בצירוף זה המתג מיותר.
    final isGeneralRoot = !_isTanach && slot.isRoot;
    final resolved = policy.resolve(slot, isTanach: _isTanach);
    final hasOverrides =
        policy.tanach.isNotEmpty ||
        policy.general.patches.keys.any((s) => !s.isRoot);

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTokens.spaceSM),
        SettingsActionTile.segmentedTile<TextDisplayBookClass>(
          icon: OtzariaIcons.bookshelf_24_regular,
          title: t('ספרים'),
          currentValue: _bookClass,
          options: [
            SegmentOption(
              value: TextDisplayBookClass.general,
              label: t('כל הספרים'),
            ),
            SegmentOption(
              value: TextDisplayBookClass.tanach,
              label: t('תנ"ך'),
            ),
          ],
          onChanged: (v) => setState(() => _bookClass = v),
        ),
        SettingsActionTile.segmentedTile<TextTarget>(
          icon: FluentIcons.book_open_24_regular,
          title: t('יעד'),
          currentValue: _target,
          options: [
            SegmentOption(value: TextTarget.body, label: t('גוף הספר')),
            SegmentOption(value: TextTarget.commentary, label: t('מפרשים')),
          ],
          onChanged: (v) => setState(() => _target = v),
        ),
        SettingsActionTile.segmentedTile<TextView>(
          icon: OtzariaIcons.book_open_tzurat_hadaf_24_regular,
          title: t('תצוגה'),
          currentValue: _view,
          options: [
            SegmentOption(value: TextView.regular, label: t('רגילה')),
            SegmentOption(value: TextView.pageShape, label: t('צורת הדף')),
          ],
          onChanged: (v) => setState(() => _view = v),
        ),
        SettingsActionTile.segmentedTile<TextChannel>(
          icon: FluentIcons.channel_24_regular,
          title: t('ערוץ'),
          currentValue: _channel,
          options: [
            SegmentOption(value: TextChannel.display, label: t('תצוגה')),
            SegmentOption(value: TextChannel.copy, label: t('העתקה')),
            SegmentOption(
              value: TextChannel.export,
              label: t('ייצוא והדפסה'),
            ),
          ],
          onChanged: (v) => setState(() => _channel = v),
        ),
        const SizedBox(height: AppTokens.spaceSM),
        AppCard.sectionDivider(context),
        if (!isGeneralRoot)
          SettingsActionTile.switchTile(
            icon: FluentIcons.branch_fork_24_regular,
            title: t('הגדרות נפרדות'),
            subtitle: isSeparate
                ? t('לצירוף הזה ערכים משלו')
                : t(
                    'יורש מהצירוף הכללי יותר: {parent}',
                    args: {
                      'parent': _parentLabel(context, slot),
                    },
                  ),
            value: isSeparate,
            onChanged: (value) => _update(
              value
                  ? policy.withSlot(_bookClass, slot, resolved.toPatch())
                  : policy.withLayer(_bookClass, layer.without(slot)),
            ),
          ),
        if (isGeneralRoot)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: AppTokens.spaceSM + AppTokens.spaceXS,
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.spaceSM),
                Expanded(
                  child: Text(
                    t('זהו הצירוף הבסיסי — הוא נערך למעלה'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (isSeparate)
          TextDisplayProfileEditor(
            profile: resolved,
            onChanged: (profile) =>
                _update(policy.withSlot(_bookClass, slot, profile.toPatch())),
          ),
        if (hasOverrides) ...[
          AppCard.sectionDivider(context),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceSM,
              vertical: AppTokens.spaceXS,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionButton.ghost(
                icon: FluentIcons.arrow_reset_24_regular,
                text: t('איפוס כל ההתאמות הנוספות'),
                onPressed: () => _update(
                  TextDisplayPolicy(
                    general: TextDisplayLayer({
                      TextDisplaySlot.root: policy.general.patchFor(
                        TextDisplaySlot.root,
                      ),
                    }),
                    tanach: TextDisplayLayer.empty,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// תווית הצירוף שממנו יורש [slot] בפועל — הראשון בשרשרת הירושה.
  String _parentLabel(BuildContext context, TextDisplaySlot slot) {
    final t = context.settingsText;
    final parent = slot.inheritanceChain.length > 1
        ? slot.inheritanceChain[1]
        : TextDisplaySlot.root;
    final target = parent.target == TextTarget.body
        ? t('גוף הספר')
        : t('מפרשים');
    final view = parent.view == TextView.regular ? t('רגילה') : t('צורת הדף');
    final channel = switch (parent.channel) {
      TextChannel.display => t('תצוגה'),
      TextChannel.copy => t('העתקה'),
      TextChannel.export => t('ייצוא והדפסה'),
    };
    final scope = _isTanach && slot.isRoot ? t('כל הספרים') : null;
    return [?scope, target, view, channel].join(' · ');
  }
}
