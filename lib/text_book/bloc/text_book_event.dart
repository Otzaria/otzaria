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
  final bool preserveState; // Whether to preserve current state during reload
  final bool loadCommentators; // Whether to load commentators
  final bool
  forceCloseLeftPane; // Force close left pane (for side-by-side mode)
  // When true and state is already loaded, keep current removeNikud (user's
  // per-book toggle) instead of applying the new value from settings.
  // Use this for font-only reloads where nikud settings did NOT change.
  final bool preserveRemoveNikud;
  // כמו preserveRemoveNikud עבור הסתרת פיסוק, שאין לה הגדרה גלובלית.
  // ברירת המחדל false — `_resetPerBookSettings` סומך עליה כדי לאפס את המצב.
  final bool preserveRemovePunctuation;
  // When true and state is already loaded, keep current continuousReadingMode.
  // ברירת המחדל false — `_resetPerBookSettings` סומך עליה כדי לאפס את המצב.
  // הצרכן היחיד שצריך true הוא ה-listener על שינוי גופן/ניקוד שלא אמור
  // לכבות מצב רצף שהמשתמש בחר.
  final bool preserveContinuousReadingMode;

  const LoadContent({
    required this.fontSize,
    required this.showSplitView,
    required this.removeNikud,
    this.preserveState = false, // Default to false for backward compatibility
    this.loadCommentators = true, // Default to true for backward compatibility
    this.forceCloseLeftPane = false, // Default to false
    this.preserveRemoveNikud =
        false, // Default to false for backward compatibility
    this.preserveRemovePunctuation = false,
    this.preserveContinuousReadingMode = false,
  });

  @override
  List<Object?> get props => [
    fontSize,
    showSplitView,
    removeNikud,
    preserveState,
    loadCommentators,
    forceCloseLeftPane,
    preserveRemoveNikud,
    preserveRemovePunctuation,
    preserveContinuousReadingMode,
  ];
}

/// החלפת מצב קריאה רציף. **רינדור בלבד** — לא משנה content, search, links,
/// selectedIndex, או visibleIndices (שנותרים ברמת שורות מקור).
class ToggleContinuousReadingMode extends TextBookEvent {
  final bool enabled;

  const ToggleContinuousReadingMode(this.enabled);

  @override
  List<Object?> get props => [enabled];
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

  /// אמת = פעולת משתמש (בחירה ידנית). שקר = בחירה אוטומטית של ברירת מחדל,
  /// שמוחלת רק כל עוד המשתמש לא נגע בבחירה ואין מפרשים פעילים.
  final bool isUserAction;

  /// שחזור בחירה שמורה פר-ספר. מוחל כל עוד המשתמש לא בחר ידנית בסשן הנוכחי,
  /// וגובר על בחירה אוטומטית (כגון 'הערות') כי זו בחירה אמיתית קודמת.
  final bool isRestore;

  const UpdateCommentators(
    this.commentators, {
    this.isUserAction = true,
    this.isRestore = false,
  });

  @override
  List<Object?> get props => [commentators, isUserAction, isRestore];
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

  /// Ctrl+לחיצה: מוסיף/מסיר את [index] מהבחירה הקיימת במקום להחליפה.
  final bool additive;

  const UpdateSelectedIndex(this.index, {this.additive = false});

  @override
  List<Object?> get props => [index, additive];
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

/// מחיל highlight מ-deep link על לשונית קיימת (כשהספר כבר פתוח).
class ApplyMarkHighlight extends TextBookEvent {
  final String highlightText;
  final int? permanentHighlightLine;
  final int? scrollToIndex;

  const ApplyMarkHighlight({
    this.highlightText = '',
    this.permanentHighlightLine,
    this.scrollToIndex,
  });

  @override
  List<Object?> get props => [
    highlightText,
    permanentHighlightLine,
    scrollToIndex,
  ];
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

/// טווח שורות בודד עבור [ApplyBookContentRanges].
typedef BookContentRangeChunk = ({
  int startLine,
  int totalLines,
  List<String> lines,
});

/// החלת כמה טווחי תוכן ב-emission יחיד — חימום הרקע צובר chunks ושולח
/// באצווה כדי לא לגרור rebuild של ה-viewport על כל chunk.
class ApplyBookContentRanges extends TextBookEvent {
  final String bookTitle;
  final List<BookContentRangeChunk> ranges;

  const ApplyBookContentRanges({
    required this.bookTitle,
    required this.ranges,
  });

  @override
  List<Object?> get props => [bookTitle, ranges];
}

/// דיווח נראות הטאב (מוצג/ברקע). טאב רקע משחרר את תוכן הספר לחלון סביב
/// המיקום הנוכחי ומשהה את חימום הרקע; טאב שנחשף שוב חוזר ונטען.
class SetTabVisibility extends TextBookEvent {
  final bool visible;

  const SetTabVisibility(this.visible);

  @override
  List<Object?> get props => [visible];
}

class CreateNoteFromToolbar extends TextBookEvent {
  const CreateNoteFromToolbar();

  @override
  List<Object?> get props => [];
}

class UpdateSelectedTextForNote extends TextBookEvent {
  final String? text;
  final int? sectionIndex;
  final int? start;
  final int? end;

  const UpdateSelectedTextForNote({
    required this.text,
    required this.sectionIndex,
    required this.start,
    required this.end,
  });

  @override
  List<Object?> get props => [text, sectionIndex, start, end];
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
  List<Object?> get props => [
    links,
    replaceExisting,
    targetBookTitlesSignature,
  ];
}

class SetLinksLoading extends TextBookEvent {
  final bool isLoading;

  const SetLinksLoading(this.isLoading);

  @override
  List<Object?> get props => [isLoading];
}

/// Event to update available commentators after background loading
class UpdateAvailableCommentators extends TextBookEvent {
  final List<String> availableCommentators;
  final List<dynamic> commentatorGroups;
  final Set<String> rareCommentators;

  const UpdateAvailableCommentators(
    this.availableCommentators,
    this.commentatorGroups, [
    this.rareCommentators = const {},
  ]);

  @override
  List<Object?> get props => [
    availableCommentators,
    commentatorGroups,
    rareCommentators,
  ];
}

class RefreshLinksForCurrentWindow extends TextBookEvent {
  final String reason;
  final String? workspaceId;

  const RefreshLinksForCurrentWindow({
    this.reason = 'manual',
    this.workspaceId,
  });

  @override
  List<Object?> get props => [reason, workspaceId];
}

class OpenFullFileEditor extends TextBookEvent {
  const OpenFullFileEditor();

  @override
  List<Object?> get props => [];
}

/// טוען את כל הקישורים (ללא סינון מפרשים) עבור טווח שורות נתון.
/// משמש לכרטסיית מפרשים עצמאית.
class LoadAllLinksForIndices extends TextBookEvent {
  final List<int> indices;

  const LoadAllLinksForIndices(this.indices);

  @override
  List<Object?> get props => [indices];
}

/// מעדכן את ה-ID וה-heCategories של הספר הנוכחי לאחר העשרה אסינכרונית.
/// נשלח מ-_enrichHeCategoriesInBackground כאשר נמצאו ערכים חדשים.
class UpdateResolvedBookId extends TextBookEvent {
  final String bookTitle;
  final int? resolvedId;
  final String? heCategories;
  final String? author;
  final String? heEra;

  const UpdateResolvedBookId({
    required this.bookTitle,
    this.resolvedId,
    this.heCategories,
    this.author,
    this.heEra,
  });

  @override
  List<Object?> get props => [
    bookTitle,
    resolvedId,
    heCategories,
    author,
    heEra,
  ];
}
