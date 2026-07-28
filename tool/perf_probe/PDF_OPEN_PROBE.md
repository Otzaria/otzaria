# אבחון פתיחת PDF

הקובץ `pdf_real_file_open_probe.dart` הוא כלי מדידה ידני, לא טסט רגרסיה.
הזמנים מודפסים כרשומות `PDF_PERF` ואינם משמשים כתנאי הצלחה.

הרצה סינתטית שאינה נוגעת במסד או בספריית המשתמש:

```powershell
flutter test tool/perf_probe/pdf_real_file_open_probe.dart
```

מדידת PDF אמיתי וקישורי האפליקציה:

```powershell
$env:OTZARIA_PDF_PROBE_MODE = 'real'
$env:OTZARIA_TALMUD_PDF = 'D:\library\תלמוד בבלי\זבחים.pdf'
$env:OTZARIA_TALMUD_TARGET_PAGE = '201'
$env:OTZARIA_LIBRARY_PATH = 'D:\library'
$env:OTZARIA_LIBRARY_FOLDER = 'otzaria'
flutter test tool/perf_probe/pdf_real_file_open_probe.dart
```

רפרודוקציה ל־pdfrx #586:

```powershell
$env:OTZARIA_PDF_PROBE_MODE = 'issue586'
$env:OTZARIA_ISSUE_586_PDF = 'D:\library\תלמוד בבלי\זבחים.pdf'
$env:OTZARIA_ISSUE_586_TARGET_PAGE = '229'
flutter test tool/perf_probe/pdf_real_file_open_probe.dart
```

המצבים האפשריים הם `synthetic` (ברירת המחדל), `real`, `issue586` ו־`all`.
במצבים התלויים בקבצים אמיתיים, קלט חסר או נתיב שגוי גורמים לכשל מפורש.
