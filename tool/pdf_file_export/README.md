# בדיקת ייצוא PDF לקובץ ב־iOS

ה־workflow `PDF file export (iOS UIKit and Files)` בונה את Runner האמיתי עם
Flutter 3.47.7 וה־lockfile של המאגר. הוא מפעיל scheme ייעודי בשם
`PdfFileExport`, ללא שינוי ב־scheme הרגיל או בבדיקות Runner הקיימות.
`flutter build ios --config-only` מכין גם את תלויות CocoaPods ו־SPM לפני Xcode;
אין הרצת `pod install` נוספת מתיקיית המאגר.

## שתי שכבות הראיה

- `PdfFileExportTests` משתמש ב־UIKit, במערכת הקבצים ובמנועי Flutter אמיתיים.
  הבדיקות שולטות ב־delegate callbacks כדי לבדוק סדר אירועים: ACK לביטול אינו
  משחרר את המקור; סיום שמירה מאוחר נשמר; cleanup ממתין לסיום dismissal; ניתוק
  scene או מנוע אינו משאיר קובץ בשימוש שנמחק מוקדם. אלה בדיקות חוזה, והן אינן
  הוכחה לפעולה של ספק Files.
- `PdfFileExportUITests` מפעיל את הבורר המערכתי עצמו דרך
  `MobilePdfExportService.instance`. בדיקה אחת שומרת PDF סינתטי באמצעות
  `On My iPhone`, והשנייה מבטלת דרך Cancel או מחוות סגירת ה־sheet במערכת
  שאינה מציגה כפתור ביטול. אין החלפה של MethodChannel או של
  callback בבדיקות אלה. ה־probe מאמת את SHA-256 של הקובץ שנשמר, את השם והנתיב
  שהוחזרו מהיעד ואת פינוי staging לאחר התוצאה הסופית.

תיקיית `Documents/OtzariaExportUITest` נוצרת רק בכניסת הבדיקה
`integration_test/pdf_file_export_ios_app.dart`. היא משתמשת בחשיפת Files שכבר
מופעלת ב־Info.plist של האפליקציה; הבדיקה אינה מוסיפה הרשאה לגרסת הייצור.
כניסת הבדיקה דורשת גם `PDF_FILE_EXPORT_IOS_PROBE=true` וגם iOS.
התרחיש נבחר באמצעות כפתור מפורש באפליקציית הבדיקה, ואינו תלוי בחשיפת
משתני הסביבה של XCTest ל־Dart. כל תרחיש שומר קבלה נפרדת בשמו.

## הרצה ובדיקת התוצרים

במחשב macOS עם Xcode, CocoaPods, Rust וה־SDK המוצמד:

```sh
python3 tool/pdf_file_export/ios_export_runner.py \
  --source "$PWD" --root "$RUNNER_TEMP/pdf-file-export-ios" \
  --commit "$(git rev-parse HEAD)"
```

הכלי מיועד ל־CI ודורש `GITHUB_RUN_ID` ו־`GITHUB_RUN_ATTEMPT` לזיהוי ה־Simulator
שבבעלותו. הוא יוצר מכשיר חדש מתוך runtime של iOS שכבר מותקן, ואינו משנה או
מוחק מכשירי Simulator קיימים. בסיום הוא מאמת שוב את ה־UUID, השם, ה־runtime
והדגם לפני מחיקת המכשיר שלו. לכל פקודה ארוכה יש deadline; timeout נשמר ככישלון.

התוצר כולל source commit/tree, hashes של קובצי המימוש והבדיקה לפני ואחרי
הבנייה, Flutter/Xcode/host, פקודות וקודי יציאה, לוגי XCTest, `xcresult` ושתי
קבלות JSON של ה־probe. שינויים ש־CocoaPods יוצר בגרף הפרויקט נשמרים בדיפ
נפרד; קוד Swift/Dart וה־pins חייבים להישאר זהים. הארטיפקט אינו כולל את
DerivedData, את container האפליקציה או את קובצי ה־PDF הסינתטיים.

`validate_ios_export.py` דורש שכל `test...` בשתי מחלקות XCTest הנוכחיות יופיע
פעם אחת כהצלחה, ללא skips או retries שמסתירים כישלון. הוא בודק בנפרד את שתי
קבלות Files, את גרסת ה־SDK ואת הניקוי. summary נכתב רק אחרי שכל אלה עברו.

בדיקות הכלים עצמן אינן דורשות macOS:

```sh
python3 -m unittest discover -s tool/pdf_file_export -p 'test_*.py' -v
```

הבדיקה מכסה Simulator וספק Files המקומי. היא אינה מחליפה QA במכשיר פיזי,
ב־iCloud או בספק צד שלישי, ואינה מודדת חיסכון כולל בזיכרון. קובץ המקור כבר
קיים בדיסק לפני שהבורר נפתח; ה־channel מעביר נתיב ומטא־נתונים בלבד.
