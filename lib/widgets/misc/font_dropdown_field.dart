import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/font_import_flow.dart';

const String _kFontSampleText = 'אבגד הוזח';

/// ערך שורת הפעולה "הוסף גופן מקובץ": לא שם גופן, ולכן לא נשלח ל-onChanged.
const String _kImportFontValue = '\u0000import-font';

IconData? _fontCategoryIcon(FontCategory category) {
  switch (category) {
    case FontCategory.serif:
      return OtzariaIcons.alef_behind_alef_24_filled;
    case FontCategory.sansSerif:
      return OtzariaIcons.alef_behind_alef_24_filled;
    case FontCategory.unknown:
      return null;
  }
}

/// שדה בחירת גופן מודרני מבוסס [AppDropdownField], עם תצוגה מקדימה ברינדור
/// של הגופן עצמו, צ'יפים לסינון (הכל / Serif / Sans), חיפוש ואזהרת תמיכה בטעמים.
class FontDropdownField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final bool enabled;

  const FontDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => _RebuildAfterSystemFontsScan(
    builder: (context, rebuild) => _buildField(context, rebuild),
  );

  /// בחירת קובץ גופן, ייבוא, והודעה למשתמש. גופן שיובא נבחר מיד.
  Future<void> _importFont(BuildContext context, VoidCallback rebuild) async {
    final result = await FontImportFlow.run(context);
    if (result == null || !context.mounted) return;
    rebuild();
    final message = fontImportMessage(context, result);
    if (result.succeeded) {
      UiSnack.showSuccess(message);
      if (result.families.isNotEmpty) onChanged(result.families.first);
    } else {
      UiSnack.showError(message);
    }
  }

  Widget _buildField(BuildContext context, VoidCallback rebuild) {
    final all = AppFonts.availableFonts;

    // O(n) lookup במקום O(n²) — מחושב פעם אחת לכל build.
    final serifValues = {
      for (final f in all)
        if (f.category == FontCategory.serif) f.value,
    };
    final sansValues = {
      for (final f in all)
        if (f.category == FontCategory.sansSerif) f.value,
    };

    final fontEntries = <AppMenuEntry<String>>[
      if (AppFonts.supportsUserFontImport)
        AppMenuEntry<String>(
          value: _kImportFontValue,
          label: context.settingsText('הוסף גופן מקובץ…'),
          icon: FluentIcons.add_24_regular,
        ),
      ...all.map(
        (font) => AppMenuEntry<String>(
          value: font.value,
          label: font.label,
          icon: _fontCategoryIcon(font.category),
          reserveTrailingGap: true,
          trailingReservedWidth: 72,
          labelWidget: _FontEntryLabel(
            preview: _FontPreviewText(
              fontFamily: font.value,
              name: font.label,
              isBundled: AppFonts.fontPaths.containsKey(font.value),
            ),
            supportsTaamim: font.supportsTaamim,
            displayOnly: font.displayOnly,
          ),
          trailing: SizedBox(
            width: 72,
            child: Opacity(
              opacity: 0.6,
              child: _FontPreviewText(
                fontFamily: font.value,
                name: _kFontSampleText,
                isBundled: AppFonts.fontPaths.containsKey(font.value),
              ),
            ),
          ),
        ),
      ),
    ];

    // גופן נבחר שאינו מותקן כלל במחשב — מסומן בתווית מיוחדת.
    final hasSelectedFont =
        value.isEmpty || fontEntries.any((entry) => entry.value == value);
    if (!hasSelectedFont) {
      // ערך שמור מגרסה ישנה (שם קובץ) מוצג בשם המשפחה שלו, לא כ"לא זמין".
      final legacyName = AppFonts.legacySystemFontDisplayName(value);
      fontEntries.insert(
        0,
        AppMenuEntry(
          value: value,
          label:
              legacyName ??
              (AppFonts.systemFontsReady
                  ? context.settingsText(
                      '{font} (לא זמין במחשב זה)',
                      args: {'font': value},
                    )
                  : value),
        ),
      );
    }

    return AppDropdownField<String>(
      value: value,
      enabled: enabled,
      enableSearch: true,
      trackItemVisibility: true,
      decoration: decoration ?? const InputDecoration(),
      entries: fontEntries,
      filterLabels: [context.settingsText('הכל'), 'Serif', 'Sans'],
      filterPredicates: [
        null,
        (e) => serifValues.contains(e.value),
        (e) => sansValues.contains(e.value),
      ],
      menuMinWidth: 260,
      selectedBuilder: (context, selectedValue) {
        final v = selectedValue ?? '';
        final matchingFont = all.firstWhere(
          (font) => font.value == v,
          orElse: () => FontInfo(value: v, label: v),
        );
        // בשדה הסגור מציגים את שם הגופן (מרונדר בגופן עצמו לזיהוי).
        return _FontEntryLabel(
          preview: _FontPreviewText(
            fontFamily: v,
            name: matchingFont.label,
            isBundled: AppFonts.fontPaths.containsKey(v),
          ),
          supportsTaamim: AppFonts.familySupportsTaamim(v),
          displayOnly: AppFonts.isDisplayOnly(v),
        );
      },
      onSelected: (newValue) {
        if (newValue == _kImportFontValue) {
          _importFont(context, rebuild);
        } else if (newValue != null) {
          onChanged(newValue);
        }
      },
    );
  }
}

