import 'dart:io';

/// מסתיר מידע אישי בדיווח לפני שהוא יוצא מהמחשב: תיקיית הפרופיל, שם המשתמש
/// במערכת וכתובות מייל. פונקציה טהורה — הסביבה מוזרקת.
class AppReportRedactor {
  AppReportRedactor({required Map<String, String> environment})
    : _profilePatterns = _buildProfilePatterns(environment),
      _userPattern = _buildUserPattern(environment);

  /// לפי משתני הסביבה של התהליך הנוכחי.
  factory AppReportRedactor.fromPlatform() {
    try {
      return AppReportRedactor(environment: Platform.environment);
    } catch (_) {
      return AppReportRedactor(environment: const {});
    }
  }

  static const String profilePlaceholder = '%USERPROFILE%';
  static const String userPlaceholder = '<user>';
  static const String emailPlaceholder = '<email>';
  static const int minUserNameLength = 3;

  /// סורק ליניארי: ביטוי רגולרי עם backtracking איטי ריבועית בטוקן ארוך
  /// (base64, `a.b.c.`). אותה משמעות בדיוק, בלי גבולות אורך.
  static String _redactEmails(String text) {
    var at = text.indexOf('@');
    if (at < 0) return text;
    final out = StringBuffer();
    var copied = 0; // כל מה שלפניו כבר הועתק או הוחלף
    while (at >= 0) {
      // החלק המקומי: הרצף שלפני ה-@, מהתו האלפאנומרי הראשון בו.
      var start = at;
      while (start > copied && _isLocal(text.codeUnitAt(start - 1))) {
        start--;
      }
      while (start < at && !_isAlnum(text.codeUnitAt(start))) {
        start++;
      }
      final end = start < at ? _domainEnd(text, at + 1) : -1;
      if (end < 0) {
        at = text.indexOf('@', at + 1);
        continue;
      }
      out
        ..write(text.substring(copied, start))
        ..write(emailPlaceholder);
      copied = end;
      at = text.indexOf('@', end);
    }
    return (out..write(text.substring(copied))).toString();
  }

  /// סוף הדומיין שמתחיל ב-[from]: תוויות לא ריקות מופרדות בנקודה ואחריהן
  /// סיומת של 2 אותיות לפחות; הסיומת המאוחרת ביותר מנצחת. -1 אם אין.
  static int _domainEnd(String text, int from) {
    var end = -1;
    var pos = from;
    while (true) {
      final labelStart = pos;
      while (pos < text.length && _isLabel(text.codeUnitAt(pos))) {
        pos++;
      }
      if (pos == labelStart || pos >= text.length) break;
      if (text.codeUnitAt(pos) != 0x2E) break;
      var tld = pos + 1;
      while (tld < text.length && _isLetter(text.codeUnitAt(tld))) {
        tld++;
      }
      if (tld - pos - 1 >= 2) end = tld;
      pos++;
    }
    return end;
  }

  static bool _isLetter(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  static bool _isAlnum(int c) => _isLetter(c) || (c >= 0x30 && c <= 0x39);

  /// תו של תווית דומיין: אלפאנומרי או `-`.
  static bool _isLabel(int c) => _isAlnum(c) || c == 0x2D;

  /// תו של החלק המקומי: תו תווית או `.` `_` `%` `+`.
  static bool _isLocal(int c) =>
      _isLabel(c) || c == 0x2E || c == 0x5F || c == 0x25 || c == 0x2B;

  final List<RegExp> _profilePatterns;
  final RegExp? _userPattern;

  String redactText(String text) {
    if (text.isEmpty) return text;
    var result = _redactEmails(text);
    for (final pattern in _profilePatterns) {
      result = result.replaceAll(pattern, profilePlaceholder);
    }
    final user = _userPattern;
    if (user != null) result = result.replaceAll(user, userPlaceholder);
    return result;
  }

  /// מחיל את ההסתרה על כל מחרוזת במבנה JSON, כולל מפתחות של מפות.
  Object? redactJson(Object? value) {
    if (value is String) return redactText(value);
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          redactText('${entry.key}'): redactJson(entry.value),
      };
    }
    if (value is List) return value.map(redactJson).toList();
    return value;
  }

  /// כל צורות הנתיב: שני סוגי הלוכסנים, וגם `\\` כפי שנכתב בתוך JSON.
  static List<RegExp> _buildProfilePatterns(Map<String, String> env) {
    final variants = <String>{};
    for (final key in const ['USERPROFILE', 'HOME']) {
      var path = env[key]?.trim() ?? '';
      while (path.length > 1 && (path.endsWith('/') || path.endsWith('\\'))) {
        path = path.substring(0, path.length - 1);
      }
      // נתיב קצר מדי (`/`, `C:`) היה מוחק חלקים לא אישיים מכל הדוח.
      if (path.length < 4) continue;
      final segments = path.split(RegExp(r'[\\/]+'));
      variants
        ..add(segments.join('\\'))
        ..add(segments.join('/'))
        ..add(segments.join(r'\\'));
    }
    final sorted = variants.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return [
      for (final variant in sorted)
        RegExp(
          '${RegExp.escape(variant)}(?![A-Za-z0-9_\\-.])',
          caseSensitive: false,
        ),
    ];
  }

  static RegExp? _buildUserPattern(Map<String, String> env) {
    final names = <String>{
      for (final key in const ['USERNAME', 'USER'])
        if ((env[key]?.trim() ?? '').length >= minUserNameLength)
          env[key]!.trim(),
    };
    if (names.isEmpty) return null;
    final alternatives =
        (names.toList()..sort((a, b) => b.length.compareTo(a.length)))
            .map(RegExp.escape)
            .join('|');
    // `<` / `>`: הסתרה חוזרת לא תהפוך את `<user>` של שם המשתמש User ל-`<<user>>`.
    return RegExp(
      r'(?<![\p{L}\p{N}_<])(?:' + alternatives + r')(?![\p{L}\p{N}_>])',
      caseSensitive: false,
      unicode: true,
    );
  }
}
