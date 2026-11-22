/// מידות של חלונית צד אחת: כמה מקום נשמר לתוכן הראשי, והטווח של רוחב החלונית.
///
/// מקור האמת היחיד לכל החלוניות באפליקציה. מסך לא כותב מספרי רוחב בעצמו אלא
/// לוקח אותם מ-[SidePaneSpecs]; בדיקה ב-`test/design_system/` אוסרת מספרים כאלה
/// בקוד מסך. הערכים הם אלה שהיו בכל מסך עד איחודם, בלי שינוי: שוני ביניהם אינו
/// פגם אלא החלטה של המסך (קורא טקסט צריך יותר מקום לטקסט מקורא PDF).
class SidePaneSpec {
  const SidePaneSpec({
    required this.minMainContentWidth,
    this.minPaneWidth = defaultMinPaneWidth,
    this.maxPaneWidth,
    this.maxPaneFraction,
    this.fixedPaneWidth,
    this.defaultPaneFraction,
    this.defaultPaneFractionList,
    this.dragLeavesForMain,
  });

  /// ברירת המחדל של `AdaptiveSidePane.minPaneWidth`.
  static const double defaultMinPaneWidth = 220;

  /// הרוחב שנשמר לתוכן הראשי לצד החלונית. מתחתיו החלונית הופכת לשכבה.
  final double minMainContentWidth;

  /// הרוחב הקטן ביותר שאפשר לצמצם אליו את החלונית בגרירה.
  final double minPaneWidth;

  /// תקרת הרוחב בפיקסלים; null: אין, או שהתקרה נגזרת מהרוחב הפנוי.
  final double? maxPaneWidth;

  /// תקרת הרוחב כחלק מרוחב המסך ([maxPaneWidth] עדיפה כשהיא קיימת).
  final double? maxPaneFraction;

  /// חלונית ברוחב קבוע שאינו נשמר ואינו נגרר.
  final double? fixedPaneWidth;

  /// הרוחב ההתחלתי כחלק מהרוחב הפנוי, כשלא נשמר רוחב.
  final double? defaultPaneFraction;

  /// כמו [defaultPaneFraction], בתצוגת רשימה (ספרייה).
  final double? defaultPaneFractionList;

  /// כמה רוחב נשאר לתוכן כשהחלונית רחבה ככל האפשר: התקרה של הרוחב הפנוי
  /// פחות הערך הזה (בלי תלות ב-[minMainContentWidth], שמכריע בין דחיקה ושכבה).
  final double? dragLeavesForMain;
}

/// טבלת המידות של חלוניות הצד, לפי מסך.
abstract final class SidePaneSpecs {
  /// רוחב ברירת המחדל של חלונית צפה (ContextOverlayPanel), גם זו של תוספים.
  /// 350 (החלטה 45, כמו חלונית המפרשים בסעיף 14; עד כה 400).
  static const double overlayPanelWidth = 350;

  /// חלונית הניווט בקורא טקסט.
  static const textReaderNav = SidePaneSpec(
    minMainContentWidth: 520,
    minPaneWidth: 200,
    maxPaneWidth: 600,
  );

  /// חלונית הניווט בקורא PDF.
  static const pdfReaderNav = SidePaneSpec(
    minMainContentWidth: 200,
    minPaneWidth: 200,
    maxPaneWidth: 600,
  );

  /// חלונית המפרשים בקורא PDF.
  static const pdfReaderCommentary = SidePaneSpec(
    minMainContentWidth: 200,
    minPaneWidth: 250,
    maxPaneWidth: 600,
  );

  /// חלונית ניווט בכרטיסיית המפרשים של ספר טקסט.
  static const textCommentatorsTabNav = SidePaneSpec(
    minMainContentWidth: 400,
    fixedPaneWidth: 320,
  );

  /// חלונית ניווט בכרטיסיית המפרשים של ספר PDF.
  static const pdfCommentatorsTabNav = SidePaneSpec(
    minMainContentWidth: 500,
    fixedPaneWidth: 320,
  );

  /// חלונית המפרשים בקורא טקסט בתצוגה מפוצלת. התקרה היא חלק מהרוחב הפנוי.
  static const splitView = SidePaneSpec(
    minMainContentWidth: 200,
    minPaneWidth: 280,
    maxPaneFraction: 0.75,
    dragLeavesForMain: 300,
  );

  /// הסרגל הצדדי בתצוגת צורת הדף. הרוחב והתקרה חלק מרוחב המסך.
  static const pageShapeSidebar = SidePaneSpec(
    minMainContentWidth: 300,
    minPaneWidth: 220,
    maxPaneFraction: 0.35,
    defaultPaneFraction: 0.22,
  );

  /// ההערות האישיות.
  static const personalNotes = SidePaneSpec(
    minMainContentWidth: 320,
    minPaneWidth: 150,
    maxPaneWidth: 500,
  );

  /// פילוח תוצאות החיפוש.
  static const searchFacets = SidePaneSpec(
    minMainContentWidth: 300,
    minPaneWidth: 220,
    maxPaneWidth: 600,
  );

  /// התצוגה המקדימה בתוצאות חיפוש (טקסט וחיפוש סמנטי). התקרה נגזרת מהרוחב
  /// הפנוי ולא קבועה.
  static const searchPreview = SidePaneSpec(
    minMainContentWidth: 300,
    minPaneWidth: 280,
    defaultPaneFraction: 0.4,
    dragLeavesForMain: 320,
  );

  /// התצוגה המקדימה בספרייה. התקרה נגזרת מהרוחב הפנוי.
  static const libraryPreview = SidePaneSpec(
    minMainContentWidth: 200,
    minPaneWidth: 280,
    defaultPaneFraction: 0.35,
    defaultPaneFractionList: 0.60,
    dragLeavesForMain: 230,
  );

  /// לוח השנה. `minMainContentWidth` כמו `LayoutConstraints.mainContentMinWidth`.
  static const calendar = SidePaneSpec(
    minMainContentWidth: 500,
    minPaneWidth: 280,
    maxPaneWidth: 520,
  );

  /// המרת יחידות.
  static const measurementConverter = SidePaneSpec(
    minMainContentWidth: 420,
    minPaneWidth: 150,
    maxPaneWidth: 280,
  );

  /// שמור וזכור.
  static const shamorZachor = SidePaneSpec(
    minMainContentWidth: 320,
    minPaneWidth: 220,
    maxPaneWidth: 420,
  );
}
