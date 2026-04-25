/// סטטוס עיבוד הקישורים לספר נתון.
enum GeneratedLinksProcessingStatus {
  /// אין cache — הספר טרם עובד.
  notStarted,

  /// יש עיבוד שרץ כרגע (קובץ cache נכתב חלקית).
  processing,

  /// חלק מהשורות עובדו ונשמרו, אך הספר לא הושלם.
  partial,

  /// כל השורות עובדו לפי גרסת הכללים הנוכחית.
  complete,

  /// ה-cache קיים אך לא תואם ל-fingerprint או ל-rulesVersion הנוכחיים.
  stale,

  /// אירעה שגיאה חוזרת; שמור זמן ניסיון אחרון ב-[GeneratedLinksCache].
  failed;

  static GeneratedLinksProcessingStatus fromJson(String value) {
    return GeneratedLinksProcessingStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => GeneratedLinksProcessingStatus.notStarted,
    );
  }

  String toJson() => name;
}
