# Links Module

תיקייה זו מכילה את כל הקוד הקשור ליצירה, העתקה ופתיחה של קישורים ישירים לספרים באוצריא.

## מבנה התיקייה:

### Core Files:
- `link_handler.dart` - מחלקה מרכזית לטיפול בכל סוגי הקישורים
- `link_generator.dart` - יצירת קישורים לספרים
- `link_parser.dart` - פענוח וניתוח קישורים

### UI Integration:
- `search_box_link_handler.dart` - טיפול בקישורים מתיבת החיפוש
- `context_menu_links.dart` - קישורים בתפריטי הקשר
- `sharing_links.dart` - שיתוף קישורים

### Models:
- `link_models.dart` - מודלים לייצוג קישורים

### Utils:
- `url_encoding.dart` - קידוד ופענוח URLs

### Main Export:
- `links.dart` - ייצוא כל המחלקות

## פורמטים נתמכים

המודול תומך בכל הפורמטים הבאים:

### 1. קישורי otzaria:// מלאים
- **`otzaria://book/שם_ספר?index=מספר&text=טקסט`** - קישורים לספרי טקסט
  - `index` - מספר המקטע בספר (0-based)
  - `text` - טקסט להדגשה או `true` להדגשת כל המקטע
- **`otzaria://pdf/שם_ספר?page=מספר`** - קישורים לספרי PDF
  - `page` - מספר העמוד בספר PDF
- **`otzaria://inline-link?path=נתיב&index=אינדקס&ref=הפניה`** - קישורים מבוססי תווים
  - `path` - נתיב מדויק לקובץ הספר
  - `index` - אינדקס המקטע (1-based, יומר ל-0-based)
  - `ref` - הפניה או תיאור המיקום

### 2. קישורי book:// פשוטים
- **`book://שם_ספר`** - פתיחת ספר מההתחלה
- **`book://שם_ספר#כותרת`** - פתיחת ספר במקום ספציפי
- **`book://שם_ספר#דף#צד`** - מבנה תלמודי מלא

### 3. קישורים פנימיים
- **`#כותרת`** - מעבר לכותרת באותו ספר הפתוח

### 4. קישורים מקוצרים (זיהוי אוטומטי)
- **`שם_ספר?page=מספר`** - יזוהה כקישור לספר
- **`שם_ספר?index=מספר`** - יזוהה כקישור לספר טקסט
- **`path=נתיב&index=אינדקס`** - יזוהה כקישור inline

### 5. קישורים חיצוניים (תמיכה עתידית)
- **`http://...`** / **`https://...`** - קישורים חיצוניים

## שימוש:

### פתיחת קישור:
```dart
import 'package:otzaria/links/links.dart';

// פתיחת קישור באפליקציה
await LinkHandler.openLinkInApp(context, 'otzaria://book/ברכות?index=5');
```

### יצירת קישור:
```dart
// יצירת קישור לספר
final url = LinkGenerator.createSharingUrl(book, position: 10);

// שיתוף קישור
await SharingLinks.shareBookLink(context, book, position: 10);
```

### בדיקת תקינות קישור:
```dart
if (LinkParser.isValidUrl(text)) {
  // הטקסט הוא קישור תקין
}
```

## אינטגרציה עם הקוד הקיים:

המודול מחליף את הקבצים הישנים:
- `lib/utils/html_link_handler.dart` - עכשיו wrapper ל-LinkHandler
- `lib/utils/search_url_handler.dart` - הועבר ל-SearchBoxLinkHandler
- `lib/utils/search_url_examples.dart` - מידע עבר לתיעוד

## עקרונות עיצוב:

1. **הפרדה** - כל הקוד הקשור לקישורים במקום אחד
2. **מודולריות** - כל מחלקה אחראית על תחום ספציפי
3. **תאימות לאחור** - הקוד הקיים ממשיך לעבוד
4. **הרחבה** - קל להוסיף סוגי קישורים חדשים
5. **בדיקות** - מבנה שמאפשר בדיקות יחידה קלות