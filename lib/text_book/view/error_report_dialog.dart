import 'dart:async';
import 'dart:io';

import 'package:otzaria/reports/bloc/book_report_draft_cubit.dart';
import 'package:otzaria/reports/book_report_selection.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/reports/view_scope.dart';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/dialogs/error_report_sender_email_dialog.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart'
    show rtlSelectionPriming;
import 'package:otzaria/utils/text/ref_helper.dart';

/// נתוני הדיווח שנאספו מתיבת סימון הטקסט + פירוט הטעות שהמשתמש הקליד.
class ReportedErrorData {
  final String selectedText; // הטקסט שסומן ע"י המשתמש
  final String errorDetails; // פירוט הטעות (שדה טקסט נוסף)

  /// הצעת תיקון מובנית; null בדיווח חופשי.
  final TextCorrection? correction;
  final BookReportSelection? selection;
  final String? selectionContext;

  const ReportedErrorData({
    required this.selectedText,
    required this.errorDetails,
    this.correction,
    this.selection,
    this.selectionContext,
  });
}

/// מה שהתוכנה יודעת בוודאות על השורה המדווחת מתוך seforim.db.
class ReportSourceSnapshot {
  final int bookId;
  final int lineIndex;
  final String? heRef;

  /// `line.content` הגולמי, כפי שהוא ב-DB.
  final String originalLine;

  const ReportSourceSnapshot({
    required this.bookId,
    required this.lineIndex,
    required this.heRef,
    required this.originalLine,
  });
}

/// פעולה שנבחרה בדיאלוג האישור.
enum ErrorReportAction {
  sendEmail,
  sendDirect,
  saveForLater,
}

/// מחלקה עזר להחזרת תוצאה מהדיאלוג (פעולה + נתונים)
class ReportDialogResult {
  final ErrorReportAction action;
  final ReportedErrorData data;

  ReportDialogResult(this.action, this.data);
}

/// תוצאת רזולוציית בחירה עבור חישוב הקשר בדיווח שגיאה.
class SelectionContextResolution {
  final String contextText;
  final int selectionStart;
  final int selectionEnd;
  final bool usedLineFallback;

  const SelectionContextResolution({
    required this.contextText,
    required this.selectionStart,
    required this.selectionEnd,
    required this.usedLineFallback,
  });
}

class _DirectReportDetails extends StatelessWidget {
  final DirectErrorReport report;

