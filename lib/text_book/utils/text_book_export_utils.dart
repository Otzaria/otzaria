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

/// מחיל על שורת ספר את אותן טרנספורמציות טקסט שנדרשות לפני ייצוא.
String applyTextBookExportTextTransforms(
  String input, {
  required bool removeNikud,
  required bool removeTaamim,
  required bool shouldReplaceHolyNames,
  HolyNameStyle holyNameStyle = HolyNameStyle.kufKuf,
  required bool stripHtml,
}) {
  var text = input;
  if (removeNikud && removeTaamim) {
    text = removeVolwels(text);
  } else if (removeNikud && !removeTaamim) {
    text = text
        .replaceAll('־', ' ')
        .replaceAll('׀', ' ')
        .replaceAll('|', ' ')
        .replaceAll(RegExp(r'[\u05B0-\u05C7]'), '');
  } else if (!removeNikud && removeTaamim) {
    text = removeTeamim(text);
  }
  if (shouldReplaceHolyNames) {
    text = replaceHolyNames(text, style: holyNameStyle);
  }
  return stripHtml ? stripHtmlIfNeeded(text) : text;
}

/// בקשת ייצוא של ספר שלם. עוברת ל-isolate, ולכן מופעי השמות מגיעים כנתונים
/// ([divineNames]) ולא נשלפים מהמסד שם.
class TextBookExportRequest {
  final String rawContent;
  final bool removeNikud;
  final bool removeTaamim;
  final bool shouldReplaceHolyNames;
  final HolyNameStyle holyNameStyle;
  final DivineNameSpans divineNames;
  final bool substituteDivineNames;

  TextBookExportRequest({
    required this.rawContent,
    required this.removeNikud,
    required this.removeTaamim,
    required this.shouldReplaceHolyNames,
    this.holyNameStyle = HolyNameStyle.kufKuf,
    DivineNameSpans? divineNames,
    this.substituteDivineNames = false,
  }) : divineNames = divineNames ?? DivineNameSpans.empty;
}

/// שורות הספר לייצוא: מופעי השמות לפי `lineIndex` על השורה הגולמית, ואחריהם
/// ניקוד/טעמים ושם הוי"ה (ה-regex, כמו בתצוגה).
List<String> textBookExportLines(
  TextBookExportRequest request, {
  required bool stripHtml,
}) {
  final content = applyDivineNamesToText(
    request.rawContent,
    request.divineNames,
    substituteOtherNames: request.substituteDivineNames,
    holyNameStyle: request.shouldReplaceHolyNames
        ? request.holyNameStyle
        : null,
  );
  return content
      .split('\n')
      .map(
        (line) => applyTextBookExportTextTransforms(
          line,
          removeNikud: request.removeNikud,
          removeTaamim: request.removeTaamim,
          shouldReplaceHolyNames: request.shouldReplaceHolyNames,
          holyNameStyle: request.holyNameStyle,
          stripHtml: stripHtml,
        ),
      )
      .toList(growable: false);
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

/// מחזיר נתיב ייצוא עם הסיומת שנבחרה בפועל על ידי המשתמש.
String normalizeTextBookExportPath(
  String path, {
  required String defaultExtension,
}) {
  final extension = extensionOfTextBookExportPath(path);
  if (extension == defaultExtension) {
    return path;
  }
  if (extension.isNotEmpty) {
    return path.substring(0, path.length - extension.length) + defaultExtension;
  }
  return '$path.$defaultExtension';
}

/// מחלץ סיומת מנתיב ייצוא, באותיות קטנות וללא הנקודה.
String extensionOfTextBookExportPath(String path) {
  final lastWindowsSeparator = path.lastIndexOf('\\');
  final lastPosixSeparator = path.lastIndexOf('/');
  final fileNameStart = lastWindowsSeparator > lastPosixSeparator
      ? lastWindowsSeparator + 1
      : lastPosixSeparator + 1;
  final fileName = path.substring(fileNameStart);
  final parts = fileName.split('.');
  if (parts.length < 2) return '';
  return parts.last.toLowerCase();
}

/// מזהה שגיאות Windows נפוצות של קובץ יעד פתוח או נעול.
bool isLockedTextBookExportFileException(FileSystemException e) {
  final code = e.osError?.errorCode;
  return code == 32 || code == 33;
}
