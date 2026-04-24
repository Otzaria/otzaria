import 'package:otzaria/product_tour/models/product_tour_models.dart';

/// שלבי הסיור הראשוני שמופיעים למשתמש חדש.
const List<TourStepSpec> kIntroTourSteps = [
  TourStepSpec(
    id: 'find-ref',
    targetId: TourTargetId.findRefField,
    title: 'איתור מקור מדויק',
    description:
        'כאן אפשר להקליד מקור מדויק ולקפוץ ישר אליו. לדוגמה, כבר מילאנו בשבילך: שו"ע או"ח סימן קיט.',
  ),
  TourStepSpec(
    id: 'full-search',
    targetId: TourTargetId.searchDialogField,
    title: 'חיפוש מתקדם',
    description:
        'כאן בוחרים סוג חיפוש ומתאימים את החיפוש לשאלה שלך: מילים, ביטויים, וצורות חיפוש נוספות.',
  ),
  TourStepSpec(
    id: 'reading-view-mode',
    targetId: TourTargetId.readingViewMode,
    title: 'מצבי תצוגה ומפרשים',
    description:
        'מהכפתור הזה מחליפים בין מצבי קריאה שונים, ופותחים עבודה נוחה יותר עם מפרשים.',
  ),
];

/// טיפים חיים קצרים שמופיעים רק כשהם רלוונטיים.
const List<LiveTipSpec> kLiveTips = [
  LiveTipSpec(
    id: LiveTipId.sideBySideSuggestion,
    targetId: TourTargetId.readingTabsBar,
    title: 'השוואה בין שני ספרים',
    description:
        'נראה שאתה מדלג שוב ושוב בין אותם ספרים. לחץ לחיצה ימנית על אחת הלשוניות כאן ובחר "הצג לצד".',
  ),
  LiveTipSpec(
    id: LiveTipId.dictionaryContextMenuHint,
    targetId: TourTargetId.readingContent,
    title: 'יש כאן פירוש זמין למילה שסימנת',
    description:
        'למילה המסומנת יש כאן פתיחת ראשי תיבות או פירוש מארמית. לחץ עליה בלחיצה ימנית כדי לראות את האפשרות עצמה.',
  ),
  LiveTipSpec(
    id: LiveTipId.commentaryHint,
    targetId: TourTargetId.readingViewMode,
    title: 'כדאי לפתוח מפרשים',
    description:
        'לספר הזה יש מפרשים זמינים. אפשר לעבור מכאן לתצוגה שמבליטה אותם ולעבוד מהר יותר.',
  ),
];

/// מחזירה את מפרט הטיפ לפי מזהה.
LiveTipSpec liveTipSpecById(LiveTipId id) {
  return kLiveTips.firstWhere((tip) => tip.id == id);
}
