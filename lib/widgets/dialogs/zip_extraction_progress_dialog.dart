import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/utils/file/zip_extractor_service.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';

/// ווידג'ט לטיפול בהצגת דיאלוג התקדמות חילוץ ZIP
class ZipExtractionProgressDialog {
  /// מציג דיאלוג התקדמות ומבצע חילוץ ZIP אם נדרש
  ///
  /// [context] - הקונטקסט של המסך
  /// [path] - נתיב התיקייה לבדיקה
  /// [onSuccess] - פונקציה שתופעל בהצלחה (מקבלת את תוצאת החילוץ)
  /// [onError] - פונקציה שתופעל בשגיאה (מקבלת הודעת שגיאה)
  static Future<void> showAndExtract({
    required BuildContext context,
    required String path,
    required Function(ZipExtractionResult) onSuccess,
    required Function(String) onError,
  }) async {
    final progressNotifier = ValueNotifier<double>(0.0);
    final messageNotifier = ValueNotifier<String>('בודק תיקייה...');
    final isExtractingNotifier = ValueNotifier<bool>(false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ZipProgressDialog(
        title: 'מעבד תיקייה',
        isExtracting: isExtractingNotifier,
        progress: progressNotifier,
        message: messageNotifier,
      ),
    );

    try {
      final extractionResult = await ZipExtractorService.checkAndExtractZipIfNeeded(
        path,
        onProgress: (p, m) {
          progressNotifier.value = p;
          messageNotifier.value = m;
          isExtractingNotifier.value = true;
        },
        onAskDeleteZip: () async {
          // סגירת דיאלוג ההתקדמות
          if (context.mounted) {
            Navigator.of(context).pop();
          }

          // שאלת המשתמש
          final shouldDelete = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => const AppDialog.twoActions(
              title: 'מחיקת קובץ דחוס',
              content:
                  'האם למחוק את קובץ ה-ZIP המקורי?\n\n'
                  'הקובץ הדחוס אינו נצרך עבור פעילות התוכנה והוא רק תופס מקום.\n'
                  'מומלץ למחוק אותו.',
              cancelText: 'השאר את הקובץ',
              confirmText: 'מחק את הקובץ',
            ),
          );

          // פתיחה מחדש של דיאלוג ההתקדמות
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => _ZipProgressDialog(
                title: 'משלים...',
                isExtracting: ValueNotifier(false),
                progress: progressNotifier,
                message: ValueNotifier('משלים חילוץ...'),
              ),
            );
          }

          return shouldDelete ?? false;
        },
      );

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (!extractionResult.success) {
        onError(extractionResult.errorMessage ?? 'שגיאה לא ידועה');
      } else {
        onSuccess(extractionResult);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      onError(e.toString());
    } finally {
      progressNotifier.dispose();
      messageNotifier.dispose();
      isExtractingNotifier.dispose();
    }
  }
}

/// דיאלוג ההתקדמות (DD-07, משפחת "תהליך"): ספינר והודעה בזמן הבדיקה, ופס
/// מדוד עם אחוזים בזמן החילוץ. אי אפשר לסגור אותו.
class _ZipProgressDialog extends StatelessWidget {
  const _ZipProgressDialog({
    required this.title,
    required this.isExtracting,
    required this.progress,
    required this.message,
  });

  final String title;
  final ValueListenable<bool> isExtracting;
  final ValueListenable<double> progress;
  final ValueListenable<String> message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageText = ValueListenableBuilder<String>(
      valueListenable: message,
      builder: (context, text, _) =>
          Semantics(liveRegion: true, child: Text(text)),
    );
    return AppDialogFrame(
      title: title,
      icon: AppDialogIcons.progress,
      size: AppDialogSize.small,
      closeEnabled: false,
      showClose: false,
      child: ValueListenableBuilder<bool>(
        valueListenable: isExtracting,
        builder: (context, extracting, _) {
          if (!extracting) {
            return Row(
              children: [
                const LoadingIndicator(size: AppTokens.iconLG, strokeWidth: 3),
                const SizedBox(width: AppTokens.spaceMD),
                Expanded(child: messageText),
              ],
            );
          }
          return ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: value,
                  minHeight: AppTokens.spaceSM,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                const SizedBox(height: AppTokens.spaceMD),
                Row(
                  children: [
                    Expanded(child: messageText),
                    Text(
                      '${(value * 100).toInt()}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
