import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/view/widgets/marker_palette_editor.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// הגדרות המרקר: נראות הסימונים, הפקדים בקורא והפלטה.
class MarkerSettingsPanel extends StatelessWidget {
  const MarkerSettingsPanel({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'tools.marker.show',
      title: 'הצגת הסימונים בספרים',
      subtitle: 'כשהתצוגה כבויה הסימונים נשמרים, ואפשר להציג אותם שוב',
      tab: SettingsTab.tools,
      cardId: 'tools.marker',
      keywords: ['מרקר', 'סימון', 'הדגשה', 'צבע', 'מוסתר'],
    ),
    SettingsSearchEntry(
      id: 'tools.marker.context_menu',
      title: 'צבעי המרקר בתפריט הלחיצה הימנית',
      subtitle: 'בחרו טקסט, לחצו לחיצה ימנית ובחרו צבע',
      tab: SettingsTab.tools,
      cardId: 'tools.marker',
      keywords: ['מרקר', 'תפריט', 'לחיצה ימנית', 'סימון'],
    ),
    SettingsSearchEntry(
      id: 'tools.marker.commentary_menu',
      title: 'גם במפרשים',
      subtitle: 'במפרשים שמתחת לספר, בצד ובצורת הדף',
      tab: SettingsTab.tools,
      cardId: 'tools.marker',
      keywords: ['מרקר', 'מפרשים', 'צורת הדף', 'תפריט'],
    ),
    SettingsSearchEntry(
      id: 'tools.marker.pdf_menu',
      title: 'גם בספרי PDF',
      subtitle: 'גם כשבוחרים טקסט בספר PDF',
      tab: SettingsTab.tools,
      cardId: 'tools.marker',
      keywords: ['מרקר', 'PDF', 'תפריט', 'סימון'],
    ),
    SettingsSearchEntry(
      id: 'tools.marker.toolbar',
      title: 'כפתור המרקר בסרגל הקורא',
      subtitle: 'מסתיר ומציג את הסימונים, בספר שיש בו סימונים',
      tab: SettingsTab.tools,
      cardId: 'tools.marker',
      keywords: ['מרקר', 'סרגל', 'כפתור', 'הסתרה'],
    ),
    SettingsSearchEntry(
      id: 'tools.marker.palette',
      title: 'צבעי המרקר',
      subtitle: 'אילו צבעים מופיעים בתפריט, שמם וסדרם',
      tab: SettingsTab.tools,
      cardId: 'tools.marker',
      keywords: ['מרקר', 'צבעים', 'פלטה', 'הדגשה'],
    ),
    SettingsSearchEntry(
      id: 'tools.marker.default_color',
      title: 'צבע ברירת המחדל',
      subtitle: 'הצבע שקיצור המקלדת לסימון משתמש בו',
      tab: SettingsTab.tools,
      cardId: 'tools.marker',
      keywords: ['מרקר', 'צבע', 'צהוב', 'קיצור'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = MarkerSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final palette = settings.palette;
        final hidden = [
          for (final key in settings.hiddenBooks)
            MarkerSettings.bookOfHiddenKey(key),
        ]..sort((a, b) => a.title.compareTo(b.title));
        final menu = settings.showInContextMenu;
        final shortcut = ShortcutValidator.getShortcutValue(
          ShortcutValidator.markerHighlightKey,
        );
        return SettingsCard(
          cardId: 'tools.marker',
          title: context.settingsText('מרקר'),
          children: [
            SettingsActionTile.switchTile(
              icon: FluentIcons.highlight_24_regular,
              title: context.settingsText('הצגת הסימונים בספרים'),
              subtitle: context.settingsText(
                settings.showHighlights
                    ? 'הסימונים מוצגים בכל הספרים'
                    : 'הסימונים מוסתרים בכל הספרים, אבל נשמרים ואפשר להציג אותם שוב',
              ),
              value: settings.showHighlights,
              onChanged: settings.setShowHighlights,
            ),
            SettingsActionTile.switchTile(
              icon: FluentIcons.text_bullet_list_square_24_regular,
              title: context.settingsText('צבעי המרקר בתפריט הלחיצה הימנית'),
              subtitle: context.settingsText(
                menu
                    ? 'בחרו טקסט, לחצו לחיצה ימנית ובחרו צבע'
                    : 'הצבעים אינם מוצגים בתפריט. אפשר לסמן בקיצור המקלדת',
              ),
              value: menu,
              onChanged: settings.setShowInContextMenu,
            ),
            // המפרשים וספרי ה-PDF תלויים בצבעים שבתפריט, ומוצגים רק כשהם מופעלים.
            if (menu) ...[
              _Nested(
                child: SettingsActionTile.switchTile(
                  icon: FluentIcons.text_column_two_24_regular,
                  title: context.settingsText('גם במפרשים'),
                  subtitle: context.settingsText(
                    settings.showInCommentaryMenu
                        ? 'במפרשים שמתחת לספר, בצד ובצורת הדף'
                        : 'רק בטקסט של הספר עצמו, לא במפרשים',
                  ),
                  value: settings.showInCommentaryMenu,
                  onChanged: settings.setShowInCommentaryMenu,
                ),
              ),
              _Nested(
                child: SettingsActionTile.switchTile(
                  icon: FluentIcons.document_pdf_24_regular,
                  title: context.settingsText('גם בספרי PDF'),
                  subtitle: context.settingsText(
                    settings.showInPdfMenu
                        ? 'גם כשבוחרים טקסט בספר PDF'
                        : 'הצבעים אינם מוצגים בתפריט של ספרי PDF',
                  ),
                  value: settings.showInPdfMenu,
                  onChanged: settings.setShowInPdfMenu,
                ),
              ),
            ],
            SettingsActionTile.switchTile(
              icon: FluentIcons.toolbox_24_regular,
              title: context.settingsText('כפתור המרקר בסרגל הקורא'),
              subtitle: context.settingsText(
                settings.showToolbarButton
                    ? 'מסתיר ומציג את הסימונים בספר. מופיע רק בספר שיש בו סימונים'
                    : 'הכפתור אינו מוצג בסרגל',
              ),
              value: settings.showToolbarButton,
              onChanged: settings.setShowToolbarButton,
            ),
            SettingsActionTile.text(
              icon: FluentIcons.color_24_regular,
              title: context.settingsText('צבעי המרקר'),
              subtitle: context.settingsText(
                'אילו צבעים מופיעים בתפריט, שמם וסדרם',
              ),
              actions: [
                ActionButton.neutral(
                  text: context.settingsText('עריכה'),
                  onPressed: () => showMarkerPaletteEditor(context),
                ),
              ],
            ),
            SettingsActionTile.dropdownTile<String>(
              icon: FluentIcons.star_24_regular,
              title: context.settingsText('צבע ברירת המחדל'),
              // הקיצור עצמו מוגדר בלשונית קיצורי המקשים.
              subtitle: shortcut == null
                  ? context.settingsText(
                      'הצבע שקיצור המקלדת לסימון משתמש בו. הקיצור אינו מוגדר',
                    )
                  : context.settingsText(
                      'הצבע שקיצור המקלדת {shortcut} משתמש בו',
                      args: {
                        'shortcut': ShortcutHelper.formatShortcutForDisplay(
                          shortcut,
                        ),
                      },
                    ),
              value: palette.defaultColorId,
              entries: [
                for (final color in palette.menuColors)
                  AppMenuEntry(
                    value: color.id,
                    // שמות ברירת המחדל מתורגמים; שם שהמשתמש נתן נשאר כמות שהוא.
                    label: context.settingsText(color.label),
                    icon: FluentIcons.circle_24_filled,
                    iconColor: Color(color.argb),
                  ),
              ],
              onSelected: (id) {
                if (id == null) return;
                settings.setPalette(palette.copyWithDefault(id));
              },
            ),
            for (final book in hidden)
              SettingsActionTile.text(
                icon: FluentIcons.eye_off_24_regular,
                title: markerBookLabel(book.title, pdf: book.pdf),
                subtitle: context.settingsText('הסימונים בספר הזה מוסתרים'),
                actions: [
                  ActionButton.neutral(
                    text: context.settingsText('הצגה'),
                    onPressed: () => settings.setBookHidden(
                      book.title,
                      false,
                      pdf: book.pdf,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// הגדרה שתלויה בהגדרה שמעליה, מוזחת פנימה.
class _Nested extends StatelessWidget {
  final Widget child;

  const _Nested({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 32),
    child: child,
  );
}
