/// מגבלת הזמן של RPC שאינו מגדיר חסם משלו.
const Duration kPluginDefaultRpcTimeout = Duration(seconds: 30);

/// ה-namespace שאליו נעול אחסון ה-KV של תוסף (storage.* בגשר ובמסלול
/// הדקלרטיבי). הערך הוא מפתח קיים בדיסק של משתמשים — אסור לשנותו.
const String kDefaultStorageNamespace = 'default';

/// מזהי המופעים הקבועים הרשומים אצל PluginRuntimeDispatcher.
/// הערכים נשמרים כפי שהם — הדיספצ'ר מפתח לפיהם מפות חיות.
class PluginInstanceIds {
  PluginInstanceIds._();

  /// מופע הרקע (PluginBackgroundHost).
  static const String background = 'background';

  /// מזהה ברירת המחדל למופע קדמי כשלא סופק מזהה מפורש (בעיקר בבדיקות).
  static const String defaultForeground = 'default';

  /// מזהה מדומה לרישומי UI ברמת התוסף (מניפסט/דקלרטיבי) — אינו מופע ריצה,
  /// ולכן ניתוב לחיצות מתעלם ממנו ונופל לבחירת הדיספצ'ר.
  static const String pluginLevel = 'plugin';
}

/// מפתח מופע ריצה יחיד אצל PluginRuntimeDispatcher: תוסף + מזהה מופע.
typedef PluginInstanceKey = ({String pluginId, String instanceId});
