# אייקוני אוצריא לתוספים

אוצריא מציגה אייקונים של תוספים משתי ספריות:

- **[Otzaria Icons](https://github.com/Otzaria/otzaria_icons)** — אייקונים מקוריים לעולם התוכן היהודי (ספרים, אותיות, צורת הדף, קישורים, חיפוש בספרייה), בסגנון Fluent ובאותה מוסכמת שמות. הרשימה המלאה והמספר המדויק — [למטה](#רשימת-האייקונים-של-אוצריא).
- **[FluentUI System Icons](https://github.com/microsoft/fluentui-system-icons)** — כ-4,500 אייקוני 24px כלליים.

בכל שדה `icon` / `iconName` של תוסף אפשר לכתוב שם מכל אחת מהן — אין צורך להצהיר על ספרייה.

## בקצרה

1. **כתבו שם, לא קובץ.** בשדה `icon` / `iconName` כותבים שם כמו `book_24_regular`, ואוצריא מציירת את האייקון **בעצמה**, בצד שלה. אין מה לארוז בתוסף ואין API שמחזיר קובץ אייקון.
2. **השם הוא `<שם>_24_regular` או `<שם>_24_filled`** — קווי או מלא. אין גדלים אחרים.
3. **שם שקיים בשתי הספריות נפתר לאוצריא.** כדי לבחור ספרייה במפורש: `otzaria:<שם>` או `fluent:<שם>`.
4. **שם שגוי לא זורק שגיאה** — מוצג אייקון פאזל או שאין אייקון בכלל (לפי המקום). [בדיקת שם](#איך-בודקים-ששם-נפתר) נעשית בקריאה אחת.

## המלצה: הצהירו על אייקונים דרך אוצריא

בכל מקום שבו אוצריא מציירת אייקון בשביל התוסף (לשונית כלים, סרגל, תפריטים — [הטבלה למטה](#איפה-תוסף-מצהיר-על-אייקון)), **מומלץ להשתמש בשם אייקון מהספריות של אוצריא, ולא באייקון משלכם** (תמונה, אימוג׳י או טקסט). הסיבות:

- **קו עיצובי אחיד.** האייקון יוצא באותו משקל קו, באותה גאומטריה ובאותה משפחה ויזואלית כמו שאר הממשק, כך שהתוסף נראה חלק מהתוכנה ולא תוספת חיצונית.
- **צבע, מצב כהה ומצבי כפתור.** אוצריא צובעת את האייקון לפי ה-theme: בהיר/כהה, מושבת, מוצג מעל רקע נבחר. אייקון שאתם מצרפים כתמונה אינו עוקב אחרי אף אחד מאלה.
- **גודל נכון בכל מקום.** אוצריא מציירת את האייקון בגודל המתאים לכל מקום (לשונית, פקד בסרגל, שורת תפריט), ובשורות תפריט היא מגדילה מעט אייקוני אותיות וקישור כדי שהסימן שלהם ייקרא. שם אייקון לא דורש לחשוב על זה.
- **RTL.** אייקוני אוצריא מצוירים לממשק הפוך מלכתחילה, ואין צורך בהיפוך.
- **אפס משקל ואפס תחזוקה.** התוסף לא גדל, ואם אוצריא תעדכן את העיצוב, האייקון של התוסף יתעדכן איתה.

מתי כן אייקון משלכם? **בתוך ה-WebView של התוסף** (כפתורים וכותרות בתוך הדף שלכם) — שם אוצריא אינה מציירת כלום ואתם צריכים SVG משלכם. גם שם כדאי להתאים אותו למראה של האייקונים בתוכנה — [ראו למטה](#אייקונים-בתוך-ה-webview-של-התוסף).

## איפה תוסף מצהיר על אייקון

| מקום | איפה מצהירים | כשהשם לא נמצא |
|------|---------------|-----------------|
| אייקון לשונית הכלים | `manifest.json` ← `contributes.toolTab.iconName` | אייקון פאזל |
| פקד בסרגל העליון של מסך עיון | `reader.addToolbarItem` ← `icon` (חובה בפקד עליון), או `contributes.startup.toolbarItems[].icon` | אייקון פאזל |
| ילד של פקד תפריט נפתח | `children[].icon` | בלי אייקון |
| פריט בתפריט הקליק הימני | `reader.addContextMenuItem` ← `icon` | בלי אייקון |
| צבע בשורת הצבעים של תפריט הקליק הימני | `colors[].icon` — מוצג במקום גוש הצבע | גוש הצבע |
| כרטיסי ספרים של ספק בספרייה | `contributes.startup.libraryBooks[].icon` | אייקון ספר |
| שינוי אייקון של פקד קיים | `reader.updateToolbarItem` ← `patch.icon` | כמו בפקד חדש |

ב-`manifest.json` (`iconName`, `libraryBooks[].icon`) הסיומת חייבת להיות `_24_regular` או `_24_filled`, ושם שלא מתאים לתבנית נדחה בהתקנה. בשדות של ה-API בזמן ריצה אין ולידציה.

## כלל ההכרעה

השם נפתר קודם בשמות הנוכחיים של אוצריא, אחר כך בכינויי התאימות שלה ורק אחר כך בפלואנט — כלומר **בשם שקיים בשתיהן, אוצריא מנצחת**. השמות הכפולים מסומנים בטבלה שלמטה. הסיבה: הגליף של אוצריא צויר לספרייה תורנית ולממשק RTL, ולכן הוא הברירה הנכונה כשהוא קיים.

> ⚠️ שימו לב: מכיוון שאוצריא מנצחת, `book_24_regular` בתוסף שלכם ייתן את **ספר אוצריא**, לא את ספר פלואנט. אם התוסף שלכם כבר מותקן והסתמך על הצורה של פלואנט באחד מהשמות המשותפים, המראה שלו ישתנה — הוסיפו `fluent:` כדי לשמר אותו. גם **שם שהוסף לאוצריא בגרסה חדשה** (למשל `check_24_regular` או `document_pdf_24_regular`) מתחיל לנצח את פלואנט ברגע שאוצריא מתעדכנת.

אם דווקא הצורה של פלואנט היא הנכונה לתוסף שלכם, כפו אותה בתחילית:

```jsonc
"iconName": "book_24_regular"          // אוצריא (ברירת מחדל)
"iconName": "otzaria:book_24_regular"  // אוצריא, במפורש
"iconName": "fluent:book_24_regular"   // פלואנט
```

תחילית מפורשת אינה נופלת לספרייה השנייה: `fluent:alef_24_regular` לא ייפתר, כי `alef_24_regular` קיים רק באוצריא. שימו לב שוולידציית המניפסט בודקת רק את **צורת** השם ולא את קיומו — `"otzaria:settings_24_regular"` יעבור התקנה בשקט ויוצג כפאזל.

### מתי להוסיף תחילית

| מצב | מה לכתוב |
|-----|-----------|
| אייקון שקיים רק באוצריא (אותיות, `lectern`, `search_in_*`...) | השם בלבד — `alef_niqqud_24_filled` |
| אייקון שקיים רק בפלואנט (`settings`, `add`, `delete`...) | השם בלבד — `settings_24_regular` |
| שם משותף, ואתם רוצים את הגרסה של אוצריא | השם בלבד, או `otzaria:` אם רוצים לנעול אותו |
| שם משותף, ואתם רוצים את הגרסה של פלואנט | `fluent:` — **חובה** |
| תוסף שחייב להיראות אותו דבר גם אחרי עדכוני ספרייה | תחילית מפורשת בכל השמות שלו |

## כללי השם

- **בשדה `iconName` שבמניפסט** הסיומת חייבת להיות `_24_regular` או `_24_filled` — `_20_`, `_16_` ו-`_24_light` נדחים בוולידציה. בשדות `icon` של ה-API בזמן ריצה אין ולידציה כלל, ושם גם `document_24_light` נפתר בפועל.
- שם שאינו קיים באף אחת מהספריות אינו זורק שגיאה: בלשונית הכלים ובפקד סרגל עליון יוצג אייקון פאזל ברירת מחדל; בפריט תפריט, בילד של תפריט נפתח ובשורת צבעים פשוט לא יוצג אייקון.
- אייקוני אוצריא אינם מתהפכים ב-RTL — הם מצוירים מלכתחילה לכיוון הממשק.
- **`regular` ו-`filled`.** בספריית אוצריא לכל אייקון יש שתי הגרסאות. `regular` הוא ציור קווי ו-`filled` ציור מלא, בעובי כבד יותר. השתמשו ב-`filled` למצב פעיל/נבחר וב-`regular` למצב רגיל, ואל תערבבו בין השניים באותה שורת פקדים בלי סיבה.

### אייקוני אותיות וקישורים

אייקוני האותיות (`alef_*`, `beit*`, `tet*`) והקישורים (`link*`) מציירים סימן קטן בתוך עיגול, ולכן הם נקראים היטב רק בגודל מספיק. אוצריא מציירת אותם מעט גדולים יותר משאר האייקונים בשורות תפריט.

- באותיות, **`_filled` הוא האות המלאה (אות "עבה") ו-`_regular` הוא קו מתאר**. אם אתם רוצים את האות המלאה, כתבו `_filled`.
- השם בנוי **נושא, ואז מילה אחת** לתג או לווריאנט, והמילה זהה בכל המשפחות: `_add`, `_delete`, `_eraser`, `_information`, `_exclamation`, `_check`, `_copy`. כך `alef_delete` ו-`link_delete` הם אותו תג על אות ועל קישור.

### מגבלה ידועה — אייקוני פלואנט כיווניים אינם זמינים

38 אייקוני פלואנט בגודל 24 שמוגדרים בחבילה עם `matchTextDirection` **חסרים ממפת השמות של התוספים** ולכן אינם נפתרים כלל (יוצגו כפאזל). ביניהם כל המשפחות שבהן היה הכי טבעי להשתמש לניווט:

`chevron_left/right_24_regular|filled` · `arrow_left/right_24_regular|filled` · `arrow_next/previous_24_*` · `arrow_forward_24_*` · `arrow_up_left/up_right/down_left_24_*` · `arrow_circle_right_24_*` · `arrow_import_24_*` · `text_align_left/right_24_*` · `text_column_two_left/right_24_*` · `swipe_right_24_*`

עד שהמפה תיווצר מחדש, השתמשו בחלופה לא-כיוונית — למשל `caret_left_24_filled` / `caret_right_24_filled`, `arrow_up_24_regular` / `arrow_down_24_regular`, או אייקון מאוצריא. כמה אייקוני אוצריא קיימים בשני הכיוונים בשמות מפורשים, למשל `text_continuous_rtl_24_regular` (חץ שמאלה) ו-`text_continuous_ltr_24_regular` (חץ ימינה).

## איך בוחרים בין שתי הספריות

אותו כלל שאוצריא עצמה פועלת לפיו:

- **אוצריא** — כשיש אייקון **ייעודי לתוכן תורני**: ספר (`book_*`), אותיות (`alef_*`, `beit*`, `tet*`), צורת הדף (`book_open_tzurat_hadaf_*`), קישורים (`link*`), חיפוש ממוקד (`search_in_book`, `search_in_library`, ...), `lectern`, `torah_scroll`, `calendar_yahrzeit`. גם כשפלואנט מציעה "משהו קרוב", הגרסה של אוצריא מתאימה יותר לתוכן.
- **פלואנט** — כל הכרום הכללי: `add`, `delete`, `settings`, `copy`, `save`, `print`, `star`, `bookmark`. הם אינם חסרים באוצריא במקרה, וציור מחדש שלהם לא היה מוסיף כלום.
- **שניהם יחד** — המצב הרגיל. תוסף טיפוסי משתמש בכמה אייקונים תורניים מאוצריא ובכמה פעולות כלליות מפלואנט, והם יושבים טוב זה לצד זה כי אוצריא צוירה בסגנון Fluent, באותה מוסכמת שמות.

## דוגמאות

### 1. רק אוצריא

```json
"contributes": {
  "toolTab": {
    "title": "סידורון",
    "iconName": "otzaria:book_open_tzurat_hadaf_24_regular"
  }
}
```

```javascript
// פקד בסרגל — אות עם ניקוד, מלאה. שם שקיים רק באוצריא לא צריך תחילית.
await Otzaria.call('reader.addToolbarItem', {
  id: 'niqqud-tools',
  title: 'ניקוד',
  icon: 'alef_niqqud_24_filled',
});
```

### 2. רק פלואנט

```json
"contributes": {
  "toolTab": {
    "title": "עוזר",
    "iconName": "fluent:sparkle_24_regular"
  }
}
```

```javascript
// "fluent:" כופה את הצורה של פלואנט גם בשם שקיים בשתי הספריות
// (`book_24_regular` קיים בשתיהן; בלי התחילית היה יוצא ספר אוצריא).
await Otzaria.call('reader.addContextMenuItem', {
  id: 'plain-book',
  label: 'פתח בספר',
  icon: 'fluent:book_24_regular',
});
```

### 3. שתי הספריות באותו תוסף

אייקון תורני מאוצריא לפעולה המרכזית, וכללי מפלואנט לפעולות המשנה:

```javascript
await Otzaria.call('reader.addToolbarItem', {
  id: 'siddur',
  type: 'menu',                                  // חובה כשיש children
  title: 'סידור',
  icon: 'book_alef_24_regular',                  // אוצריא
  children: [
    { id: 'weekday', title: 'חול',  icon: 'book_open_medium_24_regular' }, // אוצריא
    { id: 'shabbat', title: 'שבת',  icon: 'book_star_24_regular' },        // שני הספריות — אוצריא מנצחת
    { id: 'print',   title: 'הדפס', icon: 'print_24_regular' },            // פלואנט
    { id: 'settings', title: 'הגדרות', icon: 'settings_24_regular' },      // פלואנט
  ],
});
```

תפריט ההקשר, עם שורת צבעים שנכנסת בה פעולה כללית מפלואנט:

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'search-in-book',
  label: 'חפש בספר זה',
  icon: 'search_in_book_24_regular',             // אוצריא
});

await Otzaria.call('reader.addContextMenuItem', {
  id: 'highlight',
  type: 'color-row',
  colors: [
    { id: 'yellow', color: '#FFD54F', label: 'צהוב' },
    { id: 'clear',  color: '#00000000', label: 'נקה', icon: 'eraser_24_regular' }, // פלואנט
  ],
});
```

### 4. מצב רגיל ומצב פעיל

`regular` לפקד כבוי ו-`filled` לפקד פעיל, עם עדכון בלי רישום מחדש:

```javascript
await Otzaria.call('reader.addToolbarItem', {
  id: 'save-mark',
  title: 'שמור סימון',
  icon: 'bookmark_24_regular',
});

// אחרי שהמשתמש שמר:
await Otzaria.call('reader.updateToolbarItem', {
  id: 'save-mark',
  patch: { icon: 'bookmark_24_filled' },
});
```

### 5. שם משותף — שלוש הדרכים

`book_24_regular` קיים בשתי הספריות:

```javascript
icon: 'book_24_regular'          // ספר אוצריא (ברירת מחדל, אוצריא מנצחת)
icon: 'otzaria:book_24_regular'  // ספר אוצריא, ננעל גם אם פלואנט תשתנה
icon: 'fluent:book_24_regular'   // ספר פלואנט
```

### 6. ספק ספרים בספרייה

```json
"contributes": {
  "startup": {
    "libraryBooks": [{
      "id": "books",
      "provider": "mylib",
      "title": "הספרייה שלי",
      "icon": "book_pdf_24_regular"
    }]
  }
}
```

בלי `icon` הכרטיסים מקבלים את אייקון הלשונית של התוסף (`contributes.toolTab.iconName`), ובלעדיו אייקון ספר.

### 7. אותיות וקישורים

```javascript
icon: 'alef_24_filled'              // אל"ף מלאה
icon: 'alef_24_regular'             // אל"ף בקו מתאר
icon: 'alef_eraser_24_filled'       // אל"ף עם מחק
icon: 'alef_check_24_filled'        // אל"ף עם וי
icon: 'link_24_regular'             // קישור
icon: 'link_copy_24_regular'        // קישור עם סימן העתקה
icon: 'links_24_regular'            // שרשרת קישורים
```

## איך בודקים ששם נפתר

שם שגוי אינו זורק שגיאה, ולכן קל לפספס שגיאת כתיב. הקריאה `plugin.listInstalled` מחזירה לכל תוסף את `toolTabIconName`, ו-**כשהשם אינו מוכר מוחזר `puzzle_piece_24_regular`** (ראו [`plugin.listInstalled` ב-API](API_REFERENCE.md)). אם הגדרתם `iconName` ומתקבל פאזל — השם לא נמצא באף ספרייה.

בפקדים ובתפריטים הבדיקה היא עין: בפקד עליון תראו פאזל, ובפריט תפריט — שורה בלי אייקון. חפשו את השם בטבלה [שלמטה](#רשימת-האייקונים-של-אוצריא) או בקטלוג.

## אייקונים בתוך ה-WebView של התוסף

האייקונים של אוצריא אינם נטענים לתוך ה-WebView, ואין API שמחזיר קובץ אייקון. לכפתורים ולכותרות **בתוך הדף של התוסף** משתמשים ב-SVG inline, צבוע ב-`currentColor` כדי לעקוב אחרי ה-theme ([מתכון מלא ב-COOKBOOK.md](COOKBOOK.md)).

כדי שהאייקון בדף ייראה כמו זה שבתוכנה, אפשר להעתיק את ה-SVG של האייקון עצמו:

- אייקוני אוצריא — קובץ לכל אייקון ב-[`assets_src/svg/<שם>.svg`](https://github.com/Otzaria/otzaria_icons/tree/main/assets_src/svg) בריפו הספרייה. הקובץ ב-24×24 והציור נטול צבע, אז אפשר לשים `fill="currentColor"` על ה-`<svg>`. בכמה אייקונים יש חלקים לבנים (חיתוך בתוך עיגול) שאינם עוקבים אחרי ה-theme.
- אייקוני פלואנט — [ה-SVG ב-`assets`](https://github.com/microsoft/fluentui-system-icons/tree/main/assets) של הריפו שלהם, בגודל `24` ובסגנון `Regular`/`Filled`.

בדקו את הרישיון של הספרייה שממנה אתם מעתיקים (`LICENSE` ו-`THIRD_PARTY_NOTICES.md` בריפו של אוצריא, והרישיון של פלואנט) לפני שאתם מפיצים את ה-SVG בתוך התוסף. **שם אייקון בשדה `icon` אינו מעתיק כלום**, ולכן אינו מעלה את השאלה.

## מעבר לגרסת הספרייה 0.6.0 — שמות שהשתנו

בגרסה 0.6.0 של otzaria_icons שונו שמות של אייקונים קיימים. **ה־resolver הציבורי של אוצריא שומר תאימות לכל שמות גרסה 0.5.0 שנעלמו**, גם ללא תחילית וגם עם `otzaria:`. הכינויים נפתרים לפני הנפילה לפלואנט; `fluent:` ממשיך לכפות את ספריית פלואנט בלבד. הטבלה מציגה את שמות היעד; כינויי התאימות קיימים רק לשמות שנכללו בפועל בגרסה 0.5.0.

| שם ישן | שם חדש |
|--------|---------|
| `alef_addition` | `alef_add` |
| `alef_deletion` | `alef_delete` |
| `alef_with_eraser` | `alef_eraser` |
| `alef_with_exclamation` | `alef_exclamation` |
| `alef_with_information` | `alef_information` |
| `alef_with_flavors` | `alef_niqqud_taamim` |
| `alef_with_punctuation` | `alef_punctuation` |
| `alef_with_score` | `alef_niqqud` |
| `alef_half_filled` | `alef_mix` |
| `link_deletion` | `link_delete` |
| `link_with_eraser` | `link_eraser` |
| `link_with_information` | `link_information` |
| `link_book_empty` | `link_book` |
| `link_book_exclamation` | `link_exclamation` |
| `book_open_medium_line` | `book_open_medium_lines` |
| `book_open_small_line` | `book_open_small_lines` |
| `otzaria_icon_line` | `otzaria_icon_lines` |
| `otzaria_icon_2_page_line` | `otzaria_icon_2_page_lines` |
| `search_in_the_book` | `search_in_book` |
| `search_in_the_document` | `search_in_document` |
| `search_in_the_library` | `search_in_library` |
| `search_in_the_person` | `search_in_person` |
| `search_in_the_quote` | `search_in_quote` |
| `search_in_the_settings` | `search_in_settings` |
| `search_in_the_text` | `search_in_text` |
| `yoma_deilula` | `calendar_yahrzeit` |
| `stander` | `lectern` |
| `text_continuous` | `text_continuous_rtl` (ו-`text_continuous_ltr` החדש הוא הציור המקורי של פלואנט) |
| `clipboard_text_24_filled` | `clipboard_text_rtl_24_filled` |
| `icon_x_24_regular` (ה-X העבה) | `cross_24_filled` |
| `book_md`, `book_zim` | הגליפים נמחקו; הכינויים נפתרים ל־`book` באותו משקל |

משקלים וכיווניות בתאימות:

- **אותיות** (`alef_*`, `beit*`, `tet*`, למעט `alef_24` ו-`alef_mix`): מה שנקרא `_regular` והיה אות מלאה נקרא עכשיו **`_filled`**, וה-`_regular` החדש הוא קו מתאר. כינוי של שם אות שנעלם נפתר ל־`_filled` כדי לשמר את המראה הקודם. שמות שנותרו בספרייה נפתרים לציור הנוכחי שלהם; כדי לשמר אות מלאה השתמשו ב־`_filled`. למשל `alef_with_score_24_regular` ← `alef_niqqud_24_filled`.
- **`text_continuous_24_*`** נפתר דרך כינוי התאימות ל־`text_continuous_rtl_24_*`, באותו משקל ובכיוון המקורי. `fluent:text_continuous_24_*` ממשיך להציג את גרסת פלואנט.

> מומלץ להשתמש בשמות הנוכחיים בתוספים חדשים. תוסף קיים אינו חייב לשנות את השמות שנעלמו כדי לשמור על האייקונים שלו; `book_md` ו־`book_zim` מציגים כעת ספר כללי ללא סימון הפורמט.

## איך מוצאים אייקון

- **אוצריא** — הטבלה שלמטה, או הקטלוג האינטראקטיבי [`index.html`](https://github.com/Otzaria/otzaria_icons/blob/main/index.html) (חיפוש לפי שם ותצוגה בגדלים שונים). הוא טוען את הפונט בנתיב יחסי, ולכן צריך לשכפל את הריפו כולו ולפתוח את הקובץ מתוכו — הורדת הקובץ הבודד תציג שמות בלי גליפים.
- **פלואנט** — [מאגר FluentUI](https://github.com/microsoft/fluentui-system-icons), או חיפוש `FluentIcons.xxx_24_regular` בקוד אוצריא.

## רשימת האייקונים של אוצריא

הרשימה שלהלן **מגונררת מהספרייה** ואינה נערכת ביד. העמודה "גם בפלואנט" מסמנת שם שקיים בשתי הספריות — שם שבו כלל ההכרעה מכריע, ושבו התחילית `fluent:` משנה את התוצאה.

<!-- BEGIN GENERATED: otzaria-icons — אל תערכו ידנית, ראו "עדכון הרשימה" למטה -->

הספרייה מכילה **280 אייקונים**, ומהם **42** קיימים גם בפלואנט.

| שם | גם בפלואנט |
|-----|:---:|
| `alef_1_24_filled` |  |
| `alef_1_24_regular` |  |
| `alef_24_filled` |  |
| `alef_24_regular` |  |
| `alef_2_24_filled` |  |
| `alef_2_24_regular` |  |
| `alef_3_24_filled` |  |
| `alef_3_24_regular` |  |
| `alef_4_24_filled` |  |
| `alef_4_24_regular` |  |
| `alef_5_24_filled` |  |
| `alef_5_24_regular` |  |
| `alef_add_24_filled` |  |
| `alef_add_24_regular` |  |
| `alef_alef_24_filled` |  |
| `alef_alef_24_regular` |  |
| `alef_behind_alef_24_filled` |  |
| `alef_behind_alef_24_regular` |  |
| `alef_check_24_filled` |  |
| `alef_check_24_regular` |  |
| `alef_copy_24_filled` |  |
| `alef_copy_24_regular` |  |
| `alef_crown_24_filled` |  |
| `alef_crown_24_regular` |  |
| `alef_delete_24_filled` |  |
| `alef_delete_24_regular` |  |
| `alef_eraser_24_filled` |  |
| `alef_eraser_24_regular` |  |
| `alef_exclamation_24_filled` |  |
| `alef_exclamation_24_regular` |  |
| `alef_eye_24_filled` |  |
| `alef_eye_24_regular` |  |
| `alef_information_24_filled` |  |
| `alef_information_24_regular` |  |
| `alef_latin_a_24_filled` |  |
| `alef_latin_a_24_regular` |  |
| `alef_lips_24_filled` |  |
| `alef_lips_24_regular` |  |
| `alef_lock_24_filled` |  |
| `alef_lock_24_regular` |  |
| `alef_marker_24_filled` |  |
| `alef_marker_24_regular` |  |
| `alef_mix_24_filled` |  |
| `alef_mix_24_regular` |  |
| `alef_near_alef_24_filled` |  |
| `alef_near_alef_24_regular` |  |
| `alef_near_alef_rashi_24_filled` |  |
| `alef_near_alef_rashi_24_regular` |  |
| `alef_near_alef_stam_24_filled` |  |
| `alef_near_alef_stam_24_regular` |  |
| `alef_niqqud_24_filled` |  |
| `alef_niqqud_24_regular` |  |
| `alef_niqqud_taamim_24_filled` |  |
| `alef_niqqud_taamim_24_regular` |  |
| `alef_punctuation_24_filled` |  |
| `alef_punctuation_24_regular` |  |
| `alef_rashi_24_filled` |  |
| `alef_rashi_24_regular` |  |
| `alef_scissors_24_filled` |  |
| `alef_scissors_24_regular` |  |
| `alef_stam_24_filled` |  |
| `alef_stam_24_regular` |  |
| `alef_writing_24_filled` |  |
| `alef_writing_24_regular` |  |
| `apps_list_24_filled` | ✔ |
| `apps_list_24_regular` | ✔ |
| `apps_list_detail_24_filled` | ✔ |
| `apps_list_detail_24_regular` | ✔ |
| `beit_24_filled` |  |
| `beit_24_regular` |  |
| `beit_behind_alef_24_filled` |  |
| `beit_behind_alef_24_regular` |  |
| `beit_near_alef_24_filled` |  |
| `beit_near_alef_24_regular` |  |
| `book_24_filled` | ✔ |
| `book_24_regular` | ✔ |
| `book_add_24_filled` | ✔ |
| `book_add_24_regular` | ✔ |
| `book_alef_24_filled` |  |
| `book_alef_24_regular` |  |
| `book_alef_rashi_24_filled` |  |
| `book_alef_rashi_24_regular` |  |
| `book_download_24_filled` |  |
| `book_download_24_regular` |  |
| `book_empty_24_filled` |  |
| `book_empty_24_regular` |  |
| `book_exclamation_24_filled` |  |
| `book_exclamation_24_regular` |  |
| `book_fanned_24_filled` |  |
| `book_fanned_24_regular` |  |
| `book_information_24_filled` | ✔ |
| `book_information_24_regular` | ✔ |
| `book_lines_24_filled` |  |
| `book_lines_24_regular` |  |
| `book_link_24_filled` |  |
| `book_link_24_regular` |  |
| `book_links_24_filled` |  |
| `book_links_24_regular` |  |
| `book_number_24_filled` | ✔ |
| `book_number_24_regular` | ✔ |
| `book_open_large_24_filled` |  |
| `book_open_large_24_regular` |  |
| `book_open_large_lines_24_filled` |  |
| `book_open_large_lines_24_regular` |  |
| `book_open_large_search_24_filled` |  |
| `book_open_large_search_24_regular` |  |
| `book_open_medium_24_filled` |  |
| `book_open_medium_24_regular` |  |
| `book_open_medium_lines_24_filled` |  |
| `book_open_medium_lines_24_regular` |  |
| `book_open_medium_search_24_filled` |  |
| `book_open_medium_search_24_regular` |  |
| `book_open_small_24_filled` |  |
| `book_open_small_24_regular` |  |
| `book_open_small_lines_24_filled` |  |
| `book_open_small_lines_24_regular` |  |
| `book_open_tzurat_hadaf_24_filled` |  |
| `book_open_tzurat_hadaf_24_regular` |  |
| `book_pdf_24_filled` |  |
| `book_pdf_24_regular` |  |
| `book_search_24_filled` | ✔ |
| `book_search_24_regular` | ✔ |
| `book_star_24_filled` | ✔ |
| `book_star_24_regular` | ✔ |
| `book_tet_24_filled` |  |
| `book_tet_24_regular` |  |
| `book_upload_24_filled` |  |
| `book_upload_24_regular` |  |
| `book_word_24_filled` |  |
| `book_word_24_regular` |  |
| `booklet_24_filled` |  |
| `booklet_24_regular` |  |
| `booklet_empty_24_filled` |  |
| `booklet_empty_24_regular` |  |
| `books_stacked_high_24_filled` |  |
| `books_stacked_high_24_regular` |  |
| `books_stacked_low_24_filled` |  |
| `books_stacked_low_24_regular` |  |
| `bookshelf_24_filled` |  |
| `bookshelf_24_regular` |  |
| `calendar_24_filled` | ✔ |
| `calendar_24_regular` | ✔ |
| `calendar_yahrzeit_24_filled` |  |
| `calendar_yahrzeit_24_regular` |  |
| `check_24_filled` | ✔ |
| `check_24_regular` | ✔ |
| `clipboard_task_list_24_filled` |  |
| `clipboard_task_list_24_regular` |  |
| `clipboard_text_rtl_24_filled` | ✔ |
| `clipboard_text_rtl_24_regular` | ✔ |
| `clock_add_24_filled` |  |
| `clock_add_24_regular` |  |
| `cross_24_filled` |  |
| `cross_24_regular` |  |
| `dependent_library_24_filled` |  |
| `dependent_library_24_regular` |  |
| `document_alef_24_filled` |  |
| `document_alef_24_regular` |  |
| `document_bullet_list_24_filled` | ✔ |
| `document_bullet_list_24_regular` | ✔ |
| `document_column_24_filled` |  |
| `document_column_24_regular` |  |
| `document_download_24_filled` |  |
| `document_download_24_regular` |  |
| `document_html_24_filled` |  |
| `document_html_24_regular` |  |
| `document_md_24_filled` |  |
| `document_md_24_regular` |  |
| `document_pdf_24_filled` | ✔ |
| `document_pdf_24_regular` | ✔ |
| `document_tet_24_filled` |  |
| `document_tet_24_regular` |  |
| `document_text_24_filled` | ✔ |
| `document_text_24_regular` | ✔ |
| `document_upload_24_filled` |  |
| `document_upload_24_regular` |  |
| `document_word_24_filled` |  |
| `document_word_24_regular` |  |
| `group_list_24_filled` | ✔ |
| `group_list_24_regular` | ✔ |
| `lectern_24_filled` |  |
| `lectern_24_regular` |  |
| `link_24_filled` | ✔ |
| `link_24_regular` | ✔ |
| `link_add_24_filled` | ✔ |
| `link_add_24_regular` | ✔ |
| `link_alef_24_filled` |  |
| `link_alef_24_regular` |  |
| `link_book_24_filled` |  |
| `link_book_24_regular` |  |
| `link_check_24_filled` |  |
| `link_check_24_regular` |  |
| `link_copy_24_filled` |  |
| `link_copy_24_regular` |  |
| `link_delete_24_filled` |  |
| `link_delete_24_regular` |  |
| `link_document_24_filled` |  |
| `link_document_24_regular` |  |
| `link_eraser_24_filled` |  |
| `link_eraser_24_regular` |  |
| `link_exclamation_24_filled` |  |
| `link_exclamation_24_regular` |  |
| `link_eye_24_filled` |  |
| `link_eye_24_regular` |  |
| `link_information_24_filled` |  |
| `link_information_24_regular` |  |
| `link_marker_24_filled` |  |
| `link_marker_24_regular` |  |
| `link_quote_24_filled` |  |
| `link_quote_24_regular` |  |
| `link_scissors_24_filled` |  |
| `link_scissors_24_regular` |  |
| `links_24_filled` |  |
| `links_24_regular` |  |
| `list_24_filled` | ✔ |
| `list_24_regular` | ✔ |
| `otzaria_icon_24_filled` |  |
| `otzaria_icon_24_regular` |  |
| `otzaria_icon_2_page_24_filled` |  |
| `otzaria_icon_2_page_24_regular` |  |
| `otzaria_icon_2_page_lines_24_filled` |  |
| `otzaria_icon_2_page_lines_24_regular` |  |
| `otzaria_icon_empty_24_filled` |  |
| `otzaria_icon_empty_24_regular` |  |
| `otzaria_icon_lines_24_filled` |  |
| `otzaria_icon_lines_24_regular` |  |
| `person_24_filled` | ✔ |
| `person_24_regular` | ✔ |
| `person_portrait_24_filled` |  |
| `person_portrait_24_regular` |  |
| `search_24_filled` | ✔ |
| `search_24_regular` | ✔ |
| `search_check_24_filled` |  |
| `search_check_24_regular` |  |
| `search_in_book_24_filled` |  |
| `search_in_book_24_regular` |  |
| `search_in_document_24_filled` |  |
| `search_in_document_24_regular` |  |
| `search_in_library_24_filled` |  |
| `search_in_library_24_regular` |  |
| `search_in_numbered_list_24_filled` |  |
| `search_in_numbered_list_24_regular` |  |
| `search_in_person_24_filled` |  |
| `search_in_person_24_regular` |  |
| `search_in_quote_24_filled` |  |
| `search_in_quote_24_regular` |  |
| `search_in_settings_24_filled` |  |
| `search_in_settings_24_regular` |  |
| `search_in_text_24_filled` |  |
| `search_in_text_24_regular` |  |
| `search_in_titles_24_filled` |  |
| `search_in_titles_24_regular` |  |
| `search_not_found_24_filled` |  |
| `search_not_found_24_regular` |  |
| `task_list_24_filled` |  |
| `task_list_24_regular` |  |
| `task_list_square_24_filled` |  |
| `task_list_square_24_regular` |  |
| `tet_24_filled` |  |
| `tet_24_regular` |  |
| `tet_behind_tet_24_filled` |  |
| `tet_behind_tet_24_regular` |  |
| `tet_latin_t_24_filled` |  |
| `tet_latin_t_24_regular` |  |
| `tet_near_tet_24_filled` |  |
| `tet_near_tet_24_regular` |  |
| `tet_tet_24_filled` |  |
| `tet_tet_24_regular` |  |
| `text_alef_bet_list_24_filled` |  |
| `text_alef_bet_list_24_regular` |  |
| `text_bullet_list_24_filled` | ✔ |
| `text_bullet_list_24_regular` | ✔ |
| `text_continuous_ltr_24_filled` |  |
| `text_continuous_ltr_24_regular` |  |
| `text_continuous_rtl_24_filled` |  |
| `text_continuous_rtl_24_regular` |  |
| `text_number_list_24_filled` |  |
| `text_number_list_24_regular` |  |
| `torah_scroll_24_filled` |  |
| `torah_scroll_24_regular` |  |

<!-- END GENERATED: otzaria-icons -->

### עדכון הרשימה

הרשימה נגזרת משתי הספריות בזמן הבדיקה, ולכן כל שינוי בהן (אייקון שנוסף, אייקון שנמחק, או שם שהתחיל להתקיים גם בפלואנט) מפיל את
`test/plugins/utils/plugin_icon_resolver_docs_test.dart`. התיקון הוא פקודה אחת ולא עריכה ידנית:

```bash
flutter test test/plugins/utils/plugin_icon_resolver_docs_test.dart --dart-define=update_icons_doc=true
```

הפקודה כותבת מחדש את הבלוק שבין הסמנים — ורק אותו — ואז מריצה את הבדיקה שוב. הריצו אותה **מיד אחרי כל עדכון של `ref` של `otzaria_icons` ב-`pubspec.yaml`**, וכללו את `ICONS.md` באותו קומיט.

> למה בדיקה שנופלת ולא רשימה שמתעדכנת בשקט: הרשימה היא חוזה שמחברי תוספים עובדים לפיו. שם שנמחק מהספרייה מחייב בדיקת כינוי התאימות ב־`pluginIconFromName`, ולכן חייב להיראות בבדיקה; אייקון שנוסף אמור להתפרסם למחברים באותו קומיט שהכניס אותו.

**הוספת אייקון אינה דורשת עדכון קוד.** `pluginIconFromName` פותר מול `OtzariaIcons.allIcons` המגונררת בתוך הספרייה, ולכן כל אייקון שיתווסף לספרייה זמין לתוספים ברגע שה-`ref` מתעדכן — בלי לגעת בשורת קוד אחת באוצריא. שינוי שם או מחיקה מחייבים עדכון של כינויי התאימות ובדיקותיהם.

### למתחזקי `otzaria_icons`

שינויים בספרייה יצמצמו עוד את החיכוך בצד הזה. הם אינם חוסמים כלום היום — הצינור עובד גם בלעדיהם:

1. **נעיצה בתג.** לספרייה יש תגיות semver (`v0.6.0` וכו') ו-[CHANGELOG](https://github.com/Otzaria/otzaria_icons/blob/main/CHANGELOG.md) שמפרט שמות שנוספו, שונו ונמחקו בכל שחרור. `pubspec.yaml` נועץ ב-SHA של התג, כי `ref` בשם ענף או בתג אינו ניתן להשוואה בין מכונות בלי `pubspec.lock`.
2. **`icons.json` מגונרר לצד `otzaria_icons_data.dart`** — מפה של שם → codepoint. כלים שאינם Flutter (אתר התיעוד, סקריפטים) לא יצטרכו לפרסר Dart כדי לקבל את הרשימה.
3. **שינוי שם משאיר כינוי.** הספרייה עצמה אינה שומרת את השמות שהוחלפו ב־0.6.0; אוצריא שומרת אותם ב־`pluginIconFromName` עבור תוספים. כינויים מופחתים (deprecated) בספרייה יקלו על צרכנים נוספים. כל שינוי שם צריך להיכנס לטבלת [המעבר](#מעבר-לגרסת-הספרייה-060--שמות-שהשתנו) ולכינויי התאימות באותו קומיט שמעדכן את ה־`ref`.
