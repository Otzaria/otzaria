import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:pdfrx/pdfrx.dart';

/// פרק בחלונית הניווט של PDF: שמו ועמוד ה-PDF שבו הוא מתחיל.
typedef PdfChapterStart = ({String title, int page});

/// עמודי ה-PDF שבהם מתחילים פרקי מהדורת הטקסט של [pdfBook], לפי הסדר.
///
/// ריק כשאין מהדורת טקסט, אין לה פרקים, או שמיפוי העמודים אינו אמין.
Future<List<PdfChapterStart>> loadPdfChapterStarts(
  PdfBook pdfBook, {
  List<PdfOutlineNode>? outline,
}) async {
  final textBook = await companionTextBookOf(pdfBook);
  if (textBook == null) return const [];
  final chapters = await DatabaseLibraryProvider.instance.getChapterStarts(
    textBook,
  );
  if (chapters.isEmpty) return const [];
  final tocLines = [
    for (final anchor in collectTextAnchors(await textBook.tableOfContents))
      anchor.index,
  ]..sort();
  final starts = <PdfChapterStart>[];
  for (final chapter in chapters) {
    final page = await textToPdfPage(
      textBook,
      tocLineAtOrBefore(tocLines, chapter.lineIndex),
      pdfBook: pdfBook,
      outline: outline,
    );
    if (page == null) return const [];
    starts.add((title: chapter.title, page: page));
  }
  return starts;
}

/// כותרת תוכן העניינים (הדף) שבה [line] נמצאת. המיפוי משערך בין כותרות, ופרק
/// שמתחיל אחרי אמצע הדף היה מתעגל לעמוד הבא.
@visibleForTesting
int tocLineAtOrBefore(List<int> sortedTocLines, int line) {
  var result = line;
  for (final tocLine in sortedTocLines) {
    if (tocLine > line) break;
    result = tocLine;
  }
  return result;
}

/// מקבץ את סעיפי [outline] תחת [chapters]: כל סעיף עובר לפרק האחרון שמתחיל
/// בעמוד שלו או לפניו. outline שיש בו כבר היררכיה מוחזר כמו שהוא.
///
/// צומת-שורש יחיד (שם הספר) נשמר, והקיבוץ נעשה בתוכו.
List<PdfOutlineNode> groupPdfOutlineByChapters(
  List<PdfOutlineNode> outline,
  List<PdfChapterStart> chapters,
) {
  if (chapters.isEmpty) return outline;
  for (var i = 1; i < chapters.length; i++) {
    if (chapters[i].page < chapters[i - 1].page) return outline;
  }
  if (outline.length == 1 && outline.single.children.isNotEmpty) {
    final root = outline.single;
    final grouped = _groupFlat(root.children, chapters);
    if (identical(grouped, root.children)) return outline;
    return [
      PdfOutlineNode(title: root.title, dest: root.dest, children: grouped),
    ];
  }
  return _groupFlat(outline, chapters);
}

List<PdfOutlineNode> _groupFlat(
  List<PdfOutlineNode> nodes,
  List<PdfChapterStart> chapters,
) {
  if (nodes.any((n) => n.children.isNotEmpty || n.dest == null)) return nodes;
  for (var i = 1; i < nodes.length; i++) {
    if (nodes[i].dest!.pageNumber < nodes[i - 1].dest!.pageNumber) {
      return nodes;
    }
  }

  final beforeFirstChapter = <PdfOutlineNode>[];
  final members = [for (final _ in chapters) <PdfOutlineNode>[]];
  var chapter = -1;
  for (final node in nodes) {
    final page = node.dest!.pageNumber;
    while (chapter + 1 < chapters.length &&
        chapters[chapter + 1].page <= page) {
      chapter++;
    }
    (chapter < 0 ? beforeFirstChapter : members[chapter]).add(node);
  }

  return [
    ...beforeFirstChapter,
    for (var i = 0; i < chapters.length; i++)
      PdfOutlineNode(
        title: chapters[i].title,
        dest: PdfDest(chapters[i].page, PdfDestCommand.fit, null),
        children: members[i],
      ),
  ];
}
