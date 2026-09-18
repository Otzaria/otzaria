import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:url_launcher/url_launcher.dart';

/// המהדורות של [book] לרשימת הבחירה. לספר אישי — קובצי הגרסאות של קבוצתו.
Future<List<BookVersionInfo>> loadBookVersions(Book book) async {
  final probe = bookVersionsListProbeForTesting;
  if (probe != null) return probe(book);

  if (book.isUserBook) {
    return DatabaseLibraryProvider.instance.getUserBookVersions(book);
  }
  if (!book.isOfficialLibraryBook && !book.source.isAttached) return const [];
  final provider = DatabaseLibraryProvider.instance;
  return [
    ...await provider.getBookVersions(
      book.title,
      book.categoryId ?? -1,
      source: book.source,
    ),
    ...provider.getPersonalVersionsOf(book),
  ];
}

/// מחליף את שאילתת המהדורות בבדיקות widget שאין להן seforim.db.
@visibleForTesting
Future<List<BookVersionInfo>> Function(Book book)?
bookVersionsListProbeForTesting;

/// המהדורות שניתן להציע לפתיחה עבור ספר שנוסחו הפתוח הוא [currentVersionTitle]:
/// הנוסח שכבר פתוח אינו אחת מהן.
List<BookVersionInfo> selectableVersionsFor(
  List<BookVersionInfo> versions,
  String? currentVersionTitle,
) {
  if (currentVersionTitle == null) return versions;
  return versions
      .where(
        (version) =>
            version.separateBook != null ||
            version.versionTitle != currentVersionTitle,
      )
      .toList();
}

/// דיאלוג "גרסאות": מהדורות ספר רשמי (book_version) או קובצי גרסאות של ספר אישי.
/// בחירת מהדורה עם טקסט שמור פותחת את הספר בנוסח אותה מהדורה.
Future<void> showBookVersionsDialog(
  BuildContext context,
  Book book, {
  String? title,
  String? hint,
  void Function(Book target)? onVersionSelected,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => BookVersionsDialog(
      book: book,
      title: title,
      hint: hint,
      onVersionSelected: onVersionSelected,
    ),
  );
}

class BookVersionsDialog extends StatefulWidget {
  final Book book;

  /// כותרת הדיאלוג; ברירת המחדל היא "גרסאות — <שם הספר>".
  final String? title;

  /// טקסט הסבר מעל הרשימה — למה תגרום הבחירה.
  final String? hint;

  /// כשמסופק — מקבל את הספר בנוסח שנבחר במקום פתיחת כרטיסייה חדשה.
  final void Function(Book target)? onVersionSelected;

  const BookVersionsDialog({
    super.key,
    required this.book,
    this.title,
    this.hint,
    this.onVersionSelected,
  });

  @override
  State<BookVersionsDialog> createState() => _BookVersionsDialogState();
}

class _BookVersionsDialogState extends State<BookVersionsDialog> {
  // נטען פעם אחת ב-initState — Future בתוך build היה מריץ את השאילתה מחדש
  // בכל rebuild של הדיאלוג.
  late final Future<List<BookVersionInfo>> _versionsFuture;

