import 'package:flutter/services.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מעתיק את טקסט התוצאה, כמו העתקה ממסך הקריאה: המקור והכותרת מצורפים לפי
/// ההגדרות. [titleText] כבר עבר החלפת שמות קודש.
void copySearchResultText({
  required SearchResult result,
  required String rawHtml,
  required String titleText,
  required SettingsState settingsState,
}) {
  final plainText = utils.stripHtmlPreservingBreaks(
    rawHtml,
  );
  final bookName = settingsState.replaceHolyNames
      ? utils.replaceHolyNames(
          result.title,
          style: settingsState.holyNameStyle,
        )
      : result.title;
  final textToCopy = CopyUtils.formatTextWithHeaders(
    originalText: plainText,
    copyWithHeaders: settingsState.copyWithHeaders,
    copyHeaderFormat: settingsState.copyHeaderFormat,
    bookName: bookName,
    currentPath: CopyUtils.referencePath(
      bookName: bookName,
      reference: titleText,
    ),
  );
  Clipboard.setData(
    ClipboardData(text: textToCopy),
  );
  UiSnack.show(UiSnack.textCopied);
}
