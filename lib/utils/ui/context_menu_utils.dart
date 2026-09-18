import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/direct_link_menu_entries.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';

/// תווית פריט תפריט ההקשר לפתיחה ברקע — משותפת לתוצאות חיפוש ולמפרשים.
const kOpenInNewTabLabel = 'פתח בכרטיסייה חדשה';

/// פונקציות עזר לתפריטי הקשר במפרשים
/// האם להציג את "העתק בלי ניקוד" עבור הבחירה — רק כשיש בה בפועל ניקוד
/// או טעמים (issue #851). טקסט לא-מנוקד (גמרא, פוסקים) לא מקבל פריט סרק.
bool showCopyWithoutNikud(String? selectedText) =>
    selectedText != null &&
    selectedText.trim().isNotEmpty &&
    utils.hasNikud(selectedText);

class ContextMenuUtils {
  static TextBookTab _targetTabFromLink(Link link) => TextBookTab(
    book: _targetBookFromLink(link),
    index: link.index2 - 1,
    openLeftPane:
        (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
        (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
  );

  static Future<void> _openLinkTargetInNewWindow(Link link) async {
    const service = MultiWindowService();
    // ⚠️ נבדק לפני הפעולה: `openWindow` ממתין עד 20 שניות, והמשתמש היה מקבל
    // את הודעת התקרה רק בסופן.
    if (!await service.canOpenAnotherWindow() ||
        !await service.openWindow(tab: _targetTabFromLink(link))) {
      await service.reportOpenWindowFailure();
    }
  }

  static TextBook _targetBookFromLink(Link link) {
    return TextBook(
      title: utils.getTitleFromPath(link.path2),
      categoryId: link.targetCategoryId,
      fileType: link.targetFileType,
      source: link.targetSource,
    );
  }

  /// בניית רשימת פריטי תפריט הקשר למפרש ספציפי.
  ///
  /// מחזיר [List<AppContextMenuEntry>] לשימוש עם [AppContextMenuRegion].
  ///
  /// [onNavigateToLink] — ניווט אל יעד קישור. כשהוא מסופק נוספים תתי-התפריטים
  /// "מפרשים" ו"קישורים" של קטע היעד ([TargetLineLinksService]); בלעדיו התפריט
  /// מכיל רק את פעולות ההעתקה, הפתיחה והדיווח.
  ///
  /// [displayProfile] — פרופיל תצוגת המפרשים; [copyDisplayProfile] — פרופיל
  /// ערוץ ההעתקה (ברירת מחדל: כמו התצוגה). [removeNikud]/[removePunctuation]
  /// הם מסלול תאימות שנפתר מול ההגדרות הגלובליות כשאין פרופיל.
  ///
  /// דוגמה:
  /// ```dart
  /// AppContextMenuRegion(
  ///   menuBuilder: (ctx) => ContextMenuUtils.buildCommentaryContextMenu(
  ///     context: ctx,
  ///     link: link,
  ///     openBookCallback: ...,
  ///     fontSize: fontSize,
  ///     displayProfile: state.commentaryDisplayProfile,
  ///     savedSelectedText: _savedText,
  ///     onCopySelected: _copy,
  ///     onNavigateToLink: _navigateToLink,
  ///   ),
  ///   child: myCommentaryWidget,
  /// )
  /// ```
  static List<AppContextMenuEntry> buildCommentaryContextMenu({
    required BuildContext context,
    required Link link,
    required Function(TextBookTab) openBookCallback,
    required double fontSize,
    TextDisplayProfile? displayProfile,
    TextDisplayProfile? copyDisplayProfile,
    bool? removeNikud,
    bool? removePunctuation,
    String? savedSelectedText,
    required VoidCallback onCopySelected,
    VoidCallback? onCopySelectedWithoutNikud,
    void Function(Link link)? onNavigateToLink,
    VoidCallback? onNoteSaved,
  }) {
    final profile =
        displayProfile ??
        commentaryProfileFromLegacyFlags(
          context.read<SettingsBloc>().state,
          removeNikud: removeNikud,
          removePunctuation: removePunctuation,
        );
    final copyProfile = copyDisplayProfile ?? profile;
    final linksService = TargetLineLinksService.instance;
    final entries = <AppContextMenuEntry>[
      AppContextMenuEntry(
        label: 'הוסף הערה אישית',
        icon: FluentIcons.note_add_24_regular,
        onTap: () => _createCommentaryNote(
          context: context,
          link: link,
          savedSelectedText: savedSelectedText,
          onNoteSaved: onNoteSaved,
        ),
      ),
      if (!link.targetIsUserBook)
        AppContextMenuEntry(
          label: 'דווח על טעות בספר',
          icon: FluentIcons.error_circle_24_regular,
          onTap: () => _reportCommentaryError(
            context: context,
            link: link,
            fontSize: fontSize,
            savedSelectedText: savedSelectedText,
          ),
        ),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'העתק',
        icon: FluentIcons.copy_24_regular,
        enabled:
            savedSelectedText != null && savedSelectedText.trim().isNotEmpty,
        onTap: onCopySelected,
      ),
      if (onCopySelectedWithoutNikud != null &&
          showCopyWithoutNikud(savedSelectedText))
        AppContextMenuEntry(
          label: 'העתק בלי ניקוד',
          icon: FluentIcons.text_clear_formatting_24_regular,
          onTap: onCopySelectedWithoutNikud,
        ),
      AppContextMenuEntry(
        label: 'העתק את כל הפסקה',
        icon: FluentIcons.document_copy_24_regular,
        onTap: () => copyCommentaryParagraph(
          context: context,
          link: link,
          fontSize: fontSize,
          displayProfile: copyProfile,
        ),
      ),
      if (onNavigateToLink != null) ...[
        const AppContextMenuEntry.divider(),
        linksService.buildCommentariesEntry(
          link: link,
          onNavigate: onNavigateToLink,
          removeNikud: profile.removeNikud,
          removePunctuation: profile.removePunctuation,
        ),
        linksService.buildLinksEntry(
          link: link,
          onNavigate: onNavigateToLink,
          removeNikud: profile.removeNikud,
          removePunctuation: profile.removePunctuation,
        ),
      ],
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'פתח ועבור לכרטיסיה',
        icon: FluentIcons.open_24_regular,
        onTap: () => openBookCallback(_targetTabFromLink(link)),
      ),
      AppContextMenuEntry(
        label: kOpenInNewTabLabel,
        icon: FluentIcons.tab_add_24_regular,
        onTap: () => openLinkTargetInBackground(context, link),
      ),
      if (MultiWindowService.canOpenWindows)
        AppContextMenuEntry(
          label: 'פתח בחלון חדש',
          icon: FluentIcons.window_new_24_regular,
          onTap: () => _openLinkTargetInNewWindow(link),
        ),
    ];

    // קישור עומק דורש מזהה מסד; source=user מבחין בספרי משתמש בעלי ID חופף.
    final targetBookId = link.targetBookId;
    if (targetBookId != null) {
      entries.add(const AppContextMenuEntry.divider());
      entries.add(
        AppContextMenuEntry(
          label: 'העתק קישור ישיר',
          icon: FluentIcons.link_24_regular,
          childrenBuilder: () => buildDirectLinkContextMenuEntries(
            bookId: targetBookId,
            source: link.targetSource,
            index: link.index2 - 1,
            selectedText: savedSelectedText,
          ),
        ),
      );
    }

    return entries;
  }

