import 'package:equatable/equatable.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

String _searchOptionsSignature(Map<String, Map<String, bool>> options) {
  if (options.isEmpty) return '';

  final keys = options.keys.toList()..sort();
  return keys
      .map((key) {
        final inner = options[key]!;
        final innerKeys = inner.keys.toList()..sort();
        final innerSignature = innerKeys
            .map((innerKey) => '$innerKey=${inner[innerKey]}')
            .join(',');
        return '$key:{$innerSignature}';
      })
      .join('|');
}

String _alternativeWordsSignature(Map<int, List<String>> words) {
  if (words.isEmpty) return '';

  final keys = words.keys.toList()..sort();
  return keys.map((key) => '$key:${words[key]!.join(',')}').join('|');
}

String _spacingValuesSignature(Map<String, String> values) {
  if (values.isEmpty) return '';

  final keys = values.keys.toList()..sort();
  return keys.map((key) => '$key=${values[key]}').join('|');
}

abstract class TextBookState extends Equatable {
  final TextBook book;
  final int index;
  final bool showLeftPane;
  final List<String> commentators;
  const TextBookState(
    this.book,
    this.index,
    this.showLeftPane,
    this.commentators,
  );

  @override
  List<Object?> get props => [];
}

class TextBookInitial extends TextBookState {
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final SearchMatchPolicy matchPolicy;
  final Set<int>? initialSearchResultLines;
  final bool splitedView;
  final bool showPageShapeView;

  /// טקסט להדגשה בלבד — לא מפעיל חלונית חיפוש.
  final String highlightText;

  /// שורה להדגשת רקע קבועה — משמש ל-?mark deep link.
  final int? permanentHighlightLine;

  /// אינדקס הסעיף שבו מותר לבצע הדגשה ממוקדת (deep link). null = אין הדגשה כזו.
  final int? pinpointHighlightIndex;

  /// הטקסט להדגשה ממוקדת בסעיף [pinpointHighlightIndex]. null = אין.
  final String? pinpointHighlightText;

  const TextBookInitial(
    super.book,
    super.index,
    super.showLeftPane,
    super.commentators, [
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.initialSearchResultLines,
    this.splitedView = true,
    this.showPageShapeView = false,
    this.highlightText = '',
    this.permanentHighlightLine,
    this.pinpointHighlightIndex,
    this.pinpointHighlightText,
  ]);

  // קונסטרקטור עם פרמטרים בשם
  const TextBookInitial.named(
    super.book,
    super.index,
    super.showLeftPane,
    super.commentators, {
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.initialSearchResultLines,
    bool? splitedView,
    this.showPageShapeView = false,
    this.highlightText = '',
    this.permanentHighlightLine,
    this.pinpointHighlightIndex,
    this.pinpointHighlightText,
  }) : splitedView = splitedView ?? false;

  @override
  List<Object?> get props => [
    book.title,
    searchText,
    highlightText,
    permanentHighlightLine,
    _searchOptionsSignature(searchOptions),
    _alternativeWordsSignature(alternativeWords),
    _spacingValuesSignature(spacingValues),
    searchMode,
    searchDistance,
    matchPolicy,
    initialSearchResultLines,
    splitedView,
    showPageShapeView,
    pinpointHighlightIndex,
    pinpointHighlightText,
  ];
}

class TextBookLoading extends TextBookState {
  const TextBookLoading(
    super.book,
    super.index,
    super.showLeftPane,
    super.commentators,
  );

  @override
  List<Object?> get props => [book.title];
}

class TextBookError extends TextBookState {
  final String message;

  const TextBookError(
    this.message,
    super.book,
    super.index,
    super.showLeftPane,
    super.commentators,
  );

  @override
  List<Object?> get props => [message, book.title];
}

class TextBookLoaded extends TextBookState {
  final List<String> content;
  final int contentVersion;
  final double fontSize;
  final bool showSplitView;
  final bool showTzuratHadafView;
  final bool showPageShapeView;
  final List<String> activeCommentators;
  final List<CommentatorGroup> commentatorGroups;
  final List<String> availableCommentators;

