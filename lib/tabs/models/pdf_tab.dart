import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// Represents a tab with a PDF book.
///
/// The [PdfBookTab] class contains information about the PDF book,
/// such as its [book] and the current [pageNumber].
/// It also contains a [pdfViewerController] to control the viewer.
class PdfBookTab extends OpenedTab {
  /// The PDF book.
  final PdfBook book;

  /// The current page number.
  int pageNumber;

  /// The pdf viewer controller.
  PdfViewerController pdfViewerController = PdfViewerController();

  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);

  final documentRef = ValueNotifier<PdfDocumentRef?>(null);

  final TextEditingController searchController = TextEditingController();

  String searchText;

  List<PdfTextRangeWithFragments>? pdfSearchMatches;
  int? pdfSearchCurrentMatchIndex;

  final currentTitle = ValueNotifier<String>("");

  ///a flag that tells if the left pane should be shown
  late final ValueNotifier<bool> showLeftPane;

  ///a flag that tells if the left pane should be pinned on scrolling
  final pinLeftPane = ValueNotifier<bool>(false);

  /// PDF headings mapping for commentaries and links
  PdfHeadings? pdfHeadings;

  /// Links for the current book
  List<Link> links = [];

  /// Active commentators to show
  List<String> activeCommentators = [];

  /// Current line number in text (based on PDF heading)
  int? currentTextLineNumber;

  /// Creates a new instance of [PdfBookTab].
  ///
  /// The [book] parameter represents the PDF book, and the [pageNumber]
  /// parameter represents the current page number.
  PdfBookTab({
    required this.book,
    required this.pageNumber,
    bool openLeftPane = false,
    this.searchText = '',
    this.pdfSearchMatches,
    this.pdfSearchCurrentMatchIndex,
  }) : super(book.title) {
    showLeftPane = ValueNotifier<bool>(openLeftPane);
    searchController.text = searchText;
    pinLeftPane.value = Settings.getValue<bool>('key-pin-sidebar') ?? false;
  }

  /// Creates a new instance of [PdfBookTab] from a JSON map.
  ///
  /// The JSON map should have 'path' and 'pageNumber' keys.
  factory PdfBookTab.fromJson(Map<String, dynamic> json) {
    final bool shouldOpenLeftPane =
        (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false);
    return PdfBookTab(
        book:
            PdfBook(title: getTitleFromPath(json['path']), path: json['path']),
        pageNumber: json['pageNumber'],
        openLeftPane: shouldOpenLeftPane);
  }

  /// Converts the [PdfBookTab] instance into a JSON map.
  ///
  /// The JSON map contains 'path', 'pageNumber' and 'type' keys.
  @override
  Map<String, dynamic> toJson() {
    return {
      'path': book.path,
      'pageNumber':
          (pdfViewerController.isReady ? pdfViewerController.pageNumber : 1),
      'type': 'PdfBookTab'
    };
  }
}
