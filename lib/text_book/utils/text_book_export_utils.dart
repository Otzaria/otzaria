import 'dart:io';

import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// מחיל פרופיל תצוגה (ערוץ ייצוא) על שורת ספר, ומנקה HTML לפי [stripHtml].
String applyTextBookExportProfile(
  String input, {
  required TextDisplayProfile profile,
  required bool stripHtml,
}) {
  final text = applyTextDisplayProfile(input, profile);
  return stripHtml ? stripHtmlIfNeeded(text) : text;
}

/// מנקה שם ספר כך שיהיה תקין כשם קובץ במערכות הקבצים הנתמכות.
String sanitizeTextBookExportFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  return sanitized.isEmpty ? 'ספר' : sanitized;
}

/// מזהה שגיאות Windows נפוצות של קובץ יעד פתוח או נעול.
bool isLockedTextBookExportFileException(FileSystemException e) {
  final code = e.osError?.errorCode;
  return code == 32 || code == 33;
}
