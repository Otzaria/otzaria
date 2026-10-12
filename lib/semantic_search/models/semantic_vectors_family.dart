/// משפחת סט הוקטורים: לפיה נבחרים ה-`model.json` וה-release.
enum SemanticVectorsFamily {
  /// שורה ארוכה מוטמעת בכמה חלונות; נפתחת רק במנוע שפותר אותם.
  windows(
    identityAsset: 'assets/semantic/meivin-round2-windows-onnx/model.json',
    releaseTagPrefix: 'vectors-windows-',
  ),

  /// חלון אחד לכל שורה.
  anchor(
    identityAsset: 'assets/semantic/meivin-round2-onnx/model.json',
    releaseTagPrefix: 'vectors-',
  );

  const SemanticVectorsFamily({
    required this.identityAsset,
    required this.releaseTagPrefix,
  });

  /// נתיב ה-`model.json` של המשפחה באפליקציה.
  final String identityAsset;

  /// תג ה-release הוא התחילית ואחריה תג הספרייה.
  final String releaseTagPrefix;
}

/// release שאפשר להתקין: המשפחה, וה-`chunking_identity` שהמניפסט שלו חייב לשאת.
typedef SemanticVectorsCandidate = ({
  SemanticVectorsFamily family,
  int chunkingIdentity,
});
