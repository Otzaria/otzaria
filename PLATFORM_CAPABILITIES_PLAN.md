# תוכנית מקיפה לשכבת פלטפורמות ויכולות קלט

## מטרה

לבנות שכבת תשתית אחת, ברורה ויציבה, שמרכזת:

- זיהוי פלטפורמה
- זיהוי סוג מכשיר
- זיהוי יכולות קלט
- החלטות מוצר שתלויות בפלטפורמה

כך שכל הקוד בפרויקט יפסיק לפזר:

- `Platform.isWindows`
- `Platform.isIOS`
- `defaultTargetPlatform`
- `kIsWeb`

בצורה לא אחידה במסכים, בשירותים, בהגדרות ובקיצורי מקשים.

---

## למה צריך את זה

נכון לעכשיו יש בפרויקט ערבוב של כמה סוגי החלטות:

- החלטות runtime:
  "האם זה Desktop?"
- החלטות מוצר:
  "איזה modifier צריך להיות ברירת מחדל לקיצור?"
- החלטות UI:
  "האם נכון להציג tooltip?"
- החלטות device:
  "האם זה iPad או iPhone?"

והכול מפוזר היום בין:

- `dart:io Platform`
- `defaultTargetPlatform`
- בדיקות ידניות בתוך מסכים
- מסמכים חיצוניים שלא מחוברים לתשתית

התוצאה:

- קשה לקבוע מדיניות עקבית
- קשה לשתף לוגיקה בין מסכים
- קשה לממש נכון קיצורי מקשים לפי פלטפורמה

---

## הקשר למסמך הקיצורים

המסמך הזה הוא מסמך תשתית רוחבי.

הוא קשור ישירות ל:

- [SHORTCUTS_REFACTOR_PLAN.md](./SHORTCUTS_REFACTOR_PLAN.md)

ובפרט הוא משפיע על:

- ברירות מחדל שונות של קיצורי מקשים לפי פלטפורמה
- formatter שונה ל-`Ctrl` מול `⌘`
- החלטה אם להציג tooltip / help / discoverability
- ההבחנה בין iPad, iPhone, macOS, Windows ועוד

לכן:

- שכבת הפלטפורמות צריכה להיבנות **לפני** השלב המלא של platform-specific shortcuts
- אבל לא חייבים להשלים את כל המסמך הזה לפני סבב ייצוב הבאגים בקיצורים

מיפוי לשלבי מסמך הקיצורים:

- שלב 1 בקיצורים:
  לא תלוי במימוש מלא של שכבת הפלטפורמות
- שלב 2-3 בקיצורים:
  כן צריכים כבר לקבל החלטה על מבנה הפלטפורמות
- שלב 6 בקיצורים:
  תלוי ישירות במסמך הזה, כי שם בונים bindings גלובליים לפי פלטפורמה

---

## תמונת מצב נוכחית

כיום קיימים שני קבצים בשורש:

- [app_platform.dart](./app_platform.dart)
- [CORE.md](./CORE.md)

הם נותנים כיוון טוב, אבל אינם מספיקים כמו שהם.

### מה טוב בקובץ app_platform.dart

- הוא מציע לרכז שאלות פלטפורמה במקום אחד
- הוא מגדיר `isDesktop` ו-`isMobile`
- הוא מגדיר יכולות כלליות כמו:
  `supportsWindowManagement`

### מה חסר בו

- אין הבחנה בין iPad ל-iPhone
- אין הבחנה בין phone / tablet / desktop
- אין שכבת יכולות קלט:
  מקלדת, pointer, hover, modifier ראשי
- אין חיבור מפורש לקיצורי מקשים
- הוא נמצא בשורש ולא ב-`lib/core/`

### מה טוב ב-CORE.md

- הוא מזהה נכון שקובץ פלטפורמות הוא חלק מ-`core/`
- הוא מכוון לריכוז לוגיקה רוחבית

### מה חסר בו

- הוא עוסק בעיקר במיקום קבצים, לא במדיניות מוצר
- הוא לא מגדיר את שכבת היכולות שצריך בשביל קיצורים
- יש בו חוסר עקביות בשם:
  `platform.dart` מול `app_platform.dart`

---

## מה צריך להיות המבנה הנכון

### 1. שכבת Platform בסיסית

קובץ מומלץ:

- `lib/core/app_platform.dart`

אחריות:

- מערכת הפעלה
- משפחת פלטפורמה
- desktop / mobile / web

למשל:

- `isWindows`
- `isLinux`
- `isMacOS`
- `isAndroid`
- `isIOS`
- `isDesktop`
- `isMobile`
- `isWeb`

### 2. שכבת Device Class

קובץ מומלץ:

- `lib/core/device_class.dart`

אחריות:

- `phone`
- `tablet`
- `desktop`

החלטה זו לא צריכה להתבסס על `Platform.isIOS` בלבד.

אבל גם לא נכון להציג אותה כאילו היא helper סטטי פשוט ב-core בלבד.

בפועל:

- `MediaQuery` לא זמין בשכבת core סטטית
- `device class` תלוי לעיתים ב-widget tree ובגודל חלון בפועל

לכן המימוש הנכון כנראה יהיה דו-שכבתי:

- שכבת core שמחזיקה enums / policy / contracts
- שכבת UI/runtime שממפה בפועל לפי `MediaQuery`, `View`, או גודל חלון

כלומר:

- לא לבנות `device_class.dart` כ-helper סטטי נאיבי שמנסה לדעת הכול בלי context
- כן לבנות מודל מסודר שבו ההחלטה בפועל יכולה להגיע משכבת runtime

### 3. שכבת Input Capabilities

קובץ מומלץ:

- `lib/core/input_capabilities.dart`

אחריות:

- האם יש workflow של hardware keyboard
- האם יש pointer
- האם יש hover
- מה modifier הראשי לקיצורים

למשל:

- `keyboardWorkflowAvailable`
- `supportsPointer`
- `supportsHover`
- `primaryShortcutModifier`

הערת מימוש חשובה:

ב-Flutter אין API פשוט ואחיד שאומר:

- "יש עכשיו מקלדת חיצונית מחוברת"

לכן לא נכון לבנות את זה כ-property סטטי פשוט כאילו זה מידע ודאי וזמין תמיד.

במקום זאת צריך להבחין בין:

- יכולת פלטפורמה עקרונית:
  האם הפלטפורמה בכלל תומכת ב-workflow כזה
- מצב runtime:
  האם בפועל יש כרגע תנאים טובים לעבודה מבוססת מקלדת

במילים אחרות:

- `supportsHardwareKeyboard` כשדה סטטי הוא שם מטעה מדי
- עדיף לנסח capability מוצרי כמו:
  `keyboardWorkflowAvailable`
  או
  `prefersKeyboardShortcutsUI`

וכשצריך runtime state אמיתי, להביא אותו משכבת UI/interaction ולא רק מ-core

### 4. שכבת App Environment מאוחדת

קובץ מומלץ:

- `lib/core/app_environment.dart`

אחריות:

לאחד במקום אחד:

- פלטפורמה
- device class
- input capabilities

כך שמסך או שירות לא יצטרכו לחבר ידנית בין כמה helpers.

אבל גם כאן:

- לא כל המידע יהיה סטטי
- חלקו יבוא מ-runtime state
- ולכן `AppEnvironment` כנראה לא צריך להיות רק מחלקה עם getters סטטיים

אלא שכבה שיכולה לקבל נתונים גם מ-context / window metrics / interaction state.

---

## החלטות מוצר שצריך לקבע

### 1. פלטפורמה לא מספיקה

לא נכון להחליט על UI או קיצורים רק לפי:

- `Platform.isIOS`

כי iPad עם מקלדת ו-trackpad אינו זהה ל-iPhone.

### 2. צריך להבדיל בין 3 שכבות

- מערכת הפעלה
- סוג מכשיר
- יכולות קלט

### 3. קיצורי מקשים

ברירות מחדל צריכות להיקבע לפי `primaryShortcutModifier`, לא לפי if-ים מפוזרים.

כלומר:

- Windows/Linux:
  `Ctrl`
- macOS:
  `Command`
- iPadOS עם מקלדת:
  `Command`
- iPhone עם מקלדת:
  כנראה גם `Command`, אבל התצוגה לא תהיה כמו בדסקטופ

### 4. Tooltip / discoverability

לא נכון להחליט לפי "מובייל מול דסקטופ" בלבד.

צריך להחליט לפי:

- האם יש hover אמיתי
- האם יש pointer
- האם יש מקלדת

---

## אילו קבצים צריכים להשתנות

### א. קובץ חדש ב-core

