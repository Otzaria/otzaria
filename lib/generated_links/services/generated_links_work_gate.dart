/// מנגנון שמונע עיבוד קישורים חדש בזמן פעולות כבדות כמו אינדוקס או סנכרון.
///
/// תומך בכמה מקורות עומס בו-זמנית דרך reference counting.
/// [isIdle] מחזיר true רק כשכל המקורות שקטים.
class GeneratedLinksWorkGate {
  int _busyCount = 0;

  bool get isIdle => _busyCount == 0;

  /// מסמן מקור עומס חדש שפעיל.
  void setBusy() => _busyCount++;

  /// מסמן שמקור עומס אחד סיים — gate חוזר ל-idle רק כשכולם סיימו.
  void setIdle() {
    if (_busyCount > 0) _busyCount--;
  }

  /// מאפס את כל מקורות העומס (שימוש בבדיקות בלבד).
  void resetForTest() => _busyCount = 0;
}
