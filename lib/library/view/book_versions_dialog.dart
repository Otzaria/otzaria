import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:url_launcher/url_launcher.dart';

/// דיאלוג "גרסאות": רשימת המהדורות (book_version) של ספר מהספרייה הרשמית.
/// בחירת מהדורה עם טקסט שמור פותחת את הספר בנוסח אותה מהדורה.
Future<void> showBookVersionsDialog(BuildContext context, TextBook book) {
  return showDialog<void>(
    context: context,
    builder: (context) => BookVersionsDialog(book: book),
  );
}

class BookVersionsDialog extends StatefulWidget {
  final TextBook book;

  const BookVersionsDialog({super.key, required this.book});

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
    _versionsFuture = DatabaseLibraryProvider.instance.getBookVersions(
      widget.book.title,
      widget.book.categoryId ?? -1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCustomContentDialog(
      title: 'גרסאות — ${widget.book.title}',
      scrollable: false,
      actions: [
        ActionButton.neutral(
          text: 'סגור',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
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
          return ListView.separated(
            itemCount: versions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => BookVersionTile(
              book: widget.book,
              version: versions[index],
              isOnlyVersion: versions.length == 1,
            ),
          );
        },
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
  final TextBook book;
  final BookVersionInfo version;
  final bool isOnlyVersion;

  const BookVersionTile({
    super.key,
    required this.book,
    required this.version,
    required this.isOnlyVersion,
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
            ? FluentIcons.book_open_24_regular
            : FluentIcons.stack_24_regular,
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
                    onTapUrl: _openNoteUrl,
                  ),
              ],
            ),
      onTap: openable
          ? () {
              Navigator.of(context).pop();
              // הנוסח המוצג נפתח כספר רגיל; מהדורה עם טקסט שמור נפתחת
              // כ-TextBook עם versionTitle, והתוכן נטען מ-version_line.
              final target = isDisplayedText
                  ? book
                  : book.copyWith(versionTitle: version.versionTitle);
              openBook(context, target, 0, '');
            }
          : null,
    );
  }
}
