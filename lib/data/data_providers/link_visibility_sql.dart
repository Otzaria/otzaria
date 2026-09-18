/// שברי ה-SQL של נראות-קישורים פר-צד (סכמה 3, טבלת `link_suppressed_side`).
///
/// מופרדים מ-`database_library_provider.dart` כדי שיהיו ניתנים לבדיקה: שם הם
/// מוזרקים לתוך שאילתות שרצות ב-isolate מול DB בן ג'יגה-בייטים.
///
/// מוסכמת הצדדים זהה ל-`link_anchor`/`link_range`: ‏0 = צד המקור השמור,
/// ‏1 = צד היעד. השאילתה הקדמית מציגה את צד 0, ההפוכה את צד 1.
///
/// בסכמה 3 הפניות נקראות בשני הכיוונים, וכל צד מסונן לפי verdict משלו.
library;

/// נקודת ההזרקה בשאילתות סטטיות שצריכות להישאר תקינות גם מול סכמה 2.
const linkVisibilityFilterMarker = '/*LINK_VISIBILITY_FILTER*/';

/// מסנן את הצד שספריא אינה מציגה. [displayedSide] הוא הצד שהשורה שלו מוצגת.
String suppressedSideFilter(
  bool hasSuppressedSide, {
  required int displayedSide,
}) => hasSuppressedSide
    ? 'AND NOT EXISTS (SELECT 1 FROM link_suppressed_side ss '
          'WHERE ss.linkId = l.id AND ss.side = $displayedSide)'
    : '';

/// בשאילתה ההפוכה קישור תלוי-טקסט מוצג כ-SOURCE הווירטואלי ("מה זה מפרש"),
/// אבל הפניה צדדית שעולה מהצד השני היא עדיין אותה הפניה — לא מקור. שימור
/// הסוג האמיתי משאיר אותה בפאנל הקישורים במקום להזריק אותה לפאנל המפרשים.
String inverseConnectionTypeExpr(List<String> dependentTypes) {
  final quoted = dependentTypes.map((t) => "'$t'").join(', ');
  return "CASE WHEN ct.name IN ($quoted) THEN 'SOURCE' ELSE ct.name END";
}
