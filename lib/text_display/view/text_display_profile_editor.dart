import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/contained_tooltip.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// עורך פרופיל תצוגה — שורה לכל שדה. מסך ההגדרות משתמש ב-[tiles], והפופאפ
/// בסרגל הספר ב-[TextDisplayProfileTable]; שניהם בונים את אותם שדות מ-[_fields],
/// כדי שהמשתמש יראה את אותם פקדים בכל מקום.
abstract final class TextDisplayProfileEditor {
  /// השורות כרשימה — לשיבוץ ישיר בתוך [SettingsCard] (שמוסיף מפרידים).
  static List<Widget> tiles(
    BuildContext context, {
    required TextDisplayProfile profile,
    required ValueChanged<TextDisplayProfile> onChanged,
  }) => [
    for (final field in _fields(context)) field.tile(profile, onChanged),
  ];

  static List<_Field> _fields(BuildContext context) {
    final t = context.settingsText;
    final showHide = [
      SegmentOption(value: MarkVisibility.show, label: t('הצג')),
      SegmentOption(value: MarkVisibility.hide, label: t('הסתר')),
    ];
    return [
      _SegmentField<MarkVisibility>(
        icon: OtzariaIcons.alef_niqqud_24_filled,
        title: t('ניקוד'),
        options: showHide,
        read: (p) => p.nikud,
        write: (p, v) => p.copyWith(nikud: v),
      ),
      _SegmentField<TeamimVisibility>(
        icon: OtzariaIcons.alef_niqqud_taamim_24_filled,
        title: t('טעמי המקרא'),
        options: [
          SegmentOption(value: TeamimVisibility.show, label: t('הצג')),
          SegmentOption(value: TeamimVisibility.hide, label: t('הסתר')),
          SegmentOption(
            value: TeamimVisibility.followNikud,
            label: t('כמו הניקוד'),
          ),
        ],
        read: (p) => p.teamim,
        write: (p, v) => p.copyWith(teamim: v),
      ),
      _SegmentField<MarkVisibility>(
        icon: OtzariaIcons.alef_punctuation_24_filled,
        title: t('סימני פיסוק'),
        options: showHide,
        read: (p) => p.punctuation,
        write: (p, v) => p.copyWith(punctuation: v),
      ),
      _DropdownField<HolyNameDisplay>(
        icon: OtzariaIcons.alef_lock_24_filled,
        title: t('שם הוי"ה'),
        entries: [
          AppMenuEntry(value: HolyNameDisplay.asIs, label: t('ככתבו')),
          AppMenuEntry(value: HolyNameDisplay.kufKuf, label: t('יקוק')),
          AppMenuEntry(value: HolyNameDisplay.daletDalet, label: t('ידוד')),
          AppMenuEntry(value: HolyNameDisplay.hehApostrophe, label: t("ה'")),
          AppMenuEntry(value: HolyNameDisplay.doubleYod, label: t('יי')),
        ],
        read: (p) => p.holyName,
        write: (p, v) => p.copyWith(holyName: v),
      ),
      _SegmentField<DivineNamesDisplay>(
        icon: OtzariaIcons.alef_crown_24_filled,
        title: t('שאר שמות הקודש'),
        subtitle: t('אלהים, שדי, צבאות ועוד — בספרים שבהם השמות מסומנים'),
        options: [
          SegmentOption(value: DivineNamesDisplay.asIs, label: t('ככתבם')),
          SegmentOption(
            value: DivineNamesDisplay.substitute,
            label: t('בכינוי'),
          ),
        ],
        read: (p) => p.divineNames,
        write: (p, v) => p.copyWith(divineNames: v),
      ),
      _SegmentField<MarkVisibility>(
        icon: OtzariaIcons.text_font_hebrew_24_filled,
        title: t('ציוני המפרשים'),
        subtitle: t('אותיות הציון שבטקסט, למשל (א)'),
        options: showHide,
        read: (p) => p.anchorMarkers,
        write: (p, v) => p.copyWith(anchorMarkers: v),
      ),
    ];
  }
}

/// עמודה אחת בטבלה — פרופיל של יעד אחד והפעולה שמחילה שינוי בו.
typedef TextDisplayProfileColumn = ({
  String title,
  TextDisplayProfile profile,
  ValueChanged<TextDisplayProfile> onChanged,
});

/// הפרופילים כטבלה (q12 Q7): שורה לכל שדה, ועמודה לכל יעד ב-[columns].
/// אייקון ושם בעמודה הראשונה; ההסבר של שדה עובר ל-tooltip על השם. כשאין
/// מקום לטבלה (חלונית צרה, טלפון), השם עולה מעל, ולכל יעד שורה משלו.
class TextDisplayProfileTable extends StatelessWidget {
  final List<TextDisplayProfileColumn> columns;

  const TextDisplayProfileTable({super.key, required this.columns});

  /// רוחב עמודת השמות: אייקון, ריווח, ו"שאר שמות הקודש" בשורה אחת.
  static const double labelWidth = 152;

  /// התא הצר ביותר שבו "הצג | הסתר | כמו הניקוד" עוד נקרא.
  static const double minCellWidth = 200;

