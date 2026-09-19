import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// המקורות שעבורם מוצג באנר קרדיט מעל תחילת הספר.
enum BookSourceBannerKind { nationalLibrary, wikiJewishBooks }

/// הטקסט המוצג בראש ספרי "יד הרמב"ם" (הספרייה הלאומית).
const String kNationalLibraryBannerText =
    'באדיבות הספרייה הלאומית לישראל, ואגודת פרידברג לכתבי יד יהודיים\n'
    'כל הזכויות שמורות';

/// הטקסט המוצג בראש ספרי "אוצר הספרים היהודי השיתופי".
const String kWikiJewishBooksBannerText =
    'באדיבות \'אוצר הספרים היהודי השיתופי\'';

const String _wikiJewishBooksPageBaseUrl =
    'https://wiki.jewishbooks.org.il/mediawiki/wiki/';

/// בונה את כתובת דף הוויקי המקורי של הספר, לפי מוסכמת ה-URL של מדיה-ויקי
/// (רווחים הופכים לקו תחתון).
String wikiJewishBooksPageUrl(String bookTitle) =>
    _wikiJewishBooksPageBaseUrl +
    Uri.encodeComponent(bookTitle.replaceAll(' ', '_'));

/// משווה את שדות הזהות שקובעים את מקור הספר. במסלול side-by-side ה-widget
/// אינו ממופתח לפי identity, ולכן מעבר לספר בעל אותה כותרת אך מקור שונה חייב
/// לזהות גם הבדל ב-categoryId/fileType/מקור כדי לרענן את הבאנר.
bool sameSourceIdentity(TextBook a, TextBook b) =>
    a.title == b.title &&
    a.categoryId == b.categoryId &&
    a.fileType == b.fileType &&
    a.source == b.source;

/// טוען מה-DB איזה באנר מקור יש להציג לספר, אם בכלל.
/// רק ספרי הספרייה הרשמית באים ממקורות אלו; לשאר מדלגים על השאילתה.
Future<BookSourceBannerKind?> resolveBookSourceBannerKind(
  TextBook book,
) async {
  if (!book.source.isOfficial) return null;
  final sourceName = await SqliteDataProvider.instance.getBookSourceNameFromDb(
    book.title,
    book.categoryId,
    book.fileType,
  );
  if (isNationalLibrarySource(sourceName)) {
    return BookSourceBannerKind.nationalLibrary;
  }
  if (isWikiJewishBooksSource(sourceName)) {
    return BookSourceBannerKind.wikiJewishBooks;
  }
  return null;
}

/// שורה נגללת המוצגת מעל השורה הראשונה בספרים ממקורות בעלי נוסח קרדיט קבוע.
/// אינה חלק מתוכן הספר עצמו — לכן אינה משפיעה על אינדקסי שורות, קישורים או חיפוש.
class BookSourceBanner extends StatefulWidget {
  const BookSourceBanner({
    super.key,
    required this.kind,
    required this.bookTitle,
    this.fontSize,
  });

  final BookSourceBannerKind kind;
  final String bookTitle;
  final double? fontSize;

  @override
  State<BookSourceBanner> createState() => _BookSourceBannerState();
}

class _BookSourceBannerState extends State<BookSourceBanner> {
  TapGestureRecognizer? _recognizer;

  @override
  void initState() {
    super.initState();
    _setupRecognizer();
  }

  @override
  void didUpdateWidget(covariant BookSourceBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookTitle != widget.bookTitle ||
        oldWidget.kind != widget.kind) {
      _setupRecognizer();
    }
  }

  void _setupRecognizer() {
    _recognizer?.dispose();
    if (widget.kind != BookSourceBannerKind.wikiJewishBooks) {
      _recognizer = null;
      return;
    }
    final uri = Uri.parse(wikiJewishBooksPageUrl(widget.bookTitle));
    _recognizer = TapGestureRecognizer()
      ..onTap = () async {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      };
  }

  @override
  void dispose() {
    _recognizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // גופן קטן ביחס לטקסט הספר — שורת קרדיט, לא חלק מהתוכן.
    final size = widget.fontSize == null ? null : widget.fontSize! * 0.6;
    final textStyle = TextStyle(
      fontSize: size,
      height: 1.3,
      color: cs.onSurfaceVariant,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _buildContent(context, cs, textStyle),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme cs,
    TextStyle textStyle,
  ) {
    if (widget.kind == BookSourceBannerKind.nationalLibrary) {
      return Text(
        kNationalLibraryBannerText,
        textAlign: TextAlign.center,
        style: textStyle,
      );
    }

    final isOfflineMode = context.watch<SettingsBloc>().state.isOfflineMode;
    if (isOfflineMode) {
      return Text(
        kWikiJewishBooksBannerText,
        textAlign: TextAlign.center,
        style: textStyle,
      );
    }
    return Text.rich(
      TextSpan(
        style: textStyle,
        children: [
          const TextSpan(text: '$kWikiJewishBooksBannerText\nאפשר ללחוץ '),
          TextSpan(
            text: 'כאן',
            style: TextStyle(
              color: cs.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: _recognizer,
          ),
          const TextSpan(
            text: ' ולתקן את הדף המקורי או להוסיף הערת שוליים',
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
