import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// קישורים פנימיים (ציטוטי הלינקר) בתוך קטע שמוצג בחלונית — מפרש או קישור.
///
/// בגוף הספר הסימון מוזרק מ-`state.linksByLine`, שממופתח לשורות ספר הבסיס
/// בלבד. בחלונית הקטע שייך לספר אחר, ולכן הקישורים מגיעים מ-
/// [TargetLineLinksService] — אותה טעינה שכבר משרתת את תפריט ההקשר.
mixin PanelAnchorLinksMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _anchorSubscription;
  List<Link> _anchorLinks = const [];

  /// הקישור שהקטע שלו מוצג — [Link.path2]/[Link.index2] הם הספר והשורה.
  Link get anchorSourceLink;

  /// כיבוי לפי פרופיל התצוגה של הכרטיסייה.
  bool get anchorLinksEnabled;

  /// הקישורים המעוגנים בשורה המוצגת, בסדר יציב. ה-href של כל סימון נושא את
  /// המיקום ברשימה הזו, ולכן [anchorLinkFromUrl] חייב לקרוא את אותה רשימה.
  List<Link> get anchorLinks => _anchorLinks;

  void startAnchorLinks() {
    _anchorSubscription = TargetLineLinksService.instance.refreshStream.listen(
      (_) => _syncAnchorLinks(),
    );
    _requestAnchorLinks();
  }

  void restartAnchorLinks() {
    _anchorHoverTimer?.cancel();
    _anchorLinks = const [];
    _requestAnchorLinks();
  }

  void stopAnchorLinks() {
    _anchorSubscription?.cancel();
    _anchorSubscription = null;
    _anchorHoverTimer?.cancel();
  }

  Timer? _anchorHoverTimer;

  /// ריחוף על ציטוט — תצוגה מקדימה אחרי השהיה, כמו בגוף הספר (ההשהיה מונעת
  /// הבהובים כשהסמן רק חולף). [onOpen] — לחיצה על כותרת החלונית.
  void handleAnchorHover(
    String url,
    Offset globalPosition, {
    required void Function(Link link) onOpen,
    TextDisplayProfile? displayProfile,
  }) {
    LinkPreviewOverlay.cancelScheduledHide();
    _anchorHoverTimer?.cancel();
    final link = anchorLinkFromUrl(url);
    if (link == null) return;
    prefetchLinkPreview(link);
    _anchorHoverTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
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
    _anchorHoverTimer?.cancel();
    LinkPreviewOverlay.scheduleHide();
  }

  /// לחיצה על הציטוט מנווטת — ריחוף ממתין היה פותח חלונית אחרי הניווט.
  void cancelAnchorHover() {
    _anchorHoverTimer?.cancel();
    LinkPreviewOverlay.dismiss();
  }

  void _requestAnchorLinks() {
    if (!anchorLinksEnabled) return;
    TargetLineLinksService.instance.prefetch(anchorSourceLink);
    _syncAnchorLinks();
  }

  void _syncAnchorLinks() {
    if (!mounted || !anchorLinksEnabled) return;
    final next = _anchoredLinksOfDisplayedLine();
    // הזרם משותף לכל הפריטים; בלי ההשוואה כל טעינה של פריט אחד הייתה בונה
    // מחדש את כולם.
    if (identical(next, _anchorLinks) || _sameLinks(next, _anchorLinks)) return;
    setState(() => _anchorLinks = next);
  }

  List<Link> _anchoredLinksOfDisplayedLine() {
    final cached = TargetLineLinksService.instance.cached(anchorSourceLink);
    if (cached == null || cached.anchored.isEmpty) return const [];
    final line = anchorSourceLink.index2;
    return [
      for (final link in cached.anchored)
        if (link.index1 == line && _hasRangeSpan(link)) link,
    ];
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
    if (_anchorLinks.isEmpty) return rawLine;
    return injectLinkAnchorMarkers(
      rawLine: rawLine,
      anchorLinks: _anchorLinks,
      styleIndexByCommentator: const {},
      lineIndex: anchorSourceLink.index2 - 1,
      rangesOnly: true,
    );
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
  Future<void> _navigateTo(Link link) async {
    final tab = await buildLinkTargetTab(link);
    if (!mounted) return;
    widget.openBookCallback(tab);
  }

  @override
  Widget build(BuildContext context) {
    return SmartTextWidget(
      text: injectAnchorLinks(widget.html),
      settings: widget.settings,
      onAnchorTap: anchorLinks.isEmpty
          ? null
          : (url) {
              cancelAnchorHover();
              final link = anchorLinkFromUrl(url);
              if (link != null) _openAnchorTarget(link);
            },
      onAnchorHover: anchorLinks.isEmpty
          ? null
          : (url, position) =>
                handleAnchorHover(url, position, onOpen: _navigateTo),
      onAnchorHoverExit: anchorLinks.isEmpty ? null : handleAnchorHoverExit,
    );
  }
}
