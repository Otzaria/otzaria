import 'dart:io';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/models/phone_report_data.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/services/phone_report_service.dart';
import 'package:otzaria/services/sources_books_service.dart';
import 'package:otzaria/widgets/phone_report_tab.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

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
  saveForLater,
  phone,
}

/// מחלקה עזר להחזרת תוצאה מהדיאלוג (פעולה + נתונים)
class ReportDialogResult {
  final ErrorReportAction action;
  final dynamic data; // ReportedErrorData OR PhoneReportData

  ReportDialogResult(this.action, this.data);
}

/// Helper class for managing error report dialogs and actions
class ErrorReportHelper {
  static const String _reportFileName = 'דיווח שגיאות בספרים.txt';
  static const String _reportSeparator = '==============================';
  static const String _reportSeparator2 = '------------------------------';
  static const String _fallbackMail = 'otzaria.200@gmail.com';

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

  /// Build email body for error report
  static String buildEmailBody(
    String bookTitle,
    String currentRef,
    Map<String, String> bookDetails,
    String selectedText,
    String errorDetails,
    int lineNumber,
    String contextText,
  ) {
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
שם הקובץ: ${bookDetails['שם הקובץ']}
נתיב הקובץ: ${bookDetails['נתיב הקובץ']}
תיקיית המקור: ${bookDetails['תיקיית המקור']}

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

  /// שמירת דיווח לקובץ בתיקייה הראשית של הספרייה (libraryPath).
  static Future<bool> saveReportToFile(String reportContent) async {
    try {
      final libraryPath = Settings.getValue(SettingsRepository.keyLibraryPath);

      if (libraryPath == null || libraryPath.isEmpty) {
        debugPrint('libraryPath not set; cannot save report.');
        return false;
      }

      final filePath = '$libraryPath${Platform.pathSeparator}$_reportFileName';
      final file = File(filePath);

      final exists = await file.exists();

      final sink = file.openWrite(
        mode: exists ? FileMode.append : FileMode.write,
        encoding: utf8,
      );

      // אם זה קובץ חדש, כתוב את השורה הראשונה עם הוראות השליחה
      if (!exists) {
        sink.writeln('יש לשלוח קובץ זה למייל: $_fallbackMail');
        sink.writeln(_reportSeparator2);
        sink.writeln(''); // שורת רווח
      }

      // אם יש כבר תוכן קודם בקובץ קיים -> הוסף מפריד לפני הרשומה החדשה
      if (exists && (await file.length()) > 0) {
        sink.writeln(''); // שורת רווח
        sink.writeln(_reportSeparator);
        sink.writeln(''); // שורת רווח
      }

      sink.write(reportContent);
      await sink.flush();
      await sink.close();
      return true;
    } catch (e) {
      debugPrint('Failed saving report: $e');
      return false;
    }
  }

  /// סופר כמה דיווחים יש בקובץ – לפי המפריד.
  static Future<int> countReportsInFile() async {
    try {
      final libraryPath = Settings.getValue(SettingsRepository.keyLibraryPath);
      if (libraryPath == null || libraryPath.isEmpty) return 0;

      final filePath = '$libraryPath${Platform.pathSeparator}$_reportFileName';
      final file = File(filePath);
      if (!await file.exists()) return 0;

      final content = await file.readAsString(encoding: utf8);
      if (content.trim().isEmpty) return 0;

      final occurrences = _reportSeparator.allMatches(content).length;
      return occurrences + 1;
    } catch (e) {
      debugPrint('countReports error: $e');
      return 0;
    }
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

  /// SnackBar לאחר שמירה: מציג מונה + פעולה לפתיחת דוא"ל (mailto).
  static void showSavedSnack(BuildContext context, int count) {
    if (!context.mounted) return;

    final message =
        "הדיווח נשמר בהצלחה לקובץ '$_reportFileName', הנמצא בתיקייה הראשית של אוצריא.\n"
        "יש לך כבר $count דיווחים!\n"
        "כעת תוכל לשלוח את הקובץ למייל: $_fallbackMail";

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // הכפתור "שלח עכשיו בדוא"ל" מוסתר במצב אופליין
            if (!(Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ??
                false))
              TextButton(
                onPressed: () {
                  launchMail(_fallbackMail, context);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'שלח עכשיו בדוא"ל',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
              child: const Text(
                'סגור',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
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
  ) async {
    final emailBody = buildEmailBody(
      bookTitle,
      currentRef,
      bookDetails,
      reportData.selectedText,
      reportData.errorDetails,
      lineNumber,
      contextText,
    );

    if (action == ErrorReportAction.sendEmail) {
      final String? sourceFolder = bookDetails['תיקיית המקור'];

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
                  .firstWhereOrNull((entry) => sourceFolder.contains(entry.key))
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
      final saved = await saveReportToFile(emailBody);
      if (!saved) {
        if (context.mounted) {
          showSimpleSnack(context, 'שמירת הדיווח נכשלה.');
        }
        return;
      }

      final count = await countReportsInFile();
      if (context.mounted) {
        showSavedSnack(context, count);
      }
    }
  }
}

/// Tabbed dialog for error reporting with regular and phone options
class TabbedReportDialog extends StatefulWidget {
  final String selectedText;
  final double fontSize;
  final String bookTitle;
  final int currentLineNumber;
  final TextBookLoaded state;

  const TabbedReportDialog({
    super.key,
    required this.selectedText,
    required this.fontSize,
    required this.bookTitle,
    required this.currentLineNumber,
    required this.state,
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
  final Function(ErrorReportAction, ReportedErrorData) onActionSelected;
  final VoidCallback onCancel;

  const RegularReportTab({
    super.key,
    required this.selectedText,
    required this.fontSize,
    required this.state,
    required this.onActionSelected,
    required this.onCancel,
  });

  @override
  State<RegularReportTab> createState() => _RegularReportTabState();
}

class _RegularReportTabState extends State<RegularReportTab> {
  final TextEditingController _detailsController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  Future<bool> _isPhoneReportDisabled() async {
    try {
      final bookDetails =
          SourcesBooksService().getBookDetails(widget.state.book.title);
      final sourceFolder = bookDetails['תיקיית המקור'];

      if (sourceFolder != null) {
        return sourceFolder.contains('sefariaToOtzaria') ||
            sourceFolder.contains('wiki_jewish_books');
      }

      return false;
    } catch (e) {
      debugPrint('Error checking phone report availability: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
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
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
          child: _buildActionButtons(),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    // בדיקת מצב אופליין
    final isOfflineMode =
        Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

    return FutureBuilder<bool>(
      future: _isPhoneReportDisabled(),
      builder: (context, snapshot) {
        final isPhoneDisabled = snapshot.data ?? false;
        final canSubmit = widget.selectedText.isNotEmpty;

        return SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('ביטול'),
              ),
              ElevatedButton.icon(
                onPressed: canSubmit
                    ? () {
                        widget.onActionSelected(
                          ErrorReportAction.saveForLater,
                          ReportedErrorData(
                            selectedText: widget.selectedText,
                            errorDetails: _detailsController.text.trim(),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(FluentIcons.save_24_regular, size: 18),
                label: const Text('לא מחובר לרשת? שמור לדיווח מאוחר'),
              ),
              // הכפתור "שלח בדוא"ל" מוסתר במצב אופליין
              if (!isOfflineMode)
                ElevatedButton.icon(
                  onPressed: canSubmit
                      ? () {
                          widget.onActionSelected(
                            ErrorReportAction.sendEmail,
                            ReportedErrorData(
                              selectedText: widget.selectedText,
                              errorDetails: _detailsController.text.trim(),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(FluentIcons.mail_24_regular, size: 18),
                  label: const Text('שלח בדוא"ל'),
                ),
              // הכפתור "שלח ישירות לאוצריא" מוסתר במצב אופליין
              if (!isPhoneDisabled && !isOfflineMode)
                OutlinedButton(
                  onPressed: null,
                  child: const Text('שלח ישירות לאוצריא (לא פעיל זמנית)'),
                ),
            ],
          ),
        );
      },
    );
  }
}
