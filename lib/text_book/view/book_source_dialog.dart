import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:url_launcher/url_launcher.dart';

// ביטוי רגולרי להסרת תווים מפרידים (מקפים, קווים תחתונים, רווחים)
final _sourceNormalizationRegex = RegExp(r'[-_\s]');

// מיפוי שמות המקורות לטקסט בעברית וקישורים (ללא כפילויות)
const _sourceMappings = {
  'sefaria': (text: 'ספריא', url: 'https://www.sefaria.org/texts'),
  'benyehuda': (text: 'פרוייקט בן י.', url: 'https://benyehuda.org/'),
  'dicta': (text: 'ספריית דיקטה', url: 'https://library.dicta.org.il/'),
  'onyourway': (text: 'ובלכתך בדרך', url: 'https://mobile.tora.ws/'),
  'orayta': (
    text: 'אורייתא',
    url: 'https://github.com/MosheWagner/Orayta-Books',
  ),
  'tashma': (text: 'תא שמע', url: 'https://tashma.co.il/'),
  'pninim': (text: 'פנינים', url: 'https://pninim.org/'),
  'wikisource': (text: 'ויקיטקסט', url: 'https://he.wikisource.org/wiki'),
  'wikijewishbooks': (
    text: 'אוצר הספרים היהודי השיתופי',
    url: 'https://wiki.jewishbooks.org.il/',
  ),
  'nationallibrary': (text: 'יד הרמב"ם', url: 'https://fjms.genizah.org/'),
  'toratemet': (
    text: 'תורת אמת',
    url: 'https://www.toratemetfreeware.com/index.html',
  ),
  'morebooks': (text: 'ספרים פרטיים או מקורות נוספים', url: ''),
  'unknown': (text: 'מקור לא ידוע', url: ''),
};

/// המרת שם המקור לטקסט מתאים עם קישור
/// תומך בשמות המקורות כפי שהם מאוחסנים ב-DB (case-insensitive)
({String text, String url}) getSourceDisplayInfo(String source) {
  // נרמול המחרוזת: הסרת רווחים, המרה לאותיות קטנות והסרת תווים מפרידים
  final normalized = source.toLowerCase().replaceAll(
    _sourceNormalizationRegex,
    '',
  );

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

/// קישור הבית של "תא שמע"
const _tashmaUrl = 'https://tashma.co.il/';

/// בודק האם מקור הספר הוא "תא שמע".
/// הנרמול המאוחד מזהה גם וריאציות כתיב של שם תיקיית המקור.
bool isTashmaSource(String? sourceFolder) {
  final normalized = (sourceFolder ?? '').toLowerCase().replaceAll(
    _sourceNormalizationRegex,
    '',
  );
  return normalized.contains('tashma');
}

/// בודק האם מקור הספר הוא "יד הרמב"ם" של הספרייה הלאומית
/// (המקור National-LibraryToOtzaria ב-DB). מנורמל כמו [isTashmaSource].
bool isNationalLibrarySource(String? sourceFolder) {
  final normalized = (sourceFolder ?? '').toLowerCase().replaceAll(
    _sourceNormalizationRegex,
    '',
  );
  return normalized.contains('nationallibrary');
}

/// בודק האם מקור הספר הוא "אוצר הספרים היהודי השיתופי"
/// (המקור wikiJewishBooksToOtzaria ב-DB). מנורמל כמו [isTashmaSource].
bool isWikiJewishBooksSource(String? sourceFolder) {
  final normalized = (sourceFolder ?? '').toLowerCase().replaceAll(
    _sourceNormalizationRegex,
    '',
  );
  return normalized.contains('wikijewishbooks');
}

/// הצגת דיאלוג אודות הספר
Future<void> showBookSourceDialog(
  BuildContext context,
  TextBookLoaded state,
) {
  return showBookDetailsDialog(context, state.book);
}

/// מציג את כל פרטי הספר הזמינים, גם מחוץ לקורא הטקסט.
Future<void> showBookDetailsDialog(
  BuildContext context,
  Book book,
) {
  return showSingleActionDialog(
    context: context,
    title: 'אודות הספר',
    confirmText: 'סגור',
    customContent: _BookDetailsDialogContent(book: book),
  );
}

class _BookDetailsDialogContent extends StatefulWidget {
  final Book book;

  const _BookDetailsDialogContent({required this.book});

  @override
  State<_BookDetailsDialogContent> createState() =>
      _BookDetailsDialogContentState();
}

class _BookDetailsDialogContentState extends State<_BookDetailsDialogContent> {
  late final Future<BookInformation> _informationFuture;

  @override
  void initState() {
    super.initState();
    _informationFuture = BookDetailsService().getBookInformation(widget.book);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 450,
      child: FutureBuilder<BookInformation>(
        future: _informationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Text('לא ניתן לטעון את מידע הספר.');
          }
          return _buildBookDetailsContent(context, widget.book, snapshot.data!);
        },
      ),
    );
  }
}

