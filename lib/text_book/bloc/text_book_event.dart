import 'package:equatable/equatable.dart';
import 'package:otzaria/search/models/search_configuration.dart';

sealed class TextBookEvent extends Equatable {
  const TextBookEvent();

  @override
  List<Object?> get props => [];
}

class LoadContent extends TextBookEvent {
  final double fontSize;
  final bool showSplitView;
  final bool removeNikud;
  final bool continuousReadingMode;
  final bool preserveState; // Whether to preserve current state during reload
  final bool loadCommentators; // Whether to load commentators
  final bool
      forceCloseLeftPane; // Force close left pane (for side-by-side mode)
  // When true and state is already loaded, keep current removeNikud (user's
  // per-book toggle) instead of applying the new value from settings.
  // Use this for font-only reloads where nikud settings did NOT change.
  final bool preserveRemoveNikud;

  const LoadContent({
    required this.fontSize,
    required this.showSplitView,
    required this.removeNikud,
    this.continuousReadingMode = false,
    this.preserveState = false, // Default to false for backward compatibility
    this.loadCommentators = true, // Default to true for backward compatibility
    this.forceCloseLeftPane = false, // Default to false
    this.preserveRemoveNikud =
        false, // Default to false for backward compatibility
  });

  @override
  List<Object?> get props => [
        fontSize,
        showSplitView,
        removeNikud,
        continuousReadingMode,
        preserveState,
        loadCommentators,
        forceCloseLeftPane,
        preserveRemoveNikud,
      ];
}

class UpdateTextBookContinuousReadingMode extends TextBookEvent {
  final bool enabled;

