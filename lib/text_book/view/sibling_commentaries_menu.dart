import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';

/// מנהל את תת-התפריט "מפרשים נוספים על …" בתפריט ההקשר של ספרי מפרש.
///
/// כשלומדים בתוך ספר מפרש (למשל רשב"א על ברכות), הקישור ההפוך (SOURCE) של כל
/// שורה כבר נותן את שורת המקור בגמרא; מכאן נאספים שאר המפרשים על אותו קטע.
/// הטעינה אסינכרונית ולכן מתבצעת בעצלתיים עם מטמון לפי שורה, ותת-התפריט מתרענן
/// דרך [childrenRefreshStream] כשהנתונים מגיעים. instance אחד לכל מסך טקסט.
class SiblingCommentariesController {
  /// טוען את "המפרשים הנוספים" עבור קישור מקור (SOURCE) נתון.
  final Future<List<Link>> Function(Link sourceLink) loadSiblings;

  SiblingCommentariesController({required this.loadSiblings});

  // null = בטעינה; רשימה ריקה = אין מפרשים נוספים.
  final Map<int, List<Link>?> _cache = {};
  final StreamController<void> _refresh = StreamController<void>.broadcast();

  // עולה בכל [clear]. טעינה שהתחילה לפני ניקוי לא תכתוב את תוצאותיה למטמון
  // שכבר שייך לספר אחר.
  int _generation = 0;

  /// מנקה את המטמון (למשל בעת החלפת ספר באותו מסך).
  void clear() {
    _generation++;
    _cache.clear();
  }

  void dispose() => _refresh.close();

  /// מאתר את קישור ה-SOURCE הווירטואלי של השורה (הקפיצה מפרש→מקור). מוחזר null
  /// כשהשורה אינה בספר מפרש — ואז אין להציג את הפריט כלל.
  /// לשורה יכולים להיות כמה קישורי SOURCE; נבחר בעל ה-[Link.baseProvenance]
  /// הגבוה — יחס הבסיס המוצהר ולא ציטוט לטרלי שנשמר במסד בכיוון ההפוך.
  Link? sourceLinkForLine(Map<int, List<Link>> linksByLine, int lineIndex) {
    final links = linksByLine[lineIndex];
    if (links == null) return null;
    Link? best;
    for (final link in links) {
      if (!LinkTypes.isVirtualSource(link.connectionType)) continue;
      if (best == null || link.baseProvenance > best.baseProvenance) {
        best = link;
      }
    }
    return best;
  }

  /// בונה את פריט התפריט "מפרשים נוספים על <כתובת המקור>", או null כשאין מקור
  /// (השורה אינה בספר מפרש).
  AppContextMenuEntry? buildEntry({
    required int lineIndex,
    required Link? sourceLink,
    required void Function(Link link) onNavigate,
    bool? removeNikud,
    bool? removePunctuation,
  }) {
    if (sourceLink == null) return null;
    // הכתובת המלאה (displayReference) מחושבת מה-TOC של המקור ולכן תואמת את
    // פורמט הכותרת ("ב."), בעוד fallbackDisplayReference מציג את ה-heRef הגולמי
    // ("ב א"). ה-fallback משמש עד שהחישוב האסינכרוני מסתיים.
    final fallback = sourceLink.fallbackDisplayReference;
    return AppContextMenuEntry(
      label: 'מפרשים נוספים על $fallback',
      labelWidget: FutureBuilder<String>(
        future: sourceLink.displayReference,
        builder: (context, snapshot) => Text(
          'מפרשים נוספים על ${snapshot.data ?? fallback}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      icon: FluentIcons.book_24_regular,
      childrenBuilder: () => _buildChildren(
        lineIndex,
        sourceLink,
        onNavigate,
        removeNikud: removeNikud,
        removePunctuation: removePunctuation,
      ),
      childrenRefreshStream: _refresh.stream,
    );
  }

  List<AppContextMenuEntry> _buildChildren(
    int lineIndex,
    Link sourceLink,
    void Function(Link link) onNavigate, {
    bool? removeNikud,
    bool? removePunctuation,
  }) {
    if (!_cache.containsKey(lineIndex)) {
      _cache[lineIndex] = null; // מסמן "בטעינה" ומונע טעינה כפולה
      unawaited(_load(lineIndex, sourceLink));
    }
    final cached = _cache[lineIndex];
    if (cached == null) {
      return const [
        AppContextMenuEntry(label: 'טוען מפרשים…', enabled: false),
      ];
    }
    if (cached.isEmpty) {
      return const [
        AppContextMenuEntry(label: 'אין מפרשים נוספים', enabled: false),
      ];
    }
    // הרשימה כבר ממוינת לפי דורות; מוסיפים פס מבדיל בכל מעבר דור.
    final entries = <AppContextMenuEntry>[];
    CommentaryEra? lastEra;
    for (final link in cached) {
      final era = CommentaryService.getCachedBookEra(
        utils.getTitleFromPath(link.path2),
      );
      if (lastEra != null && era != lastEra) {
        entries.add(const AppContextMenuEntry.divider());
      }
      lastEra = era;
      entries.add(
        buildLinkContextMenuEntry(
          link: link,
          removeNikud: removeNikud,
          removePunctuation: removePunctuation,
          onTap: () => onNavigate(link),
        ),
      );
    }
    return entries;
  }

  Future<void> _load(int lineIndex, Link sourceLink) async {
    final generation = _generation;
    List<Link> result;
    try {
      result = await loadSiblings(sourceLink);
    } catch (_) {
      result = const [];
    }
    // clear() קרה בזמן הטעינה (מעבר ספר) — התוצאה שייכת לספר הישן, מוזנחת.
    if (generation != _generation) return;
    _cache[lineIndex] = result;
    if (!_refresh.isClosed) _refresh.add(null);
  }
}
