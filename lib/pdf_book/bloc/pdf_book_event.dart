import 'dart:ui' show Offset;

import 'package:equatable/equatable.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

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

  /// רוחב החלון של הקורא, למדיניות החלונית השמאלית; null — ברירת המחדל.
  final double? screenWidth;

  const DocumentReady({
    required this.documentRef,
    this.outline,
    required this.totalPages,
    this.screenWidth,
  });

  @override
  List<Object?> get props => [
    documentRef,
    outline?.length,
    totalPages,
    screenWidth,
  ];
}

/// Called when document loading fails
class DocumentLoadFailed extends PdfBookEvent {
  final String message;

  /// כשאמת — הבלוק יפעיל retry אוטומטי שקט במקום להציג כפתור.
  final bool autoRetry;

  const DocumentLoadFailed(this.message, {this.autoRetry = false});

  @override
  List<Object?> get props => [message, autoRetry];
}

/// Request to retry loading after a previous failure (`PdfBookError`).
class RetryLoad extends PdfBookEvent {
  const RetryLoad();
}

/// The load advanced (document opened, password entered): restart the watchdog.
class LoadProgressed extends PdfBookEvent {
  /// pdfium finished opening the file; only then can a stall be retried.
  final bool documentOpened;

  const LoadProgressed({this.documentOpened = false});

  @override
  List<Object?> get props => [documentOpened];
}

/// The native open is still running past the first timeout: tell the user,
/// keep waiting.
class LoadSlow extends PdfBookEvent {
  const LoadSlow();
}

/// The load waits on the user (password dialog): stop the watchdog until
/// [LoadProgressed].
class LoadWatchdogPaused extends PdfBookEvent {
  const LoadWatchdogPaused();
}

// ============ Navigation Events ============

/// שומר את העוגן שנלכד לפני תחילת קפיצה מפורשת.
class RememberPdfLocation extends PdfBookEvent {
  const RememberPdfLocation(this.location);
  final PdfReadingLocation location;

  @override
  List<Object> get props => [location];
}

/// חוזר לעוגן הקודם; [current] נשמר כיעד של [GoForwardPdfLocation].
class ReturnToPreviousPdfLocation extends PdfBookEvent {
  const ReturnToPreviousPdfLocation([this.current]);
  final PdfReadingLocation? current;

  @override
  List<Object?> get props => [current];
}

/// מתקדם לעוגן שממנו חזרו; [current] נשמר כנקודת חזרה.
class GoForwardPdfLocation extends PdfBookEvent {
  const GoForwardPdfLocation([this.current]);
  final PdfReadingLocation? current;

  @override
  List<Object?> get props => [current];
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

/// Zoom to [zoom] around the document point [center] (fit page / fit width).
class FitZoom extends PdfBookEvent {
  final double zoom;
  final Offset center;

  const FitZoom({required this.zoom, required this.center});

  @override
  List<Object?> get props => [zoom, center];
}

/// Set layout mode directly
class SetLayoutMode extends PdfBookEvent {
  final PdfLayoutMode layoutMode;

  const SetLayoutMode(this.layoutMode);

  @override
  List<Object?> get props => [layoutMode];
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

  const ToggleRightPane({this.show});

  @override
  List<Object?> get props => [show];
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
  final int? searchDistance;
  final SearchMatchPolicy? matchPolicy;
  final InBookSearchOrigin? searchOrigin;
  final Object? searchTemplate;

  const UpdateSearchOptions({
    this.searchOptions,
    this.alternativeWords,
    this.spacingValues,
    this.searchMode,
    this.searchDistance,
    this.matchPolicy,
    this.searchOrigin,
    this.searchTemplate = preserveInBookSearchTemplate,
  });

  @override
  List<Object?> get props => [
    searchOptions,
    alternativeWords,
    spacingValues,
    searchMode,
    searchDistance,
    matchPolicy,
    searchOrigin,
    searchTemplate,
  ];
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

// ============ UI State Events ============

/// Update loading state
class SetLoadingState extends PdfBookEvent {
  final bool isLoading;
  final bool succeeded;

  const SetLoadingState({required this.isLoading, this.succeeded = true});

  @override
  List<Object?> get props => [isLoading, succeeded];
}
