import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

const String _kFontSampleText = 'אבגד הוזח';

IconData? _fontCategoryIcon(FontCategory category) {
  switch (category) {
    case FontCategory.serif:
      return OtzariaIcons.alef_behind_alef_24_regular;
    case FontCategory.sansSerif:
      return OtzariaIcons.alef_behind_alef_24_regular;
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
  Widget build(BuildContext context) {
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

    final fontEntries = all
        .map(
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
        )
        .toList();

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
              context.settingsText(
                '{font} (לא זמין במחשב זה)',
                args: {'font': value},
              ),
        ),
      );
    }

    return AppDropdownField<String>(
      value: value,
      enabled: enabled,
      enableSearch: true,
      decoration:
          decoration ??
          const InputDecoration(
            border: OutlineInputBorder(),
          ),
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
        );
      },
      onSelected: (newValue) {
        if (newValue != null) {
          onChanged(newValue);
        }
      },
    );
  }
}

/// שם הגופן, ולצידו סימן מידע כשהגופן אינו ממפה את טעמי המקרא.
class _FontEntryLabel extends StatelessWidget {
  final Widget preview;
  final bool supportsTaamim;

  const _FontEntryLabel({required this.preview, required this.supportsTaamim});

  @override
  Widget build(BuildContext context) {
    if (supportsTaamim) return preview;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: preview),
        const SizedBox(width: 6),
        Tooltip(
          message: context.settingsText(
            'הגופן אינו תומך בטעמי המקרא; בטקסט עם טעמים יוצג גופן ברירת המחדל',
          ),
          child: Icon(
            FluentIcons.info_16_regular,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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
  void initState() {
    super.initState();
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
    final family = _loaded ? widget.fontFamily : null;
    return Text(
      widget.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontFamily: family),
    );
  }
}
