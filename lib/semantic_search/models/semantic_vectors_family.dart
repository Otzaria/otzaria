/// משפחת סט הוקטורים: לפיה נבחרים ה-`model.json` וה-release.
/// סדר הערכים הוא סדר ההעדפה שמתפרסם למעדכן ב-`otzaria_capabilities.json`.
enum SemanticVectorsFamily {
  /// שורה ארוכה מוטמעת בכמה חלונות; נפתחת רק במנוע שפותר אותם.
  windows(
    identityAsset: 'assets/semantic/meivin-qa491-windows-onnx/model.json',
    releaseTagPrefix: 'vectors-qa491-windows-',
    deltaReleaseTagPrefix: 'vectors-qa491-windows-delta-',
  ),

  /// חלון אחד לכל שורה.
  anchor(
    identityAsset: 'assets/semantic/meivin-qa491-onnx/model.json',
    releaseTagPrefix: 'vectors-qa491-',
  ),

  /// פרדס QA491 המכווץ; מחייב וקטורים ייעודיים לאותה משפחה.
  pardesWindows(
    identityAsset: 'assets/semantic/pardesqa491-windows-onnx/model.json',
    releaseTagPrefix: 'vectors-pardesqa491-windows-',
    deltaReleaseTagPrefix: 'vectors-pardesqa491-windows-delta-',
  );

  const SemanticVectorsFamily({
    required this.identityAsset,
    required this.releaseTagPrefix,
    this.deltaReleaseTagPrefix,
  });

  bool get isWindowed => this != anchor;

  /// נתיב ה-`model.json` של המשפחה באפליקציה.
  final String identityAsset;

  /// תג ה-release הוא התחילית ואחריה תג הספרייה.
  final String releaseTagPrefix;

  /// תחילית ה-release של delta אל תג ספרייה; `null` — המשפחה מתעדכנת רק ב-base.
  /// נפרדת מ-[releaseTagPrefix]: גרסאות ישנות לוקחות את המניפסט הראשון שב-release.
  final String? deltaReleaseTagPrefix;
}

/// release שאפשר להתקין: משפחת הסט, המודל ותצורת החלוקה שלו.
typedef SemanticVectorsCandidate = ({
  SemanticVectorsFamily family,
  String modelFamilyId,
  int chunkingIdentity,
});
