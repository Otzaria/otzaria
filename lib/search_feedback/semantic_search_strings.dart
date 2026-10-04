/// שם התצוגה של מצב החיפוש הסמנטי — המקום היחיד שבו השם מופיע.
const String kSemanticSearchModeName =
    'חיפוש חכם'; // TODO(name): שם זמני — טרם הוחלט סופית

/// נוסח ההסכמה, עם `{name}` במקום שם המצב. משמש גם כמפתח התרגום בהגדרות.
const String kSemanticSearchConsentTemplate =
    'השימוש ב{name} מותנה בהסכמה לשליחת נתוני שימוש אנונימיים לשיפור המנגנון: '
    'מילות החיפוש, התוצאות שהוצגו ודירוגן, הקטעים שנפתחו או שסומנו '
    '(אהבתי / לא אהבתי) וזמן העיון בהם, וכן גרסת התוכנה ומערכת ההפעלה. '
    'לא נשלחים שם, כתובת דוא"ל, נתיבי קבצים, תוכן מספרים אישיים או כל פרט '
    'מזהה אחר. מומלץ לא לכלול פרטים אישיים בטקסט החיפוש. אפשר לבטל את '
    'ההסכמה בכל עת בהגדרות, והביטול חוסם את מצב החיפוש הזה.';

/// נוסח ההסכמה המלא בעברית, עם שם המצב.
String get semanticSearchConsentText => kSemanticSearchConsentTemplate
    .replaceAll('{name}', kSemanticSearchModeName);

/// תוויות מקור ההתאמה בכרטיס תוצאה; מרוכזות כאן כי ישתנו יחד עם השם.
const String kSemanticSourceLexicalLabel = 'התאמה מילולית';
const String kSemanticSourceSemanticLabel = 'התאמה לפי עניין';
const String kSemanticSourceBothLabel = 'התאמה מילולית ולפי עניין';

/// באנר התצוגה המקדימה בפיתוח בלבד (kDebugMode), כשאין מנוע או נתונים.
const String kSemanticDebugPreviewBanner =
    'תצוגה מקדימה (דיבאג) — ללא מנוע/מודל';
