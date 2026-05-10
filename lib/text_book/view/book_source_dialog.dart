import 'package:flutter/material.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:url_launcher/url_launcher.dart';

/// המרת שם המקור לטקסט מתאים עם קישור
/// תומך בשמות המקורות כפי שהם מאוחסנים ב-DB (case-insensitive)
Map<String, String> getSourceDisplayInfo(String source) {
  final normalized = source.trim().toLowerCase();
  
  // השמות המדויקים מה-DB (case-insensitive):
  // Sefaria, Ben-YehudaToOtzaria, DictaToOtzaria, MoreBooks,
  // OnYourWayToOtzaria, OraytaToOtzaria, ToratEmetToOtzaria, Unknown,
  // pninimToOtzaria, sefariaToOtzaria, wikiJewishBooksToOtzaria,
  // wikisourceToOtzaria, tashmaToOtzaria
  
  // ספריא
  if (normalized == 'sefaria' || normalized == 'sefariatootzaria') {
    return {'text': 'ספריא', 'url': 'https://www.sefaria.org/texts'};
  }
  
  // פרוייקט בן-יהודה
  if (normalized == 'ben-yehuda' || normalized == 'ben-yehudatootzaria') {
    return {'text': 'פרוייקט בן-יהודה', 'url': 'https://benyehuda.org/'};
  }
  
  // ספריית דיקטה
  if (normalized == 'dictatootzaria') {
    return {'text': 'ספריית דיקטה', 'url': 'https://library.dicta.org.il/'};
  }
  
  // ובלכתך בדרך
  if (normalized == 'onyourwaytootzaria') {
    return {'text': 'ובלכתך בדרך', 'url': 'https://mobile.tora.ws/'};
  }
  
  // אורייתא
  if (normalized == 'oraytatootzaria') {
    return {
      'text': 'אורייתא',
      'url': 'https://github.com/MosheWagner/Orayta-Books'
    };
  }
  
  // תורת אמת
  if (normalized.contains('toratemet')) {
    return {
      'text': 'תורת אמת',
      'url': 'http://www.toratemetfreeware.com/index.html?downloads;1;'
    };
  }
  
  // תא שמע
  if (normalized == 'tashmatootzaria') {
    return {'text': 'תא שמע', 'url': 'https://tashma.co.il/'};
  }
  
  // פנינים
  if (normalized == 'pninimtootzaria') {
    return {'text': 'פנינים', 'url': 'https://pninim.org/'};
  }
  
  // אוצר הספרים היהודי השיתופי
  if (normalized == 'wikijewishbookstootzaria') {
    return {
      'text': 'אוצר הספרים היהודי השיתופי',
      'url': 'https://wiki.jewishbooks.org.il/'
    };
  }
  
  // ויקיטקסט
  if (normalized == 'wikisourcetootzaria') {
    return {'text': 'ויקיטקסט', 'url': 'https://he.wikisource.org/wiki'};
  }
  
  // ספרים פרטיים או מקורות נוספים
  if (normalized == 'morebooks') {
    return {'text': 'ספרים פרטיים או מקורות נוספים', 'url': ''};
  }
  
  // מקור לא ידוע
  if (normalized == 'unknown') {
    return {'text': 'מקור לא ידוע', 'url': ''};
  }
  
  // אם לא נמצא התאמה מדויקת, מחזירים את המקור המקורי
  return {'text': source, 'url': ''};
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
    final displayText = sourceInfo['text']!;
    final url = sourceInfo['url']!;

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
