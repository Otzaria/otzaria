// לתחזוקת טיפים חיים ראו: docs/guided_tour_developer_guide.md

import 'package:equatable/equatable.dart';
import 'package:otzaria/tour/models/tour_step.dart';

enum LiveTipId {
  sideBySideSuggestion,
  dictionaryContextMenuHint,
  commentaryHint,
  customFoldersHint,
  bookSourceHint,
  shortcutsHint,
  printHint,
  backupHint,
}

class LiveTipStorage {
  static const String resolvedTipsKey = 'live_tips_resolved';

  /// מונה כמה פעמים נפתחה התוכנה, לתזמון טיפים מבוססי-ותק שימוש.
  static const String launchCountKey = 'live_tips_launch_count';

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
  bookSourceViewed,
  printUsed,
  shortcutsSettingsOpened,
  systemSettingsOpened,
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
        'לספר הזה יש מפרשים זמינים. אפשר לפתוח את סרגל הצד בלחצן הסמוך ולעיין יותר.',
  ),
  LiveTipSpec(
    id: LiveTipId.customFoldersHint,
    area: TourSpotlightArea.navigation,
    title: 'הידעת?',
    description:
        'כותבים חידושי תורה? אפשר להציג אותם בתוך אוצריא ואף לחפש בהם. הוסיפו את '
        'התיקיה שלכם דרך הגדרות ← ספרייה ← תיקיות מותאמות אישית. כל הקבצים שבתיקיה '
        '(כולל Word ו-TXT) יתווספו ל"ספרים אישיים", והחיפוש יסרוק אותם אוטומטית. '
        'כדי לאתר אותם באיתור — סמנו "כלול ספרים אישיים".',
  ),
  LiveTipSpec(
    id: LiveTipId.bookSourceHint,
    area: TourSpotlightArea.reading,
    title: 'הידעת?',
    description:
        'בכל ספר פתוח אפשר ללחוץ על "אודות הספר" שבסרגל הכלים ולראות מהיכן הגיע '
        'הטקסט. כך תדעו למי לפנות אם מצאתם טעות בספר.',
  ),
  LiveTipSpec(
    id: LiveTipId.shortcutsHint,
    area: TourSpotlightArea.settings,
    title: 'הידעת?',
    description:
        'כמעט לכל פעולה באוצריא יש קיצור מקלדת, ואפשר גם להתאים אותו אישית. '
        'היכנסו להגדרות ← קיצורי מקלדת כדי לצפות בכל הקיצורים ולשנות אותם '
        'להרגלי העבודה שלכם.',
  ),
  LiveTipSpec(
    id: LiveTipId.printHint,
    area: TourSpotlightArea.print,
    title: 'הידעת?',
    description:
        'אפשר להדפיס את הפרק הנוכחי ישירות מסרגל הכלים של הספר — כולל '
        'המפרשים המוצגים. לחצו על כפתור ההדפסה ובחרו את הפורמט המתאים.',
  ),
  LiveTipSpec(
    id: LiveTipId.backupHint,
    area: TourSpotlightArea.settings,
    title: 'הידעת?',
    description:
        'אוצריא מגבה אוטומטית את הסימניות, ההיסטוריה וההערות שלך. '
        'בהגדרות ← מערכת אפשר לייצא את הגיבוי לקובץ ולשחזר אותו בכל עת — '
        'גם לאחר התקנה מחדש.',
  ),
];

LiveTipSpec liveTipSpecById(LiveTipId id) {
  return liveTipSpecs.firstWhere((tip) => tip.id == id);
}
