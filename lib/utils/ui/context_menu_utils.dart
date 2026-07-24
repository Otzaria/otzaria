import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
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
    String? savedSelectedText,
    required VoidCallback onCopySelected,
  }) {
    final entries = <AppContextMenuEntry>[
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

    if (!link.targetIsUserBook) {
      entries.add(const AppContextMenuEntry.divider());
      entries.add(
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
      );
    }

    return entries;
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

  /// פותח את דיאלוג דיווח הטעות עבור מפרש.
  static Future<void> _reportCommentaryError({
    required BuildContext context,
    required Link link,
    required double fontSize,
    String? savedSelectedText,
  }) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
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
      state: state,
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
  }) async {
    try {
      final settingsState = context.read<SettingsBloc>().state;
      final textBookState = context.read<TextBookBloc>().state;

      final content = await link.content;
      if (content.trim().isEmpty) {
        UiSnack.show(CommonMessages.noContentToCopy);
        return;
      }

      // ההעתקה משקפת את התצוגה: מצב הניקוד/פיסוק של הטאב חל על כל המפרשים.
      final loaded = textBookState is TextBookLoaded ? textBookState : null;
      var processedContent = (loaded?.removeNikud ?? false)
          ? utils.removeVolwels(content)
          : content;
      if (loaded?.removePunctuation ?? false) {
        processedContent = utils.removePunctuation(processedContent);
      }
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
          final textBookState = context.read<TextBookBloc>().state;
          if (textBookState is! TextBookLoaded) return;

          await copySelectedTextForBook(
            plainText: plainText,
            selectedIndex: link.index2 - 1,
            sourceContent: [plainText],
            textBookState: textBookState,
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
