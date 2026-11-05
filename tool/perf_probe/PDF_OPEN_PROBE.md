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

## תצוגה מקדימה להדפסה

`pdf_print_preview_probe.dart` מפריד בין עלות פתיחה, רינדור, יצירת `ui.Image`,
קידוד PNG ופענוחו. מצב `controller` מריץ את `PrintPreviewController` של האפליקציה,
כולל חלון העמודים, תקציב הזיכרון והביטול. מצבי `png` ו־`direct` הם השוואה ממוקדת
של שלבי הצינור; `png` משמר את מסלול ההשוואה מ־`dev@2ba2e6d76`.

יצירת קלט נפרד מבטיחה שזיכרון יצירת ה־fixtures אינו נספר במדידת התצוגה:

```powershell
dart run tool/perf_probe/make_pdf_print_preview_fixtures.dart .dart_tool/pdf-preview-fixtures
$env:OTZARIA_PREVIEW_PDF = (Resolve-Path .dart_tool/pdf-preview-fixtures/scanned.pdf).Path
$env:OTZARIA_PREVIEW_SOURCE = 'bytes'
$env:OTZARIA_PREVIEW_PIPELINE = 'png'
$env:OTZARIA_PREVIEW_LIMIT = '60'
flutter test tool/perf_probe/pdf_print_preview_probe.dart --enable-vmservice --no-dds --concurrency=1

$env:OTZARIA_PREVIEW_SOURCE = 'file'
$env:OTZARIA_PREVIEW_PIPELINE = 'controller'
flutter test tool/perf_probe/pdf_print_preview_probe.dart --enable-vmservice --no-dds --concurrency=1
```

המחולל יוצר `small.pdf` בן 3 עמודים, `mixed.pdf` בן 600 עמודים בארבעה גדלים,
ו־`scanned.pdf` בן 120 עמודים עם תמונות רעש סינתטיות; אין בו תוכן מהספרייה.
יש להריץ כל מצב בתהליך נפרד, לפחות שלוש פעמים, ולדווח את הסביבה והשונות.
זהו probe של Flutter test במצב debug, לא benchmark של חלון האפליקציה ב־release.

| משתנה | משמעות |
|---|---|
| `OTZARIA_PREVIEW_SOURCE` | `bytes` קורא ושומר את הקובץ ב־Dart; `file` משתמש ב־`openFile` |
| `OTZARIA_PREVIEW_PIPELINE` | `png`, `direct`, או `controller` |
| `OTZARIA_PREVIEW_START` | עמוד מקור ראשון, החל מ־1 |
| `OTZARIA_PREVIEW_LIMIT` | מספר עמודים לרינדור ב־`png`/`direct`, ברירת מחדל 60 |
| `OTZARIA_PREVIEW_END` | עמוד סיום כולל ב־`controller`; ללא הגדרה עד סוף הקובץ |
| `OTZARIA_PREVIEW_VISIBLE` | כמה תמונות PNG מפוענחות, ברירת מחדל 2 כדי להתאים לגיליון יחיד ושכן ב־controller; יתר ה־PNG נשמרים דחוסים |
| `OTZARIA_PREVIEW_NUP` | עמודים בגיליון ב־`controller`, ברירת מחדל 1 |
| `OTZARIA_PREVIEW_SCROLL_SHEETS` | ב־`controller`: אינדקסי גיליונות החל מ־0, למשל `0,40,0`; כל מעבר כולל פתיחה מחדש, metadata, רינדור וסגירה |
| `OTZARIA_PREVIEW_BUDGET_MIB` | תקציב תמונות, ברירת מחדל 32 MiB |
| `OTZARIA_PREVIEW_SCALE` | קנה מידה ב־`png`/`direct`, ברירת מחדל 1.5; ה־controller קובע גודל לפי התקציב |
| `OTZARIA_PREVIEW_CANCEL` | `none`, `after-render`, או `during-render` |
| `OTZARIA_PREVIEW_RESULT` | נתיב אופציונלי ל־JSON של ההרצה |

למדידת טווח קצר בקובץ גדול יש לקבוע `START=80`, ‏`LIMIT=2` ו־`END=81`.
ביטול `after-render` מופעל לפני ההמרה ל־PNG בהשוואת השלבים, ואחרי פרסום התמונה
הראשונה ב־controller. ביטול `during-render` נשלח אחרי 1 ms מתחילת פעולת הרינדור
בהשוואת השלבים, ומבקשת הטעינה ב־controller. אין להשוות נקודות ביטול שונות כאילו היו זהות.
הביטול ב־controller הוא `reset()` של generation; סגירת נתיב מפעילה `stop()` ומשאירה
תמונות קיימות עד סוף אנימציית הסגירה, ולכן אין להציג את זמן ה־reset כזמן אנימציית סגירה.

