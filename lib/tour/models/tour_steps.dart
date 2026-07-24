// לתחזוקת הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tour/models/tour_step.dart';

class TourSteps {
  static const String statusKey = 'tour_status';
  static const String completed = 'completed';
  static const String skipped = 'skipped';
  static const String completedWithoutLibrary = 'completed_without_library';
  static const String skippedWithoutLibrary = 'skipped_without_library';

  static List<TourStep> build({
    required bool libraryLoaded,
    bool isRestart = false,
  }) {
    final shortcuts = _ShortcutText();
    final steps = <TourStep>[
      if (isRestart)
        TourStep(
          id: 'restart_welcome',
          title: 'הסיור המודרך',
          body: libraryLoaded
              ? 'הסיור יעבור על כל הפיצ׳רים המרכזיים של אוצריא.\nלחץ "אני מוכן" כשתהיה מוכן להתחיל.'
              : 'ללא ספרייה טעונה יוצג סיור מקוצר.\nלאחר טעינת הספרייה תוכל לצפות בסיור המלא.\nלחץ "אני מוכן" כשתהיה מוכן להתחיל.',
          area: TourSpotlightArea.center,
          isDialog: true,
        )
      else
        TourStep(
          id: 'welcome',
          title: 'ברוכים הבאים לאוצריא',
          body: libraryLoaded
              ? 'ספרייה תורנית דיגיטלית חינמית ופתוחה. האם תרצה סיור קצר שיכיר לך את הפיצ׳רים המרכזיים? (כ-2 דקות)'
              : 'ספרייה תורנית דיגיטלית חינמית ופתוחה.\n\nמאחר שעדיין לא טענת ספרייה, יוצג כעת סיור מקוצר. לאחר טעינת הספרייה תוכל להפעיל שוב את הסיור המלא מ: הגדרות ← מערכת.',
          area: TourSpotlightArea.center,
          isDialog: true,
        ),
      TourStep(
        id: 'navigation',
        title: 'הניווט הראשי',
        body:
            'בחלק המואר תמצא את כל חלקי האפליקציה: ספרייה, איתור, עיון, חיפוש, כלים והגדרות.\n\nקיצורים: ${shortcuts.mainNavigation}',
        area: TourSpotlightArea.navigation,
      ),
    ];

    if (libraryLoaded) {
      steps.addAll([
        const TourStep(
          id: 'library',
          title: 'הספרייה',
          body:
              'כאן מוצגים כל הספרים הזמינים. תוכל לדפדף לפי קטגוריות, לחפש לפי שם, או לפתוח ספר בלחיצה.',
          area: TourSpotlightArea.fullScreen,
          action: TourStepAction.openLibrary,
        ),
        const TourStep(
          id: 'library_search',
          title: 'חיפוש מהיר בספרייה',
          body: 'הקלד כאן שם ספר, מחבר או נושא — הספרייה תסונן מיידית.',
          area: TourSpotlightArea.librarySearch,
          action: TourStepAction.openLibrary,
        ),
        const TourStep(
          id: 'categories',
          title: 'קטגוריות',
          body:
              'לחץ על קטגוריה כדי לעבור אליה: תנ״ך, משנה, תלמוד, הלכה, קבלה, מחשבה ועוד.',
          area: TourSpotlightArea.libraryCategories,
          action: TourStepAction.openLibraryHome,
        ),
        const TourStep(
          id: 'open_book',
          title: 'פתיחת ספר',
          body:
              'לחץ פעמיים על ספר כדי לפתוח אותו לקריאה. לחיצה אחת מציגה תצוגה מקדימה עם פרטי הספר בצד.',
          area: TourSpotlightArea.bookCard,
          action: TourStepAction.openLibraryBookPreview,
        ),
        TourStep(
          id: 'find_ref',
          title: 'איתור מהיר',
          body:
              'כשאתה יודע לאן להגיע, הקלד שם ספר, פרק או פסוק. איתור = נווט, חיפוש = גלה.\n\nקיצור: ${shortcuts.findRef}',
          area: TourSpotlightArea.findRef,
          action: TourStepAction.openFindRef,
        ),
        TourStep(
          id: 'reading',
          title: 'מסך הקריאה',
          body:
              'כאן קוראים את הספרים שפתחת. ניתן לפתוח מספר ספרים בטאבים שונים ולעבור ביניהם.\n\nקיצור: ${shortcuts.reading}',
          area: TourSpotlightArea.reading,
          action: TourStepAction.openReading,
        ),
        TourStep(
          id: 'tabs',
          title: 'טאבים — ספרים מרובים',
          body:
              'כל ספר שתפתח יופיע כטאב נפרד. Ctrl+Tab עובר בין טאבים, ושולחנות עבודה שומרים אוספי טאבים.',
          area: TourSpotlightArea.tabs,
          action: TourStepAction.openReading,
        ),
        const TourStep(
          id: 'toc',
          title: 'תוכן עניינים',
          body:
              'לחץ כדי לנווט ישירות לפרק או לסעיף בספר. פאנל ניווט נפתח בצד עם כל הפרקים.',
          area: TourSpotlightArea.tableOfContents,
          action: TourStepAction.openReading,
        ),
        const TourStep(
          id: 'commentators',
          title: 'מפרשים וביאורים',
          body: 'בחר אם המפרשים יוצגו לצד הטקסט, מתחתיו, או בתצוגת צורת הדף.',
          area: TourSpotlightArea.commentators,
          action: TourStepAction.openReading,
        ),
        const TourStep(
          id: 'bookmark',
          title: 'סימניות והיסטוריה',
          body:
              'כדי לסמן מקום, לחץ לחיצה ימנית על הטקסט ובחר "הוסף סימניה לקטע זה". כאן תמצא את הסימניות של הספר הנוכחי. ההיסטוריה הכללית נשמרת אוטומטית, ובקצה המסך העליון תמצא סימניות והיסטוריה.',
          area: TourSpotlightArea.bookmark,
          action: TourStepAction.openReading,
        ),
        const TourStep(
          id: 'book_search',
          title: 'חיפוש בספר',
          body:
              'חפש מילה או משפט בספר הנוכחי בלבד. התוצאות מסומנות בתוך הטקסט.',
          area: TourSpotlightArea.bookSearch,
          action: TourStepAction.openReading,
        ),
        const TourStep(
          id: 'reading_settings',
          title: 'הגדרות קריאה',
          body:
              'פתח את פאנל הגדרות הקריאה: גודל גופן, סוג גופן, ניקוד, ריווח שורות ומצב תצוגה.',
          area: TourSpotlightArea.readingSettings,
          action: TourStepAction.openReading,
        ),
      ]);
    }

    steps.addAll([
      TourStep(
        id: 'advanced_search',
        title: 'חיפוש מתקדם בכל הספרייה',
        body: libraryLoaded
            ? 'חפש כל מילה או ביטוי בכל הספרים בו-זמנית. ניתן לסנן לפי קטגוריות ולגשת לכל תוצאה.\n\nקיצור: ${shortcuts.search}'
            : 'החיפוש המתקדם יהיה זמין לאחר טעינת הספרייה. הוא מיועד למציאת רעיון או מילה כשאינך יודע היכן הם מופיעים.',
        area: TourSpotlightArea.searchDialog,
        action: TourStepAction.openSearch,
      ),
      TourStep(
        id: 'tools',
        title: 'כלים נוספים',
        body:
            'כאן תמצא לוח שנה יהודי, גימטריות, מילון ארמי, ראשי תיבות, ממיר יחידות, תוכנית לימוד והערות אישיות.\n\nקיצור: ${shortcuts.tools}',
        area: TourSpotlightArea.tools,
        action: TourStepAction.openTools,
      ),
      TourStep(
        id: 'settings',
        title: 'הגדרות',
        body:
            'כאן תוכל להתאים אישית מראה, כתב, ספרייה, כלים, קיצורים, גיבוי ועוד.\n\nקיצור: ${shortcuts.settings}',
        area: TourSpotlightArea.settings,
        action: TourStepAction.openSettings,
      ),
      const TourStep(
        id: 'appearance',
        title: 'מראה',
        body: 'בחר מצב בהיר או כהה, צבע בסיסי לממשק ומצב תצוגה מלאה.',
        area: TourSpotlightArea.designSettings,
        action: TourStepAction.openDesignSettings,
      ),
      TourStep(
        id: 'finish',
        title: libraryLoaded ? 'הסיור הסתיים!' : 'הסיור המקוצר הסתיים',
        body: libraryLoaded
            ? 'עכשיו אתה מוכן לחקור את הספרייה. תוכל להפעיל את הסיור שוב בכל עת מ: הגדרות ← מערכת ← הפעל סיור מחדש.'
            : 'לאחר טעינת הספרייה תוכל לחזור לסיור המלא מ: הגדרות ← מערכת ← הפעל סיור מחדש.',
        area: TourSpotlightArea.center,
        action: TourStepAction.openLibrary,
        isDialog: true,
      ),
    ]);

    if (!libraryLoaded) {
      return [
        steps.first, // welcome / restart_welcome
        const TourStep(
          id: 'empty_library',
          title: 'נתחיל בהגדרת הספרייה',
          body:
              'כדי להשתמש באוצריא, צריך ספרייה של ספרים. אפשר להוריד את הספרייה, לבחור תיקייה קיימת או לחלץ מקובץ ZIP.',
          area: TourSpotlightArea.emptyLibrary,
          action: TourStepAction.openLibrary,
        ),
        ...steps.skip(1), // navigation, advanced_search, tools, ...
      ];
    }

    return steps;
  }
}

