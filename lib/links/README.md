# Links Module - מודול קישורים

תיקייה זו מכילה את כל הקוד הקשור ליצירה, העתקה ופתיחה של קישורים ישירים לספרים באוצריא.

## ארכיטקטורה חדשה (2024)

המודול עבר ארגון מחדש מקצועי עם הפרדה ברורה בין שכבות:

### מבנה התיקייה:

```
lib/links/
├── links.dart                    # ייצוא ראשי
├── models/                       # מודלים בסיסיים
│   ├── link.dart                 # מודל קישור מרכזי
│   └── link_types.dart           # סוגי קישורים ו-enums
├── core/                         # פונקציונליות ליבה
│   ├── link_parser.dart          # פענוח קישורים
│   ├── link_generator.dart       # יצירת קישורים
│   └── link_handler.dart         # טיפול בקישורים
├── services/                     # שירותים
│   ├── navigation_service.dart   # ניווט בספרים
│   ├── sharing_service.dart      # שיתוף קישורים
│   └── url_service.dart          # טיפול ב-URLs
├── ui/                          # ממשק משתמש
│   ├── context_menu.dart         # תפריטי הקשר
│   └── search_integration.dart   # אינטגרציה עם חיפוש
├── utils/                       # כלים עזר
│   ├── encoding.dart             # קידוד/פענוח
│   ├── validation.dart           # בדיקות תקינות
│   └── text_processing.dart      # עיבוד טקסט
└── legacy/                      # תאימות לאחור (זמני)
    ├── link_models_wrapper.dart
    └── sharing_links_wrapper.dart
```

## שימוש מהיר

### יבוא המודול
```dart
import 'package:otzaria/links/links.dart';
```

### פתיחת קישור
```dart
await LinkHandler.openInApp(context, 'otzaria://book/ברכות?index=5');
```

### יצירת קישור
```dart
final link = BookLink.textBook('ברכות', index: 5);
final url = LinkGenerator.generate(link);
```

### שיתוף קישור
```dart
await SharingService.shareBook(context, book, position: 10);
```

### בדיקת תקינות
```dart
if (LinkValidation.isValidUrl(text)) {
  // הטקסט הוא קישור תקין
}
```

## פורמטים נתמכים

### 1. קישורי otzaria:// מלאים
- **`otzaria://book/שם_ספר?index=מספר&text=טקסט`** - קישורים לספרי טקסט
- **`otzaria://pdf/שם_ספר?page=מספר`** - קישורים לספרי PDF
- **`otzaria://inline-link?path=נתיב&index=אינדקס&ref=הפניה`** - קישורים מבוססי תווים

### 2. קישורי book:// פשוטים
- **`book://שם_ספר`** - פתיחת ספר מההתחלה
- **`book://שם_ספר#כותרת`** - פתיחת ספר במקום ספציפי

### 3. קישורים פנימיים
- **`#כותרת`** - מעבר לכותרת באותו ספר הפתוח

### 4. קישורים מקוצרים (זיהוי אוטומטי)
- **`שם_ספר?page=מספר`** - יזוהה כקישור לספר
- **`שם_ספר?index=מספר`** - יזוהה כקישור לספר טקסט

## API עיקרי

### LinkHandler - טיפול בקישורים
```dart
// פתיחת קישור באפליקציה
await LinkHandler.openInApp(context, url);

// טיפול מותאם אישית
await LinkHandler.handle(context, url, (tab) {
  // פתיחת הטאב
});
```

### LinkGenerator - יצירת קישורים
```dart
// יצירה מספר
final link = LinkGenerator.fromBook(book, position: 5);
final url = LinkGenerator.generate(link);

// יצירה מטאב
final link = LinkGenerator.fromTab(tab);
final url = LinkGenerator.generate(link);
```

### SharingService - שיתוף קישורים
```dart
// שיתוף ספר
await SharingService.shareBook(context, book);

// שיתוף עם הדגשה
await SharingService.shareWithHighlight(context, book, position, text);

// שיתוף טאב
await SharingService.shareTab(context, tab);
```

### NavigationService - ניווט בספרים
```dart
// ניווט לכותרת
await NavigationService.navigateToHeader(context, 'כותרת');

// ניווט לאינדקס
await NavigationService.navigateToIndex(context, 10);
```

## יתרונות הארכיטקטורה החדשה

1. **ארגון מקצועי** - הפרדה ברורה בין שכבות
2. **שמות ברורים** - API פשוט וקל לשימוש
3. **הרחבה קלה** - קל להוסיף פיצ'רים חדשים
4. **תחזוקה קלה** - קוד מאורגן ונקי
5. **ביצועים טובים** - קוד יעיל ומהיר
6. **בדיקות קלות** - כל מחלקה ניתנת לבדיקה בנפרד

## מעבר מהקוד הישן

ראה `MIGRATION_GUIDE.md` למדריך מפורט על המעבר מהקוד הישן לחדש.

## תאימות לאחור

הקוד הישן ממשיך לעבוד באמצעות wrapper files בתיקיית `legacy/`. 
הקבצים הישנים יוסרו בגרסה עתידית לאחר המעבר המלא.

---

*עודכן לאחרונה: ינואר 2025*