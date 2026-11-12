import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/plugin_registry_item.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';

/// פריט שתוסף רושם בשורת הפקדים של מסך העיון.
///
/// `type == 'button'` — לחצן בודד; `type == 'menu'` — תפריט נפתח שילדיו
/// הם לחצנים ([children]); `type == 'split'` — לחצן מפוצל שפעולתו הראשית היא
/// הפריט עצמו, ולצידה חץ שפותח את [children].
class PluginToolbarItem implements PluginRegistryItem {
  @override
  final String id;
  final String type;
  final String title;
  final String? icon;
  final List<String> contexts;
  final String? onClickEvent;
  @override
  final List<PluginToolbarItem> children;

  /// לחיצה על הפריט תפתח את דף התוסף, ואירוע הלחיצה יימסר לו לאחר הטעינה.
  final bool openPlugin;

  /// עם [openPlugin]: הלחיצה פותחת מופע נוסף של התוסף בכרטיסיה חדשה ומוסרת לו
  /// את האירוע, במקום למקד את המופע הראשי. דורש `allowMultipleInstances`.
  final bool newTab;

  /// ערך חופשי שהתוסף מסר ברישום — מוחזר לו כלשונו ב-payload של אירוע הלחיצה.
  final Object? param;

  /// פעולה שה-Host מבצע ישירות, בלי להעיר את מנוע התוסף.
  final CompiledDeclarativeAction? hostAction;

  /// מיקום הפריט בסרגל: 'primary' — בשורת הפקדים (ברירת מחדל, נדחס לתפריט
  /// כשאין מקום); 'overflow' — תמיד בתוך תפריט "עוד פעולות" (שלוש נקודות).
  final String placement;

  /// משקל מיון בתוך תפריט "עוד פעולות" (רלוונטי רק ל-placement 'overflow'):
  /// הפריטים המובנים תופסים משקלים קבועים בקפיצות של 10 (הדפסה = 60 בשני
  /// מסכי העיון), ופריט תוסף משתבץ ביניהם לפי ערכו. ברירת המחדל
  /// [defaultOrder] ממקמת את הפריט אחרי כל הפריטים המובנים.
  final int order;

  static const int defaultOrder = 1000;

  /// תנאי הצגה על ערכי הגדרות/אחסון — null = מוצג תמיד.
  @override
  final PluginWhenCondition? when;

  /// סוגי הספרים שהפקד מוצג בסרגל שלהם, כערכי `type` של זהות הספר
  /// (`text`, `pdf`, `docx`…). ריק = כל ספר. נבדק מול הספר של אותו סרגל,
  /// ולכן בתצוגה מפוצלת כל חלונית מחליטה לפי הספר שלה. על פריט עליון בלבד.
  final List<String> bookTypes;

  /// מקורות הספרים שהפקד מוצג בסרגל שלהם, כערכי `source` של זהות הספר
  /// (`library`, `user`, `attached`, `external`). ריק = כל מקור. מצטבר עם
  /// [bookTypes] (AND), ונבדק כמוהו מול הספר של אותו סרגל.
  final List<String> bookSources;

  const PluginToolbarItem({
    required this.id,
    this.type = 'button',
    required this.title,
    this.icon,
    this.contexts = const ['reader-text', 'reader-pdf'],
    this.onClickEvent,
    this.children = const [],
    this.openPlugin = false,
    this.newTab = false,
    this.param,
    this.hostAction,
    this.placement = 'primary',
    this.order = defaultOrder,
    this.when,
    this.bookTypes = const [],
    this.bookSources = const [],
  });

  /// האם הפקד מוצג בסרגל של ספר מסוג [bookType] וממקור [bookSource]. סרגל
  /// שאינו יודע את הספר שלו (null) מציג רק פקדים שאינם מסננים.
  bool showsForBook({String? bookType, String? bookSource}) =>
      bookFilterAllows(bookTypes, bookType) &&
      bookFilterAllows(bookSources, bookSource);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    if (icon != null) 'icon': icon,
    'contexts': contexts,
    if (onClickEvent != null) 'onClickEvent': onClickEvent,
    if (children.isNotEmpty)
      'children': children.map((child) => child.toJson()).toList(),
    if (openPlugin) 'openPlugin': true,
    if (newTab) 'newTab': true,
    if (param != null) 'param': param,
    if (placement != 'primary') 'placement': placement,
    if (order != defaultOrder) 'order': order,
    if (when != null) 'when': when!.toJson(),
    if (bookTypes.isNotEmpty) 'bookTypes': bookTypes,
    if (bookSources.isNotEmpty) 'bookSources': bookSources,
  };
}

class PluginToolbarException implements Exception {
  final String code;
  final String message;

  const PluginToolbarException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}