class _ShortcutText {
  String get mainNavigation => [
    'ספרייה ${_read('key-shortcut-open-library-browser', 'ctrl+l')}',
    'איתור ${_read('key-shortcut-open-find-ref', 'ctrl+o')}',
    'עיון ${_read('key-shortcut-open-reading-screen', 'ctrl+r')}',
    'חיפוש ${_read('key-shortcut-open-new-search', 'ctrl+shift+f')}',
    'כלים ${_read('key-shortcut-open-more', 'ctrl+m')}',
    'הגדרות ${_read('key-shortcut-open-settings', 'ctrl+comma')}',
  ].join(' · ');

  String get findRef => _read('key-shortcut-open-find-ref', 'ctrl+o');
  String get reading => _read('key-shortcut-open-reading-screen', 'ctrl+r');
  String get search => _read('key-shortcut-open-new-search', 'ctrl+shift+f');
  String get tools => _read('key-shortcut-open-more', 'ctrl+m');
  String get settings => _read('key-shortcut-open-settings', 'ctrl+comma');

  String _read(String key, String defaultValue) {
    final value = Settings.getValue<String>(key) ?? defaultValue;
    return _format(value);
  }

  String _format(String shortcut) {
    return shortcut
        .split('+')
        .map((part) {
          if (part == 'ctrl') return 'Ctrl';
          if (part == 'shift') return 'Shift';
          if (part == 'alt') return 'Alt';
          if (part == 'comma') return ',';
          if (part == 'tab') return 'Tab';
          return part.isEmpty
              ? part
              : part[0].toUpperCase() + part.substring(1);
        })
        .join('+')
        .replaceAll('Ctrl+,', 'Ctrl+,');
  }
}
