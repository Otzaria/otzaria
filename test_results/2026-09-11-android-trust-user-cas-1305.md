# issue #1305 — הורדה נכשלת ב-CERTIFICATE_VERIFY_FAILED ברשת מסוננת באנדרואיד

תאריך: 2026-09-11 | ענף: `fix/android-trust-user-cas-1305` | בסיס: `upstream/dev` (8c365b5cd) | קומיט אימות: `28dd83bf7`

## הבאג שאומת

הדיווח בפורום: `שגיאה בהורדה: HandshakeException ... CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`
בהורדת הספרייה באנדרואיד ברשת מסוננת. שוחזר באמולטור Android 14: proxy TLS על המארח (mitmproxy, reverse ל-github.com),
כל תעבורת 443 של האורח מופנית אליו ב-iptables DNAT, ותעודת ה-CA של ה-proxy מותקנת במכשיר **כתעודת משתמש בלבד**
(`/data/misc/user/0/cacerts-added/`). הגדרת ספרייה ← "Download Library" ← OK → אותה שגיאה בדיוק.

## המקור

`runtime/bin/security_context_linux.cc` ב-Dart: באנדרואיד שורשי האמון נטענים רק מ-`/system/etc/security/cacerts`.
תעודות שהמשתמש התקין אינן נטענות, ו-`network_security_config` (שכבר מצהיר על `user`) אינו משפיע על BoringSSL של Dart.
האפליקציה מצרפת 21 תעודות "NetFree Sign" לפי ספק ב-`assets/ca/netfree_cas.pem`; מסנן אחר, או ספק נטפרי שאינו ברשימה,
נופל גם כשהדפדפן במכשיר עובד.

## התיקון

- `MainActivity.kt`: ערוץ `otzaria/user_certificates`, שיטה `getUserInstalledCertificates` — קורא את `AndroidCAStore`,
  מסנן כינויי `user:` ומחזיר PEM; רץ על thread נפרד (קריאת המאגר היא I/O).
- `lib/core/user_certificates.dart`: `trustUserInstalledCertificates(context)` — מוסיף כל PEM ל-`SecurityContext`,
  מדלג על תעודה פגומה (`TlsException`), מחזיר 0 מחוץ לאנדרואיד או כשהערוץ אינו מיושם.
- `main.dart` `_loadCerts`: הקריאה אחרי טעינת התעודות המצורפות.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/core/user_certificates_test.dart` | חדש: ערוץ מזויף מחזיר [תעודה, זבל, תעודה] → 2 נוספו בלי חריגה; `isAndroid: false` → אין פנייה לערוץ; ערוץ מחזיר null → 0. התעודה בבדיקה היא CA לבדיקה שנוצר ב-openssl. על הבסיס המודול אינו קיים. |

`flutter test test/core/user_certificates_test.dart`: **3 עברו**. `flutter analyze` על הקבצים שהשתנו: נקי. `dart format`: ללא שינויים.

## אימות ויזואלי

APK debug של הבסיס ושל הענף, אותו אמולטור, אותה הפניית TLS ואותה תעודת משתמש. לפני: הודעת ה-HandshakeException בדיאלוג;
אחרי: ההורדה מתחילה. הצילומים בענף `pr-screenshots` (תיקייה `1305`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לאמולטור ולבניית APK — 126 דקות): **12,616 עברו, 23 דולגו, 18 נכשלו**. תשעת כשלי
הבסיס המוכרים + תשעה רגישי-עומס שעברו כולם בבידוד (98 עברו): `single_window_regression`, `settings_bloc`,
`text_book_bloc` ×4, `simple_text_viewer_copy_after_right_click`, `text_encoding_performance`, `raised_markers_perf`.
