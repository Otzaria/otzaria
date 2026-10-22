import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// קישורים פנימיים בקטע בחלונית, שספרו שונה מספר הבסיס.
/// נטענים דרך [TargetLineLinksService], כמו בתפריט ההקשר.
mixin PanelAnchorLinksMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _anchorSubscription;

  /// הקישורים המעוגנים בשורה המוצגת, בסדר יציב. ה-href של כל סימון נושא את
  /// המיקום ברשימה הזו, ולכן [anchorLinkFromUrl] חייב לקרוא את אותה רשימה.
  List<Link> _anchorLinks = const [];
  List<Link> _noteLinks = const [];

  /// הערות השוליים מהמסד של ספר הקטע (`line_note`) — במסד חדש הן מחליפות
  /// את קישורי FOOTNOTES של "הערות על ...", למשל בחברותא.
  BookNotes _targetNotes = BookNotes.empty;

  /// עוגני הקטע נמדדים על השורה המלאה, עם גופי ההערות: עד שההערות נטענו
  /// אין להם מקום בטקסט, וכשהטעינה נכשלה ([targetNotesError]) — לא יהיה.
  bool _targetNotesLoaded = false;
  Object? _targetNotesError;

  /// כשל בטעינת הערות ספר הקטע; העוגנים שלו אינם מוצבים.
  Object? get targetNotesError => _targetNotesError;
  DivineNameSpans _targetNames = DivineNameSpans.empty;
  List<LinkContentLine>? _targetLines;
  int _anchorHoverGeneration = 0;

  /// הקישור שהקטע שלו מוצג — [Link.path2]/[Link.index2] הם הספר והשורה.
  Link get anchorSourceLink;

  /// כיבוי לפי פרופיל התצוגה של הכרטיסייה.
  bool get anchorLinksEnabled;

  /// האם הקטע מדגיש את הציטוט המקושר ([Link.linkedAnchorStart]); אז גם בהערה.
  bool get highlightsLinkedAnchor => false;

  bool get hasPanelLinks =>
      _anchorLinks.isNotEmpty || _noteLinks.isNotEmpty || _hasStoredNotes;

  bool get _isSingleLine =>
      (anchorSourceLink.index2End ?? anchorSourceLink.index2) <=
      anchorSourceLink.index2;

  bool get _hasStoredNotes {
    for (
      var i = anchorSourceLink.index2 - 1;
      i < (anchorSourceLink.index2End ?? anchorSourceLink.index2);
      i++
    ) {
      if (_targetNotes.notesAt(i).isNotEmpty) return true;
    }
    return false;
  }

  void startAnchorLinks() {
    _anchorSubscription = TargetLineLinksService.instance.refreshStream.listen(
      (_) => _syncAnchorLinks(),
    );
    _requestAnchorLinks();
  }

  void restartAnchorLinks() {
    _cancelAnchorHoverTimer();
    _anchorLinks = const [];
    _noteLinks = const [];
    _targetNotes = BookNotes.empty;
    _targetNotesLoaded = false;
    _targetNotesError = null;
    _targetNames = DivineNameSpans.empty;
    _targetLines = null;
    _requestAnchorLinks();
  }

  void stopAnchorLinks() {
    _anchorSubscription?.cancel();
    _anchorSubscription = null;
    _cancelAnchorHoverTimer();
  }

  Timer? _anchorHoverTimer;

  // Flutter קורא ל-onExit של ספאן גם אחרי שהחלונית הוסרה מהעץ, וכבר אין context.
  AppWindowKeys? _anchorHoverWindow;

  void _cancelAnchorHoverTimer() {
    _anchorHoverTimer?.cancel();
    _anchorHoverGeneration++;
  }

  /// ריחוף על ציטוט — תצוגה מקדימה אחרי השהיה, כמו בגוף הספר (ההשהיה מונעת
  /// הבהובים כשהסמן רק חולף). [onOpen] — לחיצה על כותרת החלונית.
  void handleAnchorHover(
    String url,
    Offset globalPosition, {
    required void Function(Link link) onOpen,
    TextDisplayProfile? displayProfile,
  }) {
    _anchorHoverWindow = AppWindowKeys.of(context);
    LinkPreviewOverlay.cancelScheduledHide(_anchorHoverWindow);
    _cancelAnchorHoverTimer();
    final generation = _anchorHoverGeneration;
    final isNoteMarker = url.startsWith('otzaria://note-marker');
    final isBookNote = url.startsWith('otzaria://book-note');
    final anchorLink = isNoteMarker || isBookNote
        ? null
        : anchorLinkFromUrl(url);
    if (!isNoteMarker && !isBookNote && anchorLink == null) return;
    if (anchorLink != null) prefetchLinkPreview(anchorLink);
    _anchorHoverTimer = Timer(const Duration(milliseconds: 280), () async {
      final lineIndex = int.tryParse(
        Uri.tryParse(url)?.queryParameters['line'] ?? '',
      );
      final link =
          anchorLink ??
          await numberedNoteLinkFromUrl(url, [
            for (final candidate in _noteLinks)
              if (candidate.index1 == (lineIndex ?? -1) + 1) candidate,
          ]);
      if (!mounted || generation != _anchorHoverGeneration) return;
      if (link == null) {
        _showBookNotePreview(url, globalPosition, displayProfile);
        return;
      }
      LinkPreviewOverlay.show(
        context,
        link: link,
        globalPosition: globalPosition,
        hoverMode: true,
        displayProfile: displayProfile,
        onOpen: () {
          LinkPreviewOverlay.dismiss(window: AppWindowKeys.of(context));
          onOpen(link);
        },
      );
    });
  }

  void _showBookNotePreview(
    String url,
    Offset globalPosition,
    TextDisplayProfile? displayProfile,
  ) {
    final lineIndex = int.tryParse(
      Uri.tryParse(url)?.queryParameters['line'] ?? '',
    );
    if (lineIndex == null ||
        lineIndex < anchorSourceLink.index2 - 1 ||
        lineIndex >= (anchorSourceLink.index2End ?? anchorSourceLink.index2)) {
      return;
    }
    final lineNotes = _targetNotes.notesAt(lineIndex);
    if (lineNotes.isEmpty) return;
    final String? note;
    if (url.startsWith('otzaria://book-note')) {
      note = inlineNoteFromPreviewUrl(
        const [],
        url,
        dbNotes: _targetNotes,
        decorateBody: _noteBodyWithAnchors,
      );
    } else {
      final match = numberedBookNoteFromUrl(url, lineNotes);
      note = match == null
          ? null
          : BookNotes.toInlineHtml(
              match,
              body: _noteBodyWithAnchors(
                lineIndex,
                lineNotes.indexOf(match),
                bookNoteBodyWithDivineNames(_targetNotes, lineIndex, match),
              ),
            );
    }
    if (note == null) return;
    LinkPreviewOverlay.showContent(
      context,
      globalPosition: globalPosition,
      hoverMode: true,
      contentBuilder: (_) => InlineBookNotePreviewContent(
        content: note!,
        displayProfile: displayProfile,
        onAnchorTap: _openNoteAnchor,
      ),
    );
  }

  /// גוף ההערה [note] (מיקום ב-`notesAt`) של שורה [lineIndex] בקטע, עם חלקי
  /// הציטוטים שבו — ה-href מפנה לאותה רשימה כמו בשורה.
  String _noteBodyWithAnchors(int lineIndex, int note, String body) {
    final notes = _targetNotes.notesAt(lineIndex);
    final anchors = _anchorsAt(lineIndex);
    var html = !anchorLinksEnabled || anchors.isEmpty
        ? body
        : injectLinkAnchorMarkers(
            rawLine: body,
            anchorLinks: anchors,
            styleIndexByCommentator: const {},
            lineIndex: lineIndex,
            rangesOnly: true,
            notes: notes,
            note: note,
          );
    if (highlightsLinkedAnchor && lineIndex == anchorSourceLink.index2 - 1) {
      final linked = linkedAnchorSpan(note: note);
      if (linked != null) {
        html = wrapVisibleRange(
          html: html,
          start: linked.start,
          end: linked.end!,
          openTag: '<span class="link-anchor-range">',
          closeTag: '</span>',
        );
      }
    }
    return html;
  }

  void _openNoteAnchor(String url) {
    final link = anchorLinkFromUrl(url);
    if (link == null) return;
    LinkPreviewOverlay.dismiss(window: AppWindowKeys.of(context));
    openPanelAnchor(link);
  }

  /// ניווט מציטוט בקטע — כמו לחיצה עליו בטקסט עצמו.
  void openPanelAnchor(Link link);

  /// הציטוט המקושר ([Link.linkedAnchorStart]) בשורה הראשונה של הקטע: חלקו
  /// בטקסט השמור ([note] null) או בגוף ההערה [note]; null עד שההערות נטענו
  /// או כשאין לו חלק שם.
  LinkAnchorSpan? linkedAnchorSpan({int? note}) {
    final start = anchorSourceLink.linkedAnchorStart;
    final end = anchorSourceLink.linkedAnchorEnd;
    if (start == null || end == null || end <= start) return null;
    if (!_targetNotesLoaded) return null;
    final spans = projectAnchorSpans(
      [LinkAnchorSpan(start: start, end: end)],
      _targetNotes.notesAt(anchorSourceLink.index2 - 1),
      note: note,
    );
    return spans.isEmpty ? null : spans.single;
  }

  void handleAnchorHoverExit(String url) {
    _cancelAnchorHoverTimer();
    LinkPreviewOverlay.scheduleHide(
      mounted ? AppWindowKeys.of(context) : _anchorHoverWindow,
    );
  }

  /// לחיצה על הציטוט מנווטת — ריחוף ממתין היה פותח חלונית אחרי הניווט.
  void cancelAnchorHover() {
    _cancelAnchorHoverTimer();
    LinkPreviewOverlay.dismiss(window: AppWindowKeys.of(context));
  }

  void _requestAnchorLinks() {
    _loadTargetNotes();
    if (!anchorLinksEnabled) return;
    TargetLineLinksService.instance.prefetch(anchorSourceLink);
    _syncAnchorLinks();
  }

  Future<void> _loadTargetNotes() async {
    final link = anchorSourceLink;
    // בלי ספר אין הערות: העוגנים (אם יש) נמדדים על השורה עצמה.
    if (link.path2.isEmpty) {
      _targetNotesLoaded = true;
      return;
    }
    final title = utils.getTitleFromPath(link.path2);
    final BookNotes notes;
    try {
      notes = await BookNotesRepository.instance.notesFor(
        title,
        categoryId: link.targetCategoryId,
        source: link.targetSource,
        fileType: link.targetFileType,
      );
    } catch (error, stack) {
      if (!mounted || !identical(anchorSourceLink, link)) return;
      setState(() => _targetNotesError = error);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'otzaria',
          context: ErrorDescription(
            'while loading the footnotes of "$title"; its link anchors are not shown',
          ),
        ),
      );
      return;
    }
    if (!mounted || !identical(anchorSourceLink, link)) return;
    setState(() {
      _targetNotes = notes;
      _targetNotesLoaded = true;
    });
    final names = await DivineNamesRepository.instance.spansFor(
      title,
      categoryId: link.targetCategoryId,
      source: link.targetSource,
      fileType: link.targetFileType,
    );
    final lines = _isSingleLine ? null : await link.contentLines;
    if (!mounted || !identical(anchorSourceLink, link)) return;
    setState(() {
      _targetNames = names;
      _targetLines = lines;
    });
  }

  void _syncAnchorLinks() {
    if (!mounted || !anchorLinksEnabled) return;
    final cached =
        TargetLineLinksService.instance.cached(anchorSourceLink) ??
        TargetLineLinks.empty;
    final line = anchorSourceLink.index2;
    final next = [
      for (final link in cached.anchored)
        if (link.index1 >= line &&
            link.index1 <= (anchorSourceLink.index2End ?? line) &&
            _hasRangeSpan(link))
          link,
    ];
    final nextNotes = numberedNoteLinks([
      for (final link in cached.commentaries)
        if (link.index1 >= line &&
            link.index1 <= (anchorSourceLink.index2End ?? line))
          link,
    ]);
    // הזרם משותף לכל הפריטים; בלי ההשוואה כל טעינה של פריט אחד הייתה בונה
    // מחדש את כולם.
    if (_sameLinks(next, _anchorLinks) && _sameLinks(nextNotes, _noteLinks)) {
      return;
    }
    setState(() {
      _anchorLinks = next;
      _noteLinks = nextNotes;
    });
  }

  static bool _hasRangeSpan(Link link) {
    if (link.anchorSpans.isNotEmpty) {
      return link.anchorSpans.any((span) => (span.end ?? -1) > span.start);
    }
    final end = link.anchorEnd;
    return end != null && end > (link.anchorStart ?? 0);
  }

  static bool _sameLinks(List<Link> a, List<Link> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// מזריק את הסימון לשורה הגולמית — חייב לרוץ *לפני* כל עיבוד שמוסיף תוכן
  /// גלוי (סימוני הערות), כי אופסטי העוגן נמדדים על הטקסט כפי שנשמר.
  String injectAnchorLinks(String rawLine) {
    final lines = _targetLines;
    if (lines == null) {
      return _isSingleLine
          ? _injectLineLinks(rawLine, anchorSourceLink.index2 - 1)
          : rawLine;
    }
    return [
      for (final line in lines) _injectLineLinks(line.content, line.lineIndex),
    ].join('<br>');
  }

  List<Link> _anchorsAt(int lineIndex) => [
    for (final link in _anchorLinks)
      if (link.index1 == lineIndex + 1) link,
  ];

  String _injectLineLinks(String rawLine, int lineIndex) {
    final anchors = _anchorsAt(lineIndex);
    final html = anchors.isEmpty || !_targetNotesLoaded
        ? rawLine
        : injectLinkAnchorMarkers(
            rawLine: rawLine,
            anchorLinks: anchors,
            styleIndexByCommentator: const {},
            lineIndex: lineIndex,
            rangesOnly: true,
            notes: _targetNotes.notesAt(lineIndex),
          );
    final marked = injectDivineNameMarkers(html, _targetNames, lineIndex);
    if (!anchorLinksEnabled) return marked;
    final lineNotes = _targetNotes.notesAt(lineIndex);
    var result = lineNotes.isEmpty
        ? marked
        : addInlineNotePreviewLinks(
            marked,
            lineIndex: lineIndex,
            dbNotes: _targetNotes,
          );
    // סמן מודפס כמו (9) בלי <sup> — ההערה שלו נשמרה בלי אות-הפניה.
    if (_noteLinks.any((link) => link.index1 == lineIndex + 1) ||
        lineNotes.any((n) => n.marker == null)) {
      result = addNumberedNoteMarkerLinks(result, lineIndex: lineIndex);
    }
    return result;
  }

  /// פענוח `otzaria://anchor?ref=<line>_<i>` לקישור שממנו נוצר הסימון.
  Link? anchorLinkFromUrl(String url) {
    final ref = Uri.tryParse(url)?.queryParameters['ref'];
    final parts = ref?.split('_');
    if (parts == null || parts.length != 2) return null;
    final lineIndex = int.tryParse(parts[0]);
    final index = int.tryParse(parts[1]);
    if (lineIndex == null || index == null || index < 0) return null;
    final anchors = _anchorsAt(lineIndex);
    return index < anchors.length ? anchors[index] : null;
  }
}

