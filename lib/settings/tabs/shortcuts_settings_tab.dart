import 'package:flutter/material.dart';
import 'dart:io';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/view/custom_shortcut_dialog.dart';
import 'package:otzaria/shortcuts/view/shortcut_dropdown_tile.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';

/// טאב קיצורי מקלדת — מוצג רק בדסקטופ.
class ShortcutsSettingsTab extends StatelessWidget {
  const ShortcutsSettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'shortcuts.reset',
      title: 'איפוס קיצורי מקשים',
      subtitle: 'החזרת כל קיצורי המקלדת לברירת המחדל',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['איפוס', 'ברירת מחדל', 'מקלדת'],
    ),
    // ── ניווט כללי ──
    SettingsSearchEntry(
      id: 'shortcuts.nav.library',
      title: 'קיצור לספרייה',
      subtitle: 'פתיחת מסך הספרייה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['ספרייה', 'ctrl+l', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.find_ref',
      title: 'קיצור לאיתור',
      subtitle: 'פתיחת מסך איתור מהיר',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['איתור', 'ctrl+o', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.reading',
      title: 'קיצור לעיון',
      subtitle: 'פתיחת מסך העיון בספרים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['עיון', 'ctrl+r', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.search_window',
      title: 'קיצור לחיפוש חדש בכל הספרים',
      subtitle: 'פתיחת חלון חיפוש',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['חיפוש', 'ctrl+shift+f', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.advanced_search',
      title: 'קיצור לחיפוש מתקדם',
      subtitle: 'פתיחת חלון חיפוש במצב מתקדם',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['חיפוש', 'מתקדם', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.settings',
      title: 'קיצור להגדרות',
      subtitle: 'פתיחת מסך ההגדרות',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['הגדרות', 'ctrl+comma', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.tools',
      title: 'קיצור לכלים',
      subtitle: 'פתיחת מסך הכלים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['כלים', 'ctrl+m', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.bookmarks',
      title: 'קיצור לסימניות',
      subtitle: 'פתיחת מסך הסימניות',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סימניות', 'ctrl+shift+b', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.history',
      title: 'קיצור להיסטוריה',
      subtitle: 'פתיחת מסך ההיסטוריה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['היסטוריה', 'ctrl+h', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.nav.workspace',
      title: 'קיצור להחלף שולחן עבודה',
      subtitle: 'מעבר בין שולחנות עבודה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['שולחן עבודה', 'workspace', 'ctrl+k', 'מקלדת'],
    ),
    // ── תצוגת ספר ──
    SettingsSearchEntry(
      id: 'shortcuts.book.search_in_book',
      title: 'קיצור לחיפוש בספר הפתוח',
      subtitle: 'משמש לחיפוש מהיר במסכי תוכן וכלים תומכים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['חיפוש', 'בספר', 'ctrl+f', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.print',
      title: 'קיצור להדפסה',
      subtitle: 'הדפסת התוכן הנוכחי',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['הדפסה', 'ctrl+p', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.bookmark',
      title: 'קיצור להוסף סימניה',
      subtitle: 'שמירת סימניה במיקום הנוכחי',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סימניה', 'הוסף סימניה', 'ctrl+b', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.note',
      title: 'קיצור להוספת הערה',
      subtitle: 'הוספת הערה אישית',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['הערה', 'אישית', 'ctrl+n', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.close',
      title: 'קיצור לסגור ספר נוכחי',
      subtitle: 'סגירת הספר הפתוח',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סגור ספר', 'ctrl+w', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.close_all',
      title: 'קיצור לסגור כל הספרים',
      subtitle: 'סגירת כל הספרים הפתוחים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['סגור הכל', 'ctrl+shift+w', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.restore_closed',
      title: 'קיצור לפתיחת כרטיסייה אחרונה שנסגרה',
      subtitle: 'שחזור הכרטיסייה האחרונה שנסגרה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['שחזור', 'כרטיסייה', 'ctrl+shift+t', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.toggle_nav_pane',
      title: 'קיצור לפתח/סגור חלונית ניווט',
      subtitle: 'טוגל לחלונית הניווט הצדדית',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['ניווט', 'חלונית', 'ctrl+shift+l', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.toggle_commentators_pane',
      title: 'קיצור לפתח/סגור חלונית מפרשים',
      subtitle: 'טוגל לחלונית המפרשים בצד',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['מפרשים', 'חלונית', 'ctrl+shift+c', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.open_commentators_tab',
      title: 'קיצור לפתיחת כרטיסיית מפרשים',
      subtitle: 'פתיחת המפרשים בכרטיסייה נפרדת ליד הספר הנוכחי',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['מפרשים', 'כרטיסייה', 'טאב', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.toggle_pdf_view',
      title: 'קיצור להחלפת מצב תצוגה PDF/טקסט',
      subtitle: 'מעבר בין תצוגת PDF לתצוגת טקסט',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['PDF', 'טקסט', 'תצוגה', 'מקלדת', 'ctrl+shift+p'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.prev_toc',
      title: 'קיצור לדף/פרק הקודם',
      subtitle: 'מעבר לכותרת הקודמת (דף/פרק) בספר',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['דף', 'פרק', 'ניווט', 'קודם', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.next_toc',
      title: 'קיצור לדף/פרק הבא',
      subtitle: 'מעבר לכותרת הבאה (דף/פרק) בספר',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['דף', 'פרק', 'ניווט', 'הבא', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.prev_segment',
      title: 'קיצור לקטע הקודם',
      subtitle: 'גלילה לקטע הקודם בספר',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['קטע', 'ניווט', 'קודם', 'גלילה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.book.next_segment',
      title: 'קיצור לקטע הבא',
      subtitle: 'גלילה לקטע הבא בספר',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['קטע', 'ניווט', 'הבא', 'גלילה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.calendar.toggle_times',
      title: 'קיצור לפתיחה/סגירה זמני היום בלוח שנה',
      subtitle: 'הצגה/הסתרה של זמני היום',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['לוח שנה', 'זמנים', 'זמני היום', 'מקלדת', 'ctrl+t'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.calendar.toggle_events',
      title: 'קיצור לפתיחה/סגירה אירועים בלוח שנה',
      subtitle: 'הצגה/הסתרה של אירועים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['לוח שנה', 'אירועים', 'מקלדת', 'ctrl+e'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.calendar.today',
      title: 'קיצור למעבר להיום בלוח שנה',
      subtitle: 'ניווט מהיר לתאריך היום',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['לוח שנה', 'היום', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.calendar.create_event',
      title: 'קיצור ליצירת אירוע בלוח שנה',
      subtitle: 'פתיחת חלון יצירת אירוע',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['לוח שנה', 'אירוע', 'יצירה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.calendar.toggle_view',
      title: 'קיצור למעבר בין תצוגות לוח שנה',
      subtitle: 'החלפה בין תצוגות שונות',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['לוח שנה', 'תצוגה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.shamor_zachor.cycle_filter',
      title: 'קיצור למעבר בין סינונים בשמור וזכור',
      subtitle: 'מחזור בין הסינונים השונים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['שמור וזכור', 'סינון', 'מקלדת', 'ctrl+s'],
    ),
    // ── פתיחת כלים ──
    SettingsSearchEntry(
      id: 'shortcuts.open_tool.calendar',
      title: 'קיצור לפתיחת לוח שנה',
      subtitle: 'פתיחה מהירה של כלי לוח השנה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['לוח שנה', 'כלים', 'פתיחה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.open_tool.shamor_zachor',
      title: 'קיצור לפתיחת שמור וזכור',
      subtitle: 'פתיחה מהירה של כלי שמור וזכור',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['שמור וזכור', 'כלים', 'פתיחה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.open_tool.measurements',
      title: 'קיצור לפתיחת מדות ושיעורים',
      subtitle: 'פתיחה מהירה של כלי מדות ושיעורים',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['מדות', 'שיעורים', 'כלים', 'פתיחה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.open_tool.notes',
      title: 'קיצור לפתיחת הערות אישיות',
      subtitle: 'פתיחה מהירה של כלי ההערות האישיות',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['הערות', 'אישיות', 'כלים', 'פתיחה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.open_tool.gematria',
      title: 'קיצור לפתיחת גימטריה',
      subtitle: 'פתיחה מהירה של כלי הגימטריה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['גימטריה', 'כלים', 'פתיחה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.open_tool.aramaic_dictionary',
      title: 'קיצור לפתיחת מילון ארמי-עברי',
      subtitle: 'פתיחה מהירה של המילון הארמי-עברי',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['מילון', 'ארמי', 'עברי', 'כלים', 'פתיחה', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.open_tool.acronyms_dictionary',
      title: 'קיצור לפתיחת ראשי תיבות',
      subtitle: 'פתיחה מהירה של מילון ראשי התיבות',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['ראשי תיבות', 'מילון', 'כלים', 'פתיחה', 'מקלדת'],
    ),
    // ── העתקת קישורים ──
    SettingsSearchEntry(
      id: 'shortcuts.copy_link.book',
      title: 'קיצור להעתקת קישור ישיר לספר',
      subtitle: 'העתקת קישור ישיר לספר המוצג',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['קישור', 'העתק', 'ספר', 'deep link', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.copy_link.section',
      title: 'קיצור להעתקת קישור למקטע / לעמוד',
      subtitle: 'בטקסט — קישור למקטע הנוכחי; ב-PDF — קישור לעמוד הנוכחי',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['קישור', 'העתק', 'מקטע', 'עמוד', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.copy_link.section_mark',
      title: 'קיצור להעתקת קישור עם הדגשת המקטע',
      subtitle: 'קישור שמדגיש את המקטע הנוכחי בעת הפתיחה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['קישור', 'העתק', 'הדגשה', 'מקטע', 'מקלדת'],
    ),
    SettingsSearchEntry(
      id: 'shortcuts.copy_link.text_mark',
      title: 'קיצור להעתקת קישור עם הדגשת הטקסט',
      subtitle: 'קישור שמדגיש את הטקסט המסומן בעת הפתיחה',
      tab: SettingsTab.shortcuts,
      cardId: 'shortcuts.main',
      keywords: ['קישור', 'העתק', 'הדגשה', 'טקסט', 'מקלדת'],
    ),
  ];

  /// אוסף הקיצורים הזמינים לבחירה ב-dropdown. התווית נגזרת דינמית כדי
  /// ש-Mac יציג `⌘` במקום `CTRL`. הערך (המפתח) נשאר קנוני (`ctrl+X`).
  static final Map<String, String> _shortcutsList = _buildShortcutsList();

  static Map<String, String> _buildShortcutsList() {
    const List<String> keys = [
      'ctrl+a',
      'ctrl+b',
      'ctrl+c',
      'ctrl+d',
      'ctrl+e',
      'ctrl+f',
      'ctrl+g',
      'ctrl+h',
      'ctrl+i',
      'ctrl+j',
      'ctrl+k',
      'ctrl+l',
      'ctrl+m',
      'ctrl+n',
      'ctrl+o',
      'ctrl+p',
      'ctrl+q',
      'ctrl+r',
      'ctrl+s',
      'ctrl+t',
      'ctrl+u',
      'ctrl+v',
      'ctrl+w',
      'ctrl+x',
      'ctrl+y',
      'ctrl+z',
      'ctrl+0',
      'ctrl+1',
      'ctrl+2',
      'ctrl+3',
      'ctrl+4',
      'ctrl+5',
      'ctrl+6',
      'ctrl+7',
      'ctrl+8',
      'ctrl+9',
      'ctrl+comma',
      'ctrl+shift+b',
      'ctrl+shift+c',
      'ctrl+shift+e',
      'ctrl+shift+f',
      'ctrl+shift+l',
      'ctrl+shift+n',
      'ctrl+shift+p',
      'ctrl+shift+t',
      'ctrl+shift+w',
    ];
    return {
      for (final k in keys) k: ShortcutHelper.formatShortcutForDisplay(k),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      return const Center(child: Text('קיצורי מקשים זמינים רק בדסקטופ'));
    }

    return SingleChildScrollView(
      primary: true,
      padding: const EdgeInsets.all(16.0),
      child: ToolPanelWrapper(
        // עוטף ב-BlocBuilder כדי לרענן את רשימת הטיילים והכרטיס "הוסף קיצור"
        // מיד עם שינוי הקיצורים (פעולה זמינה -> מוגדרת ולהיפך).
        child: BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (previous, current) =>
              previous.shortcuts != current.shortcuts,
          builder: (context, _) => _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final unconfiguredKeys = ShortcutValidator.shortcutKeys
        .where((k) => (ShortcutValidator.getShortcutValue(k) ?? '').isEmpty)
        .toList();

    // קיצורי "פתיחת כלים" הם ללא ברירת מחדל, ולכן הכרטיס מוצג רק אם המשתמש
    // הגדיר קיצור לפחות לכלי אחד.
    final openToolTiles = _onlyConfigured([
      _ShortcutTile(
        settingKey: 'key-shortcut-open-tool-calendar',
        label: 'פתיחת לוח שנה',
        icon: FluentIcons.calendar_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: 'key-shortcut-open-tool-shamor-zachor',
        label: 'פתיחת שמור וזכור',
        icon: FluentIcons.checkmark_circle_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: 'key-shortcut-open-tool-measurements',
        label: 'פתיחת מדות ושיעורים',
        icon: FluentIcons.ruler_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: 'key-shortcut-open-tool-notes',
        label: 'פתיחת הערות אישיות',
        icon: FluentIcons.note_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: 'key-shortcut-open-tool-gematria',
        label: 'פתיחת גימטריה',
        icon: FluentIcons.calculator_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: 'key-shortcut-open-tool-aramaic-dictionary',
        label: 'פתיחת מילון ארמי-עברי',
        icon: FluentIcons.translate_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: 'key-shortcut-open-tool-acronyms-dictionary',
        label: 'פתיחת ראשי תיבות',
        icon: FluentIcons.text_quote_24_regular,
        allShortcuts: _shortcutsList,
      ),
    ]);

    // קיצורי "פתיחת תוסף" אופציונליים, לכל תוסף מותקן פעיל. כמו פתיחת כלים,
    // הכרטיס מוצג רק אם הוגדר קיצור לתוסף אחד לפחות.
    final pluginState = context.watch<PluginSystemBloc>().state;
    final enabledPlugins = pluginState is PluginSystemLoaded
        ? pluginState.plugins.where((p) => p.enabled).toList()
        : const <InstalledPlugin>[];
    final openPluginTiles = _onlyConfigured([
      for (final plugin in enabledPlugins)
        _ShortcutTile(
          settingKey: ShortcutValidator.openPluginShortcutKey(plugin.pluginId),
          label: 'פתיחת ${plugin.name}',
          icon:
              fluentIconFromName(plugin.manifest.toolTabIconName) ??
              FluentIcons.puzzle_piece_24_regular,
          allShortcuts: _shortcutsList,
        ),
    ]);

    // קיצורי "העתקת קישור" אופציונליים, ללא ברירת מחדל. כמו פתיחת כלים,
    // הכרטיס מוצג רק אם הוגדר קיצור לפעולה אחת לפחות.
    final copyLinkTiles = _onlyConfigured([
      _ShortcutTile(
        settingKey: ShortcutValidator.copyBookLinkKey,
        label: 'העתק קישור ישיר לספר',
        icon: FluentIcons.link_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: ShortcutValidator.copySectionLinkKey,
        label: 'העתק קישור למקטע / לעמוד',
        subtitle: 'בטקסט — מקטע; ב-PDF — עמוד',
        icon: FluentIcons.link_multiple_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: ShortcutValidator.copySectionMarkLinkKey,
        label: 'העתק קישור עם הדגשת המקטע',
        icon: FluentIcons.document_one_page_24_regular,
        allShortcuts: _shortcutsList,
      ),
      _ShortcutTile(
        settingKey: ShortcutValidator.copyTextMarkLinkKey,
        label: 'העתק קישור עם הדגשת הטקסט',
        icon: FluentIcons.highlight_24_regular,
        allShortcuts: _shortcutsList,
      ),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── כללי (איפוס) ──────────────────────────────────────────────
        SettingsCard(
          cardId: 'shortcuts.main',
          title: 'כללי',
          children: [
            SettingsActionTile.text(
              icon: FluentIcons.arrow_reset_24_regular,
              title: 'איפוס קיצורי מקשים',
              subtitle: 'החזר את כל קיצורי המקשים לברירת המחדל',
              actions: [
                ActionButton.ghost(
                  text: 'איפוס',
                  onPressed: () => _resetShortcuts(context),
                ),
              ],
            ),
          ],
        ),

        kSettingsCardSpacing,

        // ── ניווט כללי ────────────────────────────────────────────────
        SettingsCard(
          title: 'ניווט כללי',
          children: _onlyConfigured([
            _ShortcutTile(
              settingKey: 'key-shortcut-open-library-browser',
              label: 'ספרייה',
              icon: FluentIcons.library_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-find-ref',
              label: 'איתור',
              icon: FluentIcons.book_search_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-reading-screen',
              label: 'עיון',
              icon: FluentIcons.book_open_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-new-search',
              label: 'חיפוש חדש בכל הספרים',
              icon: FluentIcons.search_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: ShortcutValidator.openAdvancedSearchKey,
              label: 'חיפוש מתקדם',
              icon: FluentIcons.search_info_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-settings',
              label: 'הגדרות',
              icon: FluentIcons.settings_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-more',
              label: 'כלים',
              icon: FluentIcons.apps_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-bookmarks',
              label: 'סימניות',
              icon: FluentIcons.bookmark_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-history',
              label: 'היסטוריה',
              icon: FluentIcons.history_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-switch-workspace',
              label: 'החלף שולחן עבודה',
              icon: FluentIcons.grid_24_regular,
              allShortcuts: _shortcutsList,
            ),
          ]),
        ),

        kSettingsCardSpacing,

        // ── תצוגת ספר ─────────────────────────────────────────────────
        SettingsCard(
          title: 'תצוגת ספר',
          children: _onlyConfigured([
            _ShortcutTile(
              settingKey: ShortcutValidator.currentWindowSearchKey,
              label: 'חיפוש בספר הפתוח',
              subtitle: 'משמש לחיפוש מהיר במסכי ספרים פתוחים',
              icon: FluentIcons.search_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-print',
              label: 'הדפסה',
              icon: FluentIcons.print_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-add-bookmark',
              label: 'הוסף סימניה',
              icon: FluentIcons.bookmark_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-add-note',
              label: 'הוספת הערה',
              icon: FluentIcons.note_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-close-tab',
              label: 'סגור ספר נוכחי',
              icon: FluentIcons.dismiss_circle_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-close-all-tabs',
              label: 'סגור כל הספרים',
              icon: FluentIcons.dismiss_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-restore-closed-tab',
              label: 'פתח כרטיסייה אחרונה שנסגרה',
              icon: FluentIcons.arrow_undo_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-toggle-nav-pane',
              label: 'פתח/סגור חלונית ניווט',
              icon: FluentIcons.panel_left_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-toggle-commentators-pane',
              label: 'פתח/סגור חלונית מפרשים',
              icon: FluentIcons.panel_right_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-toggle-pdf-view',
              label: 'החלף מצב תצוגה (PDF/טקסט)',
              icon: FluentIcons.document_pdf_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-open-commentators-tab',
              label: 'פתח כרטיסיית מפרשים',
              icon: FluentIcons.open_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-prev-toc',
              label: 'הדף/פרק הקודם',
              icon: FluentIcons.arrow_previous_24_filled,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-next-toc',
              label: 'הדף/פרק הבא',
              icon: FluentIcons.arrow_next_24_filled,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-prev-segment',
              label: 'הקטע הקודם',
              icon: FluentIcons.chevron_up_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-next-segment',
              label: 'הקטע הבא',
              icon: FluentIcons.chevron_down_24_regular,
              allShortcuts: _shortcutsList,
            ),
          ]),
        ),

        kSettingsCardSpacing,

        // ── לוח שנה ושמור וזכור ───────────────────────────────────────
        SettingsCard(
          title: 'לוח שנה ושמור וזכור',
          children: _onlyConfigured([
            _ShortcutTile(
              settingKey: 'key-shortcut-calendar-toggle-times',
              label: 'לוח שנה: פתיחה/סגירה זמני היום',
              icon: FluentIcons.clock_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-calendar-toggle-events',
              label: 'לוח שנה: פתיחה/סגירה אירועים',
              icon: FluentIcons.calendar_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-calendar-today',
              label: 'לוח שנה: מעבר להיום',
              icon: FluentIcons.calendar_today_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-calendar-create-event',
              label: 'לוח שנה: יצירת אירוע',
              icon: FluentIcons.calendar_add_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-calendar-toggle-view',
              label: 'לוח שנה: מעבר בין תצוגות',
              icon: FluentIcons.calendar_multiple_24_regular,
              allShortcuts: _shortcutsList,
            ),
            _ShortcutTile(
              settingKey: 'key-shortcut-shamor-zachor-cycle-filter',
              label: 'שמור וזכור: מעבר בין הסינונים',
              icon: FluentIcons.filter_24_regular,
              allShortcuts: _shortcutsList,
            ),
          ]),
        ),

        // ── פתיחת כלים (אופציונלי) — מוצג רק כשהוגדר קיצור לכלי אחד לפחות ──
        if (openToolTiles.isNotEmpty) ...[
          kSettingsCardSpacing,
          SettingsCard(
            title: 'פתיחת כלים',
            subtitle: 'קיצורים לפתיחה מהירה של כלי מתוך מסך הכלים',
            children: openToolTiles,
          ),
        ],

        // ── פתיחת תוספים (אופציונלי) — מוצג רק כשהוגדר קיצור לתוסף אחד לפחות ──
        if (openPluginTiles.isNotEmpty) ...[
          kSettingsCardSpacing,
          SettingsCard(
            title: 'פתיחת תוספים',
            subtitle: 'קיצורים לפתיחה מהירה של תוסף מותקן',
            children: openPluginTiles,
          ),
        ],

        // ── העתקת קישורים (אופציונלי) — מוצג רק כשהוגדר קיצור אחד לפחות ──
        if (copyLinkTiles.isNotEmpty) ...[
          kSettingsCardSpacing,
          SettingsCard(
            title: 'העתקת קישורים',
            subtitle: 'קיצורים להעתקת קישור ישיר לספר, למקטע/לעמוד ולהדגשות',
            children: copyLinkTiles,
          ),
        ],

        // ── פעולות זמינות להגדרת קיצור ────────────────────────────────
        if (unconfiguredKeys.isNotEmpty) ...[
          kSettingsCardSpacing,
          SettingsCard(
            title: 'פעולות זמינות לקיצור',
            subtitle:
                'פעולות הקיימות באפליקציה ועדיין לא הוגדר להן קיצור מקלדת',
            children: [
              SettingsActionTile.text(
                icon: FluentIcons.add_24_regular,
                title: 'הוסף קיצור לפעולה זמינה',
                subtitle: '${unconfiguredKeys.length} פעולות זמינות',
                actions: [
                  ActionButton.recommended(
                    text: 'הוסף קיצור',
                    onPressed: () => _addShortcut(context, unconfiguredKeys),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// משאיר רק טיילים של קיצורים שכבר הוגדר להם ערך לא-ריק.
  /// קיצורים ללא ערך מוצגים תחת "פעולות זמינות לקיצור".
  List<Widget> _onlyConfigured(List<Widget> tiles) {
    return tiles.where((tile) {
      if (tile is _ShortcutTile) {
        final value = ShortcutValidator.getShortcutValue(tile.settingKey) ?? '';
        return value.isNotEmpty;
      }
      return true;
    }).toList();
  }

  Future<void> _addShortcut(
    BuildContext context,
    List<String> unconfiguredKeys,
  ) async {
    final settingsBloc = context.read<SettingsBloc>();

    final selectedKey = await showDialog<String>(
      context: context,
      builder: (_) => _PickActionDialog(actionKeys: unconfiguredKeys),
    );
    if (selectedKey == null || !context.mounted) return;

    final shortcut = await showDialog<String>(
      context: context,
      builder: (_) => CustomShortcutDialog(
        actionName: ShortcutValidator.shortcutNames[selectedKey],
      ),
    );
    if (shortcut == null || shortcut.isEmpty) return;

    // חישוב קונפליקטים *לפני* שליחת UpdateShortcut: הוא אסינכרוני (ה-bloc
    // עושה await על repository.updateShortcut), ולכן checkConflicts שירוץ
    // אחריו עלול לקרוא ערכים ישנים מ-Settings ולפספס כפילות.
    final conflictingNames = <String>[];
    for (final key in ShortcutValidator.shortcutKeys) {
      if (key == selectedKey) continue;
      if (ShortcutValidator.canShareShortcut(selectedKey, key)) continue;
      final existingValue = ShortcutValidator.getShortcutValue(key) ?? '';
      if (existingValue == shortcut) {
        conflictingNames.add(ShortcutValidator.shortcutNames[key] ?? key);
      }
    }

    if (conflictingNames.isNotEmpty) {
      UiSnack.showError(
        SettingsMessages.shortcutAlreadyInUse(conflictingNames.join(', ')),
      );
      return;
    }

    settingsBloc.add(UpdateShortcut(selectedKey, shortcut));
  }

  Future<void> _resetShortcuts(BuildContext context) async {
    final confirmed = await showWarningDialog(
      context: context,
      title: 'איפוס קיצורי מקשים?',
      content: 'כל קיצורי המקשים המותאמים אישית יאופסו לברירת המחדל.',
      subtitle: 'פעולה זו אינה הפיכה!',
    );
    if (confirmed == true && context.mounted) {
      context.read<SettingsBloc>().add(ResetShortcuts());
      UiSnack.showSuccess(SettingsMessages.shortcutsReset);
    }
  }
}

// ── _ShortcutTile ─────────────────────────────────────────────────────────────
// פה מחקנו את כל עטיפות ה-Theme המסורבלות
class _ShortcutTile extends StatelessWidget {
  final String settingKey;
  final String label;
  final String? subtitle;
  final IconData icon;
  final Map<String, String> allShortcuts;

  const _ShortcutTile({
    required this.settingKey,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.allShortcuts,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style.merge(kSettingsTitleStyle),
      child: ShortcutDropDownTile(
        settingKey: settingKey,
        title: label,
        subtitle: subtitle,
        selected: ShortcutValidator.defaultShortcuts[settingKey] ?? '',
        allShortcuts: allShortcuts,
        leading: Icon(icon),
      ),
    );
  }
}

// ── _PickActionDialog ────────────────────────────────────────────────────────
/// דיאלוג לבחירת פעולה מתוך רשימת הפעולות הזמינות להגדרת קיצור.
/// מחזיר את ה-`settingKey` שנבחר ([ShortcutValidator.shortcutKeys]),
/// או null אם בוטל.
///
/// הקומפוננטות הקנוניות ב-`app_dialogs.dart` (SingleActionDialog וכו') בנויות
/// סביב כפתור confirm/cancel — לא מתאימות ל-picker שבו כל פריט הוא הפעולה
/// עצמה. במקום זאת אנחנו מיישרים קו עם אותו AlertDialog + צבעי המשטח
/// (`surfaceContainerHigh`) ואותם סגנונות לכפתורי הביטול (FilledButton.tonal).
class _PickActionDialog extends StatelessWidget {
  final List<String> actionKeys;

  const _PickActionDialog({required this.actionKeys});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      title: const Text(
        'בחר פעולה להוספת קיצור',
      ),
      content: SizedBox(
        width: 420,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: actionKeys.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final key = actionKeys[i];
            final name = ShortcutValidator.shortcutNames[key] ?? key;
            return ListTile(
              title: Text(name),
              trailing: const Icon(FluentIcons.chevron_right_24_regular),
              onTap: () => Navigator.of(context).pop(key),
            );
          },
        ),
      ),
      actions: [
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
          ),
          child: const Text('ביטול'),
        ),
      ],
    );
  }
}
