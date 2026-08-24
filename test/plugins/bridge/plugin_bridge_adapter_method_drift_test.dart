import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';

/// סורק את הקוד של האדפטר עצמו ומאמת שכל action שהוא מטפל בו רשום בטבלת
/// ההרשאות. הטבלה fail-closed, ולכן method שנוסף לאדפטר ונשכח בטבלה יהיה
/// בלתי-נגיש בשקט — בדיוק הסחיפה שהבדיקה הזו תופסת.
const _adapterPath = 'lib/plugins/bridge/plugin_bridge_adapter.dart';

/// מחליף ברווח כל תו שהוא חלק מהערה או ממחרוזת, כדי שספירת הסוגריים ואיתור
/// מילות המפתח יראו קוד בלבד. שומר על אורך המקור (האינדקסים נשארים תקפים).
String _maskNonCode(String src) {
  final out = List<String>.filled(src.length, ' ');
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      var depth = 1;
      i += 2;
      while (i < src.length && depth > 0) {
        if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
          depth++;
          i += 2;
        } else if (src[i] == '*' && i + 1 < src.length && src[i + 1] == '/') {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final isRaw = i > 0 && src[i - 1] == 'r';
      final triple = src.startsWith(c * 3, i);
      final closer = triple ? c * 3 : c;
      i += closer.length;
      while (i < src.length) {
        if (!isRaw && src[i] == r'\') {
          i += 2;
          continue;
        }
        if (src.startsWith(closer, i)) {
          i += closer.length;
          break;
        }
        i++;
      }
      continue;
    }
    out[i] = c;
    i++;
  }
  return out.join();
}

/// אינדקס התו שאחרי ה-`}` הסוגר את הבלוק שנפתח ב-[openBrace].
int _matchBrace(String code, int openBrace) {
  var depth = 0;
  for (var i = openBrace; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  fail('סוגר בלוק חסר מאינדקס $openBrace');
}

final _caseKeyword = RegExp(r'\bcase\b');
final _caseLabel = RegExp(r"case\s+'([A-Za-z0-9_.]+)'\s*:");

/// תוויות ה-`case` שברמה הראשונה של בלוק ה-switch שגופו מתחיל ב-[bodyStart].
/// switch מקונן נמצא בעומק גדול יותר ולכן אינו נכלל — כך שיעדי `navigation`,
/// סוגי התראה וכיו"ב לא נחשבים בטעות ל-methods.
List<String> _topLevelCaseLabels(String src, String code, int bodyStart) {
  final bodyEnd = _matchBrace(code, bodyStart);
  final labels = <String>[];
  var depth = 0;
  for (var i = bodyStart; i < bodyEnd; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}') depth--;
    if (depth != 1 || code[i] != 'c') continue;
    if (_caseKeyword.matchAsPrefix(code, i) == null) continue;
    final label = _caseLabel.matchAsPrefix(src, i);
    if (label != null) labels.add(label.group(1)!);
  }
  return labels;
}

/// אינדקס ה-`{` שפותח את הגוף של המתודה [name] (ולא של אתר קריאה אליה).
int _methodBodyStart(String code, String name) {
  final call = RegExp('\\b$name\\s*\\(');
  for (final match in call.allMatches(code)) {
    final closeParen = _matchParen(code, match.end - 1);
    final after = code
        .substring(closeParen + 1, (closeParen + 40).clamp(0, code.length))
        .replaceAll('async', '')
        .trimLeft();
    if (after.startsWith('{')) {
      return code.indexOf('{', closeParen + 1);
    }
  }
  fail('לא נמצאה הצהרת המתודה $name');
}

