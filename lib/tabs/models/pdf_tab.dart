import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
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

  final outline = ValueNotifier<List<PdfBookmark>?>(null);

  final document = ValueNotifier<PdfDocument?>(null);

  final TextEditingController searchController = TextEditingController();

  String searchText;

  PdfTextSearchResult? pdfSearchResult;
  int? pdfSearchCurrentMatchIndex;

  /// Flag to track if document is loaded
  bool isDocumentLoaded = false;

  final currentTitle = ValueNotifier<String>("");

  ///a flag that tells if the left pane should be shown
  late final ValueNotifier<bool> showLeftPane;

  ///a flag that tells if the left pane should be pinned on scrolling
  final pinLeftPane = ValueNotifier<bool>(false);

  /// Creates a new instance of [PdfBookTab].
  ///
  /// The [book] parameter represents the PDF book, and the [pageNumber]
  /// parameter represents the current page number.
  PdfBookTab({
    required this.book,
    required this.pageNumber,
    bool openLeftPane = false,
    this.searchText = '',
    this.pdfSearchResult,
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
          (isDocumentLoaded ? pdfViewerController.pageNumber : pageNumber),
      'type': 'PdfBookTab'
    };
  }
}