  /// פותח את יעד [link] בכרטיסייה חדשה ברקע (טקסט או PDF, לפי תבנית הפתיחה).
  static Future<void> openLinkTargetInBackground(
    BuildContext context,
    Link link,
  ) async {
    // ה-bloc נשלף לפני ההמתנה: הקשר התפריט מתפרק עם סגירתו.
    final tabsBloc = context.read<TabsBloc>();
    final tab = await buildLinkTargetTab(link);
    tabsBloc.add(AddTab(tab, insertAdjacent: true, inBackground: true));
  }

  /// פריטי "פתח קישור בכרטיסייה חדשה" לתפריט הקשר של שורת טקסט, כשהלחיצה
  /// הימנית נפלה על קישור לספר אחר; ריק כשאין שם קישור כזה.
  static List<AppContextMenuEntry> buildInlineLinkContextMenuEntries(
    BuildContext context,
    Offset tapPosition,
  ) {
    final url = inlineLinkUrlAt(
      tapPosition,
      viewId: View.of(context).viewId,
    );
    if (url == null || !HtmlLinkHandler.opensAnotherBook(url)) return const [];
    return [
      AppContextMenuEntry(
        label: 'פתח קישור בכרטיסייה חדשה',
        icon: FluentIcons.tab_add_24_regular,
        onTap: () => HtmlLinkHandler.openLinkInBackground(context, url),
      ),
      const AppContextMenuEntry.divider(),
    ];
  }