הרשומות מתחילות ב־`PDF_PRINT_PREVIEW_PERF`. ‏`firstPreviewAvailableUs` הוא פרסום
ה־PNG הראשון במסלול הישן (גם הוא מפרסם כל עמוד מיד), או התמונה הראשונה במטמון
ה־controller. ‏`firstImageReadyUs` מודד תמונה מוכנה לצריכה אחרי decode אם נחוץ,
ולא את הציור הראשון למסך. פענוח PNG נראים חופף לרינדור העמודים הבאים; אין כאן
מדידה של תזמון widget או frame. ‏`totalUs` כולל סגירת המסמך והשלמת הפענוחים
הנראים; ב־controller הוא כולל גם מעברי גיליון שהתבקשו. זמן החלון הראשוני נרשם
בנפרד. אין במדידה זמן יצירת ה־fixtures או חיבור הפרופיילר.
RSS ו־Linux private resident הם מדידות של **כל התהליך**,
ולא מדידת native נפרדת או Windows private commit. שיא התהליך המצטבר מסומן בנפרד
מ־peak שנדגם כל 10 ms. ב־Windows יש להשלים private memory באמצעות
`sample_resources.ps1`/כלי המערכת; אין להסיק אותה מ־RSS.

נתוני allocations, כאשר VM service תומך בהם, הם של Dart isolate הנוכחי וכוללים
את ה־harness; הם אינם כוללים הקצאות של worker, ‏PDFium או GPU. שדות חסרים נשארים
`null`. גם העתקות הרשימה ב־ValueNotifier ועבודת ה־widgets/ImageCache של המסך הישן
אינן נמדדות. אומדן המטמון של ה־controller (8 bytes לפיקסל שמור ו־4 נוספים בזמן
רינדור) שונה מסכום הפיקסלים במצב `png`/`direct` (4 bytes), ואינו מדידת זיכרון native.
יש להשוות RSS/private שנמדדו, כולל ההפרש משורת הבסיס של כל תהליך. אין ספי זמן ב־CI.
תוצאות מדידה של Flutter על Linux, כולל חזרות, טווחי ערכים, hashes, תרחישי ביטול
ופתיחה מחדש, נמצאות ב־
[`results/pdf_print_preview_flutter_linux_20261105.json`](results/pdf_print_preview_flutter_linux_20261105.json).
ההרצה המתועדת השתמשה ב־`flutter_tester` ישיר עם אותו גוף probe; פרטי הקומפילציה
ב־JSON. אלה מדידות headless/JIT, לא התחייבות לזמני release או Windows.

### בידוד פתיחת הקובץ ב־PDFium ללא Flutter (Linux)

כשנדרשת הפרדה מעלות Flutter, אפשר להריץ את אותו PDFium ישירות בתהליך Python
נפרד, בלי תלות בחבילות Python נוספות:

```bash
python3 tool/perf_probe/native_pdf_print_preview_probe.py \
  --library build/native_assets/linux/libpdfium.so \
  --file .dart_tool/pdf-preview-fixtures/scanned.pdf \
  --source file --start 80 --count 2
```

יש לחזור עם `--source bytes`. מסלול זה מחזיק את הקובץ ואת העותק שנמסר ל־native
עד סגירת המסמך. הניסוי מודד את פתיחת PDFium, קריאת ממדי העמודים ורינדור
bitmap, ומפיק hash של הפיקסלים לבדיקת זהות בין המסלולים. ברירת המחדל
`--metadata all` קוראת ממדים לכל המסמך; `--metadata selected` קוראת רק את העמוד
הראשון ואת הטווח המבוקש, כדי לבודד את עלות פתיחת הטווח. מדידות התהליך כוללות
גם Python. הוא אינו מפעיל את ה־controller, אינו מודד מטמון תצוגה, `ui.Image`,
PNG, ציור למסך, ביטול או allocations של Dart, ואינו תחליף להרצת ה־Flutter probe.
תוצאות Linux, פרטי הסביבה, חזרות ו־hashes נשמרו ב־
[`results/pdf_print_preview_native_linux_20261105.json`](results/pdf_print_preview_native_linux_20261105.json).
