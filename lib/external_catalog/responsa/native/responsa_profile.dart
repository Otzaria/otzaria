/// תיאור גרסה של פרויקט השו"ת: **איך למצוא** דברים, לא איפה הם.
///
/// מזהי הפקדים נשמרים כאימות נוסף בלבד. נמדד שבין מהדורות ה-CD משתנים
/// 83% מהמזהים בשורש העץ ו-94.8% ברמה הראשונה; אין סיבה להניח שמזהי
/// פקדים עמידים יותר. לכן כל פקד נמצא לפי **מחלקה + טקסט + מיקום
/// בהיררכיה**, והמזהה רק מעלה את הביטחון.
///
/// **הגרסה אינה שער.** התמיכה נקבעת לפי מה שנמצא בפועל בחלונות, ולא לפי
/// מספר ברשימה — כך משתמש עם כל מהדורה שהיא מקבל שילוב עובד, בלי
/// שנצטרך לאמת כל מהדורה מראש. מה שכן נגזר מהגרסה הוא **דרגת הביטחון**
/// שמדווחת למשתמש.
library;

/// רמזים לזיהוי פקד בודד.
class ControlHints {
  final String role;
  final Set<String> classNames;

  /// מזהי פקד ידועים — ראיה תומכת, לא תנאי.
  final Set<int> controlIds;

  final Set<String> textContains;
  final bool required;

  const ControlHints({
    required this.role,
    required this.classNames,
    this.controlIds = const {},
    this.textContains = const {},
    this.required = true,
  });
}

/// רמזים לזיהוי דיאלוג שלם לפי מחלקה, כותרת ומבנה הילדים.
class DialogHints {
  final String role;
  final String windowClass;
  final Set<String> titleContains;
  final Set<String> titleEquals;
  final bool topLevel;
  final List<ControlHints> controls;

  const DialogHints({
    required this.role,
    required this.windowClass,
    this.titleContains = const {},
    this.titleEquals = const {},
    this.topLevel = true,
    this.controls = const [],
  });
}

/// דרגת הביטחון בגרסה שזוהתה.
enum ResponsaVersionConfidence {
  /// אומתה מקצה לקצה מול התקנה חיה.
  verified,

  /// זוהתה, והמבנה שלה תואם — אך לא נבדקה מקצה לקצה.
  structural,

  /// לא נמצא מבנה תואם.
  unknown,
}

class ResponsaVersionProfile {
  final int? version;
  final String mainWindowClass;

  final int browseCommand;
  final int searchCommand;

  final DialogHints citationDialogHints;
  final DialogHints infoModalHints;
  final ControlHints treeControlHints;

  /// תווית העמוד "כתיבת מקורות" בתוך ה-TabControl של דיאלוג העיון.
  final int citationTabIndex;

  /// מעל כמה חלונות MDI לשחרר חלונות לפני פתיחה.
  ///
  /// נמדד: ב-22 חלונות התוכנה **מפסיקה ליצור חלונות חדשים בשקט** —
  /// הלחיצה מתקבלת, אף חלון לא נוצר, והפעולה פוקעת. הסף שמרני.
  final int mdiSoftLimit;

  /// לכמה חלונות לרדת כשמשחררים.
  final int mdiKeep;

  /// מעל כמה חלונות המופע **אינו שמיש** ומותר לסגור גם חלונות שאוצריא
  /// לא פתחה.
  ///
  /// נמדד: פרויקט השו"ת **משחזר את הסשן הקודם** — מופע טרי לגמרי עלה
  /// עם 22 חלונות, כלומר רווי מהרגע הראשון. בלי הסף הזה מופע כזה תקוע
  /// לצמיתות: החלונות אינם "שלנו" (הם משחזור, לא מהריצה הנוכחית),
  /// ולכן לא היה מי שיסגור אותם, והתוכנה סירבה לפתוח חדשים לעד.
  final int mdiHardLimit;

  const ResponsaVersionProfile({
    required this.version,
    this.mainWindowClass = 'ResponsaProject',
    this.browseCommand = 32781,
    this.searchCommand = 32857,
    this.citationDialogHints = citationHints,
    this.infoModalHints = infoModalHintsDefault,
    this.treeControlHints = treeHints,
    this.citationTabIndex = 1,
    this.mdiSoftLimit = 12,
    this.mdiKeep = 4,
    this.mdiHardLimit = 20,
  });

  /// הגרסאות שאומתו מקצה לקצה מול התקנה חיה.
  static const Set<int> verifiedVersions = {25};

  ResponsaVersionConfidence get confidence =>
      version != null && verifiedVersions.contains(version)
      ? ResponsaVersionConfidence.verified
      : ResponsaVersionConfidence.structural;

  /// ה-profile לגרסה כלשהי.
  ///
  /// אין כאן שער: כל גרסה מקבלת את אותם רמזים מבניים, כי הם מה שנבדק
  /// בפועל מול החלונות. ההבדל היחיד הוא [confidence], שנמסר למשתמש.
  static ResponsaVersionProfile forVersion(int? version) =>
      ResponsaVersionProfile(version: version);

  static const DialogHints citationHints = DialogHints(
    role: 'citation',
    windowClass: '#32770',
    titleContains: {'עיון'},
    controls: [
      ControlHints(
        role: 'reference_edit',
        classNames: {'Edit'},
        controlIds: {1021},
      ),
      ControlHints(
        role: 'search_button',
        classNames: {'Button'},
        controlIds: {1187},
        textContains: {'חיפוש', 'בצע'},
      ),
      ControlHints(
        role: 'results_list',
        classNames: {'ListBox'},
        controlIds: {1617},
      ),
      ControlHints(
        role: 'clear_button',
        classNames: {'Button'},
        controlIds: {1062},
        textContains: {'ניקוי'},
        required: false,
      ),
      ControlHints(
        role: 'show_text_button',
        classNames: {'Button'},
        controlIds: {1},
        textContains: {'הצג'},
        required: false,
      ),
    ],
  );

  static const DialogHints infoModalHintsDefault = DialogHints(
    role: 'info_modal',
    windowClass: '#32770',
    titleEquals: {'מידע'},
    controls: [
      ControlHints(
        role: 'ok_button',
        classNames: {'Button'},
        textContains: {'אישור'},
      ),
    ],
  );

  static const ControlHints treeHints = ControlHints(
    role: 'catalog_tree',
    classNames: {'SysTreeView32'},
    controlIds: {1002},
  );
}
