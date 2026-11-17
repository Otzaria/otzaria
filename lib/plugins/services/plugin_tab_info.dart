import 'package:characters/characters.dart';
import 'package:equatable/equatable.dart';

/// אורך מרבי (בתווים גרפיים) לכותרת כרטיסיה שתוסף קבע — היא נחתכת ממילא
/// ברוחב הכרטיסיה, ולכן ארוך מזה אינו מוסיף מידע.
const int kMaxPluginTabTitleLength = 80;

/// אורך מרבי לטולטיפ של כרטיסיה שתוסף קבע.
const int kMaxPluginTabTooltipLength = 300;

/// מנקה טקסט שתוסף מבקש להציג בכרטיסיה (`ui.setTabInfo`).
///
/// מחזיר `null` כשאין מה להציג — ערך `null`, ריק או רווחים בלבד — וזו הדרך של
/// התוסף לבקש חזרה לברירת המחדל. ערך שאינו מחרוזת נזרק כ-`error.invalid_params`.
///
/// הטקסט מגיע מקוד של צד שלישי ומוצג בממשק של האפליקציה, ולכן מוסרים ממנו
/// תווי בקרה ותווי עקיפת כיוון (שמאפשרים להפוך את סדר הקריאה של כותרת), רצפי
/// רווחים מכווצים, והאורך נחתך לפי תווים גרפיים — כך שניקוד או אימוג'י לא
/// נחתכים באמצע. כותרת היא שורה אחת; בטולטיפ ([allowNewlines]) שורות חדשות
/// נשמרות, ולכל היותר שורה ריקה אחת ברצף.
String? normalizePluginTabText(
  Object? raw, {
  required int maxLength,
  required String field,
  bool allowNewlines = false,
}) {
  if (raw == null) return null;
  if (raw is! String) {
    throw Exception('error.invalid_params: $field must be a string or null');
  }
  var text = raw
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[\r\u0085\u2028\u2029]'), '\n')
      .replaceAll('\t', ' ')
      // תווי בקרה (C0, DEL, C1) — פרט לשורה חדשה — ותווי עקיפת כיוון מפורשים.
      // ביטוי גולמי: כך המעצב לא הופך את תווי הכיוון לתווים גלויים בקוד.
      .replaceAll(
        RegExp(
          r'[\u0000-\u0009\u000B-\u001F\u007F-\u009F'
          r'\u202A-\u202E\u2066-\u2069]',
        ),
        '',
      );
  if (allowNewlines) {
    text = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[^\S\n]+'), ' ').trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  } else {
    text = text.replaceAll(RegExp(r'\s+'), ' ');
  }
  text = text.trim();
  if (text.characters.length > maxLength) {
    text = text.characters.take(maxLength).toString().trimRight();
  }
  return text.isEmpty ? null : text;
}

/// בקשת `ui.setTabInfo` אחרי פענוח וניקוי.
///
/// לכל שדה שלושה מצבים: לא נמסר ([hasTitle] / [hasTooltip] שקר) — ללא שינוי;
/// נמסר כ-`null`, ריק או רווחים — איפוס לברירת המחדל; נמסר טקסט — הערך החדש.
class PluginTabInfoUpdate extends Equatable {
  const PluginTabInfoUpdate({
    this.hasTitle = false,
    this.title,
    this.hasTooltip = false,
    this.tooltip,
  });

  final bool hasTitle;
  final String? title;
  final bool hasTooltip;
  final String? tooltip;

  /// מפענח את ארגומנטי הקריאה; דורש לפחות אחד משני השדות.
  factory PluginTabInfoUpdate.parse(Map<String, dynamic> args) {
    final hasTitle = args.containsKey('title');
    final hasTooltip = args.containsKey('tooltip');
    if (!hasTitle && !hasTooltip) {
      throw Exception('error.invalid_params: title or tooltip is required');
    }
    return PluginTabInfoUpdate(
      hasTitle: hasTitle,
      title: hasTitle
          ? normalizePluginTabText(
              args['title'],
              maxLength: kMaxPluginTabTitleLength,
              field: 'title',
            )
          : null,
      hasTooltip: hasTooltip,
      tooltip: hasTooltip
          ? normalizePluginTabText(
              args['tooltip'],
              maxLength: kMaxPluginTabTooltipLength,
              field: 'tooltip',
              allowNewlines: true,
            )
          : null,
    );
  }

  @override
  List<Object?> get props => [hasTitle, title, hasTooltip, tooltip];
}
