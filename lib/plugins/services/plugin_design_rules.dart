/// כללי בדיקת העיצוב של בודק התוספים (`PluginExtendedValidator`), כנתונים.
///
/// הכללים האלה מתפרסמים ב-`docs/plugin-sdk/spec.json` תחת `designRules`
/// (`tool/plugins/plugin_spec_generator.dart` קורא אותם מהקובץ הזה), והעותק של
/// הבודק ב-`otzaria-plugin-validator` (JavaScript) צורך אותם משם. כך כלל חדש
/// או הודעה חדשה לא משתנים רק באחד משני המימושים.
///
/// הקבועים כאן חייבים להישאר ליטרלים (מחרוזות, קבוצות) כדי שהמחולל יקרא אותם.
library;

/// ערכי מילת מפתח שמותרים כערך של תכונת צבע (`color`, `background` וכו').
const Set<String> pluginDesignColorKeywords = {
  'inherit',
  'initial',
  'unset',
  'revert',
  'currentcolor',
  'transparent',
  'none',
};

/// ערכים שמותרים כערך של `font-family` מלבד `var(--font-*)`. `inherit` על
/// כפתור או שדה הוא דפוס לגיטימי כדי לקבל את גופן הדף.
const Set<String> pluginDesignFontFamilyKeywords = {
  'inherit',
  'initial',
  'unset',
  'system-ui',
};

/// סלקטור (ביטוי רגולרי, לא רגיש לאותיות) של סרגל העליון של התוסף: רק בו
/// `font-size` ב-px מותר.
const String pluginDesignTopBarSelectorPattern = r'top-?bar';

/// כללי @ שהתוכן שלהם אינו נבדק. ב-`@font-face` שם ה-`font-family` הוא ההגדרה
/// עצמה ולא שימוש בגופן.
const Set<String> pluginDesignSkippedAtRules = {'font-face'};

/// הסיומת של הודעת הכשל, לפי סוג ההפרה. הטוקנים שמוזכרים כאן הם אלה שקיימים
/// ב-`DESIGN_GUIDE.md` (`--radius`, `--font-ui`, `--font-main`, `--text-*`).
const String pluginDesignFontFamilyHint =
    'חובה var(--font-ui) לממשק, או var(--font-main) לטקסט ספר';
const String pluginDesignFontSizeHint =
    'חובה var(--text-*) (או em/rem). px מותר רק בכלל שמתייחס לסרגל העליון (ששמו מכיל topbar)';
const String pluginDesignRadiusHint = 'חובה var(--radius) (8). אין גלולות';
