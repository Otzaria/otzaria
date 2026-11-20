import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// עורך פרופיל תצוגה. מסך ההגדרות משתמש ב-[tiles] (שורה לכל שדה), והחלונית
/// בסרגל הספר ב-[popupTiles] (רשימה צפופה). שניהם משתמשים באותם פקדים —
/// מתגים, ותג "כמו הניקוד" עם מתג לטעמי המקרא (DD-32).
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
    // הצג/הסתר — מתג (דולק = מוצג), כמו בחלונית שבסרגל. שם הוי"ה נשאר
    // תפריט עם כל הנוסחים.
    return [
      _SwitchField(
        icon: OtzariaIcons.alef_niqqud_24_filled,
        title: t('ניקוד'),
        read: (p) => p.nikud == MarkVisibility.show,
        write: (p, v) =>
            p.copyWith(nikud: v ? MarkVisibility.show : MarkVisibility.hide),
      ),
      _TeamimField(
        icon: OtzariaIcons.alef_niqqud_taamim_24_filled,
        title: t('טעמי המקרא'),
      ),
      _SwitchField(
        icon: OtzariaIcons.alef_punctuation_24_filled,
        title: t('סימני פיסוק'),
        read: (p) => p.punctuation == MarkVisibility.show,
        write: (p, v) => p.copyWith(
          punctuation: v ? MarkVisibility.show : MarkVisibility.hide,
        ),
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
      _SwitchField(
        icon: OtzariaIcons.text_font_hebrew_24_filled,
        title: t('ציוני המפרשים'),
        subtitle: t('אותיות הציון שבטקסט, למשל (א)'),
        read: (p) => p.anchorMarkers == MarkVisibility.show,
        write: (p, v) => p.copyWith(
          anchorMarkers: v ? MarkVisibility.show : MarkVisibility.hide,
        ),
      ),
      _SwitchField(
        icon: OtzariaIcons.text_font_hebrew_24_filled,
        title: t('ציוני המפרשים כבדפוס'),
        subtitle: t('אות קטנה מורמת, בלי סוגריים ובלי הבדל בין המפרשים'),
        read: (p) => p.printLikeAnchorMarkers,
        write: (p, v) => p.copyWith(
          anchorMarkerStyle: v
              ? AnchorMarkerStyle.print
              : AnchorMarkerStyle.variants,
        ),
      ),
    ];
  }

  /// פקדים צפופים לחלונית הסרגל. שמות הקודש מוצגים כאן כמתג אחד שמחליף
  /// יחד את שם הוי"ה ואת שאר השמות; בחירת הנוסח נשארת בהגדרות המלאות.
  ///
  /// [preferredHolyName] — הנוסח שהמשתמש בחר לשם הוי"ה, לשימוש בהסתרה.
  static List<Widget> popupTiles(
    BuildContext context, {
    required TextDisplayProfile profile,
    required ValueChanged<TextDisplayProfile> onChanged,
    bool includeTeamimSelector = true,
    HolyNameDisplay preferredHolyName = HolyNameDisplay.kufKuf,
    bool includeHolyNames = true,
  }) {
    final t = context.settingsText;
    // אותם גדלים כמו בשאר התפריטים בתוכנה.
    final metrics =
        Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    final itemStyle = TextStyle(fontSize: metrics.fontSize);

    Widget visibilityRow({
      required IconData icon,
      required String title,
      required MarkVisibility value,
      required ValueChanged<MarkVisibility> onValue,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppTokens.spaceSMD,
          vertical: AppTokens.space2XS,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: metrics.iconSize,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.spaceSM),
            Expanded(
              child: Text(title, style: itemStyle),
            ),
            // קורא המסך מקריא את שם השורה עם המתג.
            Semantics(
              label: title,
              child: Switch(
                value: value == MarkVisibility.show,
                onChanged: (show) => onValue(
                  show ? MarkVisibility.show : MarkVisibility.hide,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      );
    }

    return [
      visibilityRow(
        icon: OtzariaIcons.alef_niqqud_24_filled,
        title: t('ניקוד'),
        value: profile.nikud,
        onValue: (v) => onChanged(profile.copyWith(nikud: v)),
      ),
      if (includeTeamimSelector)
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppTokens.spaceSMD,
            vertical: AppTokens.space2XS,
          ),
          child: Row(
            children: [
              Icon(
                OtzariaIcons.alef_niqqud_taamim_24_filled,
                size: metrics.iconSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Text(
                  t('טעמי המקרא'),
                  style: itemStyle,
                ),
              ),
              followNikudChip(
                context,
                profile: profile,
                onChanged: onChanged,
                textStyle: itemStyle,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              teamimSwitch(context, profile: profile, onChanged: onChanged),
            ],
          ),
        ),
      visibilityRow(
        icon: OtzariaIcons.alef_punctuation_24_filled,
        title: t('סימני פיסוק'),
        value: profile.punctuation,
        onValue: (v) => onChanged(profile.copyWith(punctuation: v)),
      ),
      visibilityRow(
        icon: OtzariaIcons.text_font_hebrew_24_filled,
        title: t('ציוני המפרשים'),
        value: profile.anchorMarkers,
        onValue: (v) => onChanged(profile.copyWith(anchorMarkers: v)),
      ),
      if (includeHolyNames)
        holyNamesTile(
          context,
          shown: holyNamesShown(profile),
          onShown: (show) => onChanged(
            withHolyNames(profile, show: show, preferred: preferredHolyName),
          ),
        ),
    ];
  }

  /// תג "כמו הניקוד" — משותף לחלונית ולמסך ההגדרות. בחור: גוון בהיר
  /// ומסגרת חומה; כבוי: מסגרת דקה וטקסט אפור. לחיצה מחליפה, ובניתוק
  /// נשארים על המצב שהיה בפועל.
  static Widget followNikudChip(
    BuildContext context, {
    required TextDisplayProfile profile,
    required ValueChanged<TextDisplayProfile> onChanged,
    required TextStyle textStyle,
  }) {
    final cs = Theme.of(context).colorScheme;
    final linked = profile.teamim == TeamimVisibility.followNikud;
    return Semantics(
      button: true,
      toggled: linked,
      child: Material(
        color: linked ? AppSurfaces.followChipFill(cs) : Colors.transparent,
        shape: AppTokens.followChipShape(
          BorderSide(
            width: linked ? 1.5 : 1,
            color: linked
                ? AppSurfaces.followChipBorder(cs)
                : cs.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(
            profile.copyWith(
              teamim: linked
                  ? (profile.removeTeamim
                        ? TeamimVisibility.hide
                        : TeamimVisibility.show)
                  : TeamimVisibility.followNikud,
            ),
          ),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            // הגופן העברי יושב נמוך בתיבה — הזזה קלה למעלה למרכוז.
            child: Transform.translate(
              offset: const Offset(0, -1.5),
              child: Text(
                context.settingsText('כמו הניקוד'),
                textAlign: TextAlign.center,
                style: textStyle.copyWith(
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                  fontWeight: linked ? FontWeight.w600 : FontWeight.normal,
                  color: linked ? cs.primary : cs.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// מתג טעמי המקרא: מראה את המצב בפועל. כש"כמו הניקוד" בחור הוא דהוי
  /// (מסלול ומסגרת גלויים), ולחיצה עליו קובעת הצג/הסתר ומבטלת את הקישור.
  static Widget teamimSwitch(
    BuildContext context, {
    required TextDisplayProfile profile,
    required ValueChanged<TextDisplayProfile> onChanged,
    bool shrinkWrap = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final linked = profile.teamim == TeamimVisibility.followNikud;
    final control = Switch(
      value: !profile.removeTeamim,
      onChanged: (show) => onChanged(
        profile.copyWith(
          teamim: show ? TeamimVisibility.show : TeamimVisibility.hide,
        ),
      ),
      materialTapTargetSize: shrinkWrap
          ? MaterialTapTargetSize.shrinkWrap
          : null,
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (!linked) return null;
        return states.contains(WidgetState.selected)
            ? AppSurfaces.linkedSwitchTrack(cs)
            : cs.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (!linked) return null;
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : AppSurfaces.linkedSwitchOutline(cs);
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (!linked) return null;
        return states.contains(WidgetState.selected)
            ? cs.surface
            : AppSurfaces.linkedSwitchThumb(cs);
      }),
    );
    return Semantics(
      label: context.settingsText('טעמי המקרא'),
      child: control,
    );
  }

  /// שמות הקודש מוצגים רק כששם הוי"ה וגם שאר השמות ככתבם; מצב מעורב = מוסתר.
  static bool holyNamesShown(TextDisplayProfile profile) =>
      profile.holyName == HolyNameDisplay.asIs &&
      profile.divineNames == DivineNamesDisplay.asIs;

  /// הצג: שניהם ככתבם. הסתר: נוסח קיים נשמר; אחרת הנוסח המועדף,
  /// ו"ככתבו" הופך ליקוק. שאר השמות — בכינוי.
  static TextDisplayProfile withHolyNames(
    TextDisplayProfile profile, {
    required bool show,
    required HolyNameDisplay preferred,
  }) => show
      ? profile.copyWith(
          holyName: HolyNameDisplay.asIs,
          divineNames: DivineNamesDisplay.asIs,
        )
      : profile.copyWith(
          holyName: profile.holyName != HolyNameDisplay.asIs
              ? profile.holyName
              : preferred != HolyNameDisplay.asIs
              ? preferred
              : HolyNameDisplay.kufKuf,
          divineNames: DivineNamesDisplay.substitute,
        );

  /// שורת "שמות הקודש" בסגנון שאר שורות החלונית.
  static Widget holyNamesTile(
    BuildContext context, {
    required bool shown,
    required ValueChanged<bool> onShown,
    String? subtitle,
  }) {
    final metrics =
        Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppTokens.spaceSMD,
        vertical: AppTokens.space2XS,
      ),
      child: Row(
        children: [
          Icon(
            OtzariaIcons.alef_crown_24_filled,
            size: metrics.iconSize,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.settingsText('שמות הקודש'),
                  style: TextStyle(fontSize: metrics.fontSize),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: metrics.fontSize - 2,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Semantics(
            label: context.settingsText('שמות הקודש'),
            child: Switch(
              value: shown,
              onChanged: onShown,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// שדה אחד בפרופיל: שורה במסך ההגדרות ([tile]).
sealed class _Field {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _Field({required this.icon, required this.title, this.subtitle});

  Widget tile(
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
}

/// הצג/הסתר כמתג (דולק = מוצג).
final class _SwitchField extends _Field {
  final bool Function(TextDisplayProfile) read;
  final TextDisplayProfile Function(TextDisplayProfile, bool) write;

  const _SwitchField({
    required super.icon,
    required super.title,
    super.subtitle,
    required this.read,
    required this.write,
  });

  @override
  Widget tile(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  ) => SettingsSwitchTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    value: read(profile),
    onChanged: (v) => onChanged(write(profile, v)),
  );
}

/// טעמי המקרא: תג "כמו הניקוד" ומתג — כמו בחלונית שבסרגל.
final class _TeamimField extends _Field {
  const _TeamimField({required super.icon, required super.title});

  Widget _controls(
    BuildContext context,
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextDisplayProfileEditor.followNikudChip(
        context,
        profile: profile,
        onChanged: onChanged,
        textStyle: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
      ),
      const SizedBox(width: AppTokens.spaceSM),
      TextDisplayProfileEditor.teamimSwitch(
        context,
        profile: profile,
        onChanged: onChanged,
        shrinkWrap: false,
      ),
    ],
  );

  @override
  Widget tile(
    TextDisplayProfile profile,
    ValueChanged<TextDisplayProfile> onChanged,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      // התג והמתג יורדים לשורה משלהם רק כשהכותרת באמת לא נכנסת לצידם —
      // מדידה מדויקת במקום ההערכה הכללית של SettingsActionTile.
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      double measure(String text, TextStyle? style) => (TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout()).width;
      final bodyStyle = Theme.of(context).textTheme.bodyMedium;
      const iconArea = 56.0, hPadding = 32.0, chipPadding = 24.0;
      const switchWidth = 60.0, gaps = AppTokens.spaceSM + 12;
      final needed =
          iconArea +
          hPadding +
          measure(title, AppTextStyles.settingTitle) +
          measure(context.settingsText('כמו הניקוד'), bodyStyle) +
          chipPadding +
          switchWidth +
          gaps;
      return SettingsActionTile.text(
        icon: icon,
        title: title,
        responsiveActions: constraints.maxWidth < needed,
        stacked: constraints.maxWidth < needed,
        actions: [_controls(context, profile, onChanged)],
      );
    },
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
  ) => Builder(
    builder: (context) {
      final theme = Theme.of(context);
      // הכפתור ברקע הכרטיס (ולא בגוון המודגש), עם מסגרת דקה שתבחין בו.
      return Theme(
        data: theme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppSurfaces.card(context),
              foregroundColor: theme.colorScheme.onSurface,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
        child: SettingsDropdownTile<T>(
          icon: icon,
          title: title,
          entries: entries,
          value: read(profile),
          onSelected: (v) {
            if (v != null) onChanged(write(profile, v));
          },
        ),
      );
    },
  );
}
