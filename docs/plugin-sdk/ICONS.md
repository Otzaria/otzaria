# אייקוני אוצריא לתוספים

אוצריא מציגה אייקונים של תוספים משתי ספריות:

- **[Otzaria Icons](https://github.com/Otzaria/otzaria_icons)** — אייקונים מקוריים לעולם התוכן היהודי (ספרים, אותיות, צורת הדף, חיפוש בספרייה), בסגנון Fluent ובאותה מוסכמת שמות. הרשימה המלאה והמספר המדויק — [למטה](#רשימת-האייקונים-של-אוצריא).
- **[FluentUI System Icons](https://github.com/microsoft/fluentui-system-icons)** — כ-4,500 אייקוני 24px כלליים.

בכל שדה `icon` / `iconName` של תוסף אפשר לכתוב שם מכל אחת מהן — אין צורך להצהיר על ספרייה.

## כלל ההכרעה

השם נפתר קודם בספריית אוצריא ורק אחר כך בפלואנט — כלומר **בשם שקיים בשתיהן, אוצריא מנצחת**. השמות הכפולים מסומנים בטבלה שלמטה. הסיבה: הגליף של אוצריא צויר לספרייה תורנית ולממשק RTL, ולכן הוא הברירה הנכונה כשהוא קיים.

> ⚠️ שימו לב: מכיוון שאוצריא מנצחת, `book_24_regular` בתוסף שלכם ייתן את **ספר אוצריא**, לא את ספר פלואנט. אם התוסף שלכם כבר מותקן והסתמך על הצורה של פלואנט באחד מהשמות המשותפים, המראה שלו ישתנה — הוסיפו `fluent:` כדי לשמר אותו.

אם דווקא הצורה של פלואנט היא הנכונה לתוסף שלכם, כפו אותה בתחילית:

```jsonc
"iconName": "book_24_regular"          // אוצריא (ברירת מחדל)
"iconName": "otzaria:book_24_regular"  // אוצריא, במפורש
"iconName": "fluent:book_24_regular"   // פלואנט
```

תחילית מפורשת אינה נופלת לספרייה השנייה: `fluent:alef_24_regular` לא ייפתר, כי `alef_24_regular` קיים רק באוצריא. שימו לב שוולידציית המניפסט בודקת רק את **צורת** השם ולא את קיומו — `"otzaria:settings_24_regular"` יעבור התקנה בשקט ויוצג כפאזל.

## כללי השם

- **בשדה `iconName` שבמניפסט** הסיומת חייבת להיות `_24_regular` או `_24_filled` — `_20_`, `_16_` ו-`_24_light` נדחים בוולידציה. בשדות `icon` של ה-API בזמן ריצה אין ולידציה כלל, ושם גם `document_24_light` נפתר בפועל.
- שם שאינו קיים באף אחת מהספריות אינו זורק שגיאה: בלשונית הכלים ובפקד סרגל עליון יוצג אייקון פאזל ברירת מחדל; בפריט תפריט, בילד של תפריט נפתח ובשורת צבעים פשוט לא יוצג אייקון.
- אייקוני אוצריא אינם מתהפכים ב-RTL — הם מצוירים מלכתחילה לכיוון הממשק.

### מגבלה ידועה — אייקוני פלואנט כיווניים אינם זמינים

38 אייקוני פלואנט בגודל 24 שמוגדרים בחבילה עם `matchTextDirection` **חסרים ממפת השמות של התוספים** ולכן אינם נפתרים כלל (יוצגו כפאזל). ביניהם כל המשפחות שבהן היה הכי טבעי להשתמש לניווט:

`chevron_left/right_24_regular|filled` · `arrow_left/right_24_regular|filled` · `arrow_next/previous_24_*` · `arrow_forward_24_*` · `arrow_up_left/up_right/down_left_24_*` · `arrow_circle_right_24_*` · `arrow_import_24_*` · `text_align_left/right_24_*` · `text_column_two_left/right_24_*` · `swipe_right_24_*`

עד שהמפה תיווצר מחדש, השתמשו בחלופה לא-כיוונית — למשל `caret_left_24_filled` / `caret_right_24_filled`, `arrow_up_24_regular` / `arrow_down_24_regular`, או אייקון מאוצריא.

## דוגמאות בארבעת המקומות שבהם תוסף מצהיר על אייקון

**1. אייקון לשונית הכלים — `manifest.json`:**

```json
"contributes": {
  "toolTab": {
    "title": "סידורון",
    "iconName": "book_open_tzurat_hadaf_24_regular"
  }
}
```

**2. פקד בסרגל מסך העיון — `reader.addToolbarItem`:**

```javascript
await Otzaria.call('reader.addToolbarItem', {
  id: 'open-siddur',
  type: 'menu',                        // חובה כשיש children
  title: 'פתח סידור',
  icon: 'book_alef_24_regular',        // אוצריא
  children: [
    { id: 'weekday', title: 'חול', icon: 'book_open_medium_24_regular' },
    { id: 'shabbat', title: 'שבת', icon: 'book_star_24_regular' },
  ],
});
```

**3. פריט בתפריט ההקשר — `reader.addContextMenuItem`:**

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'search-in-book',
  label: 'חפש בספר זה',
  icon: 'search_in_the_book_24_regular',   // אוצריא
});

