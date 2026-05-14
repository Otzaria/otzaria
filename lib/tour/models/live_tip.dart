// לתחזוקת טיפים חיים ראו: docs/guided_tour_developer_guide.md

import 'package:equatable/equatable.dart';
import 'package:otzaria/tour/models/tour_step.dart';

enum LiveTipId {
  sideBySideSuggestion,
  dictionaryContextMenuHint,
  commentaryHint,
}

class LiveTipStorage {
  static const String resolvedTipsKey = 'live_tips_resolved';

  static String encode(Set<LiveTipId> tips) {
    final names = tips.map((tip) => tip.name).toList()..sort();
    return names.join(',');
  }

  static Set<LiveTipId> decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <LiveTipId>{};
    }
    final result = <LiveTipId>{};
    for (final name in raw.split(',')) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      for (final tip in LiveTipId.values) {
        if (tip.name == trimmed) {
          result.add(tip);
          break;
        }
      }
    }
    return result;
  }
}

enum TourInteractionType {
  currentTabChanged,
  openedTextBook,
  readerPositionChanged,
  sideBySideEnabled,
  textSelected,
  dictionaryUsed,
  commentaryAvailable,
  commentaryUsed,
}

class TourInteraction extends Equatable {
  final TourInteractionType type;
  final DateTime timestamp;
  final String? primaryValue;

  TourInteraction({
    required this.type,
    DateTime? timestamp,
    this.primaryValue,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [
        type,
        timestamp.millisecondsSinceEpoch,
        primaryValue,
      ];
}

class LiveTipSpec extends Equatable {
  final LiveTipId id;
  final TourSpotlightArea area;
  final String title;
  final String description;

  const LiveTipSpec({
    required this.id,
    required this.area,
    required this.title,
    required this.description,
  });

  @override
  List<Object?> get props => [id, area, title, description];
}

const List<LiveTipSpec> liveTipSpecs = [
  LiveTipSpec(
    id: LiveTipId.sideBySideSuggestion,
    area: TourSpotlightArea.tabs,
    title: 'השוואה בין שני ספרים',
    description:
        'נראה שאתה מדלג שוב ושוב בין אותם ספרים. לחץ לחיצה ימנית על אחת הלשוניות כאן ובחר "הצג לצד".',
  ),
  LiveTipSpec(
    id: LiveTipId.dictionaryContextMenuHint,
    area: TourSpotlightArea.reading,
    title: 'יש כאן פירוש זמין למילה שסימנת',
    description:
        'למילה המסומנת יש כאן פתיחת ראשי תיבות או פירוש מארמית. לחץ עליה בלחיצה ימנית כדי לראות את האפשרות עצמה.',
  ),
  LiveTipSpec(
    id: LiveTipId.commentaryHint,
    area: TourSpotlightArea.commentators,
    title: 'כדאי לפתוח מפרשים',
    description:
        'לספר הזה יש מפרשים זמינים. אפשר לפתוח את סרגל הצד בלחצן הסמוך ולעבוד מהר יותר.',
  ),
];

LiveTipSpec liveTipSpecById(LiveTipId id) {
  return liveTipSpecs.firstWhere((tip) => tip.id == id);
}