  const UpdateTextBookContinuousReadingMode(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class UpdateTextBookShowSubtitles extends TextBookEvent {
  final bool show;

  const UpdateTextBookShowSubtitles(this.show);

  @override
  List<Object?> get props => [show];
}

class UpdateFontSize extends TextBookEvent {
  final double fontSize;

  const UpdateFontSize(this.fontSize);

  @override
  List<Object?> get props => [fontSize];
}

class ToggleLeftPane extends TextBookEvent {
  final bool show;

  const ToggleLeftPane(this.show);

  @override
  List<Object?> get props => [show];
}

class ToggleSplitView extends TextBookEvent {
  final bool show;

  const ToggleSplitView(this.show);

  @override
  List<Object?> get props => [show];
}

class ToggleTzuratHadafView extends TextBookEvent {
  final bool show;

  const ToggleTzuratHadafView(this.show);

  @override
  List<Object?> get props => [show];
}

class TogglePageShapeView extends TextBookEvent {
  final bool show;

  const TogglePageShapeView(this.show);

  @override
  List<Object?> get props => [show];
}

class UpdateCommentators extends TextBookEvent {
  final List<String> commentators;

  const UpdateCommentators(this.commentators);

  @override
  List<Object?> get props => [commentators];
}

class ToggleNikud extends TextBookEvent {
  final bool remove;

  const ToggleNikud(this.remove);

  @override
  List<Object?> get props => [remove];
}

class TogglePunctuation extends TextBookEvent {
  final bool remove;

  const TogglePunctuation(this.remove);

  @override
  List<Object?> get props => [remove];
}

class UpdateVisibleIndecies extends TextBookEvent {
  final List<int> visibleIndecies;

  const UpdateVisibleIndecies(this.visibleIndecies);

  @override
  List<Object?> get props => [visibleIndecies];
}

class UpdateSelectedIndex extends TextBookEvent {
  final int? index;

  const UpdateSelectedIndex(this.index);

  @override
  List<Object?> get props => [index];
}

class HighlightLine extends TextBookEvent {
  final int lineIndex;

  const HighlightLine(this.lineIndex);

  @override
  List<Object?> get props => [lineIndex];
}

class ClearHighlightedLine extends TextBookEvent {
  final int? lineIndex;

  const ClearHighlightedLine([this.lineIndex]);

  @override
  List<Object?> get props => [lineIndex];
}

/// מחיל הדגשה ממוקדת על טאב פתוח ומבקש קפיצה לסעיף [sectionIndex].
/// משמש כש‑deep link מגיע לטאב שכבר פתוח, ולכן ה‑constructor של TextBookTab
/// כבר רץ ולא מקבל את ה‑pinpoint דרך ה‑initial state.
class ApplyPinpointHighlight extends TextBookEvent {
  final int sectionIndex;
  final String text;

  const ApplyPinpointHighlight({
    required this.sectionIndex,
    required this.text,
  });

  @override
  List<Object?> get props => [sectionIndex, text];
}

class TogglePinLeftPane extends TextBookEvent {
  final bool pin;

  const TogglePinLeftPane(this.pin);

  @override
  List<Object?> get props => [pin];
}

class UpdateSearchText extends TextBookEvent {
  final String text;
  final Map<String, Map<String, bool>>? searchOptions;
  final Map<int, List<String>>? alternativeWords;
  final Map<String, String>? spacingValues;
  final SearchMode? searchMode;
  final int? searchDistance;

  const UpdateSearchText(
    this.text, {
    this.searchOptions,
    this.alternativeWords,
    this.spacingValues,
    this.searchMode,
    this.searchDistance,
  });

  @override
  List<Object?> get props => [
        text,
        searchOptions,
        alternativeWords,
        spacingValues,
        searchMode,
        searchDistance,
      ];
}

class ApplyFullBookContent extends TextBookEvent {
  final String bookTitle;
  final List<String> content;

  const ApplyFullBookContent({
    required this.bookTitle,
    required this.content,
  });

  @override
  List<Object?> get props => [bookTitle, content];
}

class ApplyBookContentRange extends TextBookEvent {
  final String bookTitle;
  final int startLine;
  final int totalLines;
  final List<String> lines;

  const ApplyBookContentRange({
    required this.bookTitle,
    required this.startLine,
    required this.totalLines,
    required this.lines,
  });

  @override
  List<Object?> get props => [bookTitle, startLine, totalLines, lines];
}

class CreateNoteFromToolbar extends TextBookEvent {
  const CreateNoteFromToolbar();

  @override
  List<Object?> get props => [];
}

class UpdateSelectedTextForNote extends TextBookEvent {
  final String? text;
  final int? start;
  final int? end;

  const UpdateSelectedTextForNote(this.text, this.start, this.end);

  @override
  List<Object?> get props => [text, start, end];
}

// Editor Events
class OpenEditor extends TextBookEvent {
  final int index;

  const OpenEditor({required this.index});

  @override
  List<Object?> get props => [index];
}

class SaveEditedSection extends TextBookEvent {
  final int index;
  final String sectionId;
  final String markdown;

  const SaveEditedSection({
    required this.index,
    required this.sectionId,
    required this.markdown,
  });

  @override
  List<Object?> get props => [index, sectionId, markdown];
}

class LoadDraftIfAny extends TextBookEvent {
  final int index;
  final String sectionId;

  const LoadDraftIfAny({required this.index, required this.sectionId});

  @override
  List<Object?> get props => [index, sectionId];
}

class DiscardDraft extends TextBookEvent {
  final int index;
  final String sectionId;

  const DiscardDraft({required this.index, required this.sectionId});

  @override
  List<Object?> get props => [index, sectionId];
}

class CloseEditor extends TextBookEvent {
  const CloseEditor();

  @override
  List<Object?> get props => [];
}

class UpdateEditorText extends TextBookEvent {
  final String text;

  const UpdateEditorText(this.text);

  @override
  List<Object?> get props => [text];
}

class AutoSaveDraft extends TextBookEvent {
  final int index;
  final String sectionId;
  final String markdown;

  const AutoSaveDraft({
    required this.index,
    required this.sectionId,
    required this.markdown,
  });

  @override
  List<Object?> get props => [index, sectionId, markdown];
}

/// Event to update links after they're loaded in background
class UpdateLinks extends TextBookEvent {
  final List<dynamic> links;
  final bool replaceExisting;
  final String? targetBookTitlesSignature;

  const UpdateLinks(
    this.links, {
    this.replaceExisting = false,
    this.targetBookTitlesSignature,
  });

  @override
  List<Object?> get props =>
      [links, replaceExisting, targetBookTitlesSignature];
}

/// Event to update available commentators after background loading
class UpdateAvailableCommentators extends TextBookEvent {
  final List<String> availableCommentators;
  final List<dynamic> commentatorGroups;

  const UpdateAvailableCommentators(
      this.availableCommentators, this.commentatorGroups);

  @override
  List<Object?> get props => [availableCommentators, commentatorGroups];
}

class RefreshLinksForCurrentWindow extends TextBookEvent {
  final String reason;

  const RefreshLinksForCurrentWindow({this.reason = 'manual'});

  @override
  List<Object?> get props => [reason];
}

class OpenFullFileEditor extends TextBookEvent {
  const OpenFullFileEditor();

  @override
  List<Object?> get props => [];
}