int _matchParen(String code, int openParen) {
  var depth = 0;
  for (var i = openParen; i < code.length; i++) {
    if (code[i] == '(') depth++;
    if (code[i] == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  fail('סוגר סוגריים חסר מאינדקס $openParen');
}

/// כל ה-methods (`domain.action`) שהאדפטר מטפל בהם בפועל.
Map<String, List<String>> _adapterMethodsByDomain(String src) {
  final code = _maskNonCode(src);

  final executeSwitch = RegExp(r'switch\s*\(\s*domain\s*\)').firstMatch(code);
  expect(executeSwitch, isNotNull, reason: 'switch (domain) לא נמצא באדפטר');
  final domainBody = code.indexOf('{', executeSwitch!.end);
  final domainBodyEnd = _matchBrace(code, domainBody);

  // domain → שם מתודת ה-handler, מתוך `case 'x': return _handleX(...)`.
  final handlerOf = <String, String>{};
  final domains = _topLevelCaseLabels(src, code, domainBody);
  for (final domain in domains) {
    final caseAt = _caseLabel
        .allMatches(src.substring(domainBody, domainBodyEnd))
        .firstWhere((m) => m.group(1) == domain);
    final region = src.substring(
      domainBody + caseAt.end,
      domainBodyEnd,
    );
    final handler = RegExp(r'(_handle[A-Za-z]+)\s*\(').firstMatch(region);
    expect(handler, isNotNull, reason: 'אין handler ל-domain $domain');
    handlerOf[domain] = handler!.group(1)!;
  }

  final result = <String, List<String>>{};
  for (final entry in handlerOf.entries) {
    final bodyStart = _methodBodyStart(code, entry.value);
    final bodyEnd = _matchBrace(code, bodyStart);
    final actionSwitch = RegExp(
      r'switch\s*\(\s*action\s*\)',
    ).firstMatch(code.substring(bodyStart, bodyEnd));
    expect(
      actionSwitch,
      isNotNull,
      reason: 'ב-${entry.value} אין switch (action) — הסורק אינו רואה אותו',
    );
    final switchBody = code.indexOf('{', bodyStart + actionSwitch!.end);
    result[entry.key] = _topLevelCaseLabels(src, code, switchBody);
  }
  return result;
}

void main() {
  group('drift בין ה-handlers באדפטר לטבלת ההרשאות', () {
    late Map<String, List<String>> byDomain;

    setUpAll(() {
      final file = File(_adapterPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'הבדיקה מריצה מתוך שורש החבילה; לא נמצא $_adapterPath',
      );
      byDomain = _adapterMethodsByDomain(file.readAsStringSync());
    });

    test('הסורק מצא את כל ה-domains ומספר methods שפוי', () {
      expect(byDomain.keys, contains('app'));
      expect(byDomain.keys, contains('reader'));
      expect(byDomain.keys, contains('network'));
      expect(byDomain.length, greaterThanOrEqualTo(18));
      final total = byDomain.values.fold<int>(0, (sum, l) => sum + l.length);
      expect(
        total,
        greaterThan(100),
        reason: 'סריקה שמחזירה מעט methods = הסורק נשבר, לא הקוד',
      );
    });

    test('כל action שהאדפטר מטפל בו רשום ב-methodPermissions', () {
      final missing = <String>[];
      for (final domain in byDomain.keys) {
        for (final action in byDomain[domain]!) {
          final method = '$domain.$action';
          if (!PluginBridgeHandler.methodPermissions.containsKey(method)) {
            missing.add(method);
          }
        }
      }
      expect(
        missing..sort(),
        isEmpty,
        reason:
            'methods שהאדפטר מטפל בהם ואינם בטבלה: $missing. הטבלה fail-closed '
            'ולכן הם בלתי-נגישים בשקט — יש להוסיף רישום מפורש.',
      );
    });

    test('אין בטבלה רישום שאינו קיים באדפטר', () {
      final handled = {
        for (final domain in byDomain.keys)
          for (final action in byDomain[domain]!) '$domain.$action',
      };
      final stale =
          PluginBridgeHandler.methodPermissions.keys
              .where((m) => !handled.contains(m))
              .toList()
            ..sort();
      expect(stale, isEmpty, reason: 'רישומים ללא handler באדפטר: $stale');
    });

    test('switch מקונן אינו נחשב ל-methods', () {
      // navigation.goTo מכיל switch על היעד ('library'/'settings'/...).
      expect(byDomain['navigation'], ['goTo']);
      // notifications.showInApp מכיל switch על סוג ההודעה.
      expect(byDomain['notifications'], isNot(contains('success')));
      expect(byDomain['notifications'], contains('showInApp'));
      // shortcut.create מכיל switch על יעד הקיצור.
      expect(byDomain['shortcut'], ['create']);
    });
  });

  group('הסורק עצמו', () {
    const sample = '''
Future<dynamic> execute(String domain, String action) async {
  switch (domain) {
    case 'alpha':
      return await _handleAlpha(action);
    default:
      throw Exception('x');
  }
}

Future<dynamic> _handleAlpha(String action) async {
  switch (action) {
    case 'first':
      // case 'commented': לא אמור להיספר
      return 1;
    case 'second':
      switch (action) {
        case 'nested':
          return 2;
      }
      return "case 'inString': גם זו לא";
    default:
      throw Exception('nope');
  }
}
''';

    test('מחלץ רק את התוויות של ה-switch החיצוני', () {
      final result = _adapterMethodsByDomain(sample);
      expect(result, {
        'alpha': ['first', 'second'],
      });
    });
  });
}
