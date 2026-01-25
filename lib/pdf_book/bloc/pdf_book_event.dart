import 'package:equatable/equatable.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/models/links.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/search/models/search_configuration.dart';

/// Base class for PDF book events
sealed class PdfBookEvent extends Equatable {
  const PdfBookEvent();

  @override
  List<Object?> get props => [];
}

// ============ Document Loading Events ============

/// Initialize and load the PDF document
class LoadPdfDocument extends PdfBookEvent {
  const LoadPdfDocument();
}

/// Called when the PDF document is ready in the viewer
class DocumentReady extends PdfBookEvent {
  final PdfDocumentRef documentRef;
  final List<PdfOutlineNode>? outline;
  final int totalPages;

  const DocumentReady({
    required this.documentRef,
    this.outline,
    required this.totalPages,
  });

  @override
  List<Object?> get props => [documentRef, outline?.length, totalPages];
}

/// Called when document loading fails
class DocumentLoadFailed extends PdfBookEvent {
  final String message;

  const DocumentLoadFailed(this.message);

  @override
  List<Object?> get props => [message];
}

/// Load PDF headings and links for commentary
class LoadHeadingsAndLinks extends PdfBookEvent {
  final PdfHeadings? headings;
  final List<Link> links;

  const LoadHeadingsAndLinks({
    this.headings,
    this.links = const [],
  });

  @override
  List<Object?> get props => [headings?.headingsMap.length, links.length];
}

// ============ Navigation Events ============

/// Update the current page number
class UpdatePageNumber extends PdfBookEvent {
  final int pageNumber;
  final String? title;
  final int? textLineNumber;

  const UpdatePageNumber({
    required this.pageNumber,
    this.title,
    this.textLineNumber,
  });

  @override
  List<Object?> get props => [pageNumber, title, textLineNumber];
}

/// Go to a specific page
class GoToPage extends PdfBookEvent {
  final int pageNumber;

  const GoToPage(this.pageNumber);

  @override
  List<Object?> get props => [pageNumber];
}

/// Go to next page
class GoToNextPage extends PdfBookEvent {
  const GoToNextPage();
}

/// Go to previous page
class GoToPreviousPage extends PdfBookEvent {
  const GoToPreviousPage();
}

/// Go to first page
class GoToFirstPage extends PdfBookEvent {
  const GoToFirstPage();
}

/// Go to last page
class GoToLastPage extends PdfBookEvent {
  const GoToLastPage();
}

// ============ Zoom Events ============

/// Update zoom level
class UpdateZoom extends PdfBookEvent {
  final double zoom;

  const UpdateZoom(this.zoom);

  @override
  List<Object?> get props => [zoom];
}

/// Zoom in
class ZoomIn extends PdfBookEvent {
  const ZoomIn();
}

/// Zoom out
class ZoomOut extends PdfBookEvent {
  const ZoomOut();
}

/// Reset zoom to 1.0
class ResetZoom extends PdfBookEvent {
  const ResetZoom();
}

/// Show or hide the zoom bar
class SetShowZoomBar extends PdfBookEvent {
  final bool show;

  const SetShowZoomBar(this.show);

  @override
  List<Object?> get props => [show];
}

// ============ Left Pane Events ============

/// Toggle left pane visibility
class ToggleLeftPane extends PdfBookEvent {
  final bool? show;

  const ToggleLeftPane([this.show]);

  @override
  List<Object?> get props => [show];
}

/// Pin/unpin the left pane
class TogglePinLeftPane extends PdfBookEvent {
  final bool? pin;

  const TogglePinLeftPane([this.pin]);

  @override
  List<Object?> get props => [pin];
}

/// Update left pane tab index
class UpdateLeftPaneTab extends PdfBookEvent {
  final int tabIndex;

  const UpdateLeftPaneTab(this.tabIndex);

  @override
  List<Object?> get props => [tabIndex];
}

/// Update sidebar width
class UpdateSidebarWidth extends PdfBookEvent {
  final double width;

  const UpdateSidebarWidth(this.width);

  @override
  List<Object?> get props => [width];
}

// ============ Right Pane (Commentary) Events ============

/// Toggle right pane visibility
class ToggleRightPane extends PdfBookEvent {
  final bool? show;
  final int? initialTabIndex;

  const ToggleRightPane({this.show, this.initialTabIndex});

  @override
  List<Object?> get props => [show, initialTabIndex];
}

/// Update right pane width
class UpdateRightPaneWidth extends PdfBookEvent {
  final double width;

  const UpdateRightPaneWidth(this.width);

  @override
  List<Object?> get props => [width];
}

// ============ Search Events ============

/// Update search text
class UpdateSearchText extends PdfBookEvent {
  final String searchText;

  const UpdateSearchText(this.searchText);

  @override
  List<Object?> get props => [searchText];
}

/// Update search options
class UpdateSearchOptions extends PdfBookEvent {
  final Map<String, Map<String, bool>>? searchOptions;
  final Map<int, List<String>>? alternativeWords;
  final Map<String, String>? spacingValues;
  final SearchMode? searchMode;

  const UpdateSearchOptions({
    this.searchOptions,
    this.alternativeWords,
    this.spacingValues,
    this.searchMode,
  });

  @override
  List<Object?> get props => [
        searchOptions,
        alternativeWords,
        spacingValues,
        searchMode,
      ];
}

/// Update search results
class UpdateSearchResults extends PdfBookEvent {
  final List<PdfPageTextRange>? matches;
  final int? currentMatchIndex;

  const UpdateSearchResults({
    this.matches,
    this.currentMatchIndex,
  });

  @override
  List<Object?> get props => [matches?.length, currentMatchIndex];
}

/// Start search
class StartSearch extends PdfBookEvent {
  final String query;

  const StartSearch(this.query);

  @override
  List<Object?> get props => [query];
}

/// Clear search results
class ClearSearch extends PdfBookEvent {
  const ClearSearch();
}

// ============ Per-Book Settings Events ============

/// Load per-book settings
class LoadPerBookSettings extends PdfBookEvent {
  const LoadPerBookSettings();
}

/// Save per-book settings
class SavePerBookSettings extends PdfBookEvent {
  const SavePerBookSettings();
}

/// Reset per-book settings
class ResetPerBookSettings extends PdfBookEvent {
  const ResetPerBookSettings();
}
