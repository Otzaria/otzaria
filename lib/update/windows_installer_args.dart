/// ארגומנטים למתקין בהתקנת per-user: /SILENT ישירות (ללא הסלמה), כדי
/// לדלג על ה-self-relaunch של המתקין. /NOLAUNCH=1 מונע פתיחה מחדש של אוצריא
/// (בעת סגירת התוכנה).
String perUserSilentInstallerArguments({required bool relaunchApp}) {
  const base = '/SILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER';
  return relaunchApp ? base : '$base /NOLAUNCH=1';
}
