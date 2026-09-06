import 'package:otzaria/core/info/app_install_timeline.dart';
import 'package:otzaria/core/info/info_topic.dart';

/// עיצוב ערכים לתצוגה בפופאפ המידע. הכל מקבל ברירת מחדל של מקף כשאין ערך,
/// כדי שהפופאפ לא יציג `null`.
class InfoValueFormat {
  static const String dash = '—';

  const InfoValueFormat._();

  static String dateTime(DateTime value) {
    final local = value.toLocal();
    final date = [
      _pad(local.day),
      _pad(local.month),
      '${local.year}',
    ].join('/');
    return '$date ${_pad(local.hour)}:${_pad(local.minute)}';
  }

  static String dateTimeOrDash(Object? value) {
    if (value is DateTime) return dateTime(value);
    final parsed = DateTime.tryParse('${value ?? ''}');
    return parsed == null ? dash : dateTime(parsed);
  }

  static String text(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return normalized.isEmpty ? dash : normalized;
  }

  static String yesNo(Object? value) => switch (value) {
    true => 'כן',
    false => 'לא',
    _ => dash,
  };

  /// מספר עם מפריד אלפים (פסיק), ללא תלות בחבילת intl.
  static String count(Object? value) {
    if (value is! num) return dash;
    final digits = value.round().abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String bytes(Object? value) {
    if (value is! num) return dash;
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = value.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final rendered = unit == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
    return '$rendered ${units[unit]}';
  }

  static String installType(Object? value) => switch (value) {
    'portable' => 'גרסה ניידת',
    'allUsers' => 'כל המשתמשים',
    'perUser' => 'משתמש זה',
    _ => dash,
  };

  static String accountType(Object? value) => switch (value) {
    'administrator' => 'מנהל',
    'standard' => 'רגיל',
    _ => dash,
  };

  /// תאריך ההתקנה. כשהתאריך נגזר מהדיסק ולא נרשם — מסומן כמוערך.
  static String installedAt(Object? value, Map<String, dynamic> section) {
    final rendered = dateTimeOrDash(value);
    if (rendered == dash) return rendered;
    return section['installedAtSource'] == InstallDateSource.derived.name
        ? '$rendered (מוערך)'
        : rendered;
  }

  /// תקציר תיקייה אישית לשורה בפופאפ: כמות הקבצים, נפחם, ומצבים שהמשתמש
  /// חייב לראות כדי להבין מדוע ספרים אינם מופיעים (תיקייה חסרה או מוסתרת).
  static String folderSummary(Map<dynamic, dynamic> folder) {
    if (folder['exists'] == false) return 'התיקייה לא נמצאה';
    final parts = <String>[
      '${count(folder['fileCount'])} קבצים',
      bytes(folder['sizeBytes']),
      if (folder['hidden'] == true) 'מוסתרת',
      if (folder['scanTruncated'] == true) 'סריקה חלקית',
    ];
    return parts.join(' · ');
  }

  /// פירוט הסיומות של תיקייה — `txt 8 · pdf 4`. ריק כשאין קבצים.
  static String folderTypes(Map<dynamic, dynamic> folder) {
    final byType = folder['filesByType'];
    if (byType is! Map || byType.isEmpty) return '';
    return byType.entries.map((e) => '${e.key} ${count(e.value)}').join(' · ');
  }

  static String pluginVersion(Map<dynamic, dynamic> plugin) {
    final version = text(plugin['version']);
    return plugin['enabled'] == false ? '$version (מושבת)' : version;
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}

/// שדה בודד בכרטיס מקטע — התווית, ומאיזה מפתח JSON הוא נקרא.
class InfoField {
  final String key;
  final String label;

  /// ערך בפורמט LTR מובהק (גרסה, תאריך, נתיב) — מוצג משמאל לימין.
  final bool isLtr;

  /// ערך ארוך (נתיב) שמוצג בשורה משלו מתחת לתווית, ברוחב מלא. בשתי עמודות
  /// נתיב נשבר לאמצע מילה ומשאיר תו בודד בשורה נפרדת.
  final bool isBlock;

  final String Function(Object? value, Map<String, dynamic> section) _format;

  const InfoField(
    this.key,
    this.label, {
    this.isLtr = false,
    this.isBlock = false,
    String Function(Object? value, Map<String, dynamic> section)? format,
  }) : _format = format ?? _defaultFormat;

  String format(Object? value, Map<String, dynamic> section) =>
      _format(value, section);

  static String _defaultFormat(Object? value, Map<String, dynamic> _) =>
      InfoValueFormat.text(value);
}

/// סדר השדות ותוויותיהם בכל מקטע. רק שדות שמופיעים כאן מוצגים בפופאפ —
/// ה-JSON המלא זמין דרך כפתור ההעתקה.
class InfoSectionFields {
  const InfoSectionFields._();

  static List<InfoField> of(InfoTopic topic) => switch (topic) {
    InfoTopic.app => app,
    InfoTopic.library => library,
    InfoTopic.folders => folders,
    InfoTopic.plugins => plugins,
    InfoTopic.errors => errors,
    InfoTopic.all => const [],
  };

  static final List<InfoField> app = [
    InfoField(
      'version',
      'גרסה',
      isLtr: true,
      format: (value, section) {
        final version = InfoValueFormat.text(value);
        final build = InfoValueFormat.text(section['buildNumber']);
        return build == InfoValueFormat.dash ? version : '$version+$build';
      },
    ),
    InfoField(
      'installedAt',
      'תאריך התקנה',
      isLtr: true,
      format: (value, section) => InfoValueFormat.installedAt(value, section),
    ),
    InfoField(
      'updatedAt',
      'עדכון אחרון',
      isLtr: true,
      format: (value, _) => InfoValueFormat.dateTimeOrDash(value),
    ),
    InfoField('previousVersion', 'גרסה קודמת', isLtr: true),
    InfoField(
      'installType',
      'סוג התקנה',
      format: (value, _) => InfoValueFormat.installType(value),
    ),
    InfoField(
      'accountType',
      'סוג חשבון',
      format: (value, _) => InfoValueFormat.accountType(value),
    ),
    InfoField(
      'elevated',
      'הרשאות מנהל בריצה',
      format: (value, _) => InfoValueFormat.yesNo(value),
    ),
    InfoField('platform', 'פלטפורמה', isLtr: true),
    InfoField('operatingSystem', 'מערכת ההפעלה', isLtr: true),
    InfoField('dataRootPath', 'תיקיית הנתונים', isLtr: true, isBlock: true),
  ];

  static final List<InfoField> library = [
    InfoField('version', 'גרסת ספרייה', isLtr: true),
    InfoField(
      'lastUpdatedAt',
      'עדכון אחרון',
      isLtr: true,
      format: (value, _) => InfoValueFormat.dateTimeOrDash(value),
    ),
    InfoField(
      'totalBooks',
      'מספר ספרים',
      format: (value, _) => InfoValueFormat.count(value),
    ),
    InfoField(
      'personalBooks',
      'ספרים אישיים',
      format: (value, _) => InfoValueFormat.count(value),
    ),
    InfoField(
      'pdfBooks',
      'ספרי PDF',
      format: (value, _) => InfoValueFormat.count(value),
    ),
    InfoField(
      'databaseSizeBytes',
      'גודל מסד הנתונים',
      isLtr: true,
      format: (value, _) => InfoValueFormat.bytes(value),
    ),
    InfoField('path', 'נתיב הספרייה', isLtr: true, isBlock: true),
    InfoField('indexPath', 'נתיב האינדקס', isLtr: true, isBlock: true),
  ];

  static final List<InfoField> folders = [
    InfoField(
      'configuredCount',
      'תיקיות מוגדרות',
      format: (value, _) => InfoValueFormat.count(value),
    ),
    InfoField(
      'existingCount',
      'מהן קיימות בדיסק',
      format: (value, _) => InfoValueFormat.count(value),
    ),
    InfoField(
      'totalFiles',
      'סך קובצי ספרים',
      format: (value, _) => InfoValueFormat.count(value),
    ),
    InfoField(
      'totalSizeBytes',
      'נפח כולל',
      isLtr: true,
      format: (value, _) => InfoValueFormat.bytes(value),
    ),
  ];

  static final List<InfoField> plugins = [
    InfoField('webViewVersion', 'גרסת WebView', isLtr: true),
    InfoField(
      'installedCount',
      'תוספים מותקנים',
      format: (value, _) => InfoValueFormat.count(value),
    ),
    InfoField(
      'enabledCount',
      'תוספים פעילים',
      format: (value, _) => InfoValueFormat.count(value),
    ),
  ];

  static final List<InfoField> errors = [
    InfoField(
      'totalEntries',
      'סך רשומות בלוג',
      format: (value, _) => InfoValueFormat.count(value),
    ),
  ];
}
