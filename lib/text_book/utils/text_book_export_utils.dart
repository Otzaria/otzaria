import 'dart:io';

import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
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

/// בקשת ייצוא של ספר שלם. עוברת ל-isolate, ולכן מופעי השמות מגיעים כנתונים
/// ([divineNames]) ולא נשלפים מהמסד שם.
class TextBookExportRequest {
  final String rawContent;
  final TextDisplayProfile profile;
  final DivineNameSpans divineNames;

  TextBookExportRequest({
    required this.rawContent,
    required this.profile,
    DivineNameSpans? divineNames,
  }) : divineNames = divineNames ?? DivineNameSpans.empty;
}

/// שורות הספר לייצוא: מופעי השמות לפי `lineIndex` על השורה הגולמית, ואחריהם
/// פרופיל הייצוא (כולל ה-regex של שם הוי"ה, כמו בתצוגה).
List<String> textBookExportLines(
  TextBookExportRequest request, {
  required bool stripHtml,
}) {
  final profile = request.profile;
  final lines = request.rawContent.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final named = applyDivineNamesToLine(
      lines[i],
      request.divineNames,
      i,
      substituteOtherNames: profile.substituteDivineNames,
      holyNameStyle: profile.replaceHolyNames ? profile.holyNameStyle : null,
    );
    lines[i] = applyTextBookExportProfile(
      named,
      profile: profile,
      stripHtml: stripHtml,
    );
  }
  return lines;
}

/// תוכן קובץ הטקסט של ייצוא ספר שלם. בקובץ טקסט אין שבירת שורות לשמור מפניה,
/// ולכן המקף נשאר רגיל; ב-Word מחבר המילים נשאר.
String createTextBookTextExport(TextBookExportRequest request) =>
    request.rawContent.isEmpty
    ? ''
    : withoutDivineNameJoiners(
        textBookExportLines(request, stripHtml: true).join('\n'),
      );

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
