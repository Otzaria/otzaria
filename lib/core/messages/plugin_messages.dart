/// ריכוז הודעות המערכת (UiSnack) של מערכת התוספים.
abstract class PluginMessages {
  static const String externalBookNotFound = 'הספר לא נמצא בקטלוג החיצוני';

  // ===== התקנה והסרה =====
  static const String pluginInstalledSuccess = 'התוסף הותקן בהצלחה';
  static const String pluginUpdatedSuccess = 'התוסף עודכן בהצלחה';
  static const String pluginAlreadyInstalledSameVersion =
      'תוסף זה כבר מותקן אצלך, באותה הגרסה. '
      'להתקנה מחדש השתמש בקישור עם overwrite=true.';

  static String newerVersionInstalled(
    String pluginName,
    String installedVersion,
  ) => 'כבר מותקנת אצלך גרסה חדשה יותר של "$pluginName" ($installedVersion)';

  static const String dropSinglePluginOnly =
      'ניתן להתקין תוסף אחד בכל פעם — הותקן הראשון מבין הקבצים שנגררו';

  static String pluginRequiresNewerApp(String minAppVersion) =>
      'התוסף דורש אוצריא בגרסה $minAppVersion לפחות — עדכן את אוצריא כדי להתקינו';

  /// כשגרסה ישנה של התוסף עוד תומכת באוצריא ישנה יותר מזו שהאחרונה דורשת.
  static String pluginRequiresNewerAppWithFallback(
    String minAppVersion,
    String minSupportedAppVersion,
  ) =>
      'הגרסה האחרונה של התוסף דורשת אוצריא $minAppVersion, ולגרסה כלשהי שלו '
      'נדרשת $minSupportedAppVersion לפחות — עדכן את אוצריא כדי להתקינו';

  static String pluginRequiresOlderApp(String maxAppVersion) =>
      'התוסף מיועד לאוצריא עד גרסה $maxAppVersion בלבד';

  static String installPluginError(Object error) =>
      'שגיאה בהתקנת התוסף: $error';

  static String installRemotePluginError(Object error) =>
      'שגיאה בהתקנת התוסף מהחנות: $error';

  static String confirmInstallError(Object error) =>
      'שגיאה באישור התקנה: $error';

  static String uninstallPluginError(Object error) =>
      'שגיאה בהסרת התוסף: $error';

  // ===== ניהול תוספים =====
  static String loadPluginsError(Object error) => 'שגיאה בטעינת תוספים: $error';

  static String pinPluginError(Object error) => 'שגיאה בהצמדת התוסף: $error';

  static String unpinPluginError(Object error) =>
      'שגיאה בהסרת הצמדת התוסף: $error';

  static String pinPluginToNavRailError(Object error) =>
      'שגיאה בהצמדת התוסף לסרגל הניווט: $error';

  static String unpinPluginFromNavRailError(Object error) =>
      'שגיאה בהסרת הצמדת התוסף מסרגל הניווט: $error';

  static String showPluginInToolsError(Object error) =>
      'שגיאה בהצגת התוסף בכלים: $error';

  static String hidePluginFromToolsError(Object error) =>
      'שגיאה בהסרת התוסף מהכלים: $error';

  static String reorderPluginsError(Object error) =>
      'שגיאה בעדכון סדר התוספים: $error';

  static String enablePluginError(Object error) => 'שגיאה בהפעלת התוסף: $error';

  static String disablePluginError(Object error) =>
      'שגיאה בהשבתת התוסף: $error';

  static String updatePermissionError(Object error) =>
      'שגיאה בעדכון הרשאה: $error';

  // ===== תוספי פיתוח =====
  static const String duplicatePluginIdError =
      'כבר קיים תוסף מותקן (רגיל) עם אותו מזהה. מחק או שנה id.';
  static const String devPluginReloaded = 'תוסף פיתוח נטען מחדש';
  static const String devPluginInstalledSuccess = 'תוסף פיתוח הותקן בהצלחה';
  static const String devPluginUpdatedSuccess = 'תוסף פיתוח עודכן בהצלחה';
  static const String localhostPluginReloaded = 'תוסף localhost נטען מחדש';

  static String loadDevPluginError(Object error) =>
      'שגיאה בטעינת תוסף פיתוח: $error';

  static String installDevPluginError(Object error) =>
      'שגיאה בהתקנת תוסף פיתוח: $error';

  static String loadLocalhostPluginError(Object error) =>
      'שגיאה בטעינת תוסף localhost: $error';

  static String detachDevPluginError(Object error) =>
      'שגיאה בניתוק התוסף: $error';

  // ===== תרומות דקלרטיביות =====
  /// הודעה שתוסף דקלרטיבי ביקש להציג (`ui.showSnack`). הייחוס לתוסף חובה —
  /// בלעדיו הודעת תוסף נראית כהודעת מערכת של אוצריא.
  static String declarativeSnack(String message, String pluginName) =>
      pluginName.trim().isEmpty ? message : '$message · מאת $pluginName';

  // ===== WebView2 =====
  static const String downloadLinkOpenFailed = 'לא ניתן לפתוח את קישור ההורדה';
  static const String fileDownloadStarted = 'הורדת הקובץ החלה';
}
