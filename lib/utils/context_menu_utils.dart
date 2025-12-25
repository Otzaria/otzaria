import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/utils/copy_utils.dart';
import 'package:otzaria/settings/settings_bloc.dart';

/// פונקציות עזר לתפריטי הקשר במפרשים
class ContextMenuUtils {
  /// בניית תפריט הקשר למפרש ספציפי
  static ctx.ContextMenu buildCommentaryContextMenu({
    required BuildContext context,
    required Link link,
    required Function(TextBookTab) openBookCallback,
    required double fontSize,
    String? savedSelectedText,
    required VoidCallback onCopySelected,
  }) {
    return ctx.ContextMenu(
      entries: [
        ctx.MenuItem(
          label: const Text('העתק'),
          icon: const Icon(FluentIcons.copy_24_regular),
          enabled:
              savedSelectedText != null && savedSelectedText.trim().isNotEmpty,
          onSelected: (_) => onCopySelected(),
        ),
        ctx.MenuItem(
          label: const Text('העתק את כל הפסקה'),
          icon: const Icon(FluentIcons.document_copy_24_regular),
          onSelected: (_) => copyCommentaryParagraph(
            context: context,
            link: link,
            fontSize: fontSize,
          ),
        ),
        const ctx.MenuDivider(),
        ctx.MenuItem(
          label: const Text('פתח ספר זה בחלון נפרד'),
          icon: const Icon(FluentIcons.open_24_regular),
          onSelected: (_) {
            openBookCallback(TextBookTab(
              book: TextBook(title: utils.getTitleFromPath(link.path2)),
              index: link.index2 - 1,
              openLeftPane:
                  (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
                      (Settings.getValue<bool>('key-default-sidebar-open') ??
                          false),
            ));
          },
        ),
      ],
    );
  }

  /// העתקת פסקה שלמה של מפרש
  static Future<void> copyCommentaryParagraph({
    required BuildContext context,
    required Link link,
    required double fontSize,
  }) async {
    try {
      // שמירת ההגדרות לפני ה-await
      final settingsState = context.read<SettingsBloc>().state;

      // טעינת התוכן של המפרש
      final content = await link.content;
      if (content.trim().isEmpty) {
        UiSnack.show('אין תוכן להעתקה');
        return;
      }

      // ניקוי תגיות HTML
      final plainText = utils.stripHtmlIfNeeded(content);

      // הוספת כותרות אם נדרש
      String finalText = plainText;
      String finalHtmlText = content;

      if (settingsState.copyWithHeaders != 'none') {
        final bookName = utils.getTitleFromPath(link.path2);
        final currentPath = link.heRef;

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

      // עיצוב הטקסט כ-HTML
      final textWithBreaks = finalHtmlText.replaceAll('\n', '<br>');
      final htmlText = '''
<div style="font-family: ${settingsState.commentatorsFontFamily}; font-size: ${fontSize}px; text-align: justify; direction: rtl;">
$textWithBreaks
</div>
''';

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

        // עיצוב הטקסט כ-HTML
        final textWithBreaks = plainText.replaceAll('\n', '<br>');
        final htmlText = '''
<div style="font-family: ${settingsState.commentatorsFontFamily}; font-size: ${fontSize}px; text-align: justify; direction: rtl;">
$textWithBreaks
</div>
''';

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
