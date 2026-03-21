import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/utils/copy_utils.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/app_menu.dart';

/// פונקציות עזר לתפריטי הקשר במפרשים
class ContextMenuUtils {
  /// בניית רשימת פריטי תפריט הקשר למפרש ספציפי.
  ///
  /// מחזיר [List<AppContextMenuEntry>] לשימוש עם [AppContextMenuRegion].
  ///
  /// דוגמה:
  /// ```dart
  /// AppContextMenuRegion(
  ///   menuBuilder: (ctx) => ContextMenuUtils.buildCommentaryMenuEntries(
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
  static List<AppContextMenuEntry> buildCommentaryMenuEntries({
    required BuildContext context,
    required Link link,
    required Function(TextBookTab) openBookCallback,
    required double fontSize,
    String? savedSelectedText,
    required VoidCallback onCopySelected,
  }) {
    return [
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
          openBookCallback(TextBookTab(
            book: TextBook(title: utils.getTitleFromPath(link.path2)),
            index: link.index2 - 1,
            openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ??
                    false) ||
                (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
          ));
        },
      ),
    ];
  }

  /// בניית תפריט הקשר למפרש ספציפי (wrapper למתודה החדשה).
  ///
  /// מתודה זו קיימת לתאימות לאחור עם קוד ישן שמשתמש ב-API הישן של תפריטי הקשר.
  /// מומלץ להשתמש ב-buildCommentaryMenuEntries ישירות.
  static List<AppContextMenuEntry> buildCommentaryContextMenu({
    required BuildContext context,
    required Link link,
    required Function(TextBookTab) openBookCallback,
    required double fontSize,
    String? savedSelectedText,
    required VoidCallback onCopySelected,
  }) {
    return buildCommentaryMenuEntries(
      context: context,
      link: link,
      openBookCallback: openBookCallback,
      fontSize: fontSize,
      savedSelectedText: savedSelectedText,
      onCopySelected: onCopySelected,
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

      final content = await link.content;
      if (content.trim().isEmpty) {
        UiSnack.show('אין תוכן להעתקה');
        return;
      }

      final plainText = utils.stripHtmlIfNeeded(content);

      String finalText = plainText;
      String finalHtmlText = content;

      if (settingsState.copyWithHeaders != 'none') {
        final bookName = utils.getTitleFromPath(link.path2);
        final currentPath = await link.displayReference;

        finalText = CopyUtils.formatTextWithHeaders(
          originalText: plainText,
          copyWithHeaders: settingsState.copyWithHeaders,
          copyHeaderFormat: settingsState.copyHeaderFormat,
          bookName: bookName,
          currentPath: currentPath,
        );

        finalHtmlText = CopyUtils.formatTextWithHeaders(
          originalText: content,
          copyWithHeaders: settingsState.copyWithHeaders,
          copyHeaderFormat: settingsState.copyHeaderFormat,
          bookName: bookName,
          currentPath: currentPath,
        );
      }

      final htmlText = CopyUtils.buildStyledHtml(
        htmlText: finalHtmlText,
        fontFamily: settingsState.commentatorsFontFamily,
        fontSize: fontSize,
      );

      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final item = DataWriterItem();
        item.add(Formats.plainText(finalText));
        item.add(Formats.htmlText(htmlText));
        await clipboard.write([item]);
        UiSnack.show('הפסקה הועתקה בהצלחה');
      }
    } catch (e) {
      debugPrint('Error copying commentary paragraph: $e');
      UiSnack.showError('שגיאה בהעתקת הפסקה');
    }
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  static Future<void> copyFormattedText({
    required BuildContext context,
    required String? savedSelectedText,
    required double fontSize,
  }) async {
    final plainText = savedSelectedText;

    if (plainText == null || plainText.trim().isEmpty) {
      UiSnack.show('אנא בחר טקסט להעתקה');
      return;
    }

    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final settingsState = context.read<SettingsBloc>().state;

        final htmlText = CopyUtils.buildStyledHtml(
          htmlText: plainText,
          fontFamily: settingsState.commentatorsFontFamily,
          fontSize: fontSize,
        );

        final item = DataWriterItem();
        item.add(Formats.plainText(plainText));
        item.add(Formats.htmlText(htmlText));

        await clipboard.write([item]);
        UiSnack.show('הטקסט הועתק');
      }
    } catch (e) {
      debugPrint('Error copying text: $e');
      UiSnack.showError('שגיאה בהעתקת הטקסט');
    }
  }
}
