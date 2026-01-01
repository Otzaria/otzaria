import 'package:flutter/material.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/services/sources_books_service.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:url_launcher/url_launcher.dart';

/// המרת שם המקור לטקסט מתאים עם קישור
Map<String, String> getSourceDisplayInfo(String source) {
  switch (source) {
    case 'Ben-Yehuda':
      return {'text': 'פרוייקט בן-יהודה', 'url': 'https://benyehuda.org/'};
    case 'Dicta':
      return {'text': 'ספריית דיקטה', 'url': 'https://library.dicta.org.il/'};
    case 'OnYourWay':
      return {'text': 'ובלכתך בדרך', 'url': 'https://mobile.tora.ws/'};
    case 'Orayta':
      return {
        'text': 'אורייתא',
        'url': 'https://github.com/MosheWagner/Orayta-Books'
      };
    case 'sefaria':
      return {'text': 'ספריא', 'url': 'https://www.sefaria.org/texts'};
    case 'MoreBooks':
      return {'text': 'ספרים פרטיים או מקורות נוספים', 'url': ''};
    case 'wiki_jewish_books':
      return {
        'text': 'אוצר הספרים היהודי השיתופי',
        'url': 'https://wiki.jewishbooks.org.il/'
      };
    case 'Tashma':
      return {'text': 'תא שמע', 'url': 'https://tashma.co.il/'};
    case 'ToratEmet':
      return {
        'text': 'תורת אמת',
        'url': 'http://www.toratemetfreeware.com/index.html?downloads;1;'
      };
    case 'wikiSource':
      return {'text': 'ויקיטקסט', 'url': 'https://he.wikisource.org/wiki'};
    case 'Pninim':
      return {'text': 'פנינים', 'url': 'https://pninim.org/'};
    default:
      return {'text': source, 'url': ''};
  }
}

/// הצגת דיאלוג אודות הספר
Future<void> showBookSourceDialog(
  BuildContext context,
  TextBookLoaded state,
) async {
  try {
    debugPrint('Opening book source dialog for: "${state.book.title}"');

    // קבלת פרטי הספר מהשירות (נטען כבר בזיכרון)
    final bookDetails = SourcesBooksService().getBookDetails(state.book.title);
    final bookSource = bookDetails['תיקיית המקור'] ?? 'לא נמצא מקור';

    // קבלת מידע התצוגה עבור המקור
    final sourceInfo = getSourceDisplayInfo(bookSource);
    final displayText = sourceInfo['text']!;
    final url = sourceInfo['url']!;

    debugPrint('Book details received: $bookDetails');
    debugPrint('Book source: $bookSource');
    debugPrint('Display text: $displayText, URL: $url');

    if (!context.mounted) return;

    // קבלת מידע נוסף מהספר עצמו
    final book = state.book;

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
                // שם הספר
                _buildInfoSection('שם הספר:', book.title),

                // מחבר
                if (book.author != null && book.author!.isNotEmpty)
                  _buildInfoSection('מחבר:', book.author!),

                // תקופה
                if (book.heEra != null && book.heEra!.isNotEmpty)
                  _buildInfoSection('תקופה:', book.heEra!),

                // קטגוריות
                if (book.heCategories != null && book.heCategories!.isNotEmpty)
                  _buildInfoSection('קטגוריות:', book.heCategories!),

                // תאריך חיבור
                if (book.compDateStringHe != null &&
                    book.compDateStringHe!.isNotEmpty)
                  _buildInfoSection('תאריך חיבור:', book.compDateStringHe!),

                // מקום חיבור
                if (book.compPlaceStringHe != null &&
                    book.compPlaceStringHe!.isNotEmpty)
                  _buildInfoSection('מקום חיבור:', book.compPlaceStringHe!),

                // תאריך פרסום
                if (book.pubDateStringHe != null &&
                    book.pubDateStringHe!.isNotEmpty)
                  _buildInfoSection('תאריך פרסום:', book.pubDateStringHe!),

                // מקום פרסום
                if (book.pubPlaceStringHe != null &&
                    book.pubPlaceStringHe!.isNotEmpty)
                  _buildInfoSection('מקום פרסום:', book.pubPlaceStringHe!),

                // נושאים
                if (book.topics.isNotEmpty)
                  _buildInfoSection('נושאים:', book.topics),

                // תיאור קצר
                if (book.heShortDesc != null && book.heShortDesc!.isNotEmpty)
                  _buildInfoSection('תיאור:', book.heShortDesc!),

                // תיאור מלא
                if (book.heDesc != null && book.heDesc!.isNotEmpty)
                  _buildInfoSection('תיאור מורחב:', book.heDesc!),

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
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.blue,
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
          TextButton(
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

/// בניית סעיף מידע עם כותרת וערך
Widget _buildInfoSection(String title, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    ),
  );
}
