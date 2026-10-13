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

const _copySlot = TextDisplaySlot(
  target: TextTarget.body,
  view: TextView.regular,
  channel: TextChannel.copy,
);
const _exportSlot = TextDisplaySlot(
  target: TextTarget.body,
  view: TextView.regular,
  channel: TextChannel.export,
);
const _pageShapeSlot = TextDisplaySlot(
  target: TextTarget.body,
  view: TextView.pageShape,
  channel: TextChannel.display,
);

/// צירוף של שכבה וחריץ — יחידת העריכה ב"התאמות נוספות".
typedef _Case = ({TextDisplayBookClass bookClass, TextDisplaySlot slot});

const _namedCases = <_Case>[
  (
    bookClass: TextDisplayBookClass.general,
    slot: TextDisplaySlot.commentaryDisplay,
  ),
  (bookClass: TextDisplayBookClass.general, slot: _copySlot),
  (bookClass: TextDisplayBookClass.general, slot: _exportSlot),
  (bookClass: TextDisplayBookClass.general, slot: _pageShapeSlot),
  (bookClass: TextDisplayBookClass.tanach, slot: TextDisplaySlot.root),
];

const _generalRoot = (
  bookClass: TextDisplayBookClass.general,
  slot: TextDisplaySlot.root,
);

typedef _Text =
    String Function(
      String hebrew, {
      String? context,
      Map<String, Object?>? args,
    });

String _caseKey(_Case c) => '${c.bookClass.name}:${c.slot.key}';

/// כרטיס "תצוגת הטקסט": השורש גלוי תמיד; תחת "התאמות נוספות" מוצגים מצבים
/// בעלי שם (מפרשים, העתקה וכו'), הצירופים המתקדמים שהוגדרו, ובורר לצירוף חדש.
class TextDisplaySettingsCard extends StatefulWidget {
  const TextDisplaySettingsCard({super.key});

  @override
  State<TextDisplaySettingsCard> createState() =>
      _TextDisplaySettingsCardState();
}

class _TextDisplaySettingsCardState extends State<TextDisplaySettingsCard> {
  bool _advancedOpen = false;
  String? _openCase;
  bool _pickerOpen = false;
  TextDisplayBookClass _bookClass = TextDisplayBookClass.general;
  TextTarget _target = TextTarget.body;
  TextView _view = TextView.regular;
  TextChannel _channel = TextChannel.display;

  void _update(TextDisplayPolicy policy) {
    context.read<SettingsBloc>().add(UpdateTextDisplayPolicy(policy));
  }

