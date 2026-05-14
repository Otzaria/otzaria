import 'package:flutter/material.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:url_launcher/url_launcher.dart';

// ביטוי רגולרי להסרת תווים מפרידים (מקפים, קווים תחתונים, רווחים)
final _sourceNormalizationRegex = RegExp(r'[-_\s]');

// מיפוי שמות המקורות לטקסט בעברית וקישורים (ללא כפילויות)
const _sourceMappings = {
  'sefaria': (text: 'ספריא', url: 'https://www.sefaria.org/texts'),
  'benyehuda': (text: 'פרוייקט בן-יהודה', url: 'https://benyehuda.org/'),
  'dicta': (text: 'ספריית דיקטה', url: 'https://library.dicta.org.il/'),
  'onyourway': (text: 'ובלכתך בדרך', url: 'https://mobile.tora.ws/'),
  'orayta': (
    text: 'אורייתא',
    url: 'https://github.com/MosheWagner/Orayta-Books'
  ),
  'tashma': (text: 'תא שמע', url: 'https://tashma.co.il/'),
  'pninim': (text: 'פנינים', url: 'https://pninim.org/'),
  'wikisource': (text: 'ויקיטקסט', url: 'https://he.wikisource.org/wiki'),
  'wikijewishbooks': (
    text: 'אוצר הספרים היהודי השיתופי',
    url: 'https://wiki.jewishbooks.org.il/'
  ),
  'morebooks': (text: 'ספרים פרטיים או מקורות נוספים', url: ''),
  'tootzaria': (text: 'מקורות שהועברו לאוצריא', url: ''),
  'toratemet': (
    text: 'תורת אמת',
    url: 'http://www.toratemetfreeware.com/index.html?downloads;1;'
  ),
  'unknown': (text: 'מקור לא ידוע', url: ''),
};

/// המרת שם המקור לטקסט מתאים עם קישור
/// תומך בשמות המקורות כפי שהם מאוחסנים ב-DB (case-insensitive)
({String text, String url}) getSourceDisplayInfo(String source) {
  // נרמול המחרוזת: הסרת רווחים, המרה לאותיות קטנות והסרת תווים מפרידים
  final normalized =
      source.toLowerCase().replaceAll(_sourceNormalizationRegex, '');

  var key = normalized;

  // טיפול מיוחד ב-ToratEmet (בגלל בעיה עם תווים)
  if (key.contains('toratemet')) {
    key = 'toratemet';
  }
  // טיפול בסיומת 'tootzaria' שנוספה לחלק מהמקורות ב-DB
  else if (key.endsWith('tootzaria') && key != 'tootzaria') {
    key = key.substring(0, key.length - 'tootzaria'.length);
  }

  // חיפוש במיפוי, אם לא נמצא - מחזירים את המקור המקורי
  return _sourceMappings[key] ?? (text: source, url: '');
}

/// הצגת דיאלוג אודות הספר
Future<void> showBookSourceDialog(
  BuildContext context,
  TextBookLoaded state,
) async {
  try {
    debugPrint('Opening book source dialog for: "${state.book.title}"');

    final bookDetails = await BookDetailsService().getBookDetails(state.book);
    final bookSource = bookDetails['תיקיית המקור'] ?? 'לא נמצא מקור';

    // קבלת מידע התצוגה עבור המקור
    final sourceInfo = getSourceDisplayInfo(bookSource);
    final displayText = sourceInfo.text;
    final url = sourceInfo.url;

    debugPrint('Book details received: $bookDetails');
    debugPrint('Book source: $bookSource');
    debugPrint('Display text: $displayText, URL: $url');

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'אודות הספר',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'מושבת זמנית',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 14),
                ),

                const Divider(height: 24),

                // מקור הספר
                const Text(
                  'מקור הספר:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // אם יש URL, הצג כקישור, אחרת הצג כטקסט רגיל
                url.isNotEmpty
                    ? InkWell(
                        onTap: () async {
                          final uri = Uri.parse(url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                        child: Text(
                          displayText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      )
                    : SelectableText(
                        displayText,
                        style: const TextStyle(fontSize: 14),
                      ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  } catch (e) {
    debugPrint('Error showing book source dialog: $e');
    if (context.mounted) {
      UiSnack.showError('שגיאה בטעינת מידע הספר: ${e.toString()}');
    }
  }
}
