import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:pdfrx/pdfrx.dart';

typedef PdfChapterStart = ({String title, int page});

/// עמודי ה-PDF שבהם מתחילים פרקי מהדורת הטקסט של [pdfBook], לפי הסדר.
///
/// ריק כשאין מהדורת טקסט, אין לה פרקים, או שמיפוי העמודים אינו אמין.
Future<List<PdfChapterStart>> loadPdfChapterStarts(
  Library library,
  PdfBook pdfBook,
) async {
  final textBook = library.getCompanionBook(pdfBook, TextBook) as TextBook?;
  if (textBook == null) return const [];
  final chapters = await DatabaseLibraryProvider.instance.getChapterStarts(
    textBook,
  );
  final starts = <PdfChapterStart>[];
  for (final chapter in chapters) {
    final page = await textToPdfPage(
      textBook,
      chapter.lineIndex,
      pdfBook: pdfBook,
    );
    if (page == null) return const [];
    starts.add((title: chapter.title, page: page));
  }
  return starts;
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
