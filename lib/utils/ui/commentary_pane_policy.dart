/// קובע אם פאנל המפרשים צריך להיפתח אוטומטית בפתיחת ספר.
///
/// [settingEnabled] - הגדרת "פתיחת פאנל המפרשים בפתיחת ספר".
/// [isSupportedMode] - האם המצב תומך בפאנל צד: ב-PDF תמיד true; בטקסט רק
///   במצב "מפרשים בצד" (showSplitView). במצב "מפרשים מתחת"/"צורת הדף" → false.
/// [hasSelectedCommentators] - יש מפרשים נבחרים (ברירת מחדל או בחירה פר-ספר).
/// [alreadyAutoOpened] - הפאנל כבר נפתח אוטומטית בטעינה זו (פתיחה פעם אחת בלבד,
///   כדי לא להיאבק עם סגירה ידנית של המשתמש).
/// [paneAlreadyOpen] - הפאנל כבר פתוח (למשל על "קישורים"/"הערות"). במצב כזה
///   לא פותחים אוטומטית, כדי לא לדרוס את הטאב שהמשתמש כבר רואה.
bool shouldAutoOpenCommentaryPane({
  required bool settingEnabled,
  required bool isSupportedMode,
  required bool hasSelectedCommentators,
  required bool alreadyAutoOpened,
  required bool paneAlreadyOpen,
}) {
  if (alreadyAutoOpened) return false;
  if (paneAlreadyOpen) return false;
  if (!settingEnabled) return false;
  if (!isSupportedMode) return false;
  return hasSelectedCommentators;
}
