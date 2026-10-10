import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:url_launcher/url_launcher.dart';

// ביטוי רגולרי להסרת תווים מפרידים (מקפים, קווים תחתונים, רווחים)
final _sourceNormalizationRegex = RegExp(r'[-_\s]');

/// נכס הלוגו של "ים החכמה" — לוגו צבעוני, מוצג בצבעיו המקוריים.
const String kYamHaHachmaLogoAsset = 'assets/logo_books/yam_hahachma_logo.png';

// מיפוי שמות המקורות לטקסט בעברית, קישור ולוגו (ללא כפילויות).
// logo ריק = אין לוגו להצגה; לוגו מוצג רק כשהמקור מחייב קרדיט חזותי.
const _sourceMappings = {
  'sefaria': (text: 'ספריא', url: 'https://www.sefaria.org/texts', logo: ''),
  'benyehuda': (text: 'פרוייקט בן י.', url: 'https://benyehuda.org/', logo: ''),
  'dicta': (
    text: 'ספריית דיקטה',
    url: 'https://library.dicta.org.il/',
    logo: '',
  ),
  'onyourway': (text: 'ובלכתך בדרך', url: 'https://mobile.tora.ws/', logo: ''),
  'orayta': (
    text: 'אורייתא',
    url: 'https://github.com/MosheWagner/Orayta-Books',
    logo: '',
  ),
  'tashma': (text: 'תא שמע', url: 'https://tashma.co.il/', logo: ''),
  'pninim': (text: 'פנינים', url: 'https://pninim.org/', logo: ''),
  'wikisource': (
    text: 'ויקיטקסט',
    url: 'https://he.wikisource.org/wiki',
    logo: '',
  ),
  'wikijewishbooks': (
    text: 'אוצר הספרים היהודי השיתופי',
    url: 'https://wiki.jewishbooks.org.il/',
    logo: '',
  ),
  'nationallibrary': (
    text: 'יד הרמב"ם',
    url: 'https://fjms.genizah.org/',
    logo: '',
  ),
  'toratemet': (
    text: 'תורת אמת',
    url: 'https://www.toratemetfreeware.com/index.html',
    logo: '',
  ),
  // רישיון "ים החכמה" מחייב להציג את שם המאגר, הלוגו וקישור אליו
  // בכל מקום שבו מוצג מקור הספר.
  'yamhahachma': (
    text: 'ים החכמה',
    url: 'https://github.com/torahtyh/yam-HaHachma',
    logo: kYamHaHachmaLogoAsset,
  ),
  'morebooks': (
    text: 'ספרים פרטיים או מקורות נוספים',
    url: '',
    logo: '',
  ),
  'ksk': (text: 'קובץ שיטות קמאי', url: '', logo: ''),
  'beitaharonveyisrael': (
    text: 'מכון בית אהרן וישראל',
    url: 'https://machon.co.il/',
    logo: '',
  ),
  'unknown': (text: 'מקור לא ידוע', url: '', logo: ''),
};

