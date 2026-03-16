# תיעוד ארכיטקטורה - אוצריא

> **עודכן אוטומטית:** קובץ זה מתעדכן אוטומטית כשמשנים קבצי ארכיטקטורה מרכזיים

## סקירה כללית

אוצריא היא אפליקציית ספרייה יהודית חינמית ופתוחה, הבנויה ב-Flutter/Dart.
התוכנה תומכת ב-Windows, Linux, Android, iOS ו-macOS.

**גרסה נוכחית:** 0.9.74

## דפוסי עיצוב מרכזיים

### 1. BLoC Pattern (Business Logic Component)
כל פיצ'ר מנוהל דרך BLoC עם שלושה רכיבים:
- **Event** - פעולות משתמש (LoadData, SearchBooks, וכו')
- **State** - מצבי UI (Loading, Loaded, Error)
- **Bloc** - לוגיקה עסקית שמקשרת בין Events ל-States

### 2. Repository Pattern
הפרדה בין לוגיקה עסקית לגישה לנתונים:
- **Repository** - API נקי לגישה לנתונים
- **Data Providers** - מימוש ספציפי (קבצים, DB, API)

### 3. Provider Pattern
Dependency Injection דרך Provider ו-RepositoryProvider

## מבנה תיקיות ליבה

```
lib/
├── main.dart                    # נקודת כניסה + אתחול
├── app.dart                     # MaterialApp + ניהול ערכות נושא
├── app_bloc_observer.dart       # ניטור BLoC לדיבאג
│
├── core/                        # רכיבי ליבה
│   ├── app_paths.dart          # ניהול נתיבי קבצים
│   ├── focus_repository.dart   # ניהול פוקוס
│   ├── ui_snack.dart           # מערכת התראות
│   └── window_*.dart           # ניהול חלונות
│
├── models/                      # מודלי נתונים
├── data/                        # שכבת נתונים
├── widgets/                     # רכיבי UI משותפים
└── theme/                       # ערכות נושא
```


## שכבת הנתונים (Data Layer)

### DataRepository (Singleton)
המרכז של כל גישה לנתונים. מתאם בין:
- FileSystemDataProvider - קריאת ספרים מקבצים
- SqliteDataProvider - הערות אישיות
- HiveDataProvider - טאבים, workspaces, היסטוריה, סימניות
- TantivyDataProvider - מנוע חיפוש

### Data Providers

| Provider | תפקיד | טכנולוגיה |
|----------|-------|-----------|
| FileSystemDataProvider | קריאת ספרים, TOC, metadata | File I/O |
| SqliteDataProvider | הערות אישיות | SQLite + sqflite |
| HiveDataProvider | אחסון מהיר של מצבים | Hive (NoSQL) |
| TantivyDataProvider | חיפוש טקסט מלא | Tantivy (Rust) |

### Cache Layer
מטמון בזיכרון לביצועים:
- **BooksCache** - רשימת ספרים (משותף בין Library ו-FindRef)
- **AcronymsCache** - ראשי תיבות (FindRef)

## רכיבי UI חובה

### 1. RtlTextField
**חובה לכל שדה טקסט!** מתקן בעיות RTL ב-Flutter Desktop:
- מקשי חיצים הפוכים
- Collapse של Selection
- תפריט הקשר מותאם

```dart
RtlTextField(
  controller: _controller,
  decoration: InputDecoration(labelText: 'חיפוש'),
)
```

### 2. UiSnack
**חובה להודעות משתמש!** מערכת התראות בסגנון Windows 11:
```dart
UiSnack.show('הפעולה בוצעה');
UiSnack.showError('שגיאה');
UiSnack.showSuccess('הצלחה');
```

### 3. Custom Dialogs
**חובה לדיאלוגים!** מ-`custom_ui_components.dart`:
- `SingleActionDialog` - כפתור אחד
- `TwoActionsDialog` - ביטול + אישור
- `WarningDialog` - אזהרה (ביטול מודגש, אישור אדום)

### 4. Action Buttons
**חובה לכפתורי פעולה!**
- `RecommendedActionButton` - פעולה מומלצת (primary)
- `NeutralActionButton` - פעולה ניטרלית (tonal)

### 5. SettingsCard
**חובה לכרטיסי הגדרות!** עיצוב Material 3:
```dart
SettingsCard(
  title: 'כותרת',
  children: [ListTile(...), SwitchListTile(...)],
)
```

### 6. Icons
**רק FluentUI Icons!**
```dart
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
Icon(FluentIcons.search_24_regular)
```


## תלויות מרכזיות

### State Management
- `flutter_bloc` ^9.1.1 - BLoC pattern
- `provider` ^6.1.5 - Dependency injection
- `equatable` ^2.0.8 - השוואת states

### Storage
- `hive` ^4.0.0-dev.2 - NoSQL מהיר (tabs, workspaces, history)
- `sqflite` ^2.4.2 - SQLite (personal notes)
- `isar` ^4.0.0-dev.14 - DB מהיר (references)

### Search
- `search_engine` (custom) - Tantivy wrapper (Rust)
- `fuzzywuzzy` ^1.1.6 - חיפוש fuzzy

### UI Components
- `fluentui_system_icons` ^1.1.273 - אייקונים (חובה!)
- `pdfrx` ^2.2.24 - PDF viewer
- `flutter_widget_from_html` ^0.17.0 - רינדור HTML
- `multi_split_view` ^3.6.1 - פיצול מסך

### Platform Support
- `window_manager` ^0.5.1 - ניהול חלונות Desktop
- `path_provider` ^2.1.5 - נתיבי מערכת
- `package_info_plus` ^9.0.0 - מידע אפליקציה

## מודלי נתונים מרכזיים

### Book (Abstract)
```dart
abstract class Book {
  final int? id;
  final String title;
  final Category? category;
  String? author;
  String? heCategories;
  int order;
  bool isUserBook;
  String? externalLibraryId;
}
```

**סוגי ספרים:**
- `TextBook` - ספרי טקסט (txt, docx)
- `PdfBook` - קבצי PDF
- `DocxBook` - קבצי Word
- `ExternalLibraryBook` - ספרים חיצוניים (Sefaria, Otzar)

### OpenedTab
```dart
sealed class OpenedTab {
  String title;
  bool isPinned;
  void dispose();
}
```

**סוגי טאבים:**
- `TextBookTab` - ספר טקסט
- `PdfBookTab` - ספר PDF
- `CombinedTab` - שני טאבים side-by-side

### Library & Category
```dart
class Library extends Category {
  // שורש עץ הקטגוריות
}

class Category {
  String title;
  List<Book> books;
  List<Category> subCategories;
  Category? parent;
}
```


## BLoCs מרכזיים

### LibraryBloc
**תפקיד:** ניהול הספרייה, ניווט בקטגוריות, חיפוש ספרים

**Events מרכזיים:**
- LoadLibrary, RefreshLibrary
- NavigateToCategory, NavigateUp
- SearchBooks, SelectBookForPreview

### TabsBloc
**תפקיד:** ניהול טאבים, side-by-side mode

**Events מרכזיים:**
- AddTab, RemoveTab, SetCurrentTab
- EnableSideBySideMode, DisableSideBySideMode
- TogglePinTab, CloneTab, MoveTab

**אופטימיזציה:** עוצר Pdfrx worker כשאין PDF tabs

### SearchBloc
**תפקיד:** חיפוש טקסט מלא (Tantivy)

**תכונות:**
- כתיב מלא/חסר
- קידומות/סיומות
- מרווחים מותאמים
- Fuzzy search

### SettingsBloc
**תפקיד:** ניהול הגדרות

**הגדרות מרכזיות:**
- seedColor, darkSeedColor
- isDarkMode, followSystemTheme
- fontSize, libraryPath

## זרימות נתונים

### אתחול
```
main() → initialize() → runApp()
  ├── Sentry.init()
  ├── Settings.init()
  ├── initHive()
  ├── SqliteDataProvider.init()
  ├── BooksCache.warmUp()
  └── BackupService.performAutoBackup()
```

### פתיחת ספר
```
User clicks → openBook() → TabsBloc.add(AddTab())
  → TabsRepository.saveTabs() → Hive
  → UI updates (BlocBuilder)
```

### חיפוש
```
User types → SearchBloc.add(SearchRequested())
  → SearchRepository.searchTexts()
  → TantivyDataProvider.search()
  → SearchBloc.emit(SearchLoaded())
```


## בעיות ארכיטקטוניות ידועות

### 1. RTL Support
**בעיה:** Flutter Desktop לא תומך טוב ב-RTL
**פתרון:** RtlTextField מתקן מקשי חיצים ו-selection

### 2. PDF Worker Memory
**בעיה:** Pdfrx worker ממשיך לרוץ גם אחרי סגירת PDF tabs
**פתרון:** TabsBloc עוצר worker אוטומטית כשאין PDF tabs

### 3. Lazy Loading של External Books
**בעיה:** טעינת Otzar/HebrewBooks הייתה חוסמת את האתחול
**פתרון:** Lazy loading - נטען רק כשמחפשים

### 4. Cache Warming
**בעיה:** קריאות DB חוזרות מאטות את האפליקציה
**פתרון:** BooksCache ו-AcronymsCache נטענים באתחול

### 5. Window Focus + Keyboard State
**בעיה:** HardwareKeyboard assertion כשמאבדים פוקוס עם מקש לחוץ
**פתרון:** AppWindowListener.onWindowFocus() מנקה את המצב

## נקודות שיפור אפשריות

### ביצועים
- [ ] העברת ספרים ל-SQLite במקום קבצי טקסט
- [ ] Semantic search עם embeddings
- [ ] טעינה lazy של TOC (נטען רק כשצריך)
- [ ] Web Workers לחיפוש (במקום Isolates)

### ארכיטקטורה
- [ ] הפרדה ברורה יותר בין UI ל-Business Logic
- [ ] Dependency Injection מסודר יותר (get_it?)
- [ ] Event Sourcing לטאבים והיסטוריה
- [ ] CQRS pattern לחיפוש

### Testing
- [ ] יותר unit tests ל-BLoCs
- [ ] Integration tests לזרימות מרכזיות
- [ ] Widget tests לרכיבי UI מותאמים אישית
- [ ] Performance tests לחיפוש

### UI/UX
- [ ] Accessibility - תמיכה ב-screen readers
- [ ] Keyboard navigation מלא
- [ ] Responsive design טוב יותר למובייל
- [ ] Dark mode אוטומטי לפי שעה



## פיצ'רים מרכזיים

### 1. Library (ספרייה)
**תיקייה:** `lib/library/`

**תפקיד:** ניהול הספרייה, ניווט בקטגוריות, חיפוש ספרים

**רכיבים:**
- `LibraryBloc` - ניהול מצב הספרייה
- `LibraryScreen` - מסך הספרייה הראשי
- `Library` model - עץ קטגוריות וספרים

**Events מרכזיים:**
- `LoadLibrary` - טעינת הספרייה
- `RefreshLibrary` - רענון הספרייה
- `NavigateToCategory` - ניווט לקטגוריה
- `SearchBooks` - חיפוש ספרים

### 2. Tabs (טאבים)
**תיקייה:** `lib/tabs/`

**תפקיד:** ניהול טאבים פתוחים, side-by-side mode

**רכיבים:**
- `TabsBloc` - ניהול מצב הטאבים
- `TabsRepository` - שמירה/טעינה מ-Hive
- `OpenedTab` - מודל טאב (sealed class)

**סוגי טאבים:**
- `TextBookTab` - ספר טקסט
- `PdfBookTab` - ספר PDF
- `CombinedTab` - שני טאבים side-by-side

**אופטימיזציה:** עוצר Pdfrx worker כשאין PDF tabs פתוחים

### 3. Search (חיפוש)
**תיקייה:** `lib/search/`

**תפקיד:** חיפוש טקסט מלא במנוע Tantivy

**רכיבים:**
- `SearchBloc` - ניהול מצב החיפוש
- `SearchRepository` - ממשק למנוע החיפוש
- `SearchScreen` - מסך תוצאות החיפוש

**תכונות:**
- כתיב מלא/חסר
- קידומות/סיומות
- מרווחים מותאמים
- Fuzzy search
- סינון לפי קטגוריות

### 4. FindRef (מציאת מראי מקום)
**תיקייה:** `lib/find_ref/`

**תפקיד:** חיפוש מראי מקום בספרים

**רכיבים:**
- `FindRefBloc` - ניהול מצב החיפוש
- `FindRefRepository` - גישה ל-Isar DB
- `FindRefDialog` - דיאלוג חיפוש

**מאגר נתונים:**
- Isar DB עם אינדקס על מראי מקום
- AcronymsCache - מטמון ראשי תיבות
- BooksCache - מטמון ספרים משותף עם Library

### 5. Personal Notes (הערות אישיות)
**תיקייה:** `lib/personal_notes/`

**תפקיד:** ניהול הערות אישיות על קטעי טקסט

**רכיבים:**
- `PersonalNotesBloc` - ניהול מצב ההערות
- `PersonalNotesRepository` - גישה ל-SQLite
- `PersonalNotesScreen` - מסך ההערות

**אחסון:** SQLite (מיגרציה מקבצים ל-DB)

### 6. Bookmarks (סימניות)
**תיקייה:** `lib/bookmarks/`

**תפקיד:** ניהול סימניות למיקומים בספרים

**רכיבים:**
- `BookmarkBloc` - ניהול מצב הסימניות
- `BookmarkRepository` - גישה ל-Hive
- `BookmarksDialog` - דיאלוג סימניות

**אחסון:** Hive

### 7. History (היסטוריה)
**תיקייה:** `lib/history/`

**תפקיד:** מעקב אחר ספרים שנקראו

**רכיבים:**
- `HistoryBloc` - ניהול מצב ההיסטוריה
- `HistoryRepository` - גישה ל-Hive
- `HistoryScreen` - מסך היסטוריה

**אחסון:** Hive

### 8. Workspaces (סביבות עבודה)
**תיקייה:** `lib/workspaces/`

**תפקיד:** ניהול סביבות עבודה (קבוצות טאבים)

**רכיבים:**
- `WorkspaceBloc` - ניהול מצב הסביבות
- `WorkspaceRepository` - גישה ל-Hive
- `Workspace` model - מודל סביבת עבודה

**תכונות:**
- שמירת קבוצות טאבים
- מעבר בין סביבות
- שמירה אוטומטית

### 9. Settings (הגדרות)
**תיקייה:** `lib/settings/`

**תפקיד:** ניהול הגדרות האפליקציה

**רכיבים:**
- `SettingsBloc` - ניהול מצב ההגדרות
- `SettingsRepository` - גישה ל-Hive
- `SettingsScreen` - מסך הגדרות

**הגדרות מרכזיות:**
- `seedColor`, `darkSeedColor` - צבעי ערכת נושא
- `isDarkMode`, `followSystemTheme` - מצב כהה
- `fontSize` - גודל גופן
- `libraryPath` - נתיב הספרייה
- `fontFamily` - משפחת גופן

### 10. TextBook (ספר טקסט)
**תיקייה:** `lib/text_book/`

**תפקיד:** תצוגת ספרי טקסט עם תכונות מתקדמות

**רכיבים:**
- `TextBookBloc` - ניהול מצב הספר
- `TextBookScreen` - מסך קריאה
- `CommentaryPanel` - פאנל פרשנים

**תכונות:**
- תצוגת טקסט עם ניקוד
- פאנל פרשנים
- חיפוש בספר
- ניווט לפי TOC
- העתקה מעוצבת

### 11. PdfBook (ספר PDF)
**תיקייה:** `lib/pdf_book/`

**תפקיד:** תצוגת קבצי PDF עם תכונות מתקדמות

**רכיבים:**
- `PdfBookBloc` - ניהול מצב ה-PDF
- `PdfBookScreen` - מסך קריאה
- `PdfCommentaryPanel` - פאנל פרשנים ל-PDF

**תכונות:**
- תצוגת PDF עם zoom
- פאנל פרשנים
- חיפוש ב-PDF
- Thumbnails
- Outlines (TOC)

**ספריה:** `pdfrx` ^2.2.24

### 12. Indexing (אינדוקס)
**תיקייה:** `lib/indexing/`

**תפקיד:** בניית אינדקס חיפוש Tantivy

**רכיבים:**
- `IndexingBloc` - ניהול תהליך האינדוקס
- `IndexingRepository` - ממשק למנוע

**תהליך:**
- סריקת כל הספרים
- חילוץ טקסט
- הוספה למנוע Tantivy
- עדכון progress

### 13. Navigation (ניווט)
**תיקייה:** `lib/navigation/`

**תפקיד:** ניווט ראשי, title bar, about screen

**רכיבים:**
- `NavigationBloc` - ניהול מצב הניווט
- `MainWindowScreen` - מסך ראשי
- `CustomTitleBar` - title bar מותאם אישית
- `AboutScreen` - מסך אודות

### 14. Shortcuts (קיצורי מקלדת)
**תיקייה:** `lib/shortcuts/`

**תפקיד:** ניהול קיצורי מקלדת מותאמים אישית

**רכיבים:**
- `KeyboardShortcuts` - מפת קיצורים
- `ShortcutHelper` - עזרים לקיצורים
- `CustomShortcutDialog` - דיאלוג עריכת קיצורים

### 15. Tools (כלים)
**תיקייה:** `lib/tools/`

**כלים זמינים:**
- **Dictionary** - מילון עברי
- **Aramaic Dictionary** - מילון ארמי
- **Acronyms Dictionary** - מילון ראשי תיבות
- **Gematria** - חישובי גימטריה
- **Calendar** - לוח שנה עברי + תזכורות
- **Shamor Zachor** - כלי לימוד שמור וזכור
- **Measurement Converter** - המרת מידות

**מסך מרכזי:** `MoreScreen` - גישה לכל הכלים

### 16. External Catalog (קטלוג חיצוני)
**תיקייה:** `lib/external_catalog/`

**תפקיד:** גישה לספריות חיצוניות (Otzar, HebrewBooks)

**רכיבים:**
- `ExternalCatalogBloc` - ניהול מצב
- `ExternalCatalogScreen` - מסך חיפוש

**ספריות חיצוניות:**
- Otzar HaHochma
- HebrewBooks.org

**אופטימיזציה:** Lazy loading - נטען רק כשמחפשים

### 17. File Sync (סנכרון קבצים)
**תיקייה:** `lib/file_sync/`

**תפקיד:** סנכרון ספרים מ-Google Drive

**רכיבים:**
- `FileSyncBloc` - ניהול תהליך הסנכרון
- `FileSyncRepository` - גישה ל-Google Drive API
- `FileSyncWidget` - ווידג'ט סנכרון

### 18. Printing (הדפסה)
**תיקייה:** `lib/printing/`

**תפקיד:** הדפסת דפים מספרים

**רכיבים:**
- `PrintingScreen` - מסך הדפסה
- שימוש בספריית `printing` + `pdf`

### 19. Update (עדכונים)
**תיקייה:** `lib/update/`

**תפקיד:** בדיקת עדכונים והתקנה

**רכיבים:**
- `MyUpdatWidget` - ווידג'ט עדכונים
- `LinuxInstaller` - התקנה ב-Linux
- שימוש בספריית `updat`

### 20. Daf Yomi (דף יומי)
**תיקייה:** `lib/daf_yomi/`

**תפקיד:** חישוב דף יומי

**רכיבים:**
- `DafYomiHelper` - חישובי דף יומי
- `Calendar` - לוח שנה עברי
- שימוש בספריית `kosher_dart`


## רכיבי UI נוספים

### 7. SegmentedSettingsTile
**חובה להגדרות עם 2-4 אפשרויות!** מ-`custom_ui_components.dart`:
```dart
SegmentedSettingsTile<String>(
  icon: FluentIcons.text_font_info_24_regular,
  title: 'הצגת הניקוד',
  subtitle: 'הניקוד יוצג בכל הספרים',
  options: const [
    SegmentOption(value: 'always', label: 'הצג תמיד'),
    SegmentOption(value: 'never', label: 'אל תציג'),
  ],
  currentValue: currentValue,
  onChanged: (value) => updateSetting(value),
);
```

**מתי להשתמש:**
- הגדרות עם 2-4 אפשרויות בלעדיות
- חלופה מודרנית ל-RadioButton או SwitchListTile מרובים

### 8. SmartText
**תיקייה:** `lib/widgets/smart_text/`

**תפקיד:** תצוגת טקסט חכמה עם קישורים

**רכיבים:**
- `SmartText` - טקסט עם זיהוי קישורים אוטומטי
- `TextWithInlineLinks` - טקסט עם קישורים מוטמעים

### 9. Custom UI Components
**קובץ:** `lib/widgets/custom_ui_components.dart`

**רכיבים נוספים:**
- `LoadingIndicator` - אינדיקטור טעינה
- `ConfirmationDialog` - דיאלוג אישור
- `InputDialog` - דיאלוג קלט
- `MultiSelectionDialog` - דיאלוג בחירה מרובה
- `FilterChipsWidget` - chips לסינון


## Data Providers מפורט

### FileSystemDataProvider
**תפקיד:** קריאת ספרים מקבצים

**פעולות:**
- `getLibrary()` - טעינת מבנה הספרייה
- `getBookText()` - קריאת תוכן ספר
- `getBookToc()` - קריאת תוכן עניינים
- `getOtzarBooks()` - טעינת ספרי אוצר
- `getHebrewBooks()` - טעינת ספרי HebrewBooks

**פורמטים נתמכים:**
- TXT - טקסט רגיל
- DOCX - Word documents
- PDF - קבצי PDF
- JSON - metadata

### SqliteDataProvider
**תפקיד:** הערות אישיות

**טבלאות:**
- `personal_notes` - הערות משתמש

**פעולות:**
- CRUD על הערות
- חיפוש בהערות

**מיגרציה:** `FileToDbMigrator` - מעביר הערות מקבצים ל-DB

### HiveDataProvider
**תפקיד:** אחסון מהיר של מצבים

**Boxes:**
- `tabs` - טאבים פתוחים (max 100MB)
- `workspaces` - סביבות עבודה (max 100MB)
- `history` - היסטוריית קריאה (max 100MB)
- `bookmarks` - סימניות (max 100MB)

**יתרונות:**
- מהיר מאוד (NoSQL)
- ללא schema
- תמיכה ב-complex objects

### TantivyDataProvider
**תפקיד:** מנוע חיפוש טקסט מלא

**טכנולוגיה:** Tantivy (Rust) דרך FFI

**תכונות:**
- חיפוש מהיר (inverted index)
- תמיכה בעברית
- Fuzzy search
- Phrase search
- Boolean queries

**אינדקס:** נבנה ב-background דרך `IndexingBloc`


## מודלי נתונים נוספים

### Ref (מראה מקום)
```dart
@collection
class Ref {
  Id id = Isar.autoIncrement;
  String? ref;
  String? bookTitle;
  int? index;
}
```

**שימוש:** מאוחסן ב-Isar DB לחיפוש מהיר

### TocEntry (ערך תוכן עניינים)
```dart
class TocEntry {
  String text;
  int index;
  int level;
  List<TocEntry> children;
}
```

**שימוש:** ניווט בספרים

### Workspace (סביבת עבודה)
```dart
class Workspace {
  String name;
  List<OpenedTab> tabs;
  int activeTabIndex;
}
```

**שימוש:** שמירת קבוצות טאבים

### PersonalNote (הערה אישית)
```dart
class PersonalNote {
  int? id;
  String bookTitle;
  int index;
  String text;
  DateTime created;
  DateTime? modified;
}
```

**שימוש:** הערות משתמש על קטעי טקסט


## Services (שירותים)

### BackupService
**קובץ:** `lib/settings/services/backup_service.dart`

**תפקיד:** גיבוי אוטומטי של נתונים

**תכונות:**
- גיבוי אוטומטי יומי
- שחזור מגיבוי
- ניהול קבצי גיבוי

### NotificationService
**קובץ:** `lib/tools/calendar/services/notification_service.dart`

**תפקיד:** תזכורות ללוח שנה עברי

**תכונות:**
- תזכורות לחגים
- תזכורות מותאמות אישית
- שימוש ב-`flutter_local_notifications`

### CommentaryService
**קובץ:** `lib/services/commentary_service.dart`

**תפקיד:** ניהול פרשנים

**תכונות:**
- טעינת רשימת פרשנים
- סינון פרשנים
- קישור בין טקסט לפרשנים

### BookDetailsService
**קובץ:** `lib/services/book_details_service.dart`

**תפקיד:** מידע על ספרים

**תכונות:**
- metadata של ספרים
- קישורים חיצוניים
- מידע על מחבר


## Utils (עזרים)

### OpenBook
**קובץ:** `lib/utils/open_book.dart`

**תפקיד:** פתיחת ספרים בטאבים

**פונקציות:**
- `openBook()` - פתיחת ספר חדש
- `openBookAtIndex()` - פתיחה במיקום ספציפי
- `openBookInNewTab()` - פתיחה בטאב חדש

### TocParser
**קובץ:** `lib/utils/toc_parser.dart`

**תפקיד:** פרסור תוכן עניינים

**פונקציות:**
- `parseToc()` - המרת טקסט ל-TocEntry
- `findTocEntry()` - חיפוש ערך בעץ

### CopyUtils
**קובץ:** `lib/utils/copy_utils.dart`

**תפקיד:** העתקה מעוצבת ללוח

**פונקציות:**
- `copyPlainText()` - העתקה רגילה
- `copyFormattedText()` - העתקה עם עיצוב
- `copyWithMetadata()` - העתקה עם מטא-דאטה

### TextManipulation
**קובץ:** `lib/utils/text_manipulation.dart`

**תפקיד:** עיבוד טקסט

**פונקציות:**
- `removeNikud()` - הסרת ניקוד
- `normalizeText()` - נרמול טקסט
- `highlightText()` - הדגשת טקסט


## Theme System (מערכת ערכות נושא)

### AppColors
**קובץ:** `lib/theme/app_colors.dart`

**צבעים מוגדרים:**
- `darkScaffold` - רקע כהה (#242424)
- `darkCard` - כרטיס כהה (#333333)
- `darkOnSurface` - טקסט כהה (#E0E0E0)
- `darkOutline` - מתאר כהה (#4A4A4A)
- `darkAppBar` - AppBar כהה (#2A2A2A)
- `dialogBarrier` - רקע דיאלוג (שחור ~13%)

### AppFonts
**קובץ:** `lib/theme/app_fonts.dart`

**גופנים זמינים:**
- TaameyAshkenaz
- FrankRuhlCLM
- Rubik
- NotoRashiHebrew
- TaameyDavidCLM
- Shofar
- KeterYG
- Tinos
- NotoSerifHebrew

### AppTheme
**קובץ:** `lib/theme/app_theme.dart`

**תכונות:**
- Dynamic color scheme מ-seed color
- תמיכה ב-monochrome למצבים ניטרליים
- Dark mode מותאם אישית
- Follow system theme

### LayoutTokens
**קובץ:** `lib/theme/layout_tokens.dart`

**קבועים:**
- `radiusXL` - 20 (כרטיסים)
- `radiusMD` - 12 (דיאלוגים)
- `radiusSM` - 8 (כפתורים)
- `spacing` - 4, 8, 16, 24, 32