  /// רוחב שם היעד ("גוף הספר", "מפרשים") לפני הפקד, כשאין מקום לטבלה.
  static const double stackedTitleWidth = 76;

  static const _cellPadding = EdgeInsetsDirectional.only(
    start: AppTokens.spaceXS,
    top: AppTokens.spaceXS,
    bottom: AppTokens.spaceXS,
  );

  @override
  Widget build(BuildContext context) {
    final fields = TextDisplayProfileEditor._fields(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsSideBySide =
            constraints.maxWidth >= labelWidth + columns.length * minCellWidth;
        return fitsSideBySide
            ? _table(context, fields)
            : _stacked(context, fields);
      },
    );
  }

  Widget _heading(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      // כותרת עמודה בצבע הערכה (DD-14), בגודל של שורות הפאנל.
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }

  // בטבלה הפקד מופרד מהשם שלו; קורא המסך מקבל את השם ואת היעד יחד.
  Widget _cell(_Field field, TextDisplayProfileColumn column) => Semantics(
    container: true,
    label: '${field.title}, ${column.title}',
    child: Padding(
      padding: _cellPadding,
      child: field.cell(column.profile, column.onChanged),
    ),
  );

  Widget _table(BuildContext context, List<_Field> fields) => Table(
    columnWidths: {
      0: const FixedColumnWidth(labelWidth),
      for (var i = 1; i <= columns.length; i++) i: const FlexColumnWidth(),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
        children: [
          const SizedBox.shrink(),
          for (final column in columns)
            Padding(
              padding: _cellPadding,
              child: _heading(context, column.title),
            ),
        ],
      ),
      for (final field in fields)
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXS),
              child: _FieldLabel(field),
            ),
            for (final column in columns) _cell(field, column),
          ],
        ),
    ],
  );

  /// בלי מקום לטבלה: השם מעל, ומתחתיו שורה לכל יעד — שם היעד ואחריו הפקד
  /// ברוחב מלא, כי בחצי רוחב של טלפון "כמו הניקוד" ו"הסתר" נשברים.
  Widget _stacked(BuildContext context, List<_Field> fields) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final field in fields) ...[
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceSM),
          child: _FieldLabel(field),
        ),
        for (final column in columns)
          Row(
            children: [
              if (columns.length > 1)
                SizedBox(
                  width: stackedTitleWidth,
                  child: _heading(context, column.title),
                ),
              Expanded(child: _cell(field, column)),
            ],
          ),
      ],
    ],
  );
}

/// אייקון ושם של שדה; ההסבר, אם יש, ב-tooltip.
class _FieldLabel extends StatelessWidget {
  final _Field field;
  const _FieldLabel(this.field);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Row(
      children: [
        Icon(
          field.icon,
          size: AppTokens.iconMD,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppTokens.spaceSM),
        Flexible(child: Text(field.title, style: theme.textTheme.bodyMedium)),
      ],
    );
    final subtitle = field.subtitle;
    return subtitle == null
        ? label
        : ContainedTooltip(message: subtitle, child: label);
  }
}

/// שדה אחד בפרופיל: שורה במסך ההגדרות ([tile]) ותא בטבלה ([cell]).
sealed class _Field {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _Field({required this.icon, required this.title, this.subtitle});

  Widget tile(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  );

  Widget cell(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  );
}

final class _SegmentField<T> extends _Field {
  final List<SegmentOption<T>> options;
  final T Function(TextDisplayProfile) read;
  final TextDisplayProfile Function(TextDisplayProfile, T) write;

  const _SegmentField({
    required super.icon,
    required super.title,
    super.subtitle,
    required this.options,
    required this.read,
    required this.write,
  });

  @override
  Widget tile(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  ) => SettingsSegmentedTile<T>(
    icon: icon,
    title: title,
    subtitle: subtitle,
    options: options,
    currentValue: read(profile),
    onChanged: (v) => onChanged(write(profile, v)),
  );

  @override
  Widget cell(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  ) => AppSegmentedControl<T>(
    options: options,
    currentValue: read(profile),
    onChanged: (v) => onChanged(write(profile, v)),
    expandToFillWidth: true,
    // "כמו הניקוד" אינו נכנס בשליש תא, ויורד לשתי שורות.
    maxLabelLines: 2,
  );
}

final class _DropdownField<T> extends _Field {
  final List<AppMenuEntry<T>> entries;
  final T Function(TextDisplayProfile) read;
  final TextDisplayProfile Function(TextDisplayProfile, T) write;

  const _DropdownField({
    required super.icon,
    required super.title,
    required this.entries,
    required this.read,
    required this.write,
  });

  @override
  Widget tile(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  ) => SettingsDropdownTile<T>(
    icon: icon,
    title: title,
    entries: entries,
    value: read(profile),
    onSelected: (v) {
      if (v != null) onChanged(write(profile, v));
    },
  );

  @override
  Widget cell(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  ) => AppDropdownField<T>(
    value: read(profile),
    // בתא אין תווית גלויה מעל השדה: השם הנגיש וה-tooltip (DESIGN_SYSTEM §3.3).
    semanticLabel: title,
    entries: entries,
    onSelected: (v) {
      if (v != null) onChanged(write(profile, v));
    },
  );
}