  static Future<void> _createCommentaryNote({
    required BuildContext context,
    required Link link,
    String? savedSelectedText,
    VoidCallback? onNoteSaved,
  }) async {
    final bookTitle = utils.getTitleFromPath(link.path2);
    final selectedText = savedSelectedText?.trim();
    final rawContent = await link.content;
    if (!context.mounted) return;

    final referenceText = selectedText?.isNotEmpty == true
        ? utils.removeVolwels(selectedText!)
        : utils.stripHtmlIfNeeded(rawContent);
    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: bookTitle,
      categoryId: link.targetCategoryId,
      lineNumber: link.index2,
    );
    if (!context.mounted) return;

    final result = await showDialog<PersonalNoteEditorResult>(
      context: context,
      builder: (_) => PersonalNoteEditorDialog(
        title: 'הערה חדשה - $bookTitle',
        referenceText: referenceText,
        icon: FluentIcons.note_add_24_regular,
        bookId: bookTitle,
        categoryId: link.targetCategoryId,
        draftLineNumber: link.index2,
        initialContent: draft?.content ?? '',
        initialContentFormat:
            draft?.contentFormat ?? PersonalNoteContentFormat.plain,
      ),
    );
    if (result == null || result.contentPlain.trim().isEmpty) return;

    try {
      await PersonalNotesRepository().addNote(
        bookId: bookTitle,
        lineNumber: link.index2,
        content: result.content,
        contentPlain: result.contentPlain,
        contentFormat: result.contentFormat,
        selectedText: selectedText,
        categoryId: link.targetCategoryId,
      );
      onNoteSaved?.call();
      if (context.mounted) UiSnack.showSuccess(TextBookMessages.noteSaved);
    } catch (e) {
      if (context.mounted) {
        UiSnack.showError(TextBookMessages.noteSaveError(e));
      }
    }
  }

  /// ממפה מפרש ([link] + תוכנו [rawContent]) לפרמטרי דיווח הטעות: הדיווח מופנה
  /// לספר המפרש עצמו (path2/index2), וללא בחירת טקסט מדווחים על כל פסקת המפרש.
  /// `reportLine` null בקישור-טווח: התוכן הוא כמה שורות מחוברות, לא שורה אחת ב-DB.
  static ({
    TextBook book,
    List<String> content,
    int lineIndex,
    String? reportLine,
    String bookTitle,
    String selectedText,
  })
  commentaryReportArgs({
    required Link link,
    required String rawContent,
    String? savedSelectedText,
  }) {
    final hasSelection =
        savedSelectedText != null && savedSelectedText.trim().isNotEmpty;
    return (
      book: _targetBookFromLink(link),
      content: [rawContent],
      lineIndex: link.index2 - 1,
      reportLine: (link.index2End ?? link.index2) == link.index2
          ? rawContent
          : null,
      bookTitle: utils.getTitleFromPath(link.path2),
      selectedText: hasSelection
          ? savedSelectedText
          : utils.stripHtmlIfNeeded(rawContent),
    );
  }

  /// מצב הטקסט, או null בחלונית ה-PDF שאין בה `TextBookBloc`. הטיפוס
  /// ה-nullable הוא ה-API של provider לתלות אופציונלית — בלעדיו הקריאה זורקת.
  static TextBookLoaded? _maybeTextBookState(BuildContext context) {
    final state = context.read<TextBookBloc?>()?.state;
    return state is TextBookLoaded ? state : null;
  }

  /// פותח את דיאלוג דיווח הטעות עבור מפרש.
  static Future<void> _reportCommentaryError({
    required BuildContext context,
    required Link link,
    required double fontSize,
    String? savedSelectedText,
  }) async {
    final rawContent = await link.content;
    if (!context.mounted) return;
    final args = commentaryReportArgs(
      link: link,
      rawContent: rawContent,
      savedSelectedText: savedSelectedText,
    );
    await ErrorReportHelper.showErrorReportDialog(
      context: context,
      selectedText: args.selectedText,
      // הדיווח מופנה לספר המפרש עצמו דרך reportBook/reportContent, ולכן אינו
      // תלוי במצב הטקסט — שאינו קיים בחלונית ה-PDF.
      state: _maybeTextBookState(context),
      fontSize: fontSize,
      bookTitle: args.bookTitle,
      savedSelectedIndex: args.lineIndex,
      reportContent: args.content,
      reportBook: args.book,
      reportLine: args.reportLine,
    );
  }

  /// העתקת פסקה שלמה של מפרש לפי [displayProfile] של ערוץ ההעתקה.
  static Future<void> copyCommentaryParagraph({
    required BuildContext context,
    required Link link,
    required double fontSize,
    required TextDisplayProfile displayProfile,
  }) async {
    try {
      final settingsState = context.read<SettingsBloc>().state;

      final content = await link.content;
      if (content.trim().isEmpty) {
        UiSnack.show(CommonMessages.noContentToCopy);
        return;
      }

      final processedContent = applyCommentaryDisplayFilters(
        content,
        displayProfile,
      );
      final plainText = utils.stripHtmlIfNeeded(processedContent);

      String finalText = plainText;
      String finalHtmlText = processedContent;

      if (settingsState.copyWithHeaders != 'none') {
        final targetBook = _targetBookFromLink(link);
        final bookName = CopyUtils.extractBookName(targetBook);
        final currentPath = await CopyUtils.extractCurrentPath(
          targetBook,
          link.index2 - 1,
        );

        finalText = CopyUtils.formatTextWithHeaders(
          originalText: plainText,
          copyWithHeaders: settingsState.copyWithHeaders,
          copyHeaderFormat: settingsState.copyHeaderFormat,
          bookName: bookName,
          currentPath: currentPath,
        );

        finalHtmlText = CopyUtils.formatTextWithHeaders(
          originalText: processedContent,
          copyWithHeaders: settingsState.copyWithHeaders,
          copyHeaderFormat: settingsState.copyHeaderFormat,
          bookName: bookName,
          currentPath: currentPath,
        );
      }

      final copyContent = CopyUtils.applyCopyPreferencesForClipboard(
        plainText: finalText,
        htmlText: finalHtmlText,
        replaceHolyNames: displayProfile.replaceHolyNames,
        holyNameStyle: displayProfile.holyNameStyle,
      );

      final htmlText = CopyUtils.buildStyledHtml(
        htmlText: copyContent.htmlText,
        fontFamily: settingsState.commentatorsFontFamily,
        fontSize: fontSize,
      );

      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final item = DataWriterItem();
        item.add(Formats.plainText(copyContent.plainText));
        item.add(Formats.htmlText(htmlText));
        await clipboard.write([item]);
        UiSnack.show(CommonMessages.paragraphCopied);
      }
    } catch (e) {
      debugPrint('Error copying commentary paragraph: $e');
      UiSnack.showError(CommonMessages.paragraphCopyError);
    }
  }

  /// מחיל את פרופיל התצוגה על תוכן מפרש גולמי (ניקוד, טעמים, פיסוק, שם הוי"ה).
  static String applyCommentaryDisplayFilters(
    String content,
    TextDisplayProfile displayProfile,
  ) => applyTextDisplayProfile(content, displayProfile);

  /// העתקת טקסט מעוצב (HTML) ללוח
  /// [removeNikud] — "העתק בלי ניקוד" (issue #851): מסיר ניקוד וטעמים
  /// מהעותק בלבד, בלי לגעת בתצוגה.
  static Future<void> copyFormattedText({
    required BuildContext context,
    required String? savedSelectedText,
    required double fontSize,
    Link? link,
    bool removeNikud = false,
  }) async {
    final plainText = savedSelectedText;

    if (plainText == null || plainText.trim().isEmpty) {
      UiSnack.show(CommonMessages.noTextSelected);
      return;
    }

    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final settingsState = context.read<SettingsBloc>().state;
        if (link != null && settingsState.copyWithHeaders != 'none') {
          // ספר הכותרת נגזר מה-link (headerBookOverride), ולכן ההעתקה עם
          // כותרות עובדת גם בחלונית ה-PDF שאין בה TextBookBloc.
          await copySelectedTextForBook(
            plainText: plainText,
            selectedIndex: link.index2 - 1,
            sourceContent: [plainText],
            textBookState: _maybeTextBookState(context),
            settingsState: settingsState,
            fontFamily: settingsState.commentatorsFontFamily,
            fontSize: fontSize,
            headerBookOverride: _targetBookFromLink(link),
            removeNikud: removeNikud,
          );
          return;
        }

        final finalPlainText = CopyUtils.applyCopyPreferences(
          text: plainText,
          replaceHolyNames: settingsState.replaceHolyNames,
          holyNameStyle: settingsState.holyNameStyle,
          removeNikud: removeNikud,
        );

        final htmlText = CopyUtils.buildStyledHtml(
          htmlText: finalPlainText,
          fontFamily: settingsState.commentatorsFontFamily,
          fontSize: fontSize,
        );

        final item = DataWriterItem();
        item.add(Formats.plainText(finalPlainText));
        item.add(Formats.htmlText(htmlText));

        await clipboard.write([item]);
        UiSnack.show(CommonMessages.textCopiedShort);
      }
    } catch (e) {
      debugPrint('Error copying text: $e');
      UiSnack.showError(CommonMessages.textCopyError);
    }
  }
}