  const _DirectReportDetails({required this.report});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 560,
      child: AppSelectionArea(
        // דיווח נשלח רק על ספר מהספרייה הרשמית; המזהה מדויק מהכותרת.
        protection: () => switch (report.location?.bookId) {
          final int bookId => BookProtectionRepository.instance.forBookId(
            bookId,
          ),
          null => BookProtectionRepository.instance.forTitle(report.bookTitle),
        },
        child: SingleChildScrollView(
          child: DetailsCard(
            children: [
              if (report.rejectionReason != null)
                _ReportDetailRow(
                  label: 'הדיווח לא נקלט',
                  value: report.rejectionReason!,
                ),
              _ReportDetailRow(label: 'ספר', value: report.bookTitle),
              _ReportDetailRow(label: 'מיקום', value: report.currentRef),
              _ReportDetailRow(
                label: 'שורה',
                value: report.lineNumber.toString(),
              ),
              _ReportDetailRow(label: 'כתובת זיהוי', value: report.senderEmail),
              _ReportDetailRow(label: 'טקסט שנבחר', value: report.selectedText),
              _ReportDetailRow(
                label: 'פירוט הטעות',
                value: report.errorDetails,
              ),
              if (report.correction case final correction?)
                _ReportDetailRow(
                  label: report.serverAcceptedCorrection == false
                      ? 'הצעת תיקון (נקלטה כטקסט בלבד)'
                      : 'הצעת תיקון',
                  value: correction.fallbackBlock,
                  child: correction.proposedText == null
                      ? null
                      : TextCorrectionDiffView(
                          before: correction.target,
                          after: correction.proposedText!,
                          style:
                              Theme.of(context).textTheme.bodyMedium ??
                              const TextStyle(),
                        ),
                ),
              _ReportDetailRow(label: 'הקשר', value: report.contextText),
              _ReportDetailRow(label: 'נתיב קובץ', value: report.filePath),
              _ReportDetailRow(
                label: 'תיקיית מקור',
                value: report.sourceFolder,
              ),
              _ReportDetailRow(
                label: 'גרסת ספרייה',
                value: report.libraryVersion,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportDetailRow extends StatelessWidget {
  final String label;
  final String value;

  /// מוצג במקום [value] כשיש תצוגה עשירה יותר לערך.
  final Widget? child;

  const _ReportDetailRow({
    required this.label,
    required this.value,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty
        ? context.settingsText('לא נשלח ערך')
        : value.trim();
    if (child == null) {
      return DetailsInfoSection(
        title: context.settingsText(label),
        value: displayValue,
        // ערך קצר בשורה אחת עם התווית; ארוך או רב־שורות מתחתיה.
        block: displayValue.length > 36 || displayValue.contains('\n'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM + 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.settingsText(label),
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXS),
          child!,
        ],
      ),
    );
  }
}

/// Helper class for managing error report dialogs and actions
class ErrorReportHelper {
  static const String _fallbackMail = 'otzaria.200@gmail.com';
  static const String _otzariaDirectReportTarget = 'אוצריא';
  static const String _sefariaDirectReportTarget = 'ספריא';

  /// עמוד העריכה העצמית של ספרי דיקטה.
  static const String dictaEditUrl = 'https://otzaria.org/library/dicta-edit';

  /// תקרת אורך לקטע שמועבר בקישור — קטע חלקי עדיין מאותר באתר (התאמת
  /// substring), וכך נמנעים מ-URL ארוך מדי.
  static const int _dictaEditTextMaxLength = 300;

  /// בונה קישור עמוק לתיקון עצמי: נתיב `goto` באתר מתרגם את שם הספר למזהה
  /// במרחב העריכה ומפנה לעורך עם הקטע המדווח ממוקד ומסומן (?find=).
  /// כשאין התאמה חד-משמעית האתר נופל לרשימת הספרים מסוננת לפי השם.
  static String dictaEditUrlFor(String bookTitle, {String selectedText = ''}) {
    final trimmed = bookTitle.trim();
    if (trimmed.isEmpty) return dictaEditUrl;

    final params = <String, String>{'title': trimmed};
    var text = selectedText.trim();
    if (text.length > _dictaEditTextMaxLength) {
      text = text.substring(0, _dictaEditTextMaxLength);
      // חיתוך בגבול מילה כדי שההתאמה באתר לא תיפול על מילה קטועה
      final lastSpace = text.lastIndexOf(' ');
      if (lastSpace > 0) text = text.substring(0, lastSpace);
    }
    if (text.isNotEmpty) params['text'] = text;

    return Uri.parse(
      '$dictaEditUrl/goto',
    ).replace(queryParameters: params).toString();
  }

  /// [state] הוא null בדיווח ממשטח ללא `TextBookBloc` (חלונית ה-PDF); אז
  /// [reportContent] חייב להיות מסופק, והוא מקור התוכן היחיד.
  static List<String> resolveReportContent({
    required TextBookLoaded? state,
    List<String>? reportContent,
  }) {
    return reportContent ?? state?.content ?? const [];
  }

  /// [reportBook] נדרש כשאין [state] — ראה [resolveReportContent].
  static TextBook? resolveReportBook({
    required TextBookLoaded? state,
    TextBook? reportBook,
  }) {
    return reportBook ?? state?.book;
  }

  /// קורא את השורה הגולמית מ-seforim.db. null כשאין מקור מוסמך: ספר אישי,
  /// מהדורה חלופית, ספר מקובץ, או שורה שאינה זהה למה שהוצג למשתמש.
  static Future<ReportSourceSnapshot?> resolveReportSource({
    required TextBook book,
    required int lineIndex,
    required List<String> content,
    String? reportLine,
  }) async {
    if (!book.isOfficialLibraryBook || book.versionTitle != null) return null;
    try {
      final resolved = await BookDatabaseResolver.resolveBook(
        title: book.title,
        categoryId: book.categoryId,
        fileType: book.fileType,
        filePath: book.filePath,
        officialOnly: true,
      );
      if (resolved == null ||
          !resolved.source.isOfficial ||
          resolved.book.isFileBacked) {
        return null;
      }
      final line = (await DbReadWorker.lines(
        SqliteDataProvider.instance.dbPath,
        resolved.book.id,
        lineIndex,
        lineIndex,
      )).firstOrNull;
      if (line == null) return null;
      final snapshot = ReportSourceSnapshot(
        bookId: resolved.book.id,
        lineIndex: lineIndex,
        heRef: line.heRef,
        originalLine: line.content,
      );
      return isSourceConsistentWithContent(
            snapshot,
            content,
            reportLine: reportLine,
          )
          ? snapshot
          : null;
    } catch (e) {
      debugPrint('Resolving report source failed: $e');
      return null;
    }
  }

  /// השורה מה-DB חייבת להיות זהה לשורה שהוצגה, אחרת המשתמש סימן במקום אחר.
  /// [reportLine] — השורה שהוצגה כש-[content] אינו מסודר לפי אינדקס השורה (מפרש).
  static bool isSourceConsistentWithContent(
    ReportSourceSnapshot snapshot,
    List<String> content, {
    String? reportLine,
  }) {
    if (reportLine != null) return reportLine == snapshot.originalLine;
    final index = snapshot.lineIndex;
    return index >= 0 &&
        index < content.length &&
        content[index] == snapshot.originalLine;
  }

  static TextCorrection? correctionForReport({
    required ReportSourceSnapshot? source,
    required String selectedText,
    String? reportNote,
  }) => source == null || reportNote != null
      ? null
      : buildCorrectionTemplate(source.originalLine, selectedText);

  static String resolveReportTargetText({
    required List<String> content,
    required String selectedText,
    int? preferredLineNumber,
    String? reportNote,
  }) {
    // Notes are already decoded by the renderer. Literal markup in their
    // visible text (for example &lt;b&gt;) must not be parsed a second time.
    if (reportNote != null) {
      return selectedText.trim().isEmpty ? reportNote.trim() : selectedText;
    }
    if (selectedText.trim().isNotEmpty) {
      return sanitizeReportText(selectedText);
    }

    final hasValidPreferredLine =
        preferredLineNumber != null &&
        preferredLineNumber >= 0 &&
        preferredLineNumber < content.length;
    if (!hasValidPreferredLine) {
      return sanitizeReportText(selectedText);
    }

    return sanitizeReportText(content[preferredLineNumber]);
  }

  /// Free reports from file-backed, user and version books also let the user
  /// select an occurrence within the complete displayed line, without needing
  /// an official structured-correction source.
  static String resolveReportSelectionSource({
    required List<String> content,
    required int lineIndex,
    required String selectedText,
    String? originalLine,
    String? reportNote,
  }) {
    if (reportNote != null) return reportNote;
    final raw =
        originalLine ??
        (lineIndex >= 0 && lineIndex < content.length
            ? content[lineIndex]
            : null);
    if (raw == null) return selectedText;
    final displayed = sanitizeReportText(raw);
    return displayed.contains(selectedText) ? displayed : selectedText;
  }

  static bool isSefariaSourceFolder(String? sourceFolder) {
    final normalizedSource = sourceFolder?.trim().toLowerCase() ?? '';
    return normalizedSource.contains('sefariatootzaria') ||
        normalizedSource.contains('sefaria');
  }

  /// נמעני המייל לפי מקור הספר, מופרדים בפסיק. סדר המפתחות חשוב, והמיפוי
  /// חייב להישאר תואם ל-getEmailRecipients בשרת (Otzaria_Website).
  ///
  /// ההתאמה היא `contains` על המחרוזת המנורמלת לאותיות קטנות בלבד — בלי הסרת
  /// מפרידים. לכן מפתח חייב להיות תת-מחרוזת של שם המקור ב-`seforim.db` כפי
  /// שהוא (למשל `wikiJewishBooksToOtzaria`); מפתח עם קו תחתון לעולם לא יתאים.
  static String emailRecipientsFor(String? sourceFolder) {
    if (sourceFolder == null) return _fallbackMail;
    const sourceToEmailMap = {
      'sefariaToOtzaria': 'corrections@sefaria.org,jewishoffice@gmail.com',
      'sefaria': 'corrections@sefaria.org,jewishoffice@gmail.com',
      'wikiJewishBooks': '$_fallbackMail,WikiJewishBooks@gmail.com',
      'wikiSource': '$_fallbackMail,novartza@gmail.com',
      'Pninim': '$_fallbackMail,contact@pninim.org',
      'Tashma': '$_fallbackMail,jewishoffice@gmail.com',
      'Dicta': '$_fallbackMail,jewishoffice@gmail.com',
      'Ben-Yehuda': '$_fallbackMail,editor@benyehuda.org',
      // רישיון "ים החכמה" מחייב שדיווח על ספר משלהם יגיע גם אליהם.
      'yam-HaHachma': '$_fallbackMail,y025837086@gmail.com',
    };
    final normalizedSource = sourceFolder.toLowerCase();
    return sourceToEmailMap.entries
            .firstWhereOrNull(
              (entry) => normalizedSource.contains(entry.key.toLowerCase()),
            )
            ?.value ??
        _fallbackMail;
  }

  /// קישור לסגמנט המדויק בספריא. [heRef] של שורה בספר מספריא הוא מראה המקום
  /// של ספריא עצמה; נתיב תוכן העניינים ("סימן שיח") נופל אצלם לתחילת הספר.
  static String? sefariaUrlFor(String? heRef) {
    final ref = heRef?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return ref.isEmpty
        ? null
        : 'https://www.sefaria.org/${Uri.encodeComponent(ref)}';
  }

  static const int _wordsAroundChange = 4;

  /// כמה מילים סביב השינוי כפי שהן בספר, ושוב אחרי התיקון (השינוי בכוכביות),
  /// לאיתור בחיפוש באתר המקור. תואם ל-buildCorrectionSnippets באתר.
  static ({String wrong, String fixed, String? context})? correctionSnippets(
    TextCorrection correction,
  ) {
    final proposed = correction.proposedText;
    if (proposed == null) return null;
    // <br> מפריד בין מילים בתצוגה; בלי רווח במקומו המילים היו מתחברות.
    List<String> words(String line) => sanitizeReportText(
      line.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' '),
    ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final oldWords = words(correction.originalLine);
    final newWords = words(
      correction.hasSelection
          ? correction.contextBefore + proposed + correction.contextAfter
          : proposed,
    );
    var prefix = 0;
    while (prefix < oldWords.length &&
        prefix < newWords.length &&
        oldWords[prefix] == newWords[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldWords.length - prefix &&
        suffix < newWords.length - prefix &&
        oldWords[oldWords.length - 1 - suffix] ==
            newWords[newWords.length - 1 - suffix]) {
      suffix++;
    }
    if (prefix == oldWords.length && prefix == newWords.length) return null;

    final from = math.max(0, prefix - _wordsAroundChange);
    final until = math.min(
      oldWords.length,
      oldWords.length - suffix + _wordsAroundChange,
    );
    final changed = newWords.sublist(prefix, newWords.length - suffix);
    final deleted = oldWords.sublist(prefix, oldWords.length - suffix);
    final newTail = newWords.length - suffix;
    final wrong = oldWords.sublist(from, until).join(' ');
    final original = oldWords.join(' ');
    final searchable = ' $original ';
    final needle = ' $wrong ';
    final first = searchable.indexOf(needle);
    final ambiguous = first >= 0 && searchable.indexOf(needle, first + 1) >= 0;
    return (
      wrong: wrong,
      context: ambiguous
          ? 'הקטע מופיע יותר מפעם אחת בשורה. מיקום הקטע: מילים ${from + 1}–$until מתוך ${oldWords.length}.\n\n'
                'השורה המקורית המלאה:\n$original\n\n'
                'השורה המתוקנת המלאה:\n${newWords.join(' ')}'
          : null,
      fixed: [
        ...newWords.sublist(from, prefix),
        changed.isNotEmpty
            ? '*${changed.join(' ')}*'
            : '*(נמחק: ${deleted.join(' ')})*',
        ...newWords.sublist(
          newTail,
          math.min(newWords.length, newTail + _wordsAroundChange),
        ),
      ].join(' '),
    );
  }

  static bool isDictaSourceFolder(String? sourceFolder) {
    final normalizedSource = sourceFolder?.trim().toLowerCase() ?? '';
    return normalizedSource.contains('dicta');
  }

  static String resolveDirectReportTargetLabel(String? sourceFolder) {
    return isSefariaSourceFolder(sourceFolder)
        ? _sefariaDirectReportTarget
        : _otzariaDirectReportTarget;
  }

  /// מנקה טקסט לדיווח: מסיר תגיות HTML ומפענח ישויות HTML נפוצות.
  static String sanitizeReportText(String text) {
    if (text.trim().isEmpty) {
      return '';
    }

    final decoded = html_parser.parseFragment(text).text ?? '';
    return decoded.replaceAll('\u00A0', ' ').trim();
  }

  /// Build 4+4 words context around a selection range within fullText
  static String buildContextAroundSelection(
    String fullText,
    int selectionStart,
    int selectionEnd, {
    int wordsBefore = 4,
    int wordsAfter = 4,
  }) {
    if (selectionStart < 0 || selectionEnd <= selectionStart) {
      return fullText;
    }
    final wordRegex = RegExp("\\S+", multiLine: true);
    // סריקת ספר שלם תוקעת את הממשק (#3727), לכן סורקים חלון סביב הבחירה.
    // מילה בקצה חתוך עלולה להיות חלקית: כשההקשר מגיע אליה מרחיבים את החלון.
    for (var radius = 1024; ; radius *= 4) {
      final lo = math.max(
        0,
        math.min(selectionStart - radius, fullText.length),
      );
      final hi = math.max(lo, math.min(selectionEnd + radius, fullText.length));
      final isWholeText = lo == 0 && hi == fullText.length;
      final matches = wordRegex.allMatches(fullText.substring(lo, hi)).toList();
      if (matches.isEmpty) {
        if (isWholeText) return fullText;
        continue;
      }
      final windowStart = selectionStart - lo;
      final windowEnd = selectionEnd - lo;

      int? startWordIndex;
      int? endWordIndex;

      for (int i = 0; i < matches.length; i++) {
        final m = matches[i];
        if (windowStart >= m.start && windowStart < m.end) {
          startWordIndex = i;
          break;
        }
        if (windowStart < m.start) {
          startWordIndex = i;
          break;
        }
      }

      for (int i = matches.length - 1; i >= 0; i--) {
        final m = matches[i];
        final selEndMinusOne = windowEnd - 1;
        if (selEndMinusOne >= m.start && selEndMinusOne < m.end) {
          endWordIndex = i;
          break;
        }
        if (selEndMinusOne > m.end) {
          endWordIndex = i;
          break;
        }
      }

      // "לא נמצאה מילה" מוכרע רק כשהחלון מגיע לקצה הטקסט באותו צד.
      if ((startWordIndex == null && hi < fullText.length) ||
          (endWordIndex == null && lo > 0)) {
        continue;
      }
      startWordIndex ??= 0;
      endWordIndex ??= matches.length - 1;

      final ctxStart = (startWordIndex - wordsBefore) < 0
          ? 0
          : (startWordIndex - wordsBefore);
      final ctxEnd = (endWordIndex + wordsAfter) >= matches.length
          ? matches.length - 1
          : (endWordIndex + wordsAfter);

      if ((lo > 0 && ctxStart == 0) ||
          (hi < fullText.length && ctxEnd == matches.length - 1)) {
        continue;
      }

      final from = lo + matches[ctxStart].start;
      final to = lo + matches[ctxEnd].end;
      if (from < 0 || to <= from || to > fullText.length) return fullText;
      return fullText.substring(from, to);
    }
  }

  /// פותר את מיקום הבחירה והקשר סביבה בצורה יציבה.
  ///
  /// נותן עדיפות לשורה שנבחרה. אם יש בשורה כמה מופעים של אותו טקסט (עמימות),
  /// לא בוחרים מופע שרירותי אלא מבצעים fallback בטוח להקשר ברמת השורה.
  static SelectionContextResolution resolveSelectionContext({
    required List<String> content,
    required String selectedText,
    int? preferredLineNumber,
    int wordsBefore = 4,
    int wordsAfter = 4,
  }) {
    final allText = content.join('\n');
    if (allText.isEmpty) {
      return const SelectionContextResolution(
        contextText: '',
        selectionStart: -1,
        selectionEnd: -1,
        usedLineFallback: false,
      );
    }

    final hasValidPreferredLine =
        preferredLineNumber != null &&
        preferredLineNumber >= 0 &&
        preferredLineNumber < content.length;

    final int? lineNumber = hasValidPreferredLine ? preferredLineNumber : null;
    final lineStart = lineNumber != null
        ? _lineStartOffset(content, lineNumber)
        : 0;
    final lineEnd = lineNumber != null
        ? lineStart + content[lineNumber].length
        : 0;

    int selectionStart = -1;
    bool usedLineFallback = false;

    if (selectedText.isNotEmpty) {
      if (lineNumber != null) {
        final lineText = content[lineNumber];
        final occurrencesInLine = _findAllOccurrences(lineText, selectedText);

        if (occurrencesInLine.length == 1) {
          // מופע יחיד בשורה — חד-משמעי
          selectionStart = lineStart + occurrencesInLine.first;
        } else if (occurrencesInLine.length > 1) {
          // עמימות: אותו טקסט מופיע כמה פעמים באותה שורה.
          // ל-SelectionArea של Flutter אין API שחושף את ה-offset המדויק
          // של הבחירה, לכן אין לנו דרך לדעת איזה מופע נבחר.
          // במקום לנחש (ראשון/אחרון), נחזיר את כל השורה כהקשר —
          // כך מי שקורא את הדיווח יראה את כל המופעים ויוכל להבין
          // בשילוב עם תיאור השגיאה של המשתמש.
          usedLineFallback = true;
          final contextText = buildContextAroundSelection(
            allText,
            lineStart,
            lineEnd,
            wordsBefore: wordsBefore,
            wordsAfter: wordsAfter,
          );
          return SelectionContextResolution(
            contextText: contextText,
            selectionStart: lineStart,
            selectionEnd: lineEnd,
            usedLineFallback: usedLineFallback,
          );
        } else {
          // הטקסט לא נמצא בשורה המועדפת — מחפשים מהשורה ואילך
          selectionStart = allText.indexOf(selectedText, lineStart);
        }
      } else {
        selectionStart = allText.indexOf(selectedText);
      }

      if (selectionStart < 0) {
        selectionStart = allText.indexOf(selectedText);
      }
    }

    if (selectionStart >= 0 && selectedText.isNotEmpty) {
      final selectionEnd = selectionStart + selectedText.length;
      final contextText = buildContextAroundSelection(
        allText,
        selectionStart,
        selectionEnd,
        wordsBefore: wordsBefore,
        wordsAfter: wordsAfter,
      );
      return SelectionContextResolution(
        contextText: contextText,
        selectionStart: selectionStart,
        selectionEnd: selectionEnd,
        usedLineFallback: usedLineFallback,
      );
    }

    if (lineNumber != null) {
      final contextText = buildContextAroundSelection(
        allText,
        lineStart,
        lineEnd,
        wordsBefore: wordsBefore,
        wordsAfter: wordsAfter,
      );
      return SelectionContextResolution(
        contextText: contextText,
        selectionStart: lineStart,
        selectionEnd: lineEnd,
        usedLineFallback: true,
      );
    }

    return SelectionContextResolution(
      contextText: allText,
      selectionStart: 0,
      selectionEnd: allText.length,
      usedLineFallback: usedLineFallback,
    );
  }

  static int _lineStartOffset(List<String> content, int lineNumber) {
    int offset = 0;
    for (int i = 0; i < lineNumber; i++) {
      offset += content[i].length + 1; // +1 עבור \n
    }
    return offset;
  }

  static List<int> _findAllOccurrences(String text, String pattern) {
    final indices = <int>[];
    if (text.isEmpty || pattern.isEmpty) return indices;

    int searchFrom = 0;
    while (searchFrom <= text.length - pattern.length) {
      final found = text.indexOf(pattern, searchFrom);
      if (found < 0) break;
      indices.add(found);
      searchFrom = found + pattern.length;
    }
    return indices;
  }

  /// Build email body for error report
  static String buildEmailBody(
    String bookTitle,
    String currentRef,
    Map<String, String> bookDetails,
    String selectedText,
    String errorDetails,
    int lineNumber,
    String contextText,
    String libraryVersion,
    String? senderEmail, {
    String? directLink,
  }) {
    final linkLine = directLink == null ? '' : '\nקישור ישיר: $directLink';
    final senderSection = (senderEmail == null || senderEmail.isEmpty)
        ? ''
        : '\nכתובת ליצירת קשר: $senderEmail\n';

    final detailsSection = (() {
      final base = errorDetails.isEmpty ? '' : '\n$errorDetails';
      final extra =
          '''
      
    מספר שורה: $lineNumber
    הקשר (4 מילים לפני ואחרי):
    $contextText''';
      return '$base$extra';
    })();

    return '''
שם הספר: $bookTitle
מיקום: $currentRef$linkLine
גרסת ספרייה: $libraryVersion
שם הקובץ: ${bookDetails['שם הקובץ']}
נתיב הקובץ: ${bookDetails['נתיב הקובץ']}
תיקיית המקור: ${bookDetails['תיקיית המקור']}
$senderSection

הטקסט שבו נמצאה הטעות:
$selectedText

פירוט הטעות:
$detailsSection
''';
  }

  /// Encode query parameters for mailto URL
  static String? encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (MapEntry<String, String> e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  /// Show simple snackbar message
  static void showSimpleSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    UiSnack.show(reportText(context, message));
  }

  static Future<String?> ensureSenderEmail(BuildContext context) async {
    final reportService = DirectErrorReportService();
    final currentEmail = reportService.senderEmail;

    if (DirectErrorReportService.isValidSenderEmail(currentEmail)) {
      return currentEmail;
    }

    final enteredEmail = await showErrorReportSenderEmailDialog(
      context: context,
      initialValue: currentEmail,
      validator: (email) => DirectErrorReportService.isValidSenderEmail(email)
          ? null
          : 'יש להזין כתובת דוא"ל תקינה.',
    );

    if (enteredEmail == null || enteredEmail.isEmpty) {
      return null;
    }

    await reportService.saveSenderEmail(enteredEmail);
    if (context.mounted) {
      UiSnack.showSuccess(reportText(context, ReportMessages.senderEmailSaved));
    }
    return enteredEmail.trim();
  }

  static DirectErrorReport buildDirectReport({
    required String senderEmail,
    required ReportedErrorData reportData,
    required String bookTitle,
    required String currentRef,
    required Map<String, String> bookDetails,
    required int lineNumber,
    required String contextText,
    required String libraryVersion,
    ReportSourceSnapshot? source,
  }) {
    final normalizedLibraryVersion = libraryVersion.trim().isEmpty
        ? 'unknown'
        : libraryVersion.trim();
    // הצעת תיקון בלי הצעה (null, מדיווח שמור מגרסה קודמת) נשלחת כדיווח חופשי.
    final correction =
        source == null || reportData.correction?.proposedText == null
        ? null
        : reportData.correction;
    const fit = DirectErrorReport.fitDisplayField;
    return DirectErrorReport(
      schemaVersion: DirectErrorReport.currentSchemaVersion,
      reportKind: correction == null
          ? DirectErrorReportKind.freeText
          : DirectErrorReportKind.textCorrection,
      correction: correction,
      location: ReportLocation(
        lineIndex: source?.lineIndex,
        bookId: source?.bookId,
        libraryBuildId: normalizedLibraryVersion == 'unknown'
            ? null
            : normalizedLibraryVersion,
        heRef: source?.heRef,
      ),
      client: ReportClientInfo(
        appVersion: ErrorLogFile.appVersion,
        platform: Platform.operatingSystem,
      ),
      id: '${DateTime.now().microsecondsSinceEpoch}-${widgetHash(bookTitle, currentRef, reportData.selectedText)}',
      senderEmail: senderEmail,
      // שדות התצוגה מקוצרים כאן, לפני ה-digest: האתר דוחה חריגה ב-v2.
      subject: fit(
        ReportMessages.reportSubject(bookTitle),
        DirectErrorReport.maxSubjectLength,
      ),
      bookTitle: fit(bookTitle, DirectErrorReport.maxTitleOrRefLength),
      currentRef: fit(currentRef, DirectErrorReport.maxTitleOrRefLength),
      lineNumber: lineNumber,
      // שדות חופשיים; surrogate בודד היה פוסל את ה-digest של הדיווח כולו.
      selectedText: fit(
        replaceLoneSurrogates(reportData.selectedText),
        DirectErrorReport.maxSelectedTextLength,
      ),
      errorDetails: replaceLoneSurrogates(reportData.errorDetails),
      contextText: fit(
        replaceLoneSurrogates(
          reportData.selectionContext == null ||
                  contextText.startsWith(reportData.selectionContext!)
              ? contextText
              : '${reportData.selectionContext}\n\n$contextText',
        ),
        DirectErrorReport.maxContextTextLength,
      ),
      filePath: bookDetails['נתיב הקובץ'] ?? '',
      sourceFolder: bookDetails['תיקיית המקור'] ?? '',
      libraryVersion: normalizedLibraryVersion,
      createdAt: DateTime.now().toUtc(),
    );
  }

  static Future<void> showDirectReportDetailsDialog(
    BuildContext context, {
    required String title,
    required DirectErrorReport report,
  }) async {
    await showSingleActionDialog(
      context: context,
      title: reportText(context, title),
      icon: FluentIcons.document_text_24_regular,
      size: AppDialogSize.medium,
      confirmText: reportText(context, 'סגור'),
      customContent: reportDialogBuilder(
        context,
        (_) => _DirectReportDetails(report: report),
      )(context),
    );
  }

  static Future<bool> handleDirectReport(
    BuildContext context,
    DirectErrorReport reportData,
  ) async {
    try {
      final reportService = DirectErrorReportService();
      final result = await runWithBlockingProgress(
        context: context,
        title: reportText(context, ReportMessages.sendingTitle),
        message: reportText(context, ReportMessages.sending),
        task: () => reportService.submitReport(reportData),
      );

      if (!context.mounted) {
        return result.isSent || result.isQueued;
      }

      if (result.isSent) {
        if (result.isDuplicate || result.correctionNotSupported) {
          UiSnack.show(reportFeedbackText(context, result.message));
        } else {
          await showDirectReportDetailsDialog(
            context,
            title: reportText(context, ReportMessages.sentSuccessTitle),
            report: reportData,
          );
        }
      } else if (result.isQueued) {
        UiSnack.show(reportFeedbackText(context, result.message));
      } else {
        UiSnack.showError(reportFeedbackText(context, result.message));
      }
      return result.isSent || result.isQueued;
    } catch (e) {
      debugPrint('Direct report error: $e');
      if (context.mounted) {
        UiSnack.showError(
          reportText(
            context,
            'שגיאה בשליחת הדיווח: {error}',
            args: {'error': e},
          ),
        );
      }
      return false;
    }
  }

  /// פירוט הטעות למייל: הסבר המשתמש, ואחריו הצעת התיקון כטקסט שגוי ומתוקן.
  /// [withFullProposal] מצרף גם את ההצעה המלאה, לנמען שמחיל אותה על הקובץ.
  static String emailErrorDetails(
    ReportedErrorData reportData, {
    bool withFullProposal = false,
  }) {
    final correction = reportData.correction;
    final details = reportData.errorDetails;
    if (correction == null) return details;
    final snippets = correctionSnippets(correction);
    if (snippets == null) return correction.appendFallbackTo(details);
    final block =
        'הטקסט השגוי:\n${snippets.wrong}\n\nהטקסט המתוקן:\n${snippets.fixed}'
        '${snippets.context == null ? '' : '\n\n${snippets.context}'}';
    final withSnippets = details.isEmpty ? block : '$details\n\n$block';
    return withFullProposal
        ? correction.appendFallbackTo(withSnippets)
        : withSnippets;
  }

  /// Handle regular report action (email or save)
  static Future<bool> handleRegularReportAction(
    BuildContext context,
    ErrorReportAction action,
    ReportedErrorData reportData,
    String bookTitle,
    String currentRef,
    Map<String, String> bookDetails,
    int lineNumber,
    String contextText,
    String libraryVersion, {
    ReportSourceSnapshot? source,
    String? reportId,
    Future<bool> Function()? verifySource,
  }) async {
    final emailBody = buildEmailBody(
      bookTitle,
      currentRef,
      bookDetails,
      reportData.selectedText,
      // לכל מקור שאינו ספריא המייל מגיע גם לתיבת אוצריא, שמחילה את ההצעה המלאה.
      emailErrorDetails(
        reportData,
        withFullProposal: !isSefariaSourceFolder(bookDetails['תיקיית המקור']),
      ),
      lineNumber,
      contextText,
      libraryVersion,
      null,
      directLink: isSefariaSourceFolder(bookDetails['תיקיית המקור'])
          ? sefariaUrlFor(source?.heRef)
          : null,
    );

    if (verifySource != null && !await verifySource()) {
      throw StateError('The source changed before delivery.');
    }
    if (action == ErrorReportAction.sendEmail) {
      final emailUri = Uri(
        scheme: 'mailto',
        path: emailRecipientsFor(bookDetails['תיקיית המקור']),
        query: encodeQueryParameters(<String, String>{
          'subject': ReportMessages.reportSubject(bookTitle),
          'body': emailBody,
        }),
      );

      try {
        final opened = await launchUrl(
          emailUri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          if (context.mounted) {
            showSimpleSnack(context, ReportMessages.cannotOpenMailApp);
          }
        }
        if (opened && context.mounted) {
          showSimpleSnack(
            context,
            'תוכנת הדואר נפתחה. הטיוטה נשמרה בהגדרות עד שתשלחו את הדיווח או תשליכו אותה במפורש.',
          );
        }
        // Opening a composer confirms neither delivery nor intentional queueing.
        return false;
      } catch (_) {
        if (context.mounted) {
          showSimpleSnack(context, 'לא ניתן לפתוח את תוכנת הדואר');
        }
      }
    } else if (action == ErrorReportAction.saveForLater) {
      if (!context.mounted) return false;
      final senderEmail = await ensureSenderEmail(context);
      if (senderEmail == null) {
        return false;
      }

      if (verifySource != null && !await verifySource()) {
        throw StateError('The source changed before queueing.');
      }
      final directReport = buildDirectReport(
        senderEmail: senderEmail,
        reportData: reportData,
        bookTitle: bookTitle,
        currentRef: currentRef,
        bookDetails: bookDetails,
        lineNumber: lineNumber,
        contextText: contextText,
        libraryVersion: libraryVersion,
        source: source,
      );

      final reportService = DirectErrorReportService();
      await reportService.queueReport(
        reportId == null ? directReport : directReport.withId(reportId),
        queueType: DirectErrorReportQueueType.manual,
      );
      final count = await reportService.getPendingReportsCount();
      if (context.mounted) {
        UiSnack.show(
          reportText(
            context,
            'הדיווח נשמר להמשך. יש כרגע {count} דיווחים ממתינים בתור, וניתן לנהל את הדיווחים השמורים בהגדרות.',
            args: {'count': count},
          ),
        );
      }
      return true;
    }
    return false;
  }

  /// Show error report dialog for text book
  ///
  /// This is a shared helper to avoid code duplication across different views.
  ///
  /// Parameters:
  /// - [context]: BuildContext for showing the dialog
  /// - [selectedText]: The text selected by the user
  /// - [state]: מצב הטקסט, או null במשטח ללא `TextBookBloc` (חלונית ה-PDF).
  ///   כשהוא null חובה לספק [reportBook] — הוא מזהה את הספר המדווח.
  /// - [fontSize]: Font size to use in the dialog
  /// - [bookTitle]: Title of the book
  /// - [savedSelectedIndex]: Optional saved selected index (can be int or ValueNotifier of int)
  /// - [reportContent]: Optional content override for reports that target a secondary text
  /// - [reportBook]: Optional book override for reports that target a secondary text
  /// - [reportLine]: השורה הגולמית ב-[savedSelectedIndex] כש-[reportContent] אינו
  ///   הספר כולו (מפרש); בלעדיה אין מסלול הצעת תיקון.
  /// - [reportNote]: טקסט תצוגה של הערת שוליים ומיקומה; מחייב דיווח חופשי
  ///   כדי שהצעת תיקון לא תחול בטעות על שורת האב.
  static Future<void> showErrorReportDialog({
    required BuildContext context,
    required String selectedText,
    required TextBookLoaded? state,
    required double fontSize,
    required String bookTitle,
    int? savedSelectedIndex,
    List<String>? reportContent,
    TextBook? reportBook,
    String? reportLine,
    String? reportNote,
  }) async {
    final effectiveContent = resolveReportContent(
      state: state,
      reportContent: reportContent,
    );
    final effectiveBook = resolveReportBook(
      state: state,
      reportBook: reportBook,
    );
    if (effectiveBook == null) {
      UiSnack.showError(
        reportText(context, ReportMessages.cannotIdentifyReportedBook),
      );
      return;
    }

    // קבלת מספר השורה הנוכחי
    int? currentLineNumber;

    // אם יש savedSelectedIndex, נשתמש בו
    currentLineNumber = savedSelectedIndex;

    // אם אין savedSelectedIndex, נשתמש ב-state
    currentLineNumber ??=
        state?.selectedIndex ??
        (state != null && state.visibleIndices.isNotEmpty
            ? state.visibleIndices.first
            : 0);

    final resolvedSelectedText = resolveReportTargetText(
      content: effectiveContent,
      selectedText: selectedText,
      preferredLineNumber: currentLineNumber,
      reportNote: reportNote,
    );
    final bookDetails = await BookDetailsService().getBookDetails(
      effectiveBook,
    );
    final directReportTargetLabel = resolveDirectReportTargetLabel(
      bookDetails['תיקיית המקור'],
    );
    final isDictaSource = isDictaSourceFolder(bookDetails['תיקיית המקור']);
    final isSefariaSource = isSefariaSourceFolder(bookDetails['תיקיית המקור']);
    // הצעת תיקון נבנית רק על השורה הגולמית מה-DB, לא על הטקסט המעובד שהוצג.
    final source = await resolveReportSource(
      book: effectiveBook,
      lineIndex: currentLineNumber,
      content: effectiveContent,
      reportLine: reportLine,
    );
    final correctionTemplate = correctionForReport(
      source: source,
      selectedText: selectedText,
      reportNote: reportNote,
    );

    if (!context.mounted) return;
    final lineIndex = currentLineNumber;

    // Freeze all routing and source data before opening the form. A draft must
    // not pick up a different open book or a new library build on restoration.
    final displayedText = resolvedSelectedText;
    final contextText =
        reportNote?.trim() ??
        sanitizeReportText(
          resolveSelectionContext(
            content: effectiveContent,
            selectedText: displayedText,
            preferredLineNumber: lineIndex,
            wordsBefore: 4,
            wordsAfter: 4,
          ).contextText,
        );
    final selectionSource = resolveReportSelectionSource(
      content: effectiveContent,
      lineIndex: lineIndex,
      selectedText: displayedText,
      originalLine: source?.originalLine ?? reportLine,
      reportNote: reportNote,
    );
    final target = <String, dynamic>{
      'selectionSource': selectionSource,
      'bookTitle': bookTitle,
      'selectedText': displayedText,
      'reportNote': reportNote,
      'fontSize': fontSize,
      'lineNumber': lineIndex + 1,
      'directReportTargetLabel': directReportTargetLabel,
      'isDictaSource': isDictaSource,
      'isSefariaSource': isSefariaSource,
      'correctionTemplate': correctionTemplate?.toJson(),
      'contextText': contextText,
      'currentRef': await refFromIndex(
        lineIndex,
        effectiveBook.tableOfContents,
      ),
      'libraryVersion': await DataCollectionService().readLibraryVersion(),
      'bookDetails': bookDetails,
      'source': source == null
          ? null
          : {
              'bookId': source.bookId,
              'lineIndex': source.lineIndex,
              'heRef': source.heRef,
              'originalLine': source.originalLine,
            },
    };
    if (context.mounted) await _showFrozenReportDialog(context, target);
  }

  static Future<void> resumeDraft(
    BuildContext context,
    ReportDraftRecord summary,
  ) async {
    final record = await ReportDraftStore.instance.read(summary.id);
    if (record == null || !context.mounted) return;
    final target = Map<String, dynamic>.from(record.payload['target'] as Map);
    await _showFrozenReportDialog(context, target, restored: record);
  }

  /// Only a single row is read, when resuming/submitting a structured draft.
  /// Unknown or changed source identity blocks submission; no retargeting.
  static Future<bool> draftSourceMatches(Map<String, dynamic> target) async {
    final source = target['source'];
    if (source is! Map) return false;
    try {
      final libraryVersion = await DataCollectionService().readLibraryVersion();
      if (libraryVersion != target['libraryVersion']) return false;
      final resolved = await BookDatabaseResolver.resolveBook(
        title: target['bookTitle'] as String,
        officialOnly: true,
      );
      if (resolved == null ||
          resolved.book.id != source['bookId'] ||
          resolved.book.isFileBacked) {
        return false;
      }
      final line = (await DbReadWorker.lines(
        SqliteDataProvider.instance.dbPath,
        source['bookId'] as int,
        source['lineIndex'] as int,
        source['lineIndex'] as int,
      )).firstOrNull;
      return line != null &&
          line.content == source['originalLine'] &&
          line.heRef == source['heRef'];
    } catch (error) {
      debugPrint('Draft source verification failed: $error');
      return false;
    }
  }

  static Future<void> _showFrozenReportDialog(
    BuildContext context,
    Map<String, dynamic> target, {
    ReportDraftRecord? restored,
  }) async {
    final template = TextCorrection.fromJson(target['correctionTemplate']);
    final selectionSource =
        target['selectionSource'] as String? ??
        target['selectedText'] as String;
    final selection = BookReportSelection.unique(
      selectionSource,
      target['selectedText'] as String,
    );
    final initialForm = <String, dynamic>{
      'mode': template == null ? 'freeText' : 'correction',
      'details': '',
      'proposedText': template?.target ?? '',
      'proposalMode': 'replace',
      'selectionStart': selection?.start,
      'selectionEnd': selection?.end,
    };
    final draft = BookReportDraftCubit(
      target: target,
      initialForm: initialForm,
      restored: restored,
    );
    final rawSource = target['source'] as Map?;
    final source = rawSource == null
        ? null
        : ReportSourceSnapshot(
            bookId: rawSource['bookId'] as int,
            lineIndex: rawSource['lineIndex'] as int,
            heRef: rawSource['heRef'] as String?,
            originalLine: rawSource['originalLine'] as String,
          );
    final sourceChanged =
        restored != null &&
        template != null &&
        !await draftSourceMatches(target);
    String reportContext(ReportedErrorData data) => [
      if (data.selectionContext != null) data.selectionContext!,
      target['contextText'] as String,
    ].join('\n\n');
    DirectErrorReport build(ReportedErrorData data, String email) =>
        buildDirectReport(
          senderEmail: email,
          reportData: data,
          bookTitle: target['bookTitle'] as String,
          currentRef: target['currentRef'] as String,
          bookDetails: Map<String, String>.from(target['bookDetails'] as Map),
          lineNumber: target['lineNumber'] as int,
          contextText: reportContext(data),
          libraryVersion: target['libraryVersion'] as String,
          source: source,
        ).withId(draft.reportId);
    if (!context.mounted) {
      await draft.close();
      return;
    }
    try {
      final result = await showDialogUntilTornDown<ReportDialogResult>(
        context: context,
        builder: reportDialogBuilder(
          context,
          (_) => TabbedReportDialog(
            selectedText: target['selectedText'] as String,
            selectionSource: selectionSource,
            fontSize: (target['fontSize'] as num).toDouble(),
            bookTitle: target['bookTitle'] as String,
            currentLineNumber: target['lineNumber'] as int,
            directReportTargetLabel:
                target['directReportTargetLabel'] as String,
            isDictaSource: target['isDictaSource'] == true,
            isSefariaSource: target['isSefariaSource'] == true,
            correctionTemplate: template,
            draft: draft,
            sourceChanged: sourceChanged,
            validateBeforeSubmit: (data) async {
              final unavailableMessage = reportText(
                context,
                'מקור הספר השתנה או אינו זמין. אפשר לשמור את הטיוטה או לעבור במפורש לדיווח חופשי.',
              );
              final tooLargeMessage = reportText(
                context,
                'הדיווח גדול מדי לשליחה. יש לקצר את הפירוט או את ההצעה; הטקסט לא ייחתך.',
              );
              if (data.correction != null &&
                  !await draftSourceMatches(target)) {
                return unavailableMessage;
              }
              return build(data, _longestEmailPlaceholder).exceedsApiBodyLimit
                  ? tooLargeMessage
                  : null;
            },
          ),
        ),
      );
      if (result == null || !context.mounted) return;
      final data = result.data;
      // The form is already durably saved before it returns an action. A mail
      // picker cancellation or transport error leaves that draft available.
      bool completed;
      if (result.action == ErrorReportAction.sendDirect) {
        final email = await ensureSenderEmail(context);
        if (email == null || !context.mounted) return;
        if (data.correction != null && !await draftSourceMatches(target)) {
          throw StateError('The source changed before delivery.');
        }
        if (!context.mounted) return;
        completed = await handleDirectReport(context, build(data, email));
      } else {
        completed = await handleRegularReportAction(
          context,
          result.action,
          data,
          target['bookTitle'] as String,
          target['currentRef'] as String,
          Map<String, String>.from(target['bookDetails'] as Map),
          target['lineNumber'] as int,
          reportContext(data),
          target['libraryVersion'] as String,
          source: source,
          reportId: draft.reportId,
          verifySource: data.correction == null
              ? null
              : () => draftSourceMatches(target),
        );
      }
      if (completed) await draft.complete();
    } catch (error, stack) {
      debugPrint('Book report failed: $error\n$stack');
      if (context.mounted) {
        UiSnack.showError(
          reportText(
            context,
            'הפעולה לא הושלמה. הטיוטה נשמרה וניתן לפתוח אותה בהגדרות.',
          ),
        );
      }
    } finally {
      await draft.close();
    }
  }
}

/// הכתובת עוד לא ידועה לפני סגירת הדיאלוג: בודקים מול האורך המרבי (RFC 5321).
final String _longestEmailPlaceholder = 'a' * 254;

String widgetHash(String bookTitle, String currentRef, String selectedText) {
  final normalized = '$bookTitle|$currentRef|$selectedText';
  return normalized.hashCode.abs().toString();
}

/// טופס דיווח על טעות בספר.
class TabbedReportDialog extends StatefulWidget {
  final String selectedText;
  final String? selectionSource;
  final double fontSize;
  final String bookTitle;
  final int currentLineNumber;
  final String directReportTargetLabel;
  final bool isDictaSource;
  final bool isSefariaSource;
  final TextCorrection? correctionTemplate;
  final BookReportDraftCubit? draft;
  final bool sourceChanged;
  final Future<String?> Function(ReportedErrorData data)? validateBeforeSubmit;

  const TabbedReportDialog({
    super.key,
    required this.selectedText,
    this.selectionSource,
    required this.fontSize,
    required this.bookTitle,
    required this.currentLineNumber,
    required this.directReportTargetLabel,
    this.isDictaSource = false,
    this.isSefariaSource = false,
    this.correctionTemplate,
    this.draft,
    this.sourceChanged = false,
    this.validateBeforeSubmit,
  });

  @override
  State<TabbedReportDialog> createState() => _TabbedReportDialogState();
}

/// הגובה שבו טופס הצעת התיקון נכנס כמעט בלי גלילה.
const double _comfortableReportDialogHeight = 660;

/// טופס בלי עורך תיקון קצר; הגובה קבוע כדי שלא ישתנה בזמן הקלדה.
const double _freeTextReportDialogHeight = 560;

class _TabbedReportDialogState extends State<TabbedReportDialog> {
  bool _leaving = false;
  final ValueNotifier<bool> _regularTabDirty = ValueNotifier(false);

  @override
  void dispose() {
    _regularTabDirty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // חישוב גובה זמין בפועל (ללא שורת המשימות ואזורים מוגנים אחרים)
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom;

    // בחלון צר הדיאלוג במסך מלא (DD-16), והגובה כאן חל רק בחלון רחב.
    final height = widget.correctionTemplate == null
        ? math.min(availableHeight, _freeTextReportDialogHeight)
        // במסך נמוך 70% חותך את הטופס; המסגרת מגבילה לגובה החלון.
        : math.max(
            availableHeight * 0.7,
            math.min(availableHeight, _comfortableReportDialogHeight),
          );

    return AppDialogFrame(
      icon: OtzariaIcons.book_exclamation_24_regular,
      title: context.settingsText('דיווח על טעות בספר'),
      subtitle: widget.bookTitle,
      subtitleMaxLines: 1,
      size: AppDialogSize.large,
      height: height,
      padding: EdgeInsets.zero,
      closeEnabled: !_leaving,
      isDirty: widget.draft == null ? _regularTabDirty : null,
      onDismissRequest: widget.draft == null ? null : _leave,
      child: AbsorbPointer(
        absorbing: _leaving,
        child: ExcludeFocus(
          excluding: _leaving,
          child: _buildRegularReportTab(),
        ),
      ),
    );
  }

  Widget _buildRegularReportTab() {
    return RegularReportTab(
      selectedText: widget.selectedText,
      selectionSource: widget.selectionSource,
      fontSize: widget.fontSize,
      directReportTargetLabel: widget.directReportTargetLabel,
      bookTitle: widget.bookTitle,
      isDictaSource: widget.isDictaSource,
      isSefariaSource: widget.isSefariaSource,
      correctionTemplate: widget.correctionTemplate,
      initialForm: widget.draft?.state.form,
      sourceChanged: widget.sourceChanged,
      onDraftChanged: widget.draft?.updateForm,
      onDiscard: widget.draft == null ? null : _discard,
      validateBeforeSubmit: widget.validateBeforeSubmit,
      onActionSelected: (action, reportData) =>
          _leave(ReportDialogResult(action, reportData)),
      onCancel: _requestLeave,
      // מעבר לתיקון עצמי באתר שומר טיוטה ונסגר בלי שאלת השלכה.
      onHandOff: _leave,
      onDirtyChanged: (dirty) => _regularTabDirty.value = dirty,
    );
  }

  void _requestLeave() {
    if (_leaving) return;
    if (widget.draft == null) {
      Navigator.of(context).maybePop();
    } else {
      _leave();
    }
  }

  Future<void> _leave([ReportDialogResult? result]) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await widget.draft?.flush();
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        UiSnack.showError(
          context.settingsText(
            'שמירת הטיוטה נכשלה. התוכן עדיין בטופס; נסו שוב.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _discard() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await widget.draft?.complete();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        UiSnack.showError(context.settingsText('השלכת הטיוטה נכשלה. נסו שוב.'));
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }
}

/// Regular report tab widget
class RegularReportTab extends StatefulWidget {
  final String selectedText;
  final String? selectionSource;
  final double fontSize;
  final String directReportTargetLabel;
  final String bookTitle;
  final bool isDictaSource;

  /// ספריא מבקשת טקסט שגוי ומתוקן בלבד, ולכן אין לה דיווח חופשי כשיש עורך תיקון.
  final bool isSefariaSource;

  /// השורה הגולמית (ובחירה אם אותרה). null = אין מקור מוסמך — רק דיווח חופשי.
  final TextCorrection? correctionTemplate;

  /// שגיאה חוסמת לפני שמירה/שליחה ישירה; הדיאלוג נשאר פתוח עם מה שהוקלד.
  final Future<String?> Function(ReportedErrorData data)? validateBeforeSubmit;
  final void Function(ErrorReportAction, ReportedErrorData) onActionSelected;
  final VoidCallback onCancel;
  final VoidCallback? onDiscard;
  final Map<String, dynamic>? initialForm;
  final ValueChanged<Map<String, dynamic>>? onDraftChanged;
  final bool sourceChanged;

  /// סוגר את הטופס אחרי שהמשתמש עבר לתקן בעצמו באתר דיקטה, בלי לשאול על
  /// טקסט שהוקלד. null: [onCancel].
  final VoidCallback? onHandOff;

  /// מדווח אם יש בטופס טקסט או הצעת תיקון שיאבדו בסגירה.
  final ValueChanged<bool>? onDirtyChanged;

  const RegularReportTab({
    super.key,
    required this.selectedText,
    this.selectionSource,
    required this.fontSize,
    required this.directReportTargetLabel,
    this.bookTitle = '',
    this.isDictaSource = false,
    this.isSefariaSource = false,
    this.correctionTemplate,
    this.validateBeforeSubmit,
    required this.onActionSelected,
    required this.onCancel,
    this.onDiscard,
    this.initialForm,
    this.onDraftChanged,
    this.sourceChanged = false,
    this.onHandOff,
    this.onDirtyChanged,
  });

  @override
  State<RegularReportTab> createState() => _RegularReportTabState();
}

enum _ReportMode { correction, freeText }

const String _sendShortcut = 'ctrl+enter';

class _RegularReportTabState extends State<RegularReportTab> {
  bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  final TextEditingController _detailsController = TextEditingController();
  final _quoteSelectionNotifier = SelectionListenerNotifier();
  final _quoteSelectionKey = GlobalKey();
  late _ReportMode _mode;
  late String _editorText;
  late ProposalMode _proposalMode;
  TextCorrectionDraft? _draft;
  BookReportSelection? _selection;
  bool _validating = false;
  bool _quoteSelectionReadScheduled = false;

  String get _selectionSource => widget.selectionSource ?? widget.selectedText;
  late final TextDirection _quoteDirection = reportContentDirection(
    _selectionSource,
  );

  bool get _isCorrection => _mode == _ReportMode.correction;

  /// לספריא אין דיווח חופשי, אלא אם השורה עצמה חוסמת הצעת תיקון.
  bool get _offersFreeText {
    final line = widget.correctionTemplate?.originalLine;
    return widget.sourceChanged ||
        !widget.isSefariaSource ||
        line == null ||
        hasLoneSurrogate(line) ||
        line.length > TextCorrection.maxTextLength;
  }

  bool get _hasDetails => _detailsController.text.trim().isNotEmpty;

  bool get _isDirty {
    final draft = _draft;
    final editedProposal =
        _isCorrection &&
        draft != null &&
        draft.correction.proposedText != widget.correctionTemplate?.target;
    return _hasDetails || editedProposal;
  }

  void _reportDirty() => widget.onDirtyChanged?.call(_isDirty);

  bool get _canSubmit {
    if (_validating) return false;
    if (!_isCorrection) return _hasDetails;
    if (widget.sourceChanged) return false;
    final draft = _draft;
    return draft != null && draft.isValid && draft.hasProposal;
  }

  @override
  void initState() {
    super.initState();
    _quoteSelectionNotifier.addListener(_handleQuoteSelectionChanged);
    final form = widget.initialForm;
    _mode = widget.correctionTemplate == null || form?['mode'] == 'freeText'
        ? _ReportMode.freeText
        : _ReportMode.correction;
    _detailsController.text = form?['details'] as String? ?? '';
    _editorText =
        form?['proposedText'] as String? ??
        widget.correctionTemplate?.target ??
        '';
    _proposalMode = form?['proposalMode'] == 'delete'
        ? ProposalMode.delete
        : ProposalMode.replace;
    final start = form?['selectionStart'];
    final end = form?['selectionEnd'];
    if (start is int && end is int) {
      final selection = BookReportSelection(start, end);
      if (selection.isValidFor(_selectionSource)) _selection = selection;
    }
    if (widget.correctionTemplate case final original?) {
      _draft = evaluateCorrectionDraft(
        original: original,
        mode: _proposalMode,
        editedText: _editorText,
      );
    }
  }

  @override
  void dispose() {
    _quoteSelectionNotifier.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submitValidated(
    ErrorReportAction action,
    ReportedErrorData data,
  ) async {
    if (_validating || !_canSubmit) return;
    setState(() => _validating = true);
    try {
      final error = await widget.validateBeforeSubmit?.call(data);
      if (!mounted) return;
      if (error != null) {
        UiSnack.showError(error);
        return;
      }
      widget.onActionSelected(action, data);
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Map<String, dynamic> get _form => {
    'mode': _mode.name,
    'details': _detailsController.text,
    'proposedText': _editorText,
    'proposalMode': _proposalMode.name,
    'selectionStart': _selection?.start,
    'selectionEnd': _selection?.end,
  };

  void _handleQuoteSelectionChanged() {
    if (!mounted || rtlSelectionPriming || _quoteSelectionReadScheduled) return;
    _quoteSelectionReadScheduled = true;
    // Selection fragments notify before both edges finish updating. Read after
    // that synchronous change, before the next input can clear the selection.
    scheduleMicrotask(() {
      _quoteSelectionReadScheduled = false;
      if (!mounted ||
          rtlSelectionPriming ||
          !_quoteSelectionNotifier.registered) {
        return;
      }
      _readQuoteSelection();
    });
  }

  void _readQuoteSelection() {
    final selected = _quoteSelectionNotifier.selection.range;
    if (selected == null) return;
    final range = BookReportSelection(
      math.min(selected.startOffset, selected.endOffset),
      math.max(selected.startOffset, selected.endOffset),
    );
    if (!range.isValidFor(_selectionSource) ||
        (_selection?.start == range.start && _selection?.end == range.end)) {
      return;
    }
    setState(() => _selection = range);
    _draftChanged();
  }

  void _clearQuoteSelection() {
    _quoteSelectionKey.currentContext
        ?.findAncestorStateOfType<SelectableRegionState>()
        ?.clearSelection();
    setState(() => _selection = null);
    _draftChanged();
  }

  void _draftChanged() {
    widget.onDraftChanged?.call(_form);
    _reportDirty();
  }

  void _handleDetailsChanged(String _) {
    if (mounted) {
      setState(() {});
      _draftChanged();
    }
  }

  /// פותח את עמוד התיקון העצמי באתר, ממוקד בקטע שנבחר, וסוגר את טופס הדיווח.
  Future<void> _openDictaSelfEdit() async {
    final opened = await launchDictaEditPage(
      widget.bookTitle,
      selectedText: widget.selectedText,
    );
    if (!mounted) return;
    if (opened) {
      // המשתמש עבר לתקן באתר — אין צורך בטופס הדיווח.
      (widget.onHandOff ?? widget.onCancel)();
    } else {
      UiSnack.showError(
        context.settingsText(ReportMessages.cannotOpenEditPage),
      );
    }
  }

  /// באנר בולט לספרי דיקטה במצב מחובר — תיקון עצמי במקום דיווח.
  Widget _buildDictaSelfEditBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: AppTokens.borderRadiusAll,
      child: InkWell(
        onTap: _openDictaSelfEdit,
        borderRadius: AppTokens.borderRadiusAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                FluentIcons.edit_24_filled,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.settingsText('לחץ כאן על מנת לתקן את הספר בעצמך'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.settingsText(
                        'ספר זה מקורו בדיקטה — התיקון ייפתח באתר אוצריא ישירות בקטע שנבחר. לחילופין, ניתן להמשיך בדיווח רגיל.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.open_24_regular,
                size: AppTokens.iconSM,
                color: colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOfflineMode =
        Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;
    final showDictaSelfEdit = widget.isDictaSource && !isOfflineMode;

    return CallbackShortcuts(
      bindings: {
        for (final activator in ShortcutHelper.activatorsFromShortcut(
          _sendShortcut,
        ))
          activator: () {
            if (_canSubmit) _confirmAndSendDirect();
          },
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.isSefariaSource) ...[
                    Text(
                      context.settingsText(
                        'הדיווח יישלח לספריא. דווחו רק על טעות בטקסט עצמו (כתיב, הקלדה, מילה חסרה או מיותרת) — לא על פתיחת ראשי תיבות, מראי מקומות חסרים או עיצוב.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.correctionTemplate != null && _offersFreeText) ...[
                    AppSegmentedControl<_ReportMode>(
                      options: [
                        SegmentOption(
                          value: _ReportMode.correction,
                          label: context.settingsText('הצעת תיקון'),
                          icon: FluentIcons.text_edit_style_24_regular,
                        ),
                        SegmentOption(
                          value: _ReportMode.freeText,
                          label: context.settingsText('דיווח חופשי'),
                          icon: FluentIcons.comment_24_regular,
                        ),
                      ],
                      currentValue: _mode,
                      onChanged: (mode) {
                        setState(() => _mode = mode);
                        _draftChanged();
                      },
                      expandToFillWidth: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.sourceChanged) ...[
                    Text(
                      context.settingsText(
                        'מקור הספר השתנה מאז שמירת הטיוטה. הצעת התיקון נשמרה לעיון בלבד; אפשר לשלוח דיווח חופשי או להתחיל דיווח חדש מהספר המעודכן.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_isCorrection)
                    TextCorrectionEditor(
                      original: widget.correctionTemplate!,
                      fontSize: widget.fontSize,
                      initialText: _editorText,
                      initialMode: _proposalMode,
                      onChanged: (draft) {
                        setState(() {
                          _draft = draft;
                          _editorText = draft.editedText ?? _editorText;
                          _proposalMode = draft.mode ?? _proposalMode;
                        });
                        _draftChanged();
                      },
                    )
                  else ...[
                    Text(
                      context.settingsText('הטקסט שנבחר'),
                      style: TextStyle(
                        fontSize: AppTokens.fontMD,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceXS),
                    Text(
                      context.settingsText(
                        'סמנו בציטוט את המילים שבהן נמצאת הטעות. המיקום וההקשר יצורפו לדיווח.',
                      ),
                    ),
                    ActionButton.ghost(
                      text: context.settingsText('נקה סימון'),
                      onPressed: _selection == null
                          ? null
                          : _clearQuoteSelection,
                    ),
                    Container(
                      constraints: const BoxConstraints(
                        maxHeight: 150,
                      ),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        // כהה מתיבת הקלט שמתחתיו: הטקסט המצוטט הוא מידע, והתיבה
                        // הבהירה היא המקום להקליד בו.
                        color: _isDark(context)
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLowest
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: AppTokens.borderRadiusAll,
                      ),
                      child: SingleChildScrollView(
                        child: AppSelectionArea(
                          child: SelectionListener(
                            key: _quoteSelectionKey,
                            selectionNotifier: _quoteSelectionNotifier,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (_selection == null)
                                    TextSpan(text: _selectionSource)
                                  else ...[
                                    TextSpan(
                                      text: _selectionSource.substring(
                                        0,
                                        _selection!.start,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _selection!.selectedText(
                                        _selectionSource,
                                      ),
                                      style: TextStyle(
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _selectionSource.substring(
                                        _selection!.end,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              key: const ValueKey('report-location-quote'),
                              textDirection: _quoteDirection,
                              style: TextStyle(
                                fontSize: widget.fontSize,
                                fontFamily: AppFonts.renderFontFamily(
                                  Settings.getValue('key-font-family') ??
                                      AppFonts.defaultFont,
                                ),
                              ),
                              textAlign: TextAlign.start,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (showDictaSelfEdit) ...[
                    const SizedBox(height: 12),
                    _buildDictaSelfEditBanner(),
                  ],
                  const SizedBox(height: 16),
                  RtlTextField(
                    key: const ValueKey('report-details-field'),
                    controller: _detailsController,
                    onChanged: _handleDetailsChanged,
                    minLines: 2,
                    maxLines: 6,
                    autofocus: !_isCorrection,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: _isDark(context)
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest
                          : AppSurfaces.card(context),
                      labelText: context.settingsText(
                        _isCorrection
                            ? 'הסבר לתיקון (רשות)'
                            : 'פירוט הטעות (חובה)',
                      ),
                      hintText: context.settingsText(
                        _isCorrection
                            ? 'מה לא תקין כאן? בלא פירוט לא נוכל לטפל'
                            : 'העתיקו כמה מילים כפי שהן בספר, ושוב כשהן מתוקנות',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _buildActionButtons(),
          ),
        ],
      ),
    );
  }

  ReportedErrorData get _reportData => ReportedErrorData(
    selectedText: !_isCorrection && _selection != null
        ? _selection!.selectedText(_selectionSource)
        : widget.selectedText,
    errorDetails: _detailsController.text.trim(),
    correction: _isCorrection ? _draft?.correction : null,
    selection: !_isCorrection ? _selection : null,
    selectionContext: !_isCorrection
        ? _selection?.contextText(_selectionSource)
        : null,
  );

  bool get _offline =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  Future<void> _confirmAndSendDirect() async {
    final reportData = _reportData;
    if (_offline) {
      await _submitValidated(ErrorReportAction.saveForLater, reportData);
      return;
    }
    final shouldSend = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('אישור שליחת דיווח'),
      content: context.settingsText(
        'לחיצה על שלח דיווח תשלח את השגיאה ישירות ל{target}. יש לבדוק את תקינות הדיווח לפני השליחה.',
        args: {
          'target': reportTargetText(context, widget.directReportTargetLabel),
        },
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שלח דיווח'),
    );
    if (shouldSend == true) {
      await _submitValidated(ErrorReportAction.sendDirect, reportData);
    }
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_offline)
          Text(
            context.settingsText(
              'מצב מנותק: הדיווח יישמר בתור לשליחה או להעברה, לאחר השלמת השדות הנדרשים.',
            ),
          ),
        if (!_canSubmit && !_validating)
          Text(
            context.settingsText(
              _isCorrection
                  ? 'כדי לשלוח או לשמור בתור, נדרשת הצעת תיקון תקינה ששונה מהמקור.'
                  : 'כדי לשלוח או לשמור בתור, יש למלא את פירוט הטעות. אפשר לשמור טיוטה חלקית בכל עת.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.onDiscard != null)
              ActionButton.ghost(
                key: const ValueKey('book-report-discard-draft'),
                text: context.settingsText('השלך טיוטה'),
                onPressed: _validating ? null : widget.onDiscard,
              ),
            ActionButton.neutral(
              key: const ValueKey('book-report-save-draft'),
              text: context.settingsText('שמור טיוטה וצא זמנית'),
              onPressed: _validating ? null : widget.onCancel,
            ),
            if (!_offline)
              ActionButton.neutral(
                text: context.settingsText('שמור לשליחה מאוחרת'),
                icon: FluentIcons.save_24_regular,
                onPressed: _canSubmit
                    ? () => _submitValidated(
                        ErrorReportAction.saveForLater,
                        _reportData,
                      )
                    : null,
              ),
            if (!_offline)
              ActionButton.neutral(
                text: context.settingsText('שלח בדוא"ל'),
                icon: FluentIcons.mail_24_regular,
                onPressed: _canSubmit
                    ? () => _submitValidated(
                        ErrorReportAction.sendEmail,
                        _reportData,
                      )
                    : null,
              ),
            ActionButton.recommended(
              text: context.settingsText(
                _offline ? 'שמור בתור ל{target}' : 'שלח ישירות ל{target}',
                args: {
                  'target': reportTargetText(
                    context,
                    widget.directReportTargetLabel,
                  ),
                },
              ),
              icon: FluentIcons.arrow_upload_24_regular,
              tooltip: ShortcutHelper.formatShortcutForDisplay(_sendShortcut),
              onPressed: _canSubmit ? _confirmAndSendDirect : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// מנסה לפתוח את עמוד התיקון העצמי של ספרי דיקטה באתר, ממוקד בקטע שנבחר
/// (כשנמסר). מחזיר אם הפתיחה הצליחה (כדי שהקורא יוכל להציג הודעת שגיאה
/// כשהדפדפן לא נפתח).
Future<bool> launchDictaEditPage(
  String bookTitle, {
  String selectedText = '',
}) async {
  try {
    final uri = Uri.parse(
      ErrorReportHelper.dictaEditUrlFor(bookTitle, selectedText: selectedText),
    );
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    debugPrint('פתיחת עמוד עריכת דיקטה נכשלה: $e');
  }
  return false;
}