Widget _buildBookDetailsContent(
  BuildContext context,
  Book book,
  BookInformation information,
) {
  final bookDetails = information.fileDetails;
  final bookSource = information.source ?? 'לא נמצא מקור';
  final sourceInfo = getSourceDisplayInfo(bookSource);
  final isTashma = isTashmaSource(bookSource);

  return AppSelectionArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailsInfoSection(title: 'שם הספר:', value: book.title),
          if (information.authors.isNotEmpty)
            DetailsInfoSection(
              title: 'מחבר:',
              value: information.authors.join(', '),
            ),
          if (information.generation != null)
            DetailsInfoSection(title: 'דור:', value: information.generation!),
          if (book.heEra != null && book.heEra!.isNotEmpty)
            DetailsInfoSection(title: 'תקופה:', value: book.heEra!),
          if (information.categories != null)
            DetailsInfoSection(
              title: 'קטגוריות:',
              value: information.categories!,
            ),
          if (book.compDateStringHe != null &&
              book.compDateStringHe!.isNotEmpty)
            DetailsInfoSection(
              title: 'תאריך חיבור:',
              value: book.compDateStringHe!,
            ),
          if (book.compPlaceStringHe != null &&
              book.compPlaceStringHe!.isNotEmpty)
            DetailsInfoSection(
              title: 'מקום חיבור:',
              value: book.compPlaceStringHe!,
            ),
          if (information.publicationDates.isNotEmpty)
            DetailsInfoSection(
              title: 'תאריך פרסום:',
              value: information.publicationDates.join(', '),
            ),
          if (information.publicationPlaces.isNotEmpty)
            DetailsInfoSection(
              title: 'מקום פרסום:',
              value: information.publicationPlaces.join(', '),
            ),
          if (information.topics.isNotEmpty)
            DetailsInfoSection(
              title: 'נושאים:',
              value: information.topics.join(', '),
            ),
          if (information.shortDescription != null)
            DetailsInfoSection(
              title: 'תיאור קצר:',
              value: information.shortDescription!,
            ),
          if (information.fullDescription != null)
            DetailsInfoSection(
              title: 'תיאור מורחב:',
              value: information.fullDescription!,
            ),
          const Divider(height: 24),
          const Text(
            'מקור הספר:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (isTashma)
            const _TashmaCopyrightNotice()
          else if (sourceInfo.url.isNotEmpty)
            InkWell(
              onTap: () async {
                final uri = Uri.parse(sourceInfo.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              child: Text(
                sourceInfo.text,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
          else
            Text(sourceInfo.text, style: const TextStyle(fontSize: 14)),
          if (bookDetails['נתיב הקובץ'] != BookDetailsService.bookNotFoundText)
            DetailsInfoSection(
              title: 'נתיב הקובץ:',
              value: bookDetails['נתיב הקובץ']!,
              valueDirection: TextDirection.ltr,
            ),
        ],
      ),
    ),
  );
}

/// נוסח זכויות היוצרים עבור ספרי "תא שמע".
/// המילים "תא שמע" מוצגות כקישור לאתר תא שמע.
class _TashmaCopyrightNotice extends StatefulWidget {
  const _TashmaCopyrightNotice();

  @override
  State<_TashmaCopyrightNotice> createState() => _TashmaCopyrightNoticeState();
}

class _TashmaCopyrightNoticeState extends State<_TashmaCopyrightNotice> {
  late final TapGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = TapGestureRecognizer()
      ..onTap = () async {
        final uri = Uri.parse(_tashmaUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      };
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 14),
        children: [
          const TextSpan(text: 'כל הזכויות שמורות ל'),
          TextSpan(
            text: 'תא שמע',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: _recognizer,
          ),
          const TextSpan(
            text:
                '. השימוש מותר במסגרת תוכנת אוצריא בלבד. '
                'אין לבצע שימוש אחר ללא אישור.',
          ),
        ],
      ),
    );
  }
}