  void _toggleCase(_Case c) {
    final key = _caseKey(c);
    setState(() => _openCase = _openCase == key ? null : key);
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
          children: _buildAdvanced(context, policy),
        ),
      ],
    );
  }

  List<Widget> _buildAdvanced(BuildContext context, TextDisplayPolicy policy) {
    final t = context.settingsText;
    final named = [
      (OtzariaIcons.book_alef_rashi_24_regular, t('במפרשים')),
      (OtzariaIcons.alef_copy_24_regular, t('בהעתקה')),
      (FluentIcons.print_24_regular, t('בייצוא ובהדפסה')),
      (OtzariaIcons.book_open_tzurat_hadaf_24_regular, t('בצורת הדף')),
      (OtzariaIcons.torah_scroll_24_regular, t('בתנ"ך')),
    ];
    final custom = _customCases(policy);
    final hasOverrides =
        policy.tanach.isNotEmpty ||
        policy.general.patches.keys.any((s) => !s.isRoot);

    return [
      for (var i = 0; i < _namedCases.length; i++)
        _caseSection(
          context,
          policy,
          _namedCases[i],
          icon: named[i].$1,
          title: named[i].$2,
        ),
      if (custom.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppTokens.spaceMD,
            AppTokens.spaceSM,
            AppTokens.spaceMD,
            AppTokens.spaceXS,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              t('התאמות מתקדמות שהוגדרו'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        for (final c in custom)
          _caseSection(
            context,
            policy,
            c,
            icon: FluentIcons.branch_fork_24_regular,
            title: _dimsLabel(t, c),
            onDelete: () => _update(_cleared(policy, c)),
          ),
      ],
      ExpandableSection(
        icon: FluentIcons.add_24_regular,
        title: t('התאמה מתקדמת...'),
        subtitle: t('ספרים, יעד, תצוגה וערוץ לבחירה חופשית'),
        isExpanded: _pickerOpen,
        onTap: () => setState(() => _pickerOpen = !_pickerOpen),
        children: _buildPicker(context, policy),
      ),
      if (hasOverrides)
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
    ];
  }

  /// צירופים עם טלאי שאינם השורש הכללי ואינם מהמצבים בעלי השם.
  List<_Case> _customCases(TextDisplayPolicy policy) => [
    for (final bookClass in TextDisplayBookClass.values)
      for (final slot in TextDisplaySlot.all)
        if (policy.layer(bookClass).patchFor(slot).isNotEmpty &&
            (bookClass: bookClass, slot: slot) != _generalRoot &&
            !_namedCases.contains((bookClass: bookClass, slot: slot)))
          (bookClass: bookClass, slot: slot),
  ];

  Widget _caseSection(
    BuildContext context,
    TextDisplayPolicy policy,
    _Case c, {
    required IconData icon,
    required String title,
    VoidCallback? onDelete,
  }) {
    final t = context.settingsText;
    return ExpandableSection(
      key: ValueKey('text-display-case-${_caseKey(c)}'),
      icon: icon,
      title: title,
      subtitle: _caseSubtitle(t, policy, c),
      isExpanded: _openCase == _caseKey(c),
      onTap: () => _toggleCase(c),
      trailing: onDelete == null
          ? null
          : SecondaryIconButton(
              icon: FluentIcons.delete_24_regular,
              tooltip: t('מחק התאמה'),
              onPressed: onDelete,
            ),
      children: _caseEditor(context, policy, c),
    );
  }

  /// עורך הצירוף: כל שינוי נכתב כסטייה מהערך הפתור וממוזג לטלאי הקיים,
  /// כך ששאר השדות ממשיכים לרשת.
  List<Widget> _caseEditor(
    BuildContext context,
    TextDisplayPolicy policy,
    _Case c,
  ) {
    final t = context.settingsText;
    final resolved = policy.resolve(
      c.slot,
      isTanach: c.bookClass == TextDisplayBookClass.tanach,
    );
    final hasPatch = policy.layer(c.bookClass).patchFor(c.slot).isNotEmpty;
    return [
      ...TextDisplayProfileEditor.tiles(
        context,
        profile: resolved,
        onChanged: (profile) => _update(
          policy.merged(
            c.bookClass,
            c.slot,
            profile.toPatch().pruneAgainst(resolved),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSM,
          vertical: AppTokens.spaceXS,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.ghost(
            icon: FluentIcons.arrow_undo_24_regular,
            text: t('חזור לברירת המחדל'),
            onPressed: hasPatch ? () => _update(_cleared(policy, c)) : null,
          ),
        ),
      ),
    ];
  }

  TextDisplayPolicy _cleared(TextDisplayPolicy policy, _Case c) =>
      policy.withLayer(c.bookClass, policy.layer(c.bookClass).without(c.slot));

  List<Widget> _buildPicker(BuildContext context, TextDisplayPolicy policy) {
    final t = context.settingsText;
    final c = (
      bookClass: _bookClass,
      slot: TextDisplaySlot(target: _target, view: _view, channel: _channel),
    );
    final theme = Theme.of(context);
    return [
      SettingsActionTile.segmentedTile<TextDisplayBookClass>(
        icon: OtzariaIcons.bookshelf_24_regular,
        title: t('ספרים'),
        currentValue: _bookClass,
        options: [
          SegmentOption(
            value: TextDisplayBookClass.general,
            label: t('כל הספרים'),
          ),
          SegmentOption(value: TextDisplayBookClass.tanach, label: t('תנ"ך')),
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
          SegmentOption(value: TextChannel.export, label: t('ייצוא והדפסה')),
        ],
        onChanged: (v) => setState(() => _channel = v),
      ),
      if (c == _generalRoot)
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
      else ...[
        SettingsActionTile.text(
          icon: FluentIcons.branch_fork_24_regular,
          title: _dimsLabel(t, c),
          subtitle: _caseSubtitle(t, policy, c),
        ),
        ..._caseEditor(context, policy, c),
      ],
    ];
  }

  String _caseSubtitle(_Text t, TextDisplayPolicy policy, _Case c) {
    final patch = policy.layer(c.bookClass).patchFor(c.slot);
    if (patch.isNotEmpty) return _patchSummary(t, patch);
    return t(
      'כמו {source}',
      args: {'source': _sourceLabel(t, _inheritedFrom(policy, c))},
    );
  }

  /// הצירוף הקרוב ביותר שממנו [c] יורש בפועל — באותו סדר שבו הפותר סורק.
  _Case _inheritedFrom(TextDisplayPolicy policy, _Case c) {
    final isTanach = c.bookClass == TextDisplayBookClass.tanach;
    final classes = [
      if (isTanach) TextDisplayBookClass.tanach,
      TextDisplayBookClass.general,
    ];
    for (final slot in c.slot.inheritanceChain) {
      for (final bookClass in classes) {
        final candidate = (bookClass: bookClass, slot: slot);
        if (candidate == c) continue;
        if (policy.layer(bookClass).patchFor(slot).isNotEmpty) {
          return candidate;
        }
      }
    }
    return _generalRoot;
  }

  String _sourceLabel(_Text t, _Case c) {
    if (c == _generalRoot) return t('בתצוגה');
    return switch (_namedCases.indexOf(c)) {
      0 => t('במפרשים', context: 'source'),
      1 => t('בהעתקה', context: 'source'),
      2 => t('בייצוא ובהדפסה', context: 'source'),
      3 => t('בצורת הדף', context: 'source'),
      4 => t('בתנ"ך', context: 'source'),
      _ => _dimsLabel(t, c),
    };
  }

  /// תווית קצרה לצירוף: רק הממדים שאינם ברירת המחדל.
  String _dimsLabel(_Text t, _Case c) {
    final slot = c.slot;
    final parts = [
      if (c.bookClass == TextDisplayBookClass.tanach) t('תנ"ך'),
      if (slot.target == TextTarget.commentary) t('מפרשים'),
      if (slot.view == TextView.pageShape) t('צורת הדף'),
      if (slot.channel == TextChannel.copy) t('העתקה'),
      if (slot.channel == TextChannel.export) t('ייצוא והדפסה'),
    ];
    return parts.isEmpty ? t('כל הספרים') : parts.join(' · ');
  }

  String _patchSummary(_Text t, TextDisplayPatch patch) {
    String visibility(MarkVisibility v) =>
        v == MarkVisibility.show ? t('הצג') : t('הסתר');
    final parts = [
      if (patch.nikud case final v?) '${t('ניקוד')}: ${visibility(v)}',
      if (patch.teamim case final v?)
        '${t('טעמי המקרא')}: ${switch (v) {
          TeamimVisibility.show => t('הצג'),
          TeamimVisibility.hide => t('הסתר'),
          TeamimVisibility.followNikud => t('כמו הניקוד'),
        }}',
      if (patch.punctuation case final v?)
        '${t('סימני פיסוק')}: ${visibility(v)}',
      if (patch.holyName case final v?)
        '${t('שם הוי"ה')}: ${switch (v) {
          HolyNameDisplay.asIs => t('ככתבו'),
          HolyNameDisplay.kufKuf => t('יקוק'),
          HolyNameDisplay.hehApostrophe => t("ה'"),
        }}',
      if (patch.anchorMarkers case final v?)
        '${t('ציוני המפרשים')}: ${visibility(v)}',
    ];
    return parts.join(' · ');
  }
}