await Otzaria.call('reader.addContextMenuItem', {
  id: 'plain-book',
  label: 'פתח בספר',
  icon: 'fluent:book_24_regular',          // דווקא הצורה של פלואנט
});
```

**4. שורת צבעים בתפריט ההקשר** — ב-`type: 'color-row'` כל צבע יכול לשאת `icon`, והוא מוצג במקום גוש הצבע:

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'highlight',
  type: 'color-row',
  colors: [
    { id: 'yellow', color: '#FFD54F', label: 'צהוב' },
    { id: 'clear', color: '#00000000', label: 'נקה', icon: 'eraser_24_regular' },
  ],
});
```

## איך מוצאים אייקון

- **אוצריא** — הטבלה שלמטה, או הקטלוג האינטראקטיבי [`index.html`](https://github.com/Otzaria/otzaria_icons/blob/main/index.html) (חיפוש לפי שם ותצוגה בגדלים שונים). הוא טוען את הפונט בנתיב יחסי, ולכן צריך לשכפל את הריפו כולו ולפתוח את הקובץ מתוכו — הורדת הקובץ הבודד תציג שמות בלי גליפים.
- **פלואנט** — [מאגר FluentUI](https://github.com/microsoft/fluentui-system-icons), או חיפוש `FluentIcons.xxx_24_regular` בקוד אוצריא.

## רשימת האייקונים של אוצריא

הרשימה שלהלן **מגונררת מהספרייה** ואינה נערכת ביד. העמודה "גם בפלואנט" מסמנת שם שקיים בשתי הספריות — שם שבו כלל ההכרעה מכריע, ושבו התחילית `fluent:` משנה את התוצאה.

<!-- BEGIN GENERATED: otzaria-icons — אל תערכו ידנית, ראו "עדכון הרשימה" למטה -->

הספרייה מכילה **135 אייקונים**, ומהם **32** קיימים גם בפלואנט.

| שם | גם בפלואנט |
|-----|:---:|
| `alef_1_24_regular` |  |
| `alef_24_filled` |  |
| `alef_24_regular` |  |
| `alef_2_24_regular` |  |
| `alef_3_24_regular` |  |
| `alef_behind_alef_24_regular` |  |
| `alef_deletion_24_regular` |  |
| `alef_near_alef_24_regular` |  |
| `alef_rashi_24_regular` |  |
| `alef_stam_24_regular` |  |
| `alef_with_eraser_24_regular` |  |
| `alef_with_flavors_24_regular` |  |
| `alef_with_information_24_regular` |  |
| `alef_with_punctuation_24_regular` |  |
| `alef_with_score_24_regular` |  |
| `alef_writing_24_regular` |  |
| `apps_list_24_filled` | ✔ |
| `apps_list_24_regular` | ✔ |
| `apps_list_detail_24_filled` | ✔ |
| `apps_list_detail_24_regular` | ✔ |
| `beit_behind_alef_24_regular` |  |
| `beit_near_alef_24_regular` |  |
| `book_24_filled` | ✔ |
| `book_24_regular` | ✔ |
| `book_alef_24_filled` |  |
| `book_alef_24_regular` |  |
| `book_alef_rashi_24_filled` |  |
| `book_alef_rashi_24_regular` |  |
| `book_download_24_filled` |  |
| `book_download_24_regular` |  |
| `book_empty_24_filled` |  |
| `book_empty_24_regular` |  |
| `book_hyperlink_24_filled` |  |
| `book_hyperlink_24_regular` |  |
| `book_information_24_filled` | ✔ |
| `book_information_24_regular` | ✔ |
| `book_link_24_filled` |  |
| `book_link_24_regular` |  |
| `book_number_24_filled` | ✔ |
| `book_number_24_regular` | ✔ |
| `book_open_large_24_filled` |  |
| `book_open_large_24_regular` |  |
| `book_open_large_lines_24_filled` |  |
| `book_open_large_lines_24_regular` |  |
| `book_open_large_search_24_filled` |  |
| `book_open_large_search_24_regular` |  |
| `book_open_medium_24_regular` |  |
| `book_open_medium_line_24_regular` |  |
| `book_open_medium_search_24_regular` |  |
| `book_open_small_24_regular` |  |
| `book_open_small_line_24_regular` |  |
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
| `book_zim_24_filled` |  |
| `book_zim_24_regular` |  |
| `booklet_24_regular` |  |
| `booklet_empty_24_regular` |  |
| `books_stacked_high_24_regular` |  |
| `books_stacked_low_24_regular` |  |
| `bookshelf_24_filled` |  |
| `bookshelf_24_regular` |  |
| `calendar_24_filled` | ✔ |
| `calendar_24_regular` | ✔ |
| `clipboard_task_list_24_filled` |  |
| `clipboard_task_list_24_regular` |  |
| `clipboard_text_24_filled` |  |
| `clipboard_text_rtl_24_regular` | ✔ |
| `clock_add_24_regular` |  |
| `dependent_library_24_regular` |  |
| `document_bullet_list_24_filled` | ✔ |
| `document_bullet_list_24_regular` | ✔ |
| `document_column_24_filled` |  |
| `document_column_24_regular` |  |
| `document_word_24_filled` |  |
| `document_word_24_regular` |  |
| `group_list_24_filled` | ✔ |
| `group_list_24_regular` | ✔ |
| `hyperlink_24_regular` |  |
| `icon_x_24_regular` |  |
| `link_24_regular` | ✔ |
| `list_24_filled` | ✔ |
| `list_24_regular` | ✔ |
| `otzaria_icon_24_filled` |  |
| `otzaria_icon_24_regular` |  |
| `otzaria_icon_2_page_24_filled` |  |
| `otzaria_icon_2_page_24_regular` |  |
| `otzaria_icon_2_page_line_24_regular` |  |
| `otzaria_icon_empty_24_regular` |  |
| `otzaria_icon_line_24_filled` |  |
| `otzaria_icon_line_24_regular` |  |
| `person_24_filled` | ✔ |
| `person_24_regular` | ✔ |
| `search_24_filled` | ✔ |
| `search_24_regular` | ✔ |
| `search_in_numbered_list_24_regular` |  |
| `search_in_the_book_24_regular` |  |
| `search_in_the_document_24_regular` |  |
| `search_in_the_library_24_regular` |  |
| `search_in_the_person_24_regular` |  |
| `search_in_the_settings_24_regular` |  |
| `search_in_the_text_24_regular` |  |
| `search_in_titles_24_regular` |  |
| `search_not_found_24_filled` |  |
| `search_not_found_24_regular` |  |
| `stander_24_filled` |  |
| `stander_24_regular` |  |
| `task_list_24_filled` |  |
| `task_list_24_regular` |  |
| `task_list_square_24_filled` |  |
| `task_list_square_24_regular` |  |
| `tet_24_regular` |  |
| `tet_behind_tet_24_regular` |  |
| `tet_near_tet_24_regular` |  |
| `tet_tet_24_regular` |  |
| `text_alef_bet_list_24_regular` |  |
| `text_bullet_list_24_filled` | ✔ |
| `text_bullet_list_24_regular` | ✔ |
| `text_continuous_24_filled` | ✔ |
| `text_continuous_24_regular` | ✔ |
| `text_number_list_24_filled` |  |
| `text_number_list_24_regular` |  |
| `torah_scroll_24_regular` |  |
| `yoma_deilula_24_regular` |  |

<!-- END GENERATED: otzaria-icons -->

### עדכון הרשימה

הרשימה נגזרת משתי הספריות בזמן הבדיקה, ולכן כל שינוי בהן (אייקון שנוסף, אייקון שנמחק, או שם שהתחיל להתקיים גם בפלואנט) מפיל את
`test/plugins/utils/plugin_icon_resolver_docs_test.dart`. התיקון הוא פקודה אחת ולא עריכה ידנית:

```bash
flutter test test/plugins/utils/plugin_icon_resolver_docs_test.dart --dart-define=update_icons_doc=true
```

הפקודה כותבת מחדש את הבלוק שבין הסמנים — ורק אותו — ואז מריצה את הבדיקה שוב. הריצו אותה **מיד אחרי כל עדכון של `ref` של `otzaria_icons` ב-`pubspec.yaml`**, וכללו את `ICONS.md` באותו קומיט.

> למה בדיקה שנופלת ולא רשימה שמתעדכנת בשקט: הרשימה היא חוזה שמחברי תוספים עובדים לפיו. שם שנמחק מהספרייה שובר תוסף קיים, ולכן חייב להיראות בבדיקה; אייקון שנוסף אמור להתפרסם למחברים באותו קומיט שהכניס אותו.

**מה *לא* דורש עדכון:** הקוד. `pluginIconFromName` פותר מול `OtzariaIcons.allIcons` המגונררת בתוך הספרייה, ולכן כל אייקון שיתווסף לספרייה זמין לתוספים ברגע שה-`ref` מתעדכן — בלי לגעת בשורת קוד אחת באוצריא.

### למתחזקי `otzaria_icons`

שלושה שינויים בספרייה יצמצמו עוד את החיכוך בצד הזה. הם אינם חוסמים כלום היום — הצינור עובד גם בלעדיהם:

1. **תגיות semver לשחרורים.** כרגע `pubspec.yaml` מצביע על SHA גולמי, כי אין תגיות. עם `v0.3.0` וכו' אפשר יהיה לנעוץ `ref: v0.3.0` — נעיצה קריאה ובת-השוואה, במקום SHA שאי אפשר לדעת ממנו אם הוא קדימה או אחורה. (הנעיצה עצמה חייבת להישאר: `pubspec.lock` אינו במעקב, ובלי `ref` שתי מכונות יבנו מול ספריות שונות.)
2. **`icons.json` מגונרר לצד `otzaria_icons_data.dart`** — מפה של שם → codepoint. כלים שאינם Flutter (אתר התיעוד, סקריפטים) לא יצטרכו לפרסר Dart כדי לקבל את הרשימה.
3. **CHANGELOG שמפרט שמות שנוספו ושנמחקו בכל שחרור.** מחיקה או שינוי-שם שוברים תוסף מותקן, וכרגע אין דרך לראות אותם בלי diff על הקובץ המגונרר.
