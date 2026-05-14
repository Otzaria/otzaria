import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/models/phone_report_data.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/services/phone_report_service.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/dialogs/error_report_sender_email_dialog.dart';
import 'package:otzaria/widgets/misc/phone_report_tab.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// נתוני הדיווח שנאספו מתיבת סימון הטקסט + פירוט הטעות שהמשתמש הקליד.
class ReportedErrorData {
  final String selectedText; // הטקסט שסומן ע"י המשתמש
  final String errorDetails; // פירוט הטעות (שדה טקסט נוסף)
  const ReportedErrorData({
    required this.selectedText,
    required this.errorDetails,
  });
}

/// פעולה שנבחרה בדיאלוג האישור.
enum ErrorReportAction {
  cancel,
  sendEmail,
  sendDirect,
  saveForLater,
  phone,
}

/// מחלקה עזר להחזרת תוצאה מהדיאלוג (פעולה + נתונים)
class ReportDialogResult {
  final ErrorReportAction action;
  final dynamic data; // ReportedErrorData OR PhoneReportData

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
      child: SingleChildScrollView(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReportDetailRow(label: 'ספר', value: report.bookTitle),
              _ReportDetailRow(label: 'מיקום', value: report.currentRef),
              _ReportDetailRow(
                label: 'שורה',
                value: report.lineNumber.toString(),
              ),
              _ReportDetailRow(label: 'כתובת זיהוי', value: report.senderEmail),
              _ReportDetailRow(label: 'טקסט שנבחר', value: report.selectedText),
              _ReportDetailRow(
                  label: 'פירוט הטעות', value: report.errorDetails),
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

  const _ReportDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? 'לא נשלח ערך' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 3),
          SelectableText(
            displayValue,
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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

  static List<String> resolveReportContent({
    required TextBookLoaded state,
    List<String>? reportContent,
  }) {
    return reportContent ?? state.content;
  }

  static TextBook resolveReportBook({
    required TextBookLoaded state,
    TextBook? reportBook,
  }) {
    return reportBook ?? state.book;
  }

  static String resolveReportTargetText({
    required List<String> content,
    required String selectedText,
    int? preferredLineNumber,
  }) {
    if (selectedText.trim().isNotEmpty) {
      return sanitizeReportText(selectedText);
    }

    final hasValidPreferredLine = preferredLineNumber != null &&
        preferredLineNumber >= 0 &&
        preferredLineNumber < content.length;
    if (!hasValidPreferredLine) {
      return sanitizeReportText(selectedText);
    }

    return sanitizeReportText(content[preferredLineNumber]);
  }

  static bool isSefariaSourceFolder(String? sourceFolder) {
    final normalizedSource = sourceFolder?.trim().toLowerCase() ?? '';
    return normalizedSource.contains('sefariatootzaria') ||
        normalizedSource.contains('sefaria');
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
    final matches = wordRegex.allMatches(fullText).toList();
    if (matches.isEmpty) return fullText;

    int startWordIndex = 0;
    int endWordIndex = matches.length - 1;

    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      if (selectionStart >= m.start && selectionStart < m.end) {
        startWordIndex = i;
        break;
      }
      if (selectionStart < m.start) {
        startWordIndex = i;
        break;
      }
    }

    for (int i = matches.length - 1; i >= 0; i--) {
      final m = matches[i];
      final selEndMinusOne = selectionEnd - 1;
      if (selEndMinusOne >= m.start && selEndMinusOne < m.end) {
        endWordIndex = i;
        break;
      }
      if (selEndMinusOne > m.end) {
        endWordIndex = i;
        break;
      }
    }

    final ctxStart =
        (startWordIndex - wordsBefore) < 0 ? 0 : (startWordIndex - wordsBefore);
    final ctxEnd = (endWordIndex + wordsAfter) >= matches.length
        ? matches.length - 1
        : (endWordIndex + wordsAfter);

    final from = matches[ctxStart].start;
    final to = matches[ctxEnd].end;
    if (from < 0 || to <= from || to > fullText.length) return fullText;
    return fullText.substring(from, to);
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

    final hasValidPreferredLine = preferredLineNumber != null &&
        preferredLineNumber >= 0 &&
        preferredLineNumber < content.length;

    final int? lineNumber = hasValidPreferredLine ? preferredLineNumber : null;
    final lineStart =
        lineNumber != null ? _lineStartOffset(content, lineNumber) : 0;
    final lineEnd =
        lineNumber != null ? lineStart + content[lineNumber].length : 0;

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
    String? senderEmail,
  ) {
    final senderSection = (senderEmail == null || senderEmail.isEmpty)
        ? ''
        : '\nכתובת ליצירת קשר: $senderEmail\n';

    final detailsSection = (() {
      final base = errorDetails.isEmpty ? '' : '\n$errorDetails';
      final extra = '''
      
    מספר שורה: $lineNumber
    הקשר (4 מילים לפני ואחרי):
    $contextText''';
      return '$base$extra';
    })();

    return '''
שם הספר: $bookTitle
מיקום: $currentRef
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

  /// Launch mailto URL
  static Future<void> launchMail(String email, BuildContext context) async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: email,
    );
    try {
      await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        UiSnack.show('לא ניתן לפתוח את תוכנת הדואר');
      }
    }
  }

  /// Show simple snackbar message
  static void showSimpleSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    UiSnack.show(message);
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
    );

    if (enteredEmail == null || enteredEmail.isEmpty) {
      return null;
    }

    if (!DirectErrorReportService.isValidSenderEmail(enteredEmail)) {
      UiSnack.showError('יש להזין כתובת דוא"ל תקינה.');
      return null;
    }

    await reportService.saveSenderEmail(enteredEmail);
    if (context.mounted) {
      UiSnack.showSuccess('כתובת הזיהוי נשמרה. ניתן לשנות אותה בהגדרות.');
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
  }) {
    final normalizedLibraryVersion =
        libraryVersion.trim().isEmpty ? 'unknown' : libraryVersion.trim();
    return DirectErrorReport(
      id: '${DateTime.now().microsecondsSinceEpoch}-${widgetHash(bookTitle, currentRef, reportData.selectedText)}',
      senderEmail: senderEmail,
      subject: 'דיווח על טעות: $bookTitle',
      bookTitle: bookTitle,
      currentRef: currentRef,
      lineNumber: lineNumber,
      selectedText: reportData.selectedText,
      errorDetails: reportData.errorDetails,
      contextText: contextText,
      filePath: bookDetails['נתיב הקובץ'] ?? '',
      sourceFolder: bookDetails['תיקיית המקור'] ?? '',
      libraryVersion: normalizedLibraryVersion,
      createdAt: DateTime.now(),
    );
  }

  /// Show success dialog for phone report
  static void showPhoneReportSuccessDialog(
    BuildContext context,
    VoidCallback onReportAgain,
  ) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('דיווח נשלח בהצלחה'),
        content: const Text('הדיווח נשלח בהצלחה לצוות אוצריא. תודה על הדיווח!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('סגור'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onReportAgain();
            },
            child: const Text('פתח דוח שגיאות אחר'),
          ),
        ],
      ),
    );
  }

  static Future<void> showDirectReportDetailsDialog(
    BuildContext context, {
    required String title,
    required DirectErrorReport report,
  }) async {
    await showSingleActionDialog(
      context: context,
      title: title,
      confirmText: 'סגור',
      customContent: _DirectReportDetails(report: report),
    );
  }

  /// Handle phone report submission
  static Future<void> handlePhoneReport(
    BuildContext context,
    PhoneReportData reportData,
  ) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final phoneReportService = PhoneReportService();
      final result = await phoneReportService.submitReport(reportData);

      if (!context.mounted) return;

      // Hide loading indicator
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (result.isSuccess) {
        // Success callback will be handled by caller
      } else {
        showSimpleSnack(context, result.message);
      }
    } catch (e) {
      // Hide loading indicator
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      debugPrint('Phone report error: $e');
      showSimpleSnack(context, 'שגיאה בשליחת הדיווח: ${e.toString()}');
    }
  }

  static Future<void> handleDirectReport(
    BuildContext context,
    DirectErrorReport reportData,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final reportService = DirectErrorReportService();
      final result = await reportService.submitReport(reportData);

      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!context.mounted) {
        return;
      }

      if (result.isSent) {
        await showDirectReportDetailsDialog(
          context,
          title: 'הדיווח נשלח בהצלחה',
          report: reportData,
        );
      } else if (result.isQueued) {
        UiSnack.show(result.message);
      } else {
        UiSnack.showError(result.message);
      }
    } catch (e) {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      debugPrint('Direct report error: $e');
      if (context.mounted) {
        UiSnack.showError('שגיאה בשליחת הדיווח: ${e.toString()}');
      }
    }
  }

  /// Handle regular report action (email or save)
  static Future<void> handleRegularReportAction(
    BuildContext context,
    ErrorReportAction action,
    ReportedErrorData reportData,
    String bookTitle,
    String currentRef,
    Map<String, String> bookDetails,
    int lineNumber,
    String contextText,
    String libraryVersion,
  ) async {
    final emailBody = buildEmailBody(
      bookTitle,
      currentRef,
      bookDetails,
      reportData.selectedText,
      reportData.errorDetails,
      lineNumber,
      contextText,
      libraryVersion,
      null,
    );

    if (action == ErrorReportAction.sendEmail) {
      final String? sourceFolder = bookDetails['תיקיית המקור'];
      final normalizedSource = sourceFolder?.toLowerCase() ?? '';

      // קביעת כתובות המייל לפי מקור הספר
      // סדר המפתחות חשוב כדי לחקות את סדר הבדיקות המקורי
      final sourceToEmailMap = {
        'sefariaToOtzaria': 'corrections@sefaria.org',
        'sefaria': 'corrections@sefaria.org',
        'wiki_jewish_books':
            '$_fallbackMail,WikiJewishBooks@gmail.com', // שליחה גם לאוצריא וגם ל-WikiJewishBooks
        'wikiSource':
            '$_fallbackMail,novartza@gmail.com', // שליחה גם לאוצריא וגם ל-wikiSource
        'Pninim':
            '$_fallbackMail,contact@pninim.org', // שליחה גם לאוצריא וגם ל-Pninim
        'Tashma':
            '$_fallbackMail,jewishoffice@gmail.com', // שליחה גם לאוצריא וגם ל-Tashma
        'Ben-Yehuda':
            '$_fallbackMail,editor@benyehuda.org', // שליחה גם לאוצריא וגם ל-Ben-Yehuda
      };

      final emailAddress = sourceFolder == null
          ? _fallbackMail
          : sourceToEmailMap.entries
                  .firstWhereOrNull(
                    (entry) =>
                        normalizedSource.contains(entry.key.toLowerCase()),
                  )
                  ?.value ??
              _fallbackMail;

      final emailUri = Uri(
        scheme: 'mailto',
        path: emailAddress,
        query: encodeQueryParameters(<String, String>{
          'subject': 'דיווח על טעות: $bookTitle',
          'body': emailBody,
        }),
      );

      try {
        if (!await launchUrl(emailUri, mode: LaunchMode.externalApplication)) {
          if (context.mounted) {
            showSimpleSnack(context, 'לא ניתן לפתוח את תוכנת הדואר');
          }
        }
      } catch (_) {
        if (context.mounted) {
          showSimpleSnack(context, 'לא ניתן לפתוח את תוכנת הדואר');
        }
      }
    } else if (action == ErrorReportAction.saveForLater) {
      final senderEmail = await ensureSenderEmail(context);
      if (senderEmail == null) {
        return;
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
      );

      final reportService = DirectErrorReportService();
      await reportService.queueReport(
        directReport,
        queueType: DirectErrorReportQueueType.manual,
      );
      final count = await reportService.getPendingReportsCount();
      if (context.mounted) {
        UiSnack.show(
          'הדיווח נשמר להמשך. יש כרגע $count דיווחים ממתינים בתור, וניתן לנהל את הדיווחים השמורים בהגדרות.',
        );
      }
    }
  }

  /// Show error report dialog for text book
  ///
  /// This is a shared helper to avoid code duplication across different views.
  ///
  /// Parameters:
  /// - [context]: BuildContext for showing the dialog
  /// - [selectedText]: The text selected by the user
  /// - [state]: Current TextBookLoaded state
  /// - [fontSize]: Font size to use in the dialog
  /// - [bookTitle]: Title of the book
  /// - [savedSelectedIndex]: Optional saved selected index (can be int or ValueNotifier of int)
  /// - [reportContent]: Optional content override for reports that target a secondary text
  /// - [reportBook]: Optional book override for reports that target a secondary text
  static Future<void> showErrorReportDialog({
    required BuildContext context,
    required String selectedText,
    required TextBookLoaded state,
    required double fontSize,
    required String bookTitle,
    int? savedSelectedIndex,
    List<String>? reportContent,
    TextBook? reportBook,
  }) async {
    final effectiveContent = resolveReportContent(
      state: state,
      reportContent: reportContent,
    );
    final effectiveBook = resolveReportBook(
      state: state,
      reportBook: reportBook,
    );

    // קבלת מספר השורה הנוכחי
    int? currentLineNumber;

    // אם יש savedSelectedIndex, נשתמש בו
    currentLineNumber = savedSelectedIndex;

    // אם אין savedSelectedIndex, נשתמש ב-state
    currentLineNumber ??= state.selectedIndex ??
        (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0);

    final resolvedSelectedText = resolveReportTargetText(
      content: effectiveContent,
      selectedText: selectedText,
      preferredLineNumber: currentLineNumber,
    );
    final bookDetails =
        await BookDetailsService().getBookDetails(effectiveBook);
    final directReportTargetLabel = resolveDirectReportTargetLabel(
      bookDetails['תיקיית המקור'],
    );

    if (!context.mounted) return;

    // פתיחת הדיאלוג
    final ReportDialogResult? result = await showDialog<ReportDialogResult>(
      context: context,
      builder: (BuildContext dialogContext) {
        return TabbedReportDialog(
          selectedText: resolvedSelectedText,
          fontSize: fontSize,
          bookTitle: bookTitle,
          currentLineNumber: currentLineNumber! + 1, // +1 כי השורות מתחילות מ-1
          state: state,
          directReportTargetLabel: directReportTargetLabel,
        );
      },
    );

    // טיפול בתוצאה
    if (result == null || !context.mounted) return;

    try {
      final libraryVersion = await DataCollectionService().readLibraryVersion();
      if (!context.mounted) return;

      if (result.data is ReportedErrorData) {
        // === דיווח רגיל (מייל או שמירה) ===
        final errorData = result.data as ReportedErrorData;
        final sanitizedErrorData = ReportedErrorData(
          selectedText: sanitizeReportText(errorData.selectedText),
          errorDetails: errorData.errorDetails.trim(),
        );

        final selectionResolution = resolveSelectionContext(
          content: effectiveContent,
          selectedText: sanitizedErrorData.selectedText,
          preferredLineNumber: currentLineNumber,
          wordsBefore: 4,
          wordsAfter: 4,
        );
        final contextText = sanitizeReportText(selectionResolution.contextText);

        // קבלת פרטי הספר
        final currentRef = await refFromIndex(
          currentLineNumber,
          effectiveBook.tableOfContents,
        );
        // ביצוע הפעולה שנבחרה
        if (result.action == ErrorReportAction.sendEmail ||
            result.action == ErrorReportAction.saveForLater) {
          if (!context.mounted) return;
          await handleRegularReportAction(
            context,
            result.action,
            sanitizedErrorData,
            bookTitle,
            currentRef,
            bookDetails,
            currentLineNumber + 1,
            contextText,
            libraryVersion,
          );
        } else if (result.action == ErrorReportAction.sendDirect) {
          if (!context.mounted) return;

          final senderEmail = await ensureSenderEmail(context);
          if (senderEmail == null || !context.mounted) {
            return;
          }

          final directReport = buildDirectReport(
            senderEmail: senderEmail,
            reportData: sanitizedErrorData,
            bookTitle: bookTitle,
            currentRef: currentRef,
            bookDetails: bookDetails,
            lineNumber: currentLineNumber + 1,
            contextText: contextText,
            libraryVersion: libraryVersion,
          );

          await handleDirectReport(context, directReport);
        }
      } else if (result.data is PhoneReportData) {
        // === דיווח טלפוני ===
        if (!context.mounted) return;
        await handlePhoneReport(context, result.data as PhoneReportData);
      }
    } catch (e) {
      debugPrint('Error handling report result: $e');
      if (context.mounted) {
        showSimpleSnack(context, 'שגיאה בטיפול בדיווח: ${e.toString()}');
      }
    }
  }
}

String widgetHash(String bookTitle, String currentRef, String selectedText) {
  final normalized = '$bookTitle|$currentRef|$selectedText';
  return normalized.hashCode.abs().toString();
}

/// Tabbed dialog for error reporting with regular and phone options
class TabbedReportDialog extends StatefulWidget {
  final String selectedText;
  final double fontSize;
  final String bookTitle;
  final int currentLineNumber;
  final TextBookLoaded state;
  final String directReportTargetLabel;

  const TabbedReportDialog({
    super.key,
    required this.selectedText,
    required this.fontSize,
    required this.bookTitle,
    required this.currentLineNumber,
    required this.state,
    required this.directReportTargetLabel,
  });

  @override
  State<TabbedReportDialog> createState() => _TabbedReportDialogState();
}

class _TabbedReportDialogState extends State<TabbedReportDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DataCollectionService _dataService = DataCollectionService();

  // Phone report data
  String _libraryVersion = 'unknown';
  int? _bookId;
  bool _isLoadingData = true;
  List<String> _dataErrors = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadPhoneReportData();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPhoneReportData() async {
    try {
      final availability =
          await _dataService.checkDataAvailability(widget.bookTitle);

      if (mounted) {
        setState(() {
          _libraryVersion = availability['libraryVersion'] ?? 'unknown';
          _bookId = availability['bookId'];
          _dataErrors = List<String>.from(availability['errors'] ?? []);
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading phone report data: $e');
      if (mounted) {
        setState(() {
          _dataErrors = ['שגיאה בטעינת נתוני הדיווח'];
          _isLoadingData = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // חישוב גובה זמין בפועל (ללא שורת המשימות ואזורים מוגנים אחרים)
    final mediaQuery = MediaQuery.of(context);
    final availableHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 400,
          maxWidth: mediaQuery.size.width * 0.6,
          minHeight: 400,
          maxHeight: availableHeight * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'דיווח על טעות בספר',
                style: Theme.of(context).textTheme.headlineSmall,
                textDirection: TextDirection.rtl,
              ),
            ),
            TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              splashBorderRadius: BorderRadius.circular(AppTokens.radiusMD),
              tabs: const [
                Tab(text: 'שליחת דיווח'),
                Tab(text: 'דיווח דרך קו אוצריא'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRegularReportTab(),
                  _buildPhoneReportTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegularReportTab() {
    return RegularReportTab(
      selectedText: widget.selectedText,
      fontSize: widget.fontSize,
      state: widget.state,
      directReportTargetLabel: widget.directReportTargetLabel,
      onActionSelected: (action, reportData) {
        Navigator.of(context).pop(ReportDialogResult(action, reportData));
      },
      onCancel: () {
        Navigator.of(context).pop();
      },
    );
  }

  Widget _buildPhoneReportTab() {
    if (_isLoadingData) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('טוען נתוני דיווח...'),
          ],
        ),
      );
    }

    if (_dataErrors.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'לא ניתן לטעון את נתוני הדיווח:',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ..._dataErrors.map((error) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                  ),
                )),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      );
    }

    return PhoneReportTab(
      selectedText: widget.selectedText,
      fontSize: widget.fontSize,
      libraryVersion: _libraryVersion,
      bookId: _bookId,
      lineNumber: widget.currentLineNumber,
      onSubmit: (selectedText, errorId, moreInfo, lineNumber) async {
        final reportData = PhoneReportData(
          selectedText: selectedText,
          errorId: errorId,
          moreInfo: moreInfo,
          libraryVersion: _libraryVersion,
          bookId: _bookId!,
          lineNumber: lineNumber,
        );
        Navigator.of(context)
            .pop(ReportDialogResult(ErrorReportAction.phone, reportData));
      },
      onCancel: () {
        Navigator.of(context).pop();
      },
    );
  }
}

/// Regular report tab widget
class RegularReportTab extends StatefulWidget {
  final String selectedText;
  final double fontSize;
  final TextBookLoaded state;
  final String directReportTargetLabel;
  final void Function(ErrorReportAction, ReportedErrorData) onActionSelected;
  final VoidCallback onCancel;

  const RegularReportTab({
    super.key,
    required this.selectedText,
    required this.fontSize,
    required this.state,
    required this.directReportTargetLabel,
    required this.onActionSelected,
    required this.onCancel,
  });

  @override
  State<RegularReportTab> createState() => _RegularReportTabState();
}

class _RegularReportTabState extends State<RegularReportTab> {
  final TextEditingController _detailsController = TextEditingController();

  bool get _canSubmit => _detailsController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _detailsController.addListener(_handleDetailsChanged);
  }

  @override
  void dispose() {
    _detailsController.removeListener(_handleDetailsChanged);
    _detailsController.dispose();
    super.dispose();
  }

  void _handleDetailsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('הטקסט שנבחר:'),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(
                    maxHeight: 150,
                  ),
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.selectedText,
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        fontFamily:
                            Settings.getValue('key-font-family') ?? 'candara',
                      ),
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'פירוט הטעות: (חובה לפרט מהי הטעות, בלא פירוט לא נוכל לטפל)',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                RtlTextField(
                  controller: _detailsController,
                  minLines: 3,
                  maxLines: null,
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'כתוב כאן מה לא תקין, הצע תיקון וכו\'',
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _buildActionButtons(),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    // בדיקת מצב אופליין
    final isOfflineMode =
        Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

    final reportData = ReportedErrorData(
      selectedText: widget.selectedText,
      errorDetails: _detailsController.text.trim(),
    );

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          NeutralActionButton(
            text: 'ביטול',
            onPressed: widget.onCancel,
          ),
          if (_canSubmit)
            NeutralActionButton(
              text: 'שמור לשליחה מאוחרת',
              icon: FluentIcons.save_24_regular,
              onPressed: () {
                widget.onActionSelected(
                  ErrorReportAction.saveForLater,
                  reportData,
                );
              },
            ),
          if (!isOfflineMode && _canSubmit)
            NeutralActionButton(
              text: 'שלח בדוא"ל',
              icon: FluentIcons.mail_24_regular,
              onPressed: () {
                widget.onActionSelected(
                  ErrorReportAction.sendEmail,
                  reportData,
                );
              },
            ),
          if (_canSubmit)
            RecommendedActionButton(
              text: isOfflineMode
                  ? 'שמור בתור ל${widget.directReportTargetLabel}'
                  : 'שלח ישירות ל${widget.directReportTargetLabel}',
              icon: FluentIcons.arrow_upload_24_regular,
              onPressed: () async {
                // דיאלוג אישור לפני שליחה ישירה
                final shouldSend = await showTwoActionsDialog(
                  context: context,
                  title: 'אישור שליחת דיווח',
                  content: 'לחיצה על שלח דיווח תשלח את השגיאה ישירות '
                      'ל${widget.directReportTargetLabel}, יש לשים לב '
                      'לתקינות הדיווח לפני השליחה',
                  cancelText: 'ביטול',
                  confirmText: 'שלח דיווח',
                );
                if (shouldSend == true) {
                  widget.onActionSelected(
                    ErrorReportAction.sendDirect,
                    reportData,
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}
