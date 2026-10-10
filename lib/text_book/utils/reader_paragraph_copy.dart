import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:super_clipboard/super_clipboard.dart';

/// The plain and HTML text that copying paragraph [index] puts on the
/// clipboard: [processedText], the paragraph as the copy profile renders it,
/// with the headers that [copyWithHeaders] asks for. The headers name
/// [headerBook] and its path in [bookContent]; without a book there are no
/// headers.
Future<({String plainText, String htmlText})> buildParagraphCopyText({
  required String processedText,
  required int index,
  required String copyWithHeaders,
  required String copyHeaderFormat,
  TextBook? headerBook,
  List<String>? bookContent,
  bool Function(int)? isLineLoaded,
}) async {
  final plainText = utils.stripHtmlIfNeeded(processedText);
  var finalText = plainText;
  var finalHtmlText = processedText;

  if (copyWithHeaders != 'none' && headerBook != null) {
    final bookName = CopyUtils.extractBookName(headerBook);
    final currentPath = await CopyUtils.extractCurrentPath(
      headerBook,
      index,
      bookContent: bookContent,
      isLineLoaded: isLineLoaded,
    );
    finalText = CopyUtils.formatTextWithHeaders(
      originalText: plainText,
      copyWithHeaders: copyWithHeaders,
      copyHeaderFormat: copyHeaderFormat,
      bookName: bookName,
      currentPath: currentPath,
    );
    finalHtmlText = CopyUtils.formatTextWithHeaders(
      originalText: processedText,
      copyWithHeaders: copyWithHeaders,
      copyHeaderFormat: copyHeaderFormat,
      bookName: bookName,
      currentPath: currentPath,
    );
  }

  // The holy name was already replaced by the copy profile.
  final copyContent = CopyUtils.applyCopyPreferencesForClipboard(
    plainText: finalText,
    htmlText: finalHtmlText,
    replaceHolyNames: false,
  );
  return (plainText: copyContent.plainText, htmlText: copyContent.htmlText);
}

/// Copies paragraph [index] to the clipboard, as built by
/// [buildParagraphCopyText].
Future<void> copyParagraphToClipboard({
  required String processedText,
  required int index,
  required String copyWithHeaders,
  required String copyHeaderFormat,
  required String fontFamily,
  required double fontSize,
  TextBook? headerBook,
  List<String>? bookContent,
  bool Function(int)? isLineLoaded,
  bool plainTextOnly = false,
}) async {
  final text = await buildParagraphCopyText(
    processedText: processedText,
    index: index,
    copyWithHeaders: copyWithHeaders,
    copyHeaderFormat: copyHeaderFormat,
    headerBook: headerBook,
    bookContent: bookContent,
    isLineLoaded: isLineLoaded,
  );
  await SystemClipboard.instance?.write([
    CopyUtils.buildClipboardItem(
      plainText: text.plainText,
      htmlText: text.htmlText,
      fontFamily: fontFamily,
      fontSize: fontSize,
      plainTextOnly: plainTextOnly,
    ),
  ]);
}
