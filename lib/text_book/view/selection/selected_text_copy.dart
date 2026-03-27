import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/copy_utils.dart';

/// בוחר את תוכן ה-HTML המתאים ביותר לטקסט שנבחר.
String resolveHtmlTextForSelection({
  required String plainText,
  required int? selectedIndex,
  required List<String> sourceContent,
}) {
  if (selectedIndex == null ||
      selectedIndex < 0 ||
      selectedIndex >= sourceContent.length) {
    return plainText;
  }

  final originalData = sourceContent[selectedIndex];
  final plainTextCleaned = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
  final originalCleaned = originalData
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (plainTextCleaned == originalCleaned) {
    return originalData;
  }

  if (originalCleaned.contains(plainTextCleaned)) {
    return plainText;
  }

  return plainText;
}

/// מעתיק טקסט נבחר מספר טקסט תוך שמירה על כותרות ועיצוב.
Future<void> copySelectedTextForBook({
  required String plainText,
  required int? selectedIndex,
  required List<String> sourceContent,
  required TextBookLoaded textBookState,
  required SettingsState settingsState,
  required String fontFamily,
  required double fontSize,
}) async {
  var htmlContentToUse = resolveHtmlTextForSelection(
    plainText: plainText,
    selectedIndex: selectedIndex,
    sourceContent: sourceContent,
  );

  var finalPlainText = plainText;
  if (settingsState.copyWithHeaders != 'none') {
    final bookName = CopyUtils.extractBookName(textBookState.book);
    final currentIndex = selectedIndex ?? 0;
    final currentPath = await CopyUtils.extractCurrentPath(
      textBookState.book,
      currentIndex,
      bookContent: textBookState.content,
    );

    finalPlainText = CopyUtils.formatTextWithHeaders(
      originalText: plainText,
      copyWithHeaders: settingsState.copyWithHeaders,
      copyHeaderFormat: settingsState.copyHeaderFormat,
      bookName: bookName,
      currentPath: currentPath,
    );

    htmlContentToUse = CopyUtils.formatTextWithHeaders(
      originalText: htmlContentToUse,
      copyWithHeaders: settingsState.copyWithHeaders,
      copyHeaderFormat: settingsState.copyHeaderFormat,
      bookName: bookName,
      currentPath: currentPath,
    );
  }

  await CopyUtils.copyStyledToClipboard(
    plainText: finalPlainText,
    htmlText: htmlContentToUse,
    fontFamily: fontFamily,
    fontSize: fontSize,
  );
}
