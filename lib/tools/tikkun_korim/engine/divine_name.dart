/// הסתרת שם השם ומספור עברי לטור הסמנים. פורט של `maskDivineName`
/// ו-`numToHebrewGematria` (reader.js).
library;

const String _marks = '[֑-ׇֿ-]*';

final RegExp _divineName = RegExp(
  'י($_marks)ה($_marks)ו($_marks)ה',
);

/// י-ה-ו-ה → י-ק-ו-ק, תוך שמירת הניקוד והטעמים שבין האותיות.
String maskDivineName(String text) {
  if (text.isEmpty) return text;
  return text.replaceAllMapped(
    _divineName,
    (m) => 'י${m[1]}ק${m[2]}ו${m[3]}ק',
  );
}

const List<String> _units = [
  '',
  'א',
  'ב',
  'ג',
  'ד',
  'ה',
  'ו',
  'ז',
  'ח',
  'ט',
  'י',
  'יא',
  'יב',
  'יג',
  'יד',
  'טו',
  'טז',
  'יז',
  'יח',
  'יט',
  'כ',
  'כא',
  'כב',
  'כג',
  'כד',
  'כה',
  'כו',
  'כז',
  'כח',
  'כט',
  'ל',
  'לא',
  'לב',
  'לג',
  'לד',
  'לה',
  'לו',
  'לז',
  'לח',
  'לט',
  'מ',
  'מא',
  'מב',
  'מג',
  'מד',
  'מה',
  'מו',
  'מז',
  'מח',
  'מט',
  'נ',
];

/// מספר פרק/פסוק באותיות. מעל 50 האותיות מצטרפות חשבונית (נ/ק ועוד
/// השארית), ומעל 149 מוחזרות הספרות — בדיוק כמו בתוסף.
String numToHebrewGematria(int n) {
  if (n <= 0) return '';
  if (n <= 50) return _units[n];
  if (n < 100) return 'נ${_units[n - 50]}';
  if (n < 150) return 'ק${_units[n - 100]}';
  return '$n';
}