/// קטע טקסט בחלונית עם הקישורים הפנימיים שבו פעילים. לשימוש כשאין צורך
/// בעיבוד נוסף של השורה; קטע שמוסיף סימוני הערות משתמש ישירות במיקסין.
class PanelAnchoredText extends StatefulWidget {
  const PanelAnchoredText({
    super.key,
    required this.link,
    required this.html,
    required this.settings,
    required this.enabled,
    required this.openBookCallback,
    this.onAnchorActivated,
  });

  final Link link;
  final String html;
  final RenderSettings settings;
  final bool enabled;
  final void Function(OpenedTab) openBookCallback;

  /// נקרא לפני הניווט, כדי שהורה עם onTap משלו יוכל לוותר על אותה הקשה.
  final VoidCallback? onAnchorActivated;

  @override
  State<PanelAnchoredText> createState() => _PanelAnchoredTextState();
}

class _PanelAnchoredTextState extends State<PanelAnchoredText>
    with PanelAnchorLinksMixin<PanelAnchoredText> {
  @override
  Link get anchorSourceLink => widget.link;

  @override
  bool get anchorLinksEnabled => widget.enabled;

  @override
  void initState() {
    super.initState();
    startAnchorLinks();
  }

  @override
  void didUpdateWidget(PanelAnchoredText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link || oldWidget.enabled != widget.enabled) {
      restartAnchorLinks();
    }
  }

  @override
  void dispose() {
    stopAnchorLinks();
    super.dispose();
  }

  Future<void> _openAnchorTarget(Link link) async {
    widget.onAnchorActivated?.call();
    await _navigateTo(link);
  }

  @override
  void openPanelAnchor(Link link) => _openAnchorTarget(link);

  // בלי onAnchorActivated: הלחיצה על כותרת החלונית אינה הקשה על הפריט שמתחת.
  Future<void> _navigateTo(Link link) =>
      openLinkTarget(link, (tab) => widget.openBookCallback(tab));

  @override
  Widget build(BuildContext context) {
    return SmartTextWidget(
      text: injectAnchorLinks(widget.html),
      settings: widget.settings,
      onAnchorTap: !hasPanelLinks
          ? null
          : (url) {
              cancelAnchorHover();
              final link = anchorLinkFromUrl(url);
              if (link != null) _openAnchorTarget(link);
            },
      onAnchorHover: !hasPanelLinks
          ? null
          : (url, position) =>
                handleAnchorHover(url, position, onOpen: _navigateTo),
      onAnchorHoverExit: !hasPanelLinks ? null : handleAnchorHoverExit,
    );
  }
}
