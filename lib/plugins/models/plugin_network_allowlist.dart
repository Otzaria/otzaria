/// רשימת ה-URLs המאושרים גישה לרשת עבור תוספים.
///
/// **מקור האמת היחיד** עבור כל גישת רשת של תוספים. גם אם תוסף
/// מצהיר ב-manifest על דומיין מסוים — הגישה תיחסם אם ה-URL לא
/// נמצא ברשימה כאן.
///
/// כל ערך הוא **קידומת** (prefix) — מאושרים ה-URL עצמו וכל
/// תתי-הנתיבים תחתיו, ולא שאר הדומיין.
///
/// ## דוגמה
/// אם הרשימה מכילה: `https://github.com/Otzaria/otzaria-library`
///
/// יותרו:
/// - `https://github.com/Otzaria/otzaria-library`
/// - `https://github.com/Otzaria/otzaria-library/`
/// - `https://github.com/Otzaria/otzaria-library/releases/latest`
/// - `https://github.com/Otzaria/otzaria-library?tab=readme`
///
/// ייחסמו:
/// - `https://github.com/` (נתיב הורה)
/// - `https://github.com/Otzaria/another-repo` (נתיב אחר)
/// - `https://github.com/Otzaria/otzaria-library2` (קידומת תואמת חלקית)
///
/// ## כללים
/// - חובה לכלול scheme מלא (`https://` או `http://`).
/// - מותר לציין דומיין שלם כדי להתיר את כולו: `https://api.example.com`
///   יתיר כל URL שמתחיל ב-`https://api.example.com/`.
/// - אין להשאיר `/` סופי — הוא לא משנה את ההתנהגות אך מבלבל.
const List<String> pluginNetworkAllowlist = <String>[
  // הוסיפו כאן URLs מאושרים — דוגמה (להסיר/להשאיר לפי הצורך):
  // 'https://github.com/Otzaria/otzaria-library',
];

/// בודקת האם [uri] מורשה לגישה על-ידי תוספים.
///
/// מחזירה `true` רק אם ה-URL הוא בדיוק אחת מהקידומות ברשימה
/// [pluginNetworkAllowlist], או נתיב תחתיה (מופרד ב-`/`, `?` או `#`).
///
/// השוואת קידומת מתבצעת case-insensitive על ה-scheme וה-host
/// (תקני URI), ו-case-sensitive על הנתיב.
bool isUriAllowedForPluginNetwork(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return false;
  }

  // מנרמלים scheme + host ל-lowercase כפי שדורש תקן ה-URI,
  // ושומרים על נתיב/query/fragment כמו שהם (case-sensitive).
  final normalizedHost = uri.host.toLowerCase();
  final normalizedUrl = StringBuffer()
    ..write(uri.scheme.toLowerCase())
    ..write('://')
    ..write(normalizedHost);
  if (uri.hasPort) {
    normalizedUrl..write(':')..write(uri.port);
  }
  normalizedUrl.write(uri.path);
  if (uri.hasQuery) {
    normalizedUrl..write('?')..write(uri.query);
  }
  if (uri.hasFragment) {
    normalizedUrl..write('#')..write(uri.fragment);
  }
  final fullUrl = normalizedUrl.toString();

  for (final rawPrefix in pluginNetworkAllowlist) {
    // מנרמלים את הקידומת באותו אופן.
    final prefixUri = Uri.tryParse(rawPrefix);
    if (prefixUri == null) continue;
    if (prefixUri.scheme != 'http' && prefixUri.scheme != 'https') continue;

    final normalizedPrefix = StringBuffer()
      ..write(prefixUri.scheme.toLowerCase())
      ..write('://')
      ..write(prefixUri.host.toLowerCase());
    if (prefixUri.hasPort) {
      normalizedPrefix..write(':')..write(prefixUri.port);
    }
    normalizedPrefix.write(prefixUri.path);
    final prefix = normalizedPrefix.toString();

    if (fullUrl == prefix) return true;
    if (fullUrl.startsWith('$prefix/')) return true;
    if (fullUrl.startsWith('$prefix?')) return true;
    if (fullUrl.startsWith('$prefix#')) return true;
  }

  return false;
}