  /// מפרשים "נדירים" שמוסתרים מרשימת הבחירה הכללית (ספרים גדולים בלבד).
  /// מוצגים ברשימה רק כשהשורה הנוכחית כוללת קישור מהם.
  final Set<String> rareCommentators;
  final List<Link> links;
  final List<Link> visibleLinks;

  /// סוגי הקישורים שנבחרו להצגה בפאנל הקישורים (ב-UPPERCASE).
  /// ריק = הכל מוצג. הסינון עצמו נעשה בשכבת ה-UI.
  final Set<String> selectedLinkTypes;
  final List<TocEntry> tableOfContents;
  final bool isTanach;

  /// הגבלת המו"ל והבאנר של הספר, מהמסד שלו.
  final BookProtection protection;

  /// שכבות תצוגת הטקסט, מהספציפי לכללי: עקיפות זמניות של הכרטיסייה, קובץ
  /// ההגדרות של הספר, והמדיניות הגלובלית כפי שנטענה. ראה [displayProfile].
  final TextDisplayLayer displayOverrides;
  final TextDisplayLayer bookDisplayLayer;
  final TextDisplayPolicy displayPolicy;
  final bool supportsContinuousReadingMode;
  final bool continuousReadingMode;

  /// נגזר מ-[content] + [continuousReadingMode]. ה-bloc מחזיק אותו רק כדי
  /// שהרינדור לא ייאלץ לחשב מחדש בכל build. **אסור** להזליג segmentIndex
  /// אל ה-state הלוגי — selectedIndex/highlightedLine/searchText נשארים
  /// ברמת שורות מקור.
  final List<ReadingSegment> readingSegments;
  final List<int> visibleIndices;

  /// העוגן הראשי של הבחירה — מניע גלילה, highlight, ניווט TOC ודיווח טעות.
  final int? selectedIndex;

  /// כל הקטעים שנבחרו להצגת מפרשים (Ctrl+לחיצה). [selectedIndex] תמיד נכלל בו
  /// כשאינו null. ריק = אין בחירה.
  final Set<int> selectedIndices;
  final bool pinLeftPane;
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final SearchMatchPolicy matchPolicy;

  /// האם ההתאמה הפעילה בספר דורשת מילים שלמות. `false` מדגיש גם בתוך מילה
  /// ("שמים" בתוך "השמים") — חלונית החיפוש שולחת אותו רק במסלול הפשוט, כך
  /// שהדגשת תוצאות המנוע נשארת כשהייתה.
  final bool searchWholeWord;

  /// שורות הספר שחיפוש המנוע החזיר בפועל (0-based), או null כשלא רץ חיפוש
  /// מנוע. ההדגשה במדיניות התאמה שאינה ברירת המחדל מוגבלת לשורות האלה, כדי
  /// שהאפליקציה לא תשחזר בעצמה את החלטת המנוע (טווח פסקה/כותרת, סף מילים).
  final Set<int>? searchResultLines;
  final String? currentTitle;
  final String? selectedTextForNote;
  final int? selectedTextSectionIndex;
  final int? selectedTextStart;
  final int? selectedTextEnd;
  final int? highlightedLine;
  final bool linksLoading;

  /// אינדקס הסעיף שבו מבוצעת הדגשה ממוקדת (deep link). null = אין.
  final int? pinpointHighlightIndex;

  /// הטקסט להדגשה ממוקדת באותו סעיף. null = אין.
  final String? pinpointHighlightText;

  // Editor state
  final bool isEditorOpen;
  final int? editorIndex;
  final String? editorSectionId;
  final String? editorText;
  final bool hasDraft;
  final bool hasLinksFile;

  // Caches
  final Map<int, List<Link>> linksByLine;

  // Controllers
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
  final ScrollOffsetController? scrollOffsetController;

  /// טקסט להדגשה בלבד — לא מפעיל חלונית חיפוש.
  final String highlightText;

  /// שורה להדגשת רקע קבועה (ללא timer ניקוי) — משמש ל-?mark deep link.
  /// מדגיש את רקע השורה בצבע secondaryContainer.
  final int? permanentHighlightLine;

  TextBookLoaded({
    required TextBook book,
    required bool showLeftPane,
    required this.content,
    this.contentVersion = 0,
    required this.fontSize,
    required this.showSplitView,
    this.showTzuratHadafView = false,
    this.showPageShapeView = false,
    required this.activeCommentators,
    required this.commentatorGroups,
    required this.availableCommentators,
    this.rareCommentators = const {},
    required this.links,
    this.visibleLinks = const [],
    this.selectedLinkTypes = const {},
    required this.linksByLine,
    required this.tableOfContents,
    bool? removeNikud,
    bool removePunctuation = false,
    this.isTanach = false,
    this.protection = BookProtection.none,
    bool nikudExemptByTanach = false,
    bool punctuationExemptByTanach = false,
    bool? commentaryRemoveNikudOverride,
    bool? commentaryRemovePunctuationOverride,
    TextDisplayLayer? displayOverrides,
    TextDisplayLayer? bookDisplayLayer,
    TextDisplayPolicy? displayPolicy,
    this.supportsContinuousReadingMode = false,
    this.continuousReadingMode = false,
    this.readingSegments = const [],
    required this.visibleIndices,
    this.selectedIndex,
    this.selectedIndices = const {},
    required this.pinLeftPane,
    required this.searchText,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.searchWholeWord = true,
    this.searchResultLines,
    required this.scrollController,
    required this.positionsListener,
    this.scrollOffsetController,
    this.currentTitle,
    this.selectedTextForNote,
    this.selectedTextSectionIndex,
    this.selectedTextStart,
    this.selectedTextEnd,
    this.highlightedLine,
    this.linksLoading = false,
    this.pinpointHighlightIndex,
    this.pinpointHighlightText,
    this.isEditorOpen = false,
    this.editorIndex,
    this.editorSectionId,
    this.editorText,
    this.hasDraft = false,
    this.hasLinksFile = false,
    this.highlightText = '',
    this.permanentHighlightLine,
  }) : displayOverrides =
           displayOverrides ??
           legacyDisplayOverrides(
             view: showPageShapeView ? TextView.pageShape : TextView.regular,
             commentaryRemoveNikud: commentaryRemoveNikudOverride,
             commentaryRemovePunctuation: commentaryRemovePunctuationOverride,
           ),
       bookDisplayLayer = bookDisplayLayer ?? TextDisplayLayer.empty,
       displayPolicy =
           displayPolicy ??
           legacyDisplayPolicy(
             removeNikud: removeNikud ?? false,
             removePunctuation: removePunctuation,
             nikudExemptByTanach: nikudExemptByTanach,
             punctuationExemptByTanach: punctuationExemptByTanach,
           ),
       super(book, selectedIndex ?? 0, showLeftPane, activeCommentators);

  factory TextBookLoaded.initial({
    required TextBook book,
    required int index,
    required bool showLeftPane,
    required bool splitView,
    List<String>? commentators,
  }) {
    return TextBookLoaded(
      book: book,
      content: const [],
      contentVersion: 0,
      fontSize: 25.0, // Default font size
      showLeftPane: showLeftPane,
      showSplitView: splitView,
      showTzuratHadafView: false,
      showPageShapeView: false,
      activeCommentators: commentators ?? const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      supportsContinuousReadingMode: false,
      continuousReadingMode: false,
      readingSegments: const [],
      pinLeftPane: Settings.getValue<bool>('key-pin-sidebar') ?? false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
      scrollOffsetController: null,
      visibleIndices: [index],
      selectedTextForNote: null,
      selectedTextSectionIndex: null,
      selectedTextStart: null,
      selectedTextEnd: null,
      highlightedLine: null,
      linksLoading: false,
      isEditorOpen: false,
      editorIndex: null,
      editorSectionId: null,
      editorText: null,
      hasDraft: false,
      hasLinksFile: false,
    );
  }

  /// רק שורה שהמנוע החזיר משתתפת בהדגשה במדיניות שאינה סטנדרטית.
  bool lineParticipatesInSearchHighlight(int lineIndex) =>
      searchResultLines?.contains(lineIndex) ?? false;

  /// השורה הסמוכה כשגם היא וגם [lineIndex] שורות תוצאה — ביטוי שנמשך משורה
  /// לשורה מודגש בשתיהן. [next]: השורה הבאה, אחרת הקודמת.
  String? searchResultNeighbour(int lineIndex, {required bool next}) {
    final neighbour = next ? lineIndex + 1 : lineIndex - 1;
    if (neighbour < 0 ||
        neighbour >= content.length ||
        !lineParticipatesInSearchHighlight(lineIndex) ||
        !lineParticipatesInSearchHighlight(neighbour)) {
      return null;
    }
    return content[neighbour];
  }

  /// מצב התצוגה הפעיל — קובע מאיזה חריץ נפתרות ההגדרות.
  TextView get activeView =>
      showPageShapeView ? TextView.pageShape : TextView.regular;

  /// כל השכבות מהספציפי לכללי, בסדר שהרזולבר מצפה לו.
  List<TextDisplayLayer> get displayLayers => [
    displayOverrides,
    bookDisplayLayer,
    ...displayPolicy.layersFor(isTanach: isTanach),
  ];

  /// הפרופיל הפתור ליעד, לתצוגה ([view] ברירת מחדל: הפעילה) ולערוץ.
  TextDisplayProfile displayProfile({
    required TextTarget target,
    TextView? view,
    TextChannel channel = TextChannel.display,
  }) => TextDisplayResolver.resolve(
    slot: TextDisplaySlot(
      target: target,
      view: view ?? activeView,
      channel: channel,
    ),
    layers: displayLayers,
  );

  TextDisplayProfile get bodyDisplayProfile =>
      displayProfile(target: TextTarget.body);

  /// חל על המפרשים, הקישורים והתצוגות המקדימות.
  TextDisplayProfile get commentaryDisplayProfile =>
      displayProfile(target: TextTarget.commentary);

  bool get removeNikud => bodyDisplayProfile.removeNikud;
  bool get removePunctuation => bodyDisplayProfile.removePunctuation;
  bool get commentaryRemoveNikud => commentaryDisplayProfile.removeNikud;
  bool get commentaryRemovePunctuation =>
      commentaryDisplayProfile.removePunctuation;

  TextDisplaySlot get _bodySlot => TextDisplaySlot(
    target: TextTarget.body,
    view: activeView,
    channel: TextChannel.display,
  );
  TextDisplaySlot get _commentarySlot => TextDisplaySlot(
    target: TextTarget.commentary,
    view: activeView,
    channel: TextChannel.display,
  );

  /// עקיפה זמנית של המפרשים בכרטיסייה, אם קיימת.
  bool? get commentaryRemoveNikudOverride =>
      removeFlagOf(displayOverrides.patchFor(_commentarySlot).nikud);
  bool? get commentaryRemovePunctuationOverride =>
      removeFlagOf(displayOverrides.patchFor(_commentarySlot).punctuation);

  /// האם הספר קיבל ניקוד רק בזכות היותו תנ"ך: המדיניות מנקדת את גופו אך לא
  /// את מפרשיו.
  bool get nikudExemptByTanach =>
      !displayPolicy.resolve(_bodySlot, isTanach: isTanach).removeNikud &&
      displayPolicy.resolve(_commentarySlot, isTanach: isTanach).removeNikud;

  bool get punctuationExemptByTanach =>
      !displayPolicy.resolve(_bodySlot, isTanach: isTanach).removePunctuation &&
      displayPolicy
          .resolve(_commentarySlot, isTanach: isTanach)
          .removePunctuation;

  TextBookLoaded copyWith({
    TextBook? book,
    List<String>? content,
    int? contentVersion,
    double? fontSize,
    bool? showLeftPane,
    bool? showSplitView,
    bool? showTzuratHadafView,
    bool? showPageShapeView,
    List<String>? activeCommentators,
    List<CommentatorGroup>? commentatorGroups,
    List<String>? availableCommentators,
    Set<String>? rareCommentators,
    List<Link>? links,
    List<Link>? visibleLinks,
    Set<String>? selectedLinkTypes,
    Map<int, List<Link>>? linksByLine,
    List<TocEntry>? tableOfContents,
    bool? removeNikud,
    bool? removePunctuation,
    bool? isTanach,
    BookProtection? protection,
    bool? nikudExemptByTanach,
    bool? punctuationExemptByTanach,
    bool? commentaryRemoveNikudOverride,
    bool? commentaryRemovePunctuationOverride,
    bool clearCommentaryRemoveNikudOverride = false,
    bool clearCommentaryRemovePunctuationOverride = false,
    TextDisplayLayer? displayOverrides,
    TextDisplayLayer? bookDisplayLayer,
    TextDisplayPolicy? displayPolicy,
    bool? supportsContinuousReadingMode,
    bool? continuousReadingMode,
    List<ReadingSegment>? readingSegments,
    int? selectedIndex,
    bool clearSelectedIndex = false,
    Set<int>? selectedIndices,
    bool clearSelectedIndices = false,
    List<int>? visibleIndices,
    bool? pinLeftPane,
    String? searchText,
    Map<String, Map<String, bool>>? searchOptions,
    Map<int, List<String>>? alternativeWords,
    Map<String, String>? spacingValues,
    SearchMode? searchMode,
    int? searchDistance,
    SearchMatchPolicy? matchPolicy,
    bool? searchWholeWord,
    Set<int>? searchResultLines,
    ItemScrollController? scrollController,
    ItemPositionsListener? positionsListener,
    ScrollOffsetController? scrollOffsetController,
    String? currentTitle,
    String? selectedTextForNote,
    int? selectedTextSectionIndex,
    int? selectedTextStart,
    int? selectedTextEnd,
    bool clearSelectedText = false,
    int? highlightedLine,
    bool clearHighlight = false,
    bool? linksLoading,
    int? pinpointHighlightIndex,
    String? pinpointHighlightText,
    bool clearPinpointHighlight = false,
    bool clearSearchResultLines = false,
    bool? isEditorOpen,
    int? editorIndex,
    String? editorSectionId,
    String? editorText,
    bool? hasDraft,
    bool? hasLinksFile,
    // לאיפוס highlightText ו-permanentHighlightLine יש להעביר ערכים מפורשים
    String? highlightText,
    bool clearHighlightText = false,
    int? permanentHighlightLine,
    bool clearPermanentHighlight = false,
  }) {
    final nextView = (showPageShapeView ?? this.showPageShapeView)
        ? TextView.pageShape
        : TextView.regular;
    final bodySlot = TextDisplaySlot(
      target: TextTarget.body,
      view: nextView,
      channel: TextChannel.display,
    );
    final commentarySlot = TextDisplaySlot(
      target: TextTarget.commentary,
      view: nextView,
      channel: TextChannel.display,
    );
    var overrides = displayOverrides ?? this.displayOverrides;
    if (removeNikud != null) {
      overrides = overrides.merged(
        bodySlot,
        TextDisplayPatch(nikud: visibilityOf(removeNikud)),
      );
    }
    if (removePunctuation != null) {
      overrides = overrides.merged(
        bodySlot,
        TextDisplayPatch(punctuation: visibilityOf(removePunctuation)),
      );
    }
    if (clearCommentaryRemoveNikudOverride) {
      overrides = overrides.withSlot(
        commentarySlot,
        overrides.patchFor(commentarySlot).copyWith(clearNikud: true),
      );
    } else if (commentaryRemoveNikudOverride != null) {
      overrides = overrides.merged(
        commentarySlot,
        TextDisplayPatch(nikud: visibilityOf(commentaryRemoveNikudOverride)),
      );
    }
    if (clearCommentaryRemovePunctuationOverride) {
      overrides = overrides.withSlot(
        commentarySlot,
        overrides.patchFor(commentarySlot).copyWith(clearPunctuation: true),
      );
    } else if (commentaryRemovePunctuationOverride != null) {
      overrides = overrides.merged(
        commentarySlot,
        TextDisplayPatch(
          punctuation: visibilityOf(commentaryRemovePunctuationOverride),
        ),
      );
    }
    var policy = displayPolicy ?? this.displayPolicy;
    if (nikudExemptByTanach != null || punctuationExemptByTanach != null) {
      final body = policy.resolve(
        bodySlot,
        isTanach: isTanach ?? this.isTanach,
      );
      policy = legacyDisplayPolicy(
        removeNikud: body.removeNikud,
        removePunctuation: body.removePunctuation,
        nikudExemptByTanach: nikudExemptByTanach ?? this.nikudExemptByTanach,
        punctuationExemptByTanach:
            punctuationExemptByTanach ?? this.punctuationExemptByTanach,
      );
    }
    return TextBookLoaded(
      book: book ?? this.book,
      content: content ?? this.content,
      contentVersion: contentVersion ?? this.contentVersion,
      fontSize: fontSize ?? this.fontSize,
      showLeftPane: showLeftPane ?? this.showLeftPane,
      showSplitView: showSplitView ?? this.showSplitView,
      showTzuratHadafView: showTzuratHadafView ?? this.showTzuratHadafView,
      showPageShapeView: showPageShapeView ?? this.showPageShapeView,
      activeCommentators: activeCommentators ?? this.activeCommentators,
      commentatorGroups: commentatorGroups ?? this.commentatorGroups,
      availableCommentators:
          availableCommentators ?? this.availableCommentators,
      rareCommentators: rareCommentators ?? this.rareCommentators,
      links: links ?? this.links,
      visibleLinks: visibleLinks ?? this.visibleLinks,
      selectedLinkTypes: selectedLinkTypes ?? this.selectedLinkTypes,
      linksByLine: linksByLine ?? this.linksByLine,
      tableOfContents: tableOfContents ?? this.tableOfContents,
      isTanach: isTanach ?? this.isTanach,
      protection: protection ?? this.protection,
      displayOverrides: overrides,
      bookDisplayLayer: bookDisplayLayer ?? this.bookDisplayLayer,
      displayPolicy: policy,
      supportsContinuousReadingMode:
          supportsContinuousReadingMode ?? this.supportsContinuousReadingMode,
      continuousReadingMode:
          continuousReadingMode ?? this.continuousReadingMode,
      readingSegments: readingSegments ?? this.readingSegments,
      visibleIndices: visibleIndices ?? this.visibleIndices,
      selectedIndex: clearSelectedIndex
          ? null
          : (selectedIndex ?? this.selectedIndex),
      selectedIndices: clearSelectedIndices
          ? const {}
          : (selectedIndices ?? this.selectedIndices),
      pinLeftPane: pinLeftPane ?? this.pinLeftPane,
      searchText: searchText ?? this.searchText,
      searchOptions: searchOptions ?? this.searchOptions,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      spacingValues: spacingValues ?? this.spacingValues,
      searchMode: searchMode ?? this.searchMode,
      searchDistance: searchDistance ?? this.searchDistance,
      matchPolicy: matchPolicy ?? this.matchPolicy,
      searchWholeWord: searchWholeWord ?? this.searchWholeWord,
      searchResultLines: clearSearchResultLines
          ? null
          : (searchResultLines ?? this.searchResultLines),
      scrollController: scrollController ?? this.scrollController,
      positionsListener: positionsListener ?? this.positionsListener,
      scrollOffsetController:
          scrollOffsetController ?? this.scrollOffsetController,
      currentTitle: currentTitle ?? this.currentTitle,
      selectedTextForNote: clearSelectedText
          ? null
          : (selectedTextForNote ?? this.selectedTextForNote),
      selectedTextSectionIndex: clearSelectedText
          ? null
          : (selectedTextSectionIndex ?? this.selectedTextSectionIndex),
      selectedTextStart: clearSelectedText
          ? null
          : (selectedTextStart ?? this.selectedTextStart),
      selectedTextEnd: clearSelectedText
          ? null
          : (selectedTextEnd ?? this.selectedTextEnd),
      highlightedLine: clearHighlight
          ? null
          : (highlightedLine ?? this.highlightedLine),
      linksLoading: linksLoading ?? this.linksLoading,
      pinpointHighlightIndex: clearPinpointHighlight
          ? null
          : (pinpointHighlightIndex ?? this.pinpointHighlightIndex),
      pinpointHighlightText: clearPinpointHighlight
          ? null
          : (pinpointHighlightText ?? this.pinpointHighlightText),
      isEditorOpen: isEditorOpen ?? this.isEditorOpen,
      editorIndex: editorIndex ?? this.editorIndex,
      editorSectionId: editorSectionId ?? this.editorSectionId,
      editorText: editorText ?? this.editorText,
      hasDraft: hasDraft ?? this.hasDraft,
      hasLinksFile: hasLinksFile ?? this.hasLinksFile,
      highlightText: clearHighlightText
          ? ''
          : (highlightText ?? this.highlightText),
      permanentHighlightLine: clearPermanentHighlight
          ? null
          : (permanentHighlightLine ?? this.permanentHighlightLine),
    );
  }