צריך ליצור:

- `lib/core/app_platform.dart`

ולא להשאיר helper כזה בשורש הפרויקט.

### ב. מסמך CORE

צריך לעדכן בעתיד את:

- [CORE.md](./CORE.md)

כך שישקף את המבנה הסופי:

- `app_platform.dart`
- `device_class.dart`
- `input_capabilities.dart`
- `app_environment.dart`

### ג. מסמך הקיצורים

צריך לעדכן את:

- [SHORTCUTS_REFACTOR_PLAN.md](./SHORTCUTS_REFACTOR_PLAN.md)

כך שיהיה תלוי מפורשות בשכבת platform capabilities.

### ד. מסכי הגדרות קיצורים

צריך לעדכן בעתיד את:

- `lib/settings/tabs/shortcuts_settings_tab.dart`

כדי שלא יתבסס רק על:

- `Platform.isAndroid || Platform.isIOS`

כאילו קיצורים "זמינים רק בדסקטופ".

במקום זה צריך מדיניות חכמה יותר:

- האם יש keyboard workflow?
- האם נכון להציג את ה-UI הזה בפלטפורמה/מכשיר הזה?

### ה. מנגנון formatter של קיצורים

צריך לעדכן בעתיד את:

- `lib/shortcuts/shortcut_helper.dart`

או את ה-formatter החדש בריפקטור,

כדי שיציג:

- `CTRL`
- `⌘`
- `ALT`
- `SHIFT`

לפי פלטפורמה, ולא `WIN`.

### ו. מנגנון default shortcuts

צריך לעדכן בעתיד את:

- `lib/shortcuts/shortcut_validator.dart`

או את ה-registry החדש,

כך שברירות מחדל תלויות פלטפורמה לא יהיו hardcoded כ-`ctrl+...` לכולם.

---

## סדר עבודה מומלץ

### שלב א — ייצוב והחלטות

- להחליט על שמות הקבצים והמיקום ב-`lib/core/`
- להחליט על המודלים:
  platform / device class / input capabilities
- לעדכן את מסמך הקיצורים בהפניה למסמך הזה

### שלב ב — תשתית בסיסית

- ליצור `lib/core/app_platform.dart`
- ליצור `lib/core/device_class.dart`
- ליצור `lib/core/input_capabilities.dart`
- ליצור `lib/core/app_environment.dart`

### שלב ג — חיבור ראשוני לקיצורים

- לקבוע `primaryShortcutModifier`
- לחבר formatter פלטפורמי
- לחבר ברירות מחדל תלויות פלטפורמה

זה השלב שבו המסמך הזה מתחבר ישירות לשלב 6 במסמך הקיצורים.

### שלב ד — מעבר הדרגתי של UI

- לעדכן מסכי הגדרות
- לעדכן tooltips
- לעדכן נקודות שבהן מחליטים אם להציג UI של קיצורים

### שלב ה — ניקוי

- להסיר `Platform.isX` מפוזרים במקומות שבהם שכבת core החדשה מכסה את הצורך
- לאחד שמות ומסמכים

---

## מה לא לעשות

- לא להסתפק ב-`isDesktop` / `isMobile` בלבד
- לא לקבוע מדיניות קיצורים ישירות מתוך `Platform.isIOS`
- לא להניח ש-iPad ו-iPhone זהים
- לא לבנות מדיניות tooltip רק לפי "מובייל"
- לא להשאיר helper פלטפורמה בשורש הפרויקט אם הוא נועד ל-runtime
- לא לבנות `device class` כ-helper סטטי טהור אם הוא תלוי ב-`MediaQuery`/גודל חלון
- לא להניח שיש דרך סטטית פשוטה לדעת ב-Flutter אם מחוברת כרגע מקלדת חיצונית

---

## Definition of Done

השכבה הזו תיחשב מסודרת רק אם:

- יש source of truth אחד לפלטפורמה
- יש source of truth אחד ל-device class
- יש source of truth אחד ל-input capabilities
- מסמך הקיצורים מפנה במפורש לשכבה הזו
- קיצורי מקשים יכולים להחליט על modifier ותצוגה דרך השכבה הזו
- אין תלות רק ב-`isDesktop` / `isMobile` עבור החלטות מוצר מורכבות
- ברור במסמך ובמימוש מה סטטי ב-core ומה תלוי ב-runtime/context
