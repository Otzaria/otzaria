#ifndef RUNNER_SPLASH_WINDOW_H_
#define RUNNER_SPLASH_WINDOW_H_

// חלון splash נייטיב (Win32): חלון שכבת-אלפא (layered), שקוף, click-through
// וללא-מסגרת, המציג את סמל האפליקציה הצף ממורכז על המסך הראשי, עם אנימציות
// fade-in (הופעה) ו-fade-out (סגירה). הוא נפרד מחלון ה-Flutter הראשי — ולכן
// הסמל יציב, לא זז ולא נעלם, בעוד החלון הראשי נשאר מוסתר עד שתוכנו מוכן ואז
// נפתח ישר בגבולותיו הסופיים (ללא קפיצה/פער).
//
// **Thread ייעודי:** החלון נוצר ומנוהל על thread נפרד משלו, עם לולאת הודעות
// משלו — כך DWM מרכיב אותו והאנימציה רצה גם בזמן שה-thread הראשי עסוק באתחול
// מנוע Flutter. כדי שיצירת החלון לא תתעכב על ה-loader lock (DLL_THREAD_ATTACH
// בזמן טעינת ה-DLLs של המנוע), [Show] מחזיק "מחסום": הוא ממתין שה-thread ייצור
// את החלון ויסיים את ה-fade-in *לפני* שהמנוע מתחיל לטעון DLLs.
//
// [Show] נקרא מ-wWinMain (לפני אתחול המנוע). [Close] נקרא מה-platform thread
// דרך ה-method channel "otzaria/splash" בעת חשיפת החלון הראשי, ומסמן ל-thread
// של ה-splash (דרך אירוע) לבצע fade-out ולהיהרס. (אין סגירה מ-OnDestroy — הוא
// נורה מזויף בתחילת window.Create וסוגר את ה-splash מוקדם מדי.)
namespace splash {

// יוצר את ה-thread, ומציג את חלון ה-splash עם אנימציית fade-in (סינכרונית, בזמן
// המחסום). נקרא פעם אחת ב-wWinMain, לפני אתחול מנוע Flutter, למשוב ויזואלי מיידי.
// במקרה כשל (למשל פענוח ה-PNG נכשל) — no-op; האפליקציה ממשיכה ללא splash.
void Show();

// מסמן ל-thread של ה-splash לבצע fade-out (ובסיומו להרוס את החלון). אינו חוסם
// ואינו ממתין. אידמפוטנטי. נקרא מה-platform thread דרך ה-channel "otzaria/splash"
// בעת חשיפת החלון הראשי.
void Close();

// האם קיים חלון splash של אוצריא כלשהי — גם של תהליך אחר. מופע שני משתמש בזה
// כדי להבחין בין מופע ראשון שעדיין באתחול לבין כזה שחלונו מוסתר שלא כדין.
bool IsAnyInstanceShowing();

}  // namespace splash

#endif  // RUNNER_SPLASH_WINDOW_H_
