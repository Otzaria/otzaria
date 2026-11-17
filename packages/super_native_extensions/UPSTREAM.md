# מקור החבילה והתיקון המקומי

החבילה מבוססת על `super_native_extensions 0.9.1` מ־Pub, תחת רישיון MIT.
כל 247 הקבצים המקוריים, שני קובצי הרישיון והרשאות ההרצה נשמרו בקומיט
הייבוא הנפרד. `super_clipboard` נשאר בגרסת Pub ‏0.9.1.

- מקור: <https://github.com/superlistapp/super_native_extensions>
- ארכיון: <https://pub.dev/api/archives/super_native_extensions-0.9.1.tar.gz>
- SHA-256: `b9611dcb68f1047d6f3ef11af25e4e68a21b1a705bbcc3eb8cb4e9f5c3148569`

## ההבדל המקומי

היסטוריית הלוח של Windows יכולה להציע תמונה דרך `IDataObject` כ־
`CF_BITMAP / TYMED_GDI` בלבד. הקורא המקורי מסנן פורמט זה ולכן לא מציע
אותו ל־Flutter כתמונה. התיקון מוגבל לקבצי Windows הבאים:

- `rust/src/win32/reader.rs`: זיהוי הפורמט, העתקת התמונה מאובייקט המקור,
  שחרור ה־`STGMEDIUM` והמרה ב־worker עם אתחול COM. אין קריאה מחדש מהלוח
  הגלובלי. נשמרת הקדימות PNG, ‏DIBV5, ‏DIB ולבסוף BITMAP.
  מעטפת BMP של DIB מקבלת היסט פיקסלים לפי הכותרת, מסכות וטבלת צבעים.
  נתמכות כותרות CORE, ‏INFO, ‏V4 ו־V5; מבנה לא מוכר או חתוך נדחה.
  פרופיל V5 ארוז נבדק אחרי הפיקסלים ואינו נוסף להיסט.
- `rust/src/win32/image_conversion.rs`: המרת עותק ה־HBITMAP ל־PNG דרך WIC.
  התעלמות מאלפא מוגבלת ל־CF_BITMAP, שאינו מגדיר ערוץ אלפא.
- `rust/src/win32/bitmap_reader_tests.rs`: בדיקות Windows של פיקסלים, בעלות,
  שחרור משאבים, קדימות, אלפא, GIF וטקסט.

- `rust/src/win32/drag.rs`: לפני `DoDragDrop` נבדק מצב הכפתור הראשי עם
  `GetAsyncKeyState`, בהתאם ל־`SM_SWAPBUTTON`. אם שוחרר בזמן הכנת/סריאליזציית
  הבקשה, הגרירה מסתיימת ב־`UserCancelled` במסלול הניקוי הרגיל, בלי drop.
  ה־`DataObject` וה־provider handles משתחררים כרגיל. אין שינוי ב־API של Dart.
  מיפוי הכפתור הפיזי לפי תיעוד Microsoft:
  <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getasynckeystate>.

- `lib/src/native/drag.dart`: ביטול session בהכנה נבדק שוב אחרי סריאליזציה
  ולפני מסירת הבקשה ל־native. `dragStarted` מציין שהבקשה כבר נמסרה;
  `cancelSession` אינו משחרר session אחרי נקודת העברת הבעלות. זו הרחבת
  סמנטיקת `dragStarted` במימוש native בלבד; אין קורא קיים אחר של getter זה
  בקוד המשובץ. מימוש web ללא שינוי והמחווה מוגבלת ל־Windows native.
  כך גם שחרור ולחיצה מחדש או פירוק widget בזמן ההכנה מבטלים את הגרירה הישנה.
  אין שינוי בחתימות ה־API.

## אימות ובנייה

`python3 tool/verify_super_native_extensions.py` מאמת את הארכיון ואת כל
הקבצים המנוהלים, ומרשה שינויים רק בארבעת קובצי המוצר שלעיל ובסקריפט ה־Gradle
של Cargokit (בהמשך). תיקון Dart זה נבדק ב־`flutter analyze packages/super_native_extensions/lib/src/native/drag.dart`
ובבדיקות transport של האפליקציה. שאר קוד Dart
המקורי מוחרג מה־formatter ומה־analyzer של האפליקציה; קוד האפליקציה ממשיך
לעבור אותם, וקוד Rust המתוקן עובר rustfmt ובדיקות Windows ב־CI.
אפשר להעביר `--archive /path/to/archive.tar.gz` לצורך אימות ללא הורדה נוספת.

מתוך `packages/super_native_extensions/rust`, ב־Windows:

```powershell
cargo test --locked bitmap_reader_tests -- --test-threads=1 --nocapture
```

בדיקת החלפת הלוח דורשת לוח ריק, מאמתת זאת לפני כל שינוי ומנקה את נתוני
הבדיקה גם כשבדיקת הפיקסלים נכשלת. לוח שאינו ריק גורם לכישלון ללא החלפתו.

`cargokit/gradle/plugin.gradle` תוקן עבור AGP 9 ו־Gradle 9: גרסת compileSdk
מגיעה כ־`android-37.0`, ו־`project.exec` הוסר ב־Gradle 9 (משתמשים ב־`ExecOperations`).
זה תואם לבעיה הפתוחה superlistapp/super_native_extensions#565; ב־upstream
Cargokit הוחלף ב־native assets (‏#595), בגרסת 0.10.0-dev בלבד.

השינוי במקור Rust משנה את crate hash; בינארי מוכן
של 0.9.1 המקורית אינו מתאים לו. בהיעדר בינארי חתום תואם, Cargokit בונה
מהמקור ולכן נדרש Rust toolchain גם בבניות שאר הפלטפורמות.

לאחר שחרור חבילה רשמית עם תמיכה זו, אפשר להסיר יחד את ה־override, העותק,
החרגת הניתוח והאימות הייעודי, ולעדכן את ה־lockfile. יש להריץ שוב את בדיקות
הלוח והבניות הנתמכות לפני ההחלפה.
