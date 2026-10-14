import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
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
  int _anchorHoverGeneration = 0;

  /// הקישור שהקטע שלו מוצג — [Link.path2]/[Link.index2] הם הספר והשורה.
  Link get anchorSourceLink;

  /// כיבוי לפי פרופיל התצוגה של הכרטיסייה.
  bool get anchorLinksEnabled;

  bool get hasPanelLinks =>
      _anchorLinks.isNotEmpty || _noteLinks.isNotEmpty || _lineNotes.isNotEmpty;

  bool get _isSingleLine =>
      (anchorSourceLink.index2End ?? anchorSourceLink.index2) <=
      anchorSourceLink.index2;

  List<BookNote> get _lineNotes => _isSingleLine
      ? _targetNotes.notesAt(anchorSourceLink.index2 - 1)
      : const [];

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
    _requestAnchorLinks();
  }

  void stopAnchorLinks() {
    _anchorSubscription?.cancel();
    _anchorSubscription = null;
    _cancelAnchorHoverTimer();
  }

  Timer? _anchorHoverTimer;

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
    LinkPreviewOverlay.cancelScheduledHide();
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
      final link = anchorLink ?? await numberedNoteLinkFromUrl(url, _noteLinks);
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
          LinkPreviewOverlay.dismiss();
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
    final lineNotes = _lineNotes;
    if (lineNotes.isEmpty) return;
    final String? note;
    if (url.startsWith('otzaria://book-note')) {
      note = inlineNoteFromPreviewUrl(const [], url, dbNotes: _targetNotes);
    } else {
      final match = numberedBookNoteFromUrl(url, lineNotes);
      note = match == null ? null : BookNotes.toInlineHtml(match);
    }
    if (note == null) return;
    LinkPreviewOverlay.showContent(
      context,
      globalPosition: globalPosition,
      hoverMode: true,
      contentBuilder: (_) => InlineBookNotePreviewContent(
        content: note!,
        displayProfile: displayProfile,
      ),
    );
  }

  void handleAnchorHoverExit(String url) {
    _cancelAnchorHoverTimer();
    LinkPreviewOverlay.scheduleHide();
  }

  /// לחיצה על הציטוט מנווטת — ריחוף ממתין היה פותח חלונית אחרי הניווט.
  void cancelAnchorHover() {
    _cancelAnchorHoverTimer();
    LinkPreviewOverlay.dismiss();
  }

  void _requestAnchorLinks() {
    if (!anchorLinksEnabled) return;
    TargetLineLinksService.instance.prefetch(anchorSourceLink);
    _syncAnchorLinks();
    _loadTargetNotes();
  }

  Future<void> _loadTargetNotes() async {
    final link = anchorSourceLink;
    if (!_isSingleLine || link.path2.isEmpty) return;
    final notes = await BookNotesRepository.instance.notesFor(
      utils.getTitleFromPath(link.path2),
      categoryId: link.targetCategoryId,
      source: link.targetSource,
      fileType: link.targetFileType,
    );
    if (!mounted || !identical(anchorSourceLink, link)) return;
    if (identical(notes, _targetNotes)) return;
    setState(() => _targetNotes = notes);
  }

  void _syncAnchorLinks() {
    if (!mounted || !anchorLinksEnabled) return;
    final cached =
        TargetLineLinksService.instance.cached(anchorSourceLink) ??
        TargetLineLinks.empty;
    final line = anchorSourceLink.index2;
    final next = [
      for (final link in cached.anchored)
        if (link.index1 == line && _hasRangeSpan(link)) link,
    ];
    final nextNotes = numberedNoteLinks([
      for (final link in cached.commentaries)
        if (link.index1 == line) link,
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
    final lineIndex = anchorSourceLink.index2 - 1;
    final html = _anchorLinks.isEmpty
        ? rawLine
        : injectLinkAnchorMarkers(
            rawLine: rawLine,
            anchorLinks: _anchorLinks,
            styleIndexByCommentator: const {},
            lineIndex: lineIndex,
            rangesOnly: true,
          );
    // אחרי הציטוטים: אופסטי קישור-משתמש נמדדים על השורה הגולמית.
    // HTML של טווח אינו שומר גבולות שורות מקור; מספר הערה יכול לחזור.
    if (!_isSingleLine) return html;
    final lineNotes = _lineNotes;
    var result = lineNotes.isEmpty
        ? html
        : addInlineNotePreviewLinks(
            html,
            lineIndex: lineIndex,
            dbNotes: _targetNotes,
          );
    // סמן מודפס כמו (9) בלי <sup> — ההערה שלו נשמרה בלי אות-הפניה.
    if (_noteLinks.isNotEmpty || lineNotes.any((n) => n.marker == null)) {
      result = addNumberedNoteMarkerLinks(result, lineIndex: lineIndex);
    }
    return result;
  }

  /// פענוח `otzaria://anchor?ref=<line>_<i>` לקישור שממנו נוצר הסימון.
  Link? anchorLinkFromUrl(String url) {
    final ref = Uri.tryParse(url)?.queryParameters['ref'];
    final parts = ref?.split('_');
    if (parts == null || parts.length != 2) return null;
    final index = int.tryParse(parts[1]);
    if (index == null || index < 0 || index >= _anchorLinks.length) return null;
    return _anchorLinks[index];
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
    if (oldWidget.link != widget.link) restartAnchorLinks();
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
