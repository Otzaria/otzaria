# מדריך מעבר לארכיטקטורה החדשה של מודול הקישורים

## שינויים עיקריים

### 1. מבנה קבצים חדש
```
הישן:                          החדש:
lib/links/core/                lib/links/core/
lib/links/models/              lib/links/models/
lib/links/ui/                  lib/links/ui/
lib/links/utils/               lib/links/utils/
                               lib/links/services/
```

### 2. שמות קבצים
```
הישן:                          החדש:
link_models.dart               link.dart + link_types.dart
url_encoding.dart              encoding.dart
book_navigation.dart           navigation_service.dart
sharing_links.dart             sharing_service.dart
context_menu_links.dart        context_menu.dart
search_box_link_handler.dart   search_integration.dart
url_handler_service.dart       url_service.dart
url_processor.dart             url_service.dart
text_with_inline_links.dart    text_processing.dart
```

### 3. שמות מחלקות ופונקציות

#### LinkParser
```dart
// הישן
LinkParser.parseUrl(url)

// החדש
LinkParser.parse(url)
```

#### LinkGenerator
```dart
// הישן
LinkGenerator.generateUrl(link)

// החדש
LinkGenerator.generate(link)
```

#### LinkHandler
```dart
// הישן
LinkHandler.handleLink(context, url, callback)
LinkHandler.openLinkInApp(context, url)

// החדש
LinkHandler.handle(context, url, callback)
LinkHandler.openInApp(context, url)
```

#### SharingService (הישן SharingLinks)
```dart
// הישן
SharingLinks.shareBookLink(context, book)
SharingLinks.shareTabLink(context, tab)

// החדש
SharingService.shareBook(context, book)
SharingService.shareTab(context, tab)
```

#### NavigationService (הישן BookNavigation)
```dart
// הישן
BookNavigation.navigateToHeader(context, header)
BookNavigation.findHeaderIndex(book, header)

// החדש
NavigationService.navigateToHeader(context, header)
NavigationService.findHeaderIndex(book, header)
```

#### UrlService (הישן UrlHandlerService + UrlProcessor)
```dart
// הישן
UrlHandlerService.initialize()
UrlProcessor.handleInitialUrl(context, url, callback)

// החדש
UrlService.initialize()
UrlService.handleInitialUrl(context, url, callback)
```

#### UrlEncoding → Encoding
```dart
// הישן
UrlEncoding.safeDecode(text)
UrlEncoding.safeEncode(text)
UrlEncoding.cleanUrl(url)

// החדש
UrlEncoding.decode(text)
UrlEncoding.encode(text)
UrlEncoding.clean(url)
```

#### TextProcessing (הישן text_with_inline_links)
```dart
// הישן
addInlineLinksToText(text, links)

// החדש
TextProcessing.addInlineLinks(text, links)
```

### 4. מודלים חדשים

#### BookLink
```dart
// הישן - יצירה ידנית
final link = BookLink(
  bookTitle: 'ספר',
  type: LinkType.textBook,
  position: 5,
);

// החדש - factory constructors
final link = BookLink.textBook('ספר', index: 5);
final pdfLink = BookLink.pdfBook('ספר', page: 10);
final simpleLink = BookLink.simple('ספר', header: 'כותרת');
final internalLink = BookLink.internal('כותרת');
```

#### LinkParseResult
```dart
// הישן
const LinkParseResult.success(link)
const LinkParseResult.failure(error)

// החדש - יותר אפשרויות
LinkParseResult.success(link)
LinkParseResult.failure(error)
LinkParseResult.empty()
LinkParseResult.invalidFormat(details)
LinkParseResult.missingParams(details)
```

### 5. Validation חדש
```dart
// חדש - בדיקות תקינות מפורטות
LinkValidation.isValidUrl(text)
LinkValidation.isValidBookTitle(title)
LinkValidation.isValidIndex(index)
LinkValidation.isValidPage(page)
LinkValidation.validateUrlParams(params)
```

### 6. Context Menu
```dart
// הישן
ContextMenuLinks.createShareBookLinkMenuItem(context, book)

// החדש
ContextMenuLinks.shareBookItem(context, book)
ContextMenuLinks.bookItems(context, book) // רשימה מלאה
```

### 7. Search Integration
```dart
// הישן
SearchBoxLinkHandler.isValidUrl(text)
SearchBoxLinkHandler.handleSearchUrl(context, url)

// החדש
SearchIntegration.isValidUrl(text)
SearchIntegration.handleSearchUrl(context, url)
SearchIntegration.detectUrls(text) // חדש
SearchIntegration.autoCorrectUrl(url) // חדש
```

## שלבי המעבר

### שלב 1: עדכון imports
החלף את כל ה-imports הישנים:
```dart
// הישן
import 'package:otzaria/links/core/link_handler.dart';
import 'package:otzaria/links/models/link_models.dart';
import 'package:otzaria/links/ui/sharing_links.dart';

// החדש
import 'package:otzaria/links/links.dart'; // import אחד לכל המודול
```

### שלב 2: עדכון קריאות לפונקציות
החלף את שמות הפונקציות לפי הטבלה למעלה.

### שלב 3: עדכון יצירת אובייקטים
השתמש ב-factory constructors החדשים במקום יצירה ידנית.

### שלב 4: בדיקות
הרץ בדיקות כדי לוודא שהכל עובד כמו קודם.

## יתרונות הארכיטקטורה החדשה

1. **ארגון טוב יותר** - הפרדה ברורה בין שכבות
2. **שמות קצרים יותר** - קל יותר לזכור ולהשתמש
3. **פחות תלות** - כל מחלקה עצמאית יותר
4. **API נקי יותר** - פונקציות פשוטות וברורות
5. **הרחבה קלה** - קל להוסיף פיצ'רים חדשים
6. **בדיקות טובות יותר** - כל מחלקה ניתנת לבדיקה בנפרד
7. **תחזוקה קלה יותר** - קוד מאורגן ונקי

## תאימות לאחור

הקבצים הישנים יישארו זמנית עם wrapper functions שקוראות לקוד החדש, כדי לא לשבור קוד קיים. לאחר המעבר המלא, הקבצים הישנים יוסרו.