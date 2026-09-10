# issue #1318 — כפתורי כרטיס הסיור גולשים מהכרטיס במסך צר

תאריך: 2026-09-10 | ענף: `fix/tour-welcome-buttons-overflow-1318` | בסיס: `upstream/dev` (8c365b5cd) | קומיט אימות: `4c26dacca`

## הבאג שאומת

אמולטור Android 14 (1080×2400), התקנה נקייה במצב אנגלית: כרטיס "Welcome to Otzaria" עם פס
"RIGHT OVERFLOWED BY 60 PIXELS" וכפתור "Let's Begin" חתוך. המקור: `Row` קשיח ב-`TourTooltipCard`.

## התיקון

`OverflowBar` (spaceBetween; בגלישה — יישור לסוף, ריווח 8): כשיש מקום הפריסה זהה; כשאין, "דלג" וקבוצת
"הצגה אוטומטית + הבא" יורדים לשורות נפרדות. חל על כל מצבי הכרטיס.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/tour/widgets/tour_welcome_card_narrow_test.dart` | חדש: כרטיס הפתיחה ברוחב 320 בעברית ובאנגלית — ללא חריגת RenderFlex, הכפתורים קיימים. על הבסיס: "overflowed by 180 / 420 pixels". |

`flutter test test/tour/widgets/`: **7 עברו**. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

APK debug של הבסיס ושל הענף על האמולטור, אנגלית (`tour_status` אופס כדי להציג שוב את כרטיס הפתיחה). לפני: גלישה;
אחרי: "Skip — I'll Explore On My Own" בשורה אחת ו-"Let's Begin" מתחתיו, בלי חיתוך. הצילומים בענף `pr-screenshots`
(תיקייה `1318`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לסוויטה נוספת ולאמולטור): **12,623 עברו, 23 דולגו, 10 נכשלו** — תשעת כשלי הבסיס
המוכרים + `single_window_regression_test` רגיש-עומס שעבר בבידוד (6 עברו).