  @override
  void initState() {
    super.initState();
    _versionsFuture = loadBookVersions(widget.book);
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.hint;
    return AppCustomContentDialog(
      title: widget.title ?? 'גרסאות — ${widget.book.title}',
      scrollable: false,
      actions: [
        ActionButton.neutral(
          text: 'סגור',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(
            child: FutureBuilder<List<BookVersionInfo>>(
              future: _versionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final versions = snapshot.data ?? const [];
                if (versions.isEmpty) {
                  return const Center(
                    child: Text('לא נמצא מידע על גרסאות לספר זה.'),
                  );
                }
                final book = widget.book;
                final selectable = book.isUserBook
                    ? versions
                          .where(
                            (v) =>
                                v.separateBook?.source != book.source ||
                                v.separateBook?.id != book.id,
                          )
                          .toList()
                    : selectableVersionsFor(
                        versions,
                        book is TextBook ? book.versionTitle : null,
                      );
                if (selectable.isEmpty) {
                  return const Center(
                    child: Text('אין נוסחאות נוספות מלבד הנוסח הפתוח.'),
                  );
                }
                return ListView.separated(
                  itemCount: selectable.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => BookVersionTile(
                    book: widget.book,
                    version: selectable[index],
                    isOnlyVersion:
                        versions.where((v) => v.separateBook == null).length ==
                        1,
                    onSelected: widget.onVersionSelected,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// פותח קישור מהערות גרסה; קישורים יחסיים (כמו '/adin-even-israel') נפתרים
/// מול אתר ספריא — מקור המטא-דאטה.
Future<bool> _openNoteUrl(String url) async {
  final uri = Uri.parse(url);
  final resolved = uri.hasScheme
      ? uri
      : Uri.parse('https://www.sefaria.org').resolveUri(uri);
  if (await canLaunchUrl(resolved)) {
    await launchUrl(resolved);
  }
  return true;
}

/// שורת מהדורה בדיאלוג הגרסאות. ציבורי לצורך בדיקות widget.
class BookVersionTile extends StatelessWidget {
  final Book book;
  final BookVersionInfo version;
  final bool isOnlyVersion;

  /// כשמסופק — מקבל את הספר בנוסח שנבחר במקום פתיחת כרטיסייה חדשה.
  final void Function(Book target)? onSelected;

  const BookVersionTile({
    super.key,
    required this.book,
    required this.version,
    required this.isOnlyVersion,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // מהדורה יחידה בלי טקסט שמור = הנוסח המוצג עצמו (ספר חד-גרסתי).
    // כמה מהדורות בלי טקסט = מאגר ישן שאינו כולל את טקסטי הגרסאות.
    final isDisplayedText = !version.hasContent && isOnlyVersion;
    final openable = version.hasContent || isDisplayedText;

    final subtitleParts = <String>[
      if (isDisplayedText) 'הנוסח המוצג בספרייה',
      if (!version.hasContent && !isOnlyVersion)
        'טקסט הגרסה אינו כלול במאגר הנוכחי',
    ];
    final notes = (version.heVersionNotes ?? version.versionNotes)?.trim();
    final hasNotes = notes?.isNotEmpty == true;

    // בפריט מנוטרל ListTile צובע את האייקון בצבע ה-disabled של ה-theme.
    return ListTile(
      enabled: openable,
      leading: Icon(
        isDisplayedText
            ? OtzariaIcons.otzaria_icon_2_page_24_regular
            : OtzariaIcons.books_stacked_high_24_regular,
        color: openable ? theme.colorScheme.primary : null,
      ),
      title: Text(version.displayTitle),
      subtitle: subtitleParts.isEmpty && !hasNotes
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                // ההערות מגיעות מספריא כ-HTML עם קישורי <a> — רינדור כטקסט
                // גולמי מציג את התגיות מעורבבות בפסקת RTL.
                if (hasNotes)
                  HtmlWidget(
                    notes!,
                    textStyle: theme.textTheme.bodySmall,
                    customStylesBuilder: (element) {
                      final font = theme.textTheme.bodySmall?.fontFamily;
                      final weight = AppFonts.headingFontWeightOverride(
                        element.localName,
                        font,
                      );
                      final size = AppFonts.headingFontSizeOverride(
                        element.localName,
                        font,
                      );
                      final css = <String, String>{
                        'font-weight': ?weight,
                        'font-size': ?size,
                      };
                      return css.isEmpty ? null : css;
                    },
                    onTapUrl: _openNoteUrl,
                  ),
              ],
            ),
      onTap: openable
          ? () {
              Navigator.of(context).pop();
              // הנוסח המוצג נפתח כספר רגיל; מהדורה עם טקסט שמור נפתחת
              // כ-TextBook עם versionTitle, והתוכן נטען מ-version_line.
              // גרסת ספר אישי היא קובץ-ספר נפרד, ונפתחת כמות שהיא.
              final book = this.book;
              final target =
                  version.separateBook ??
                  (isDisplayedText || book is! TextBook
                      ? book
                      : book.copyWith(
                          versionTitle: version.versionTitle,
                          // displayTitle תמיד מאוכלס, ולכן מהדורה שנבחרת אחרי
                          // אחרת אינה יורשת את שם התצוגה שלה.
                          heVersionTitle: version.displayTitle,
                        ));
              final handler = onSelected;
              if (handler != null) {
                handler(target);
                return;
              }
              openBook(context, target, 0, '');
            }
          : null,
    );
  }
}
