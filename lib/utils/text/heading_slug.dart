import 'package:flutter/foundation.dart';

final _disallowed = RegExp(r'[^\p{L}\p{N}\p{M}_\s-]', unicode: true);
final _whitespace = RegExp(r'\s');

const _unknown = 0, _remove = 1, _keep = 2, _dash = 3;

// סיווג כל יחידת קוד פעם אחת בעזרת ה-regex; חוסך regex לכל תו בסריקת ספר.
final _classes = Uint8List(0x10000);

/// מספר הקריאות שנפלו למסלול ה-regex (surrogate); לבדיקות בלבד.
@visibleForTesting
int headingSlugRegexFallbackCount = 0;

int _classify(int unit) {
  final ch = String.fromCharCode(unit);
  if (ch.contains(_disallowed)) return _classes[unit] = _remove;
  return _classes[unit] = ch.contains(_whitespace) ? _dash : _keep;
}

String _headingSlugRegex(String lowered) =>
    lowered.replaceAll(_disallowed, '').replaceAll(_whitespace, '-');

/// מזהה עוגן לכותרת לפי האלגוריתם של GitHub (`github-slugger`).
///
/// מקפים עוקבים אינם מאוחדים ומקפים בקצוות אינם נחתכים — בכוונה, כדי
/// שכותרת כמו `## ערכי JSON ← מיפוי` תניב `ערכי-json--מיפוי` בדיוק כמו ב-GitHub.
String headingSlug(String value) {
  final lowered = value.trim().toLowerCase();
  final out = StringBuffer();
  for (var i = 0; i < lowered.length; i++) {
    final unit = lowered.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDFFF) {
      headingSlugRegexFallbackCount++;
      return _headingSlugRegex(lowered);
    }
    var cls = _classes[unit];
    if (cls == _unknown) cls = _classify(unit);
    if (cls == _keep) {
      out.writeCharCode(unit);
    } else if (cls == _dash) {
      out.write('-');
    }
  }
  return out.toString();
}