/// בונה מחדש כשסריקת גופני המערכת ברקע מסתיימת, כדי שיצטרפו לרשימה.
/// ה-builder מקבל גם פעולת בנייה מחדש, לרענון אחרי ייבוא גופן.
class _RebuildAfterSystemFontsScan extends StatefulWidget {
  final Widget Function(BuildContext context, VoidCallback rebuild) builder;

  const _RebuildAfterSystemFontsScan({required this.builder});

  @override
  State<_RebuildAfterSystemFontsScan> createState() =>
      _RebuildAfterSystemFontsScanState();
}

class _RebuildAfterSystemFontsScanState
    extends State<_RebuildAfterSystemFontsScan> {
  @override
  void initState() {
    super.initState();
    if (AppFonts.systemFontsReady) return;
    AppFonts.warmUpSystemFontsCache().whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _rebuild);
}

/// שם הגופן, ולצידו סימן "לתצוגה בלבד" כשאין לגופן קובץ (גופן מערכת ב-iOS),
/// וסימן מידע כשהגופן אינו ממפה את טעמי המקרא.
class _FontEntryLabel extends StatelessWidget {
  final Widget preview;
  final bool supportsTaamim;
  final bool displayOnly;

  const _FontEntryLabel({
    required this.preview,
    required this.supportsTaamim,
    this.displayOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (supportsTaamim && !displayOnly) return preview;
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: preview),
        if (displayOnly) ...[
          const SizedBox(width: AppTokens.spaceSM),
          Tooltip(
            message: context.settingsText(
              'גופן מערכת שמוצג בקריאה בלבד: בהדפסה, בייצוא PDF, בטיקון ובתוספים יוחלף בגופן מובנה',
            ),
            child: Text(
              context.settingsText('לתצוגה בלבד'),
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (!supportsTaamim) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: context.settingsText(
              'הגופן אינו תומך בטעמי המקרא; בטקסט עם טעמים יוצג גופן ברירת המחדל',
            ),
            child: Icon(
              FluentIcons.info_16_regular,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// מציג את שם הגופן (ובאופן אופציונלי מחרוזת דוגמה) מרונדרים בגופן עצמו.
/// עבור גופני מערכת טוען את הגופן ל-engine ברקע, ומציג ברירת-מחדל עד הטעינה.
class _FontPreviewText extends StatefulWidget {
  final String fontFamily;
  final String name;
  final bool isBundled;

  const _FontPreviewText({
    required this.fontFamily,
    required this.name,
    required this.isBundled,
  });

  @override
  State<_FontPreviewText> createState() => _FontPreviewTextState();
}

class _FontPreviewTextState extends State<_FontPreviewText> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveFont();
  }

  @override
  void didUpdateWidget(covariant _FontPreviewText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.isBundled != widget.isBundled) {
      _resolveFont();
    }
  }

  void _resolveFont() {
    if (!AppMenuItemVisibility.isVisibleOf(context)) {
      _loaded = false;
      return;
    }
    if (widget.isBundled) {
      _loaded = true;
      return;
    }
    _loaded = false;
    final family = widget.fontFamily;
    AppFonts.ensureFontLoaded(family).then((_) {
      if (mounted && widget.fontFamily == family) {
        setState(() => _loaded = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final family = _loaded && AppMenuItemVisibility.isVisibleOf(context)
        ? widget.fontFamily
        : null;
    return Text(
      widget.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontFamily: AppFonts.renderFontFamily(family)),
    );
  }
}
