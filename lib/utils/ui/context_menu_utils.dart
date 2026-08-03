import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/direct_link_menu_entries.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';

/// פונקציות עזר לתפריטי הקשר במפרשים
class ContextMenuUtils {
  static TextBook _targetBookFromLink(Link link) {
    return TextBook(
      title: utils.getTitleFromPath(link.path2),
      categoryId: link.targetCategoryId,
      fileType: link.targetFileType,
      isUserBook: link.targetIsUserBook,
    );
  }

  /// בניית רשימת פריטי תפריט הקשר למפרש ספציפי.
  ///
  /// מחזיר [List<AppContextMenuEntry>] לשימוש עם [AppContextMenuRegion].
  ///
  /// דוגמה:
  /// ```dart
  /// AppContextMenuRegion(
  ///   menuBuilder: (ctx) => ContextMenuUtils.buildCommentaryContextMenu(
  ///     context: ctx,
  ///     link: link,
  ///     openBookCallback: ...,
  ///     fontSize: fontSize,
  ///     removeNikud: removeNikud,
  ///     removePunctuation: removePunctuation,
  ///     savedSelectedText: _savedText,
  ///     onCopySelected: _copy,
  ///   ),
  ///   child: myCommentaryWidget,
  /// )
  /// ```
  static List<AppContextMenuEntry> buildCommentaryContextMenu({
    required BuildContext context,
    required Link link,
    required Function(TextBookTab) openBookCallback,
    required double fontSize,
    required bool removeNikud,
    required bool removePunctuation,
    String? savedSelectedText,
    required VoidCallback onCopySelected,
  }) {
    final entries = <AppContextMenuEntry>[
      AppContextMenuEntry(
        label: 'הוסף הערה אישית',
        icon: FluentIcons.note_add_24_regular,
        onTap: () => _createCommentaryNote(
          context: context,
          link: link,
          savedSelectedText: savedSelectedText,
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
      AppContextMenuEntry(
        label: 'העתק את כל הפסקה',
        icon: FluentIcons.document_copy_24_regular,
        onTap: () => copyCommentaryParagraph(
          context: context,
          link: link,
          fontSize: fontSize,
          removeNikud: removeNikud,
          removePunctuation: removePunctuation,
        ),
      ),
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'פתח ספר זה בחלון נפרד',
        icon: FluentIcons.open_24_regular,
        onTap: () {
          openBookCallback(
            TextBookTab(
              book: _targetBookFromLink(link),
              index: link.index2 - 1,
              openLeftPane:
                  (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                  (Settings.getValue<bool>('key-default-sidebar-open') ??
                      false),
            ),
          );
        },
      ),
    ];

    if (link.targetCategoryId != null) {
      entries.add(const AppContextMenuEntry.divider());
      entries.add(
        AppContextMenuEntry(
          label: 'העתק קישור ישיר',
          icon: FluentIcons.link_24_regular,
          childrenBuilder: () => buildDirectLinkContextMenuEntries(
            bookId: link.targetCategoryId!,
            index: link.index2 - 1,
            selectedText: savedSelectedText,
          ),
        ),
      );
    }

    return entries;
  }

  static Future<void> _createCommentaryNote({
    required BuildContext context,
    required Link link,
    String? savedSelectedText,
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
      if (context.mounted) UiSnack.showSuccess(TextBookMessages.noteSaved);
    } catch (e) {
      if (context.mounted) {
        UiSnack.showError(TextBookMessages.noteSaveError(e));
      }
    }
  }

  /// ממפה מפרש ([link] + תוכנו [rawContent]) לפרמטרי דיווח הטעות: הדיווח מופנה
  /// לספר המפרש עצמו (path2/index2), וללא בחירת טקסט מדווחים על כל פסקת המפרש.
  static ({
    TextBook book,
    List<String> content,
    int lineIndex,
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
    );
  }

  /// העתקת פסקה שלמה של מפרש
  static Future<void> copyCommentaryParagraph({
    required BuildContext context,
    required Link link,
    required double fontSize,
    required bool removeNikud,
    required bool removePunctuation,
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
        removeNikud: removeNikud,
        removePunctuation: removePunctuation,
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
        replaceHolyNames: settingsState.replaceHolyNames,
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

  static String applyCommentaryDisplayFilters(
    String content, {
    required bool removeNikud,
    required bool removePunctuation,
  }) {
    var processedContent = removeNikud ? utils.removeVolwels(content) : content;
    if (removePunctuation) {
      processedContent = utils.removePunctuation(processedContent);
    }
    return processedContent;
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  static Future<void> copyFormattedText({
    required BuildContext context,
    required String? savedSelectedText,
    required double fontSize,
    Link? link,
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
          );
          return;
        }

        final finalPlainText = CopyUtils.applyCopyPreferences(
          text: plainText,
          replaceHolyNames: settingsState.replaceHolyNames,
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