/// המרת שם המקור לטקסט מתאים עם קישור
/// תומך בשמות המקורות כפי שהם מאוחסנים ב-DB (case-insensitive)
({String text, String url, String logo}) getSourceDisplayInfo(String source) {
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
  return _sourceMappings[key] ?? (text: source, url: '', logo: '');
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

/// בודק האם מקור הספר הוא "מכון בית אהרן וישראל"
/// (המקור BeitAharonVeYisraelToOtzaria ב-DB). מנורמל כמו [isTashmaSource].
bool isBeitAharonVeYisraelSource(String? sourceFolder) {
  final normalized = (sourceFolder ?? '').toLowerCase().replaceAll(
    _sourceNormalizationRegex,
    '',
  );
  return normalized.contains('beitaharonveyisrael');
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
          DetailsInfoSection(
            icon: OtzariaIcons.booklet_empty_24_regular,
            title: 'שם הספר:',
            value: book.title,
          ),
          if (information.authors.isNotEmpty)
            DetailsInfoSection(
              title: 'מחבר:',
              icon: OtzariaIcons.person_24_regular,
              value: information.authors.join(', '),
            ),
          if (information.generation != null)
            DetailsInfoSection(
              icon: FluentIcons.people_team_24_regular,
              title: 'דור:',
              value: information.generation!,
            ),
          if (book.heEra != null && book.heEra!.isNotEmpty)
            DetailsInfoSection(
              icon: FluentIcons.history_24_regular,
              title: 'תקופה:',
              value: book.heEra!,
            ),
          if (information.categories != null)
            DetailsInfoSection(
              title: 'קטגוריות:',
              icon: FluentIcons.folder_24_regular,
              value: information.categories!,
            ),
          if (book.compDateStringHe != null &&
              book.compDateStringHe!.isNotEmpty)
            DetailsInfoSection(
              title: 'תאריך חיבור:',
              icon: OtzariaIcons.calendar_24_regular,
              value: book.compDateStringHe!,
            ),
          if (book.compPlaceStringHe != null &&
              book.compPlaceStringHe!.isNotEmpty)
            DetailsInfoSection(
              title: 'מקום חיבור:',
              icon: FluentIcons.location_24_regular,
              value: book.compPlaceStringHe!,
            ),
          if (information.publicationDates.isNotEmpty)
            DetailsInfoSection(
              title: 'תאריך פרסום:',
              icon: FluentIcons.print_24_regular,
              value: information.publicationDates.join(', '),
            ),
          if (information.publicationPlaces.isNotEmpty)
            DetailsInfoSection(
              title: 'מקום פרסום:',
              icon: FluentIcons.building_24_regular,
              value: information.publicationPlaces.join(', '),
            ),
          if (information.topics.isNotEmpty)
            DetailsInfoSection(
              title: 'נושאים:',
              icon: FluentIcons.tag_24_regular,
              value: information.topics.join(', '),
            ),
          if (information.shortDescription != null)
            DetailsInfoSection(
              title: 'תיאור קצר:',
              icon: OtzariaIcons.book_information_24_regular,
              value: information.shortDescription!,
            ),
          if (information.fullDescription != null)
            DetailsInfoSection(
              title: 'תיאור מורחב:',
              icon: FluentIcons.document_text_24_regular,
              value: information.fullDescription!,
            ),
          const Divider(height: 24),
          Row(
            children: [
              Icon(
                OtzariaIcons.book_information_24_filled,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              const Text(
                'מקור הספר:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isTashma)
            const _TashmaCopyrightNotice()
          else
            _SourceCredit(info: sourceInfo),
          if (bookDetails['נתיב הקובץ'] != BookDetailsService.bookNotFoundText)
            _buildFilePathSection(bookDetails['נתיב הקובץ']!),
        ],
      ),
    ),
  );
}

/// שם המקור כפי שמוצג למשתמש: לוגו (למקורות שהרישיון שלהם מחייב קרדיט חזותי),
/// שם המאגר, והכל לחיץ כקישור לאתר המקור כשקיים.
class _SourceCredit extends StatelessWidget {
  const _SourceCredit({required this.info});

  final ({String text, String url, String logo}) info;

  Future<void> _openSource() async {
    final uri = Uri.parse(info.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = info.url.isNotEmpty;
    final label = Text(
      info.text,
      style: TextStyle(
        fontSize: 14,
        color: hasUrl ? Theme.of(context).colorScheme.primary : null,
        decoration: hasUrl ? TextDecoration.underline : null,
      ),
    );

    // הלוגו מוצג בצבעיו המקוריים (ללא colorFilter), ולכן נראה זהה
    // במצב בהיר ובמצב כהה ובכל הפלטפורמות.
    final content = info.logo.isEmpty
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                info.logo,
                height: 36,
                filterQuality: FilterQuality.medium,
                semanticLabel: info.text,
              ),
              const SizedBox(width: 8),
              Flexible(child: label),
            ],
          );

    if (!hasUrl) return content;
    return InkWell(onTap: _openSource, child: content);
  }
}

/// נתיב קובץ בספריית אוצריא כפי שמוצג למשתמש: בלי הקידומת `אוצריא/` ובלי
/// הסיומת. מחזיר null לנתיב שאינו בספרייה (למשל נתיב מוחלט של ספר אישי).
String? libraryDisplayPath(String filePath) {
  const libraryPrefix = 'אוצריא/';
  if (!filePath.startsWith(libraryPrefix)) return null;
  final relative = filePath.substring(libraryPrefix.length);
  final lastSlash = relative.lastIndexOf('/');
  final lastDot = relative.lastIndexOf('.');
  return lastDot > lastSlash ? relative.substring(0, lastDot) : relative;
}

Widget _buildFilePathSection(String filePath) {
  final libraryPath = libraryDisplayPath(filePath);
  return DetailsInfoSection(
    title: 'נתיב הקובץ:',
    icon: FluentIcons.folder_open_24_regular,
    value: libraryPath ?? filePath,
    valueDirection: libraryPath == null ? TextDirection.ltr : null,
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