  /// האם השורה [index] מודגשת כרקע קבוע (ללא highlightText פעיל).
  bool isPermanentHighlight(int index) =>
      permanentHighlightLine == index && highlightText.isEmpty;

  /// האם השורה [index] מודגשת ברקע צהוב (highlightText + permanentHighlightLine).
  bool isHighlightYellowBackground(int index) =>
      highlightText.isNotEmpty && permanentHighlightLine == index;

  @override
  List<Object?> get props => [
    book.title,
    book.id,
    // שדות שההעשרה ברקע (UpdateResolvedBookId) מעדכנת — בלעדיהם ה-emit
    // של העדכון נבלע כשווה-ערך והדיאלוגים לא רואים את הקטגוריות.
    book.heCategories,
    book.author,
    book.heEra,
    contentVersion,
    content.length,
    fontSize,
    showLeftPane,
    showSplitView,
    showTzuratHadafView,
    showPageShapeView,
    // השוואה לפי תוכן (לא רק אורך) — אחרת החלפת מפרש אחד באחר באותו אורך
    // נבלעת ע"י השוואת ה-state והבחירה לא מתעדכנת.
    activeCommentators,
    commentatorGroups,
    availableCommentators.length,
    rareCommentators,
    links.length,
    visibleLinks.length,
    // השוואה לפי תוכן — החלפת סוג אחד באחר שומרת על אותו גודל ותיבלע
    // בהשוואת ה-state, והסינון לא יתעדכן.
    selectedLinkTypes,
    tableOfContents.length,
    isTanach,
    protection,
    displayOverrides,
    bookDisplayLayer,
    displayPolicy,
    supportsContinuousReadingMode,
    continuousReadingMode,
    readingSegments.length,
    visibleIndices,
    selectedIndex,
    selectedIndices,
    pinLeftPane,
    searchText,
    _searchOptionsSignature(searchOptions),
    _alternativeWordsSignature(alternativeWords),
    _spacingValuesSignature(spacingValues),
    searchMode,
    searchDistance,
    matchPolicy,
    searchWholeWord,
    searchResultLines,
    currentTitle,
    selectedTextForNote,
    selectedTextSectionIndex,
    selectedTextStart,
    selectedTextEnd,
    highlightedLine,
    linksLoading,
    pinpointHighlightIndex,
    pinpointHighlightText,
    isEditorOpen,
    editorIndex,
    editorSectionId,
    editorText,
    hasDraft,
    hasLinksFile,
    highlightText,
    permanentHighlightLine,
  ];
}
