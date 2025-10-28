# מסמך דרישות: מעבר מ-pdfrx ל-Syncfusion PDF Viewer

## מבוא

פרויקט אוצריא הוא אפליקציית Flutter לספריית ספרים יהודיים עם אפשרויות חיפוש חכם. הפרויקט משתמש כיום בחבילת `pdfrx: ^1.3.2` להצגת קבצי PDF. מטרת התכונה היא להחליף את חבילת pdfrx בחבילת `syncfusion_flutter_pdfviewer` (גרסה 31.2.3 או ישנה יותר במידת הצורך עקב התנגשויות), תוך שמירה על כל הפונקציונליות הקיימת והתאמת הקוד לממשק ה-API החדש.

**הערה חשובה:** לאחר סקירת הקוד הקיים והדוגמאות של Syncfusion, זוהו הבדלים משמעותיים ב-API שידרשו התאמות מעמיקות, במיוחד בתחומי חיפוש הטקסט, תצוגת Thumbnails, וטיפול ב-Annotations.

## מילון מונחים (Glossary)

- **Application**: אפליקציית אוצריא - אפליקציית Flutter לספריית ספרים יהודיים
- **pdfrx Package**: החבילה הנוכחית המשמשת להצגת PDF (גרסה 1.3.2)
- **Syncfusion Package**: החבילה החדשה שתחליף את pdfrx (syncfusion_flutter_pdfviewer גרסה 31.2.3 או ישנה יותר)
- **PDF Viewer**: הרכיב המציג קבצי PDF במסך
- **PDF Controller**: אובייקט השולט בתצוגת ה-PDF (ניווט, זום, וכו')
- **Outline/TOC**: תוכן עניינים היררכי של מסמך PDF
- **Text Search**: פונקציונליות חיפוש טקסט בתוך מסמך PDF
- **Thumbnails**: תצוגת תמונות ממוזערות של דפי PDF
- **Page Converter**: מנגנון המרה בין מספרי דפים של PDF למספרי שורות של ספר טקסט
- **Indexing Repository**: מאגר האחראי על אינדוקס תוכן הספרים לחיפוש
- **PdfBook**: מודל נתונים המייצג ספר בפורמט PDF
- **TextBook**: מודל נתונים המייצג ספר בפורמט טקסט
- **PdfBookTab**: מודל המייצג טאב פתוח עם ספר PDF
- **Ref Helper**: עוזר ליצירת הפניות (references) מתוכן עניינים

## דרישות

### דרישה 1: החלפת תלות החבילה ורישוי

**User Story:** כמפתח, אני רוצה להחליף את תלות pdfrx בתלות syncfusion_flutter_pdfviewer ולהגדיר רישוי, כדי שהאפליקציה תשתמש בספריית PDF החדשה באופן חוקי.

#### קריטריוני קבלה

1. WHEN המפתח מעדכן את קובץ pubspec.yaml, THE Application SHALL הסיר את התלות `pdfrx: ^1.3.2`
2. WHEN המפתח מעדכן את קובץ pubspec.yaml, THE Application SHALL הוסיף את התלות `syncfusion_flutter_pdfviewer: ^31.2.3`
3. WHEN המפתח מעדכן את קובץ pubspec.yaml, THE Application SHALL הוסיף את התלות `syncfusion_flutter_pdf: ^31.2.3`
4. WHEN המפתח מעדכן את קובץ pubspec.yaml, THE Application SHALL הוסיף את התלות `syncfusion_flutter_core: ^31.2.3`
5. IF מתרחשת התנגשות חבילות, THEN THE Application SHALL השתמש בגרסה ישנה יותר של syncfusion שתואמת לתלויות הקיימות
6. WHEN המפתח מריץ `flutter pub get`, THE Application SHALL טעון בהצלחה את כל התלויות ללא שגיאות
7. WHEN המפתח מגדיר רישוי, THE Application SHALL רשום את מפתח הרישוי ב-main.dart לפני runApp
8. THE Application SHALL קרוא ל-`SyncfusionLicense.registerLicense(licenseKey)` עם מפתח הרישוי הקיים

### דרישה 2: עדכון הצהרות Import

**User Story:** כמפתח, אני רוצה לעדכן את כל הצהרות ה-import בקוד, כדי שהקוד יפנה לחבילה החדשה במקום לישנה.

#### קריטריוני קבלה

1. WHEN המפתח סורק את הקוד, THE Application SHALL זהה את כל הקבצים המכילים `import 'package:pdfrx/pdfrx.dart'`
2. WHEN המפתח מעדכן קובץ קוד, THE Application SHALL החליף כל הופעה של `import 'package:pdfrx/pdfrx.dart'` ב-`import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart'`
3. WHERE נדרש גישה למסמך PDF, THE Application SHALL הוסיף גם `import 'package:syncfusion_flutter_pdf/pdf.dart'`
4. WHERE נדרש גישה לנושא (theme), THE Application SHALL הוסיף `import 'package:syncfusion_flutter_core/theme.dart'`
5. THE Application SHALL עדכן imports בקבצים הבאים: pdf_book_screen.dart, pdf_outlines_screen.dart, pdf_page_number_dispaly.dart, pdf_search_screen.dart, pdf_thumbnails_screen.dart, pdf_tab.dart, page_converter.dart, ref_helper.dart, printing_screen.dart, indexing_repository.dart, daf_yomi_helper.dart
6. WHEN כל ה-imports מעודכנים, THE Application SHALL קומפל ללא שגיאות של imports חסרים

### דרישה 3: החלפת PdfViewerController

**User Story:** כמפתח, אני רוצה להחליף את PdfViewerController של pdfrx ב-PdfViewerController של Syncfusion, כדי לשמור על פונקציונליות בקרת התצוגה.

#### קריטריוני קבלה

1. WHEN המפתח מעדכן את PdfBookTab, THE Application SHALL החליף את סוג PdfViewerController מ-pdfrx ל-Syncfusion
2. WHEN המפתח מעדכן את pdf_book_screen.dart, THE Application SHALL יצור instance של PdfViewerController של Syncfusion
3. THE Application SHALL שמור על כל הפונקציונליות הבאה: goToPage, zoomUp, zoomDown, pageNumber, pageCount, isReady
4. WHEN המשתמש מנווט בין דפים, THE Application SHALL עדכן את מספר הדף הנוכחי בצורה נכונה
5. WHEN המשתמש משנה רמת זום, THE Application SHALL שנה את רמת הזום של התצוגה בהתאם

### דרישה 4: החלפת רכיב PdfViewer

**User Story:** כמשתמש, אני רוצה לראות קבצי PDF בצורה תקינה, כדי שאוכל לקרוא את תוכן הספרים.

#### קריטריוני קבלה

1. WHEN המשתמש פותח ספר PDF, THE Application SHALL הציג את תוכן ה-PDF באמצעות SfPdfViewer של Syncfusion
2. THE Application SHALL תמוך בפתיחת PDF מקובץ (SfPdfViewer.file)
3. WHEN המשתמש גולל את המסמך, THE Application SHALL הציג את הדפים בצורה חלקה
4. THE Application SHALL שמור על צבע הרקע המוגדר בנושא (Theme)
5. WHEN המשתמש מקיש עם העכבר, THE Application SHALL הסתיר את חלונית הצד אם היא לא מוצמדת
6. THE Application SHALL תמוך במקסימום זום של פי 10
7. THE Application SHALL תמוך בהצפנת PDF עם סיסמה

### דרישה 5: החלפת פונקציונליות Outline (תוכן עניינים)

**User Story:** כמשתמש, אני רוצה לנווט בתוכן העניינים של הספר, כדי לעבור במהירות לפרקים שונים.

#### קריטריוני קבלה

1. WHEN המשתמש פותח ספר PDF, THE Application SHALL טען את תוכן העניינים (Outline) באמצעות PdfDocument של Syncfusion
2. THE Application SHALL הציג את תוכן העניינים בצורה היררכית עם אפשרות להרחבה וכיווץ
3. WHEN המשתמש לוחץ על פריט בתוכן העניינים, THE Application SHALL נווט לדף המתאים במסמך
4. THE Application SHALL סנכרן את הפריט הפעיל בתוכן העניינים עם הדף הנוכחי במסמך
5. WHEN המשתמש מחפש בתוכן העניינים, THE Application SHALL סנן ויציג רק פריטים תואמים
6. THE Application SHALL גלול אוטומטית לפריט הפעיל בתוכן העניינים

### דרישה 6: החלפת פונקציונליות חיפוש טקסט

**User Story:** כמשתמש, אני רוצה לחפש טקסט בתוך מסמך PDF, כדי למצוא במהירות מידע ספציפי.

#### קריטריוני קבלה

1. WHEN המשתמש מזין טקסט לחיפוש, THE Application SHALL חפש את הטקסט במסמך באמצעות PdfTextSearchResult של Syncfusion
2. THE Application SHALL הציג את מספר התוצאות שנמצאו
3. THE Application SHALL תמוך בניווט בין תוצאות החיפוש (הבא/הקודם)
4. WHEN המשתמש מנווט לתוצאה, THE Application SHALL נווט לדף המכיל את התוצאה ויסמן אותה אוטומטית
5. WHERE המשתמש רוצה לראות הקשר טקסטואלי, THE Application SHALL חלץ טקסט הדף באופן lazy (רק כשנדרש)
6. THE Application SHALL שמור cache של טקסט דפים שכבר חולצו
7. THE Application SHALL שמור את מצב החיפוש (טקסט ואינדקס נוכחי) בטאב



### דרישה 8: עדכון מנגנון המרת דפים (Page Converter)

**User Story:** כמפתח, אני רוצה להמיר בין מספרי דפים של PDF למספרי שורות של ספר טקסט, כדי לאפשר סנכרון בין גרסאות שונות של אותו ספר.

#### קריטריוני קבלה

1. WHEN המערכת טוענת outline של PDF, THE Application SHALL השתמש ב-API של Syncfusion לטעינת תוכן העניינים
2. THE Application SHALL בנה מפת המרה בין דפי PDF לאינדקסים של ספר טקסט
3. WHEN המשתמש עובר מגרסת PDF לגרסת טקסט, THE Application SHALL המיר את מספר הדף הנוכחי לאינדקס המתאים
4. WHEN המשתמש עובר מגרסת טקסט לגרסת PDF, THE Application SHALL המיר את האינדקס הנוכחי למספר דף מתאים
5. THE Application SHALL שמור את מפות ההמרה ב-cache לביצועים טובים יותר

### דרישה 9: עדכון Ref Helper

**User Story:** כמפתח, אני רוצה ליצור הפניות (references) מתוכן עניינים של PDF, כדי לאפשר ניווט והצגת מיקום נוכחי.

#### קריטריוני קבלה

1. WHEN המערכת יוצרת refs מספרייה, THE Application SHALL השתמש ב-API של Syncfusion לטעינת outline של PDF
2. THE Application SHALL חלץ את כל הצמתים (nodes) מתוכן העניינים באופן רקורסיבי
3. WHEN המערכת מחפשת ref לפי מספר דף, THE Application SHALL מצא את הפריט הקרוב ביותר בתוכן העניינים
4. THE Application SHALL בנה מחרוזת ref מלאה מכל רמות ההיררכיה
5. THE Application SHALL שמור את ה-refs במסד נתונים Isar לחיפוש מהיר

### דרישה 10: עדכון Indexing Repository

**User Story:** כמפתח, אני רוצה לאנדקס את תוכן ספרי PDF, כדי לאפשר חיפוש מהיר בכל הספרייה.

#### קריטריוני קבלה

1. WHEN המערכת מאנדקסת ספר PDF, THE Application SHALL פתח את המסמך באמצעות PdfDocument של Syncfusion
2. THE Application SHALL חלץ טקסט מכל דף במסמך
3. THE Application SHALL יצור ref לכל שורה טקסט על בסיס תוכן העניינים
4. THE Application SHALL שמור את הטקסט והמטא-דאטה במנוע החיפוש Tantivy
5. WHEN האינדוקס מתבצע, THE Application SHALL דווח על התקדמות למשתמש
6. THE Application SHALL תמוך בביטול תהליך האינדוקס

### דרישה 11: עדכון Daf Yomi Helper

**User Story:** כמשתמש, אני רוצה לפתוח את הדף היומי בלחיצת כפתור, כדי ללמוד את הדף היומי בקלות.

#### קריטריוני קבלה

1. WHEN המשתמש פותח דף יומי, THE Application SHALL חפש את הדף בתוכן העניינים של הספר
2. THE Application SHALL השתמש ב-API של Syncfusion לטעינת outline
3. WHEN הדף נמצא, THE Application SHALL נווט לדף המתאים במסמך
4. THE Application SHALL תמוך בחיפוש בקטגוריות שונות (תלמוד בבלי, ירושלמי, וכו')

### דרישה 12: עדכון מסך הדפסה

**User Story:** כמשתמש, אני רוצה להדפיס או לשמור PDF, כדי לשמור עותק פיזי או דיגיטלי של התוכן.

#### קריטריוני קבלה

1. WHEN המשתמש לוחץ על כפתור הדפסה, THE Application SHALL הציג תצוגת מקדימה של ה-PDF
2. THE Application SHALL השתמש ב-PdfViewer של Syncfusion להצגת התצוגה המקדימה
3. THE Application SHALL תמוך בשיתוף ושמירת קובץ PDF
4. THE Application SHALL שמור על כל אפשרויות העיצוב (גופן, גודל, שוליים, וכו')

### דרישה 13: עדכון PdfBookTab Model

**User Story:** כמפתח, אני רוצה לשמור את מצב הטאב של PDF, כדי לשחזר את המצב בפתיחה מחדש.

#### קריטריוני קבלה

1. WHEN המערכת יוצרת PdfBookTab, THE Application SHALL אתחל את PdfViewerController של Syncfusion
2. THE Application SHALL שמור את מספר הדף הנוכחי
3. THE Application SHALL שמור את מצב החיפוש (טקסט חיפוש, תוצאות, אינדקס נוכחי)
4. THE Application SHALL שמור את מצב תוכן העניינים (outline)
5. WHEN הטאב נסגר, THE Application SHALL שמור את המצב ל-JSON
6. WHEN הטאב נפתח מחדש, THE Application SHALL שחזר את המצב מ-JSON

### דרישה 14: טיפול בקישורים (Links) ב-PDF

**User Story:** כמשתמש, אני רוצה ללחוץ על קישורים בתוך מסמך PDF, כדי לנווט לדפים אחרים או לפתוח URLs חיצוניים.

#### קריטריוני קבלה

1. WHEN המשתמש לוחץ על קישור פנימי, THE Application SHALL נווט לדף המתאים במסמך
2. WHEN המשתמש לוחץ על קישור חיצוני (URL), THE Application SHALL הציג דיאלוג אישור
3. WHEN המשתמש מאשר, THE Application SHALL פתח את ה-URL בדפדפן חיצוני
4. THE Application SHALL סמן קישורים בצבע כחול עם אפקט hover

### דרישה 15: תמיכה במצב כהה (Dark Mode)

**User Story:** כמשתמש, אני רוצה לראות PDF במצב כהה, כדי להפחית עייפות עיניים בסביבה חשוכה.

#### קריטריוני קבלה

1. WHEN המשתמש מפעיל מצב כהה, THE Application SHALL החיל פילטר הפיכת צבעים על תצוגת ה-PDF
2. THE Application SHALL השתמש ב-ColorFilter עם BlendMode.difference במצב כהה
3. WHEN המשתמש מכבה מצב כהה, THE Application SHALL הסיר את הפילטר
4. THE Application SHALL סנכרן את המצב עם SettingsBloc

### דרישה 16: תמיכה בסיסמאות PDF

**User Story:** כמשתמש, אני רוצה לפתוח קבצי PDF מוגנים בסיסמה, כדי לגשת לתוכן מוגן.

#### קריטריוני קבלה

1. WHEN המשתמש פותח PDF מוגן בסיסמה, THE Application SHALL זהה שגיאת סיסמה דרך onDocumentLoadFailed callback
2. WHEN המערכת מזהה שגיאת סיסמה, THE Application SHALL הציג דיאלוג לבקשת סיסמה
3. WHEN המשתמש מזין סיסמה, THE Application SHALL טען מחדש את המסמך עם הסיסמה
4. WHEN המשתמש מזין סיסמה נכונה, THE Application SHALL פתח את המסמך
5. WHEN המשתמש מזין סיסמה שגויה, THE Application SHALL הציג הודעת שגיאה ויאפשר ניסיון נוסף

### דרישה 17: שמירת תאימות API

**User Story:** כמפתח, אני רוצה לשמור על ממשק API דומה ככל האפשר, כדי למזער שינויים בקוד המשתמש.

#### קריטריוני קבלה

1. WHERE אפשרי, THE Application SHALL שמור על שמות מתודות ופרמטרים זהים
2. WHERE נדרש שינוי API, THE Application SHALL תעד את השינוי בהערות קוד
3. THE Application SHALL יצור wrapper functions במידת הצורך לשמירה על תאימות
4. THE Application SHALL וודא שכל הפונקציונליות הקיימת ממשיכה לעבוד

### דרישה 18: בדיקות ואימות

**User Story:** כמפתח, אני רוצה לוודא שהמעבר לא שבר פונקציונליות קיימת, כדי לשמור על איכות האפליקציה.

#### קריטריוני קבלה

1. WHEN המפתח מריץ את האפליקציה, THE Application SHALL קומפל ללא שגיאות
2. WHEN המפתח פותח ספר PDF, THE Application SHALL הציג את התוכן בצורה תקינה
3. WHEN המפתח מבצע חיפוש, THE Application SHALL מצא ויציג תוצאות נכונות
4. WHEN המפתח מנווט בתוכן עניינים, THE Application SHALL עבור לדפים הנכונים
5. WHEN המפתח משתמש ב-thumbnails, THE Application SHALL הציג ונווט נכון
6. WHEN המפתח עובר בין גרסאות PDF וטקסט, THE Application SHALL המיר מספרי דפים נכון
7. THE Application SHALL עבור בדיקות ידניות של כל התכונות הקיימות
