# מקור החבילה והתיקון המקומי

החבילה מבוססת על `irondash_engine_context 0.5.5` מ־Pub, תחת רישיון MIT.
כל 68 הקבצים המקוריים, קובצי הרישיון והרשאות ההרצה נשמרו בקומיט הייבוא
הנפרד.

- מקור: <https://github.com/irondash/irondash>
- ארכיון: <https://pub.dev/api/archives/irondash_engine_context-0.5.5.tar.gz>
- SHA-256: `2bb0bc13dfda9f5aaef8dde06ecc5feb1379f5bb387d59716d799554f3f305d7`

## ההבדל המקומי

רק `cargokit/gradle/plugin.gradle`, כדי שהבנייה תעבור עם AGP 9 ו־Gradle 9:

- compileSdk 37 מגיע כ־`android-37.0`; מפרשים רק את המספר הראשי.
- `project.exec` הוסר ב־Gradle 9; המשימה משתמשת ב־`ExecOperations` מוזרק.

הבעיה פתוחה ב־upstream (irondash/irondash#95). ב־main של upstream Cargokit
הוחלף ב־native assets (irondash/irondash#90), וזה שוחרר רק כ־0.6.0-dev.0;
מאגר irondash/cargokit עצמו בארכיון. סקריפט ה־Gradle אינו חלק מ־crate hash,
ולכן הבינארים החתומים של 0.5.5 עדיין מתאימים.

## אימות

`python3 tool/verify_vendored_packages.py --package irondash_engine_context`
מאמת את הארכיון ואת כל הקבצים המנוהלים, ומרשה שינוי רק בקובץ שלעיל.

`super_native_extensions 0.9.1` דורש `irondash_engine_context ^0.5.5`, ולכן הסרת
ה־override לבדו תחזיר את 0.5.5 השבורה מ־Pub. מסירים אותו רק יחד עם המעבר ל־
`super_native_extensions` / `super_clipboard` ‏0.10 יציבה (תלויה ב־irondash ‏^0.6),
כולל העותק, החרגת הניתוח והאימות, ומעדכנים את ה־lockfile.
