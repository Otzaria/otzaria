import 'dart:async';

import 'package:flutter/widgets.dart';
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
  List<Link> _anchorLinks = const [];
  List<Link> _noteLinks = const [];
  int _anchorHoverGeneration = 0;

  /// הקישור שהקטע שלו מוצג — [Link.path2]/[Link.index2] הם הספר והשורה.
  Link get anchorSourceLink;

  /// כיבוי לפי פרופיל התצוגה של הכרטיסייה.
  bool get anchorLinksEnabled;

  /// הקישורים המעוגנים בשורה המוצגת, בסדר יציב. ה-href של כל סימון נושא את
  /// המיקום ברשימה הזו, ולכן [anchorLinkFromUrl] חייב לקרוא את אותה רשימה.
  List<Link> get anchorLinks => _anchorLinks;

  bool get hasPanelLinks => _anchorLinks.isNotEmpty || _noteLinks.isNotEmpty;

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
    final anchorLink = isNoteMarker ? null : anchorLinkFromUrl(url);
    if (!isNoteMarker && anchorLink == null) return;
    if (anchorLink != null) prefetchLinkPreview(anchorLink);
    _anchorHoverTimer = Timer(const Duration(milliseconds: 280), () async {
      final link = anchorLink ?? await numberedNoteLinkFromUrl(url, _noteLinks);
      if (!mounted || link == null) return;
      if (generation != _anchorHoverGeneration) return;
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
    if (_noteLinks.isEmpty ||
        (anchorSourceLink.index2End ?? anchorSourceLink.index2) >
            anchorSourceLink.index2) {
      return html;
    }
    return addNumberedNoteMarkerLinks(html, lineIndex: lineIndex);
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
