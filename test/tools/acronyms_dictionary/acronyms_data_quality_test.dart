import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

/// בדיקות איכות לנתוני `assets/Acronyms.json` ולרשימת האישורים הידניים
/// `tool/acronyms_pipeline/data/decisions.csv`. הצינור עצמו (סינון, מיזוג,
/// דוחות) מתועד ב-`tool/acronyms_pipeline/README.md`.

const _ledgerPath = 'tool/acronyms_pipeline/data/decisions.csv';
const _sourcesPath = 'tool/acronyms_pipeline/data/sources.json';

final _nikud = RegExp('[\u0591-\u05bd\u05bf-\u05c7]');
final _invisible = RegExp(
  '[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff\u00ad]',
);
final _control = RegExp('[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]');
final _markup = RegExp(r'<[^>]*>|&[a-zA-Z#0-9]{2,8};|[{}\[\]<>|\\]');
final _allowed = RegExp("^[\u05d0-\u05ea\\s'\"\\-,()./]+\$");

// שם בודק שמציין כלי, מודל או סוכן לא יכול לאשר (ראו merge.py).
const _automatedNames = [
  'claude', 'gpt', 'gemini', 'opus', 'sonnet', 'haiku', 'copilot', 'codex',
  'chatbot', 'robot', 'agent', 'automat', 'קלוד', 'אוטומט', 'סוכן', 'רובוט', //
];
const _automatedWords = {'ai', 'bot', 'llm', 'auto', 'model', 'script', 'tool'};

bool isAutomatedReviewer(String name) {
  final low = name.toLowerCase();
  if (_automatedNames.any(low.contains)) return true;
  return low.split(RegExp(r'[\W_]+')).any(_automatedWords.contains);
}

bool isValidDate(String text) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
    DateTime.tryParse(text) != null &&
    DateTime.parse(text).toIso8601String().startsWith(text);

// שמות אותיות, אחרי קיפול אותיות סופיות (ראו tool/acronyms_pipeline/filters.py).
const _letterNames = {
  'אלפ', 'בית', 'גימל', 'דלת', 'דלית', 'הא', 'הי', 'הה', 'ואו', 'וו', 'ויו',
  'זינ', 'זיינ', 'חית', 'טית', 'יוד', 'כפ', 'למד', 'ממ', 'נונ', 'סמכ', 'עינ',
  'עיינ', 'פא', 'צדי', 'צדיק', 'קופ', 'ריש', 'שינ', 'תיו', 'תו', //
};
const _foldFrom = 'ךםןףץ';
const _foldTo = 'כמנפצ';

String _fold(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = _foldFrom.indexOf(c);
    b.write(i < 0 ? c : _foldTo[i]);
  }
  return b.toString();
}

String _signature(String s) => s
    .replaceAll(_invisible, '')
    .replaceAll(_nikud, '')
    .replaceAll('״', '"')
    .replaceAll('׳', "'")
    .replaceAll('"', '')
    .replaceAll("'", '')
    .replaceAll(RegExp(r'[-־]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'^[ .,;:]+|[ .,;:]+$'), '');

bool _isBlank(String s) =>
    !RegExp('[\u05d0-\u05ea]').hasMatch(s.replaceAll(_nikud, ''));

/// הפענוח כולו רצף של שני שמות אותיות ויותר.
bool _onlyLetterNames(String meaning) {
  final words = _signature(meaning).split(' ').where((w) => w.isNotEmpty);
  return words.length >= 2 &&
      words.every((w) => _letterNames.contains(_fold(w)));
}

const _units = {
  'אחד': 1, 'אחת': 1, 'שני': 2, 'שתי': 2, 'שנים': 2, 'שתים': 2, 'שניים': 2,
  'שתיים': 2, 'שלוש': 3, 'שלש': 3, 'שלושה': 3, 'שלשה': 3, 'ארבע': 4,
  'ארבעה': 4, 'חמש': 5, 'חמשה': 5, 'חמישה': 5, 'שש': 6, 'שישה': 6, 'ששה': 6,
  'שבע': 7, 'שבעה': 7, 'שמונה': 8, 'שמנה': 8, 'תשע': 9, 'תשעה': 9, //
};
const _tens = {
  'עשר': 10, 'עשרה': 10, 'עשרים': 20, 'שלושים': 30, 'שלשים': 30, 'ארבעים': 40,
  'חמישים': 50, 'חמשים': 50, 'שישים': 60, 'ששים': 60, 'שבעים': 70,
  'שמונים': 80, 'שמנים': 80, 'תשעים': 90, //
};
const _numberPrefix = {
  'פרק', 'סימן', 'סעיף', 'דף', 'עמוד', 'מספר', 'שנת', 'פסוק', 'מצוה', 'מצווה',
  'בפרק', 'לפרק', //
};

/// ערך של רצף מילות מספר ("שמונים ואחד" = 81), או null אם יש מילה שאינה מספר.
int? _numberPhraseValue(List<String> words) {
  var total = 0, pending = 0;
  for (final raw in words) {
    final w = raw.startsWith('ו') && raw.length > 2 ? raw.substring(1) : raw;
    if (_units.containsKey(w)) {
      pending += _units[w]!;
    } else if ((w == 'עשר' || w == 'עשרה') && pending > 0) {
      total += pending + 10;
      pending = 0;
    } else if (_tens.containsKey(w)) {
      total += _tens[w]! + pending;
      pending = 0;
    } else if (w == 'מאה') {
      total += 100;
    } else if (w == 'מאות') {
      total += (pending == 0 ? 1 : pending) * 100;
      pending = 0;
    } else if (w == 'מאתיים' || w == 'מאתים') {
      total += 200;
    } else if (w == 'אלף') {
      total = (total + pending == 0 ? 1 : total + pending) * 1000;
      pending = 0;
    } else if (w == 'אלפיים') {
      total += 2000;
    } else if (w == 'אלפים') {
      total += (pending == 0 ? 1 : pending) * 1000;
      pending = 0;
    } else {
      return null;
    }
  }
  return words.isEmpty ? null : total + pending;
}

/// ערך המפתח כמספר בגימטריה (אותיות בסדר יורד), או null אם אינו מספר.
int? _gematriaValue(String key) {
  const values = {
    'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5, 'ו': 6, 'ז': 7, 'ח': 8, 'ט': 9,
    'י': 10, 'כ': 20, 'ל': 30, 'מ': 40, 'נ': 50, 'ס': 60, 'ע': 70, 'פ': 80,
    'צ': 90, 'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400, //
  };
  final vs = [
    for (final r in _fold(_signature(key)).runes)
      values[String.fromCharCode(r)] ?? -1,
  ];
  if (vs.isEmpty || vs.contains(-1)) return null;
  for (var i = 1; i < vs.length; i++) {
    if (vs[i] > vs[i - 1] && !(vs[i - 1] == 9 && (vs[i] == 6 || vs[i] == 7))) {
      return null;
    }
    if (vs[i] == vs[i - 1] && vs[i] < 400) return null;
  }
  return vs.reduce((a, b) => a + b);
}

/// הפענוח הוא רק המפתח כמספר ("קכ״ג" = "מאה עשרים ושלוש", גם אחרי "פרק").
/// קיצורי פרקים אמיתיים כמו פ"א = "פרק א" לא נפסלים: "א" אינה מילת מספר.
bool _gematriaOnly(String key, String meaning) {
  final value = _gematriaValue(key);
  if (value == null) return false;
  var words = _signature(meaning).split(' ');
  while (words.isNotEmpty && _numberPrefix.contains(words.first)) {
    words = words.sublist(1);
  }
  return _numberPhraseValue(words) == value;
}

/// סיבות פסילה לפירוש חדש. רשימה ריקה = תקין.
List<String> noiseReasons(String key, String meaning) {
  final reasons = <String>[];
  if (_control.hasMatch(meaning)) reasons.add('control_chars');
  if (_markup.hasMatch(meaning)) reasons.add('markup');
  final plain = meaning.replaceAll(_invisible, '').trim();
  if (_isBlank(plain)) return [...reasons, 'empty'];
  if (_nikud.hasMatch(meaning) ||
      _invisible.hasMatch(meaning) ||
      meaning != meaning.replaceAll(RegExp(r'\s+'), ' ').trim() ||
      RegExp(r'^[.,;:]|[.,;:]$').hasMatch(meaning) ||
      RegExp('[־׳״“”]').hasMatch(meaning)) {
    reasons.add('not_normalised');
  }
  if (!_allowed.hasMatch(plain)) reasons.add('unexpected_characters');
  if (_signature(plain) == _signature(key)) reasons.add('same_as_key');
  if (RegExp(r'[-,:(]$').hasMatch(plain) ||
      '('.allMatches(plain).length != ')'.allMatches(plain).length) {
    reasons.add('truncated');
  }
  if (_onlyLetterNames(plain)) reasons.add('letter_names');
  if (_gematriaOnly(key, plain)) reasons.add('gematria_number');
  return reasons;
}

/// CSV לפי RFC 4180 (שדות במירכאות, מירכאות כפולות בתוך שדה, שורות בתוך שדה).
List<Map<String, String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  if (text.startsWith('\ufeff')) text = text.substring(1);
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  if (rows.isEmpty) return const [];
  final header = rows.first;
  return [
    for (final r in rows.skip(1).where((r) => r.any((f) => f.isNotEmpty)))
      {
        for (var i = 0; i < header.length; i++)
          header[i]: i < r.length ? r[i] : '',
      },
  ];
}

/// רשומה שנכנסה לקובץ: אושרה בידי אדם, או נבדקה בידי סוכן (`agent_approved`).
bool _included(Map<String, String> row) =>
    row['status'] == 'approved' || row['status'] == 'agent_approved';

void main() {
  late Map<String, dynamic> raw;
  late List<Map<String, String>> ledger;
  late Map<String, dynamic> sources;

  setUpAll(() {
    raw =
        jsonDecode(File('assets/Acronyms.json').readAsStringSync())
            as Map<String, dynamic>;
    ledger = parseCsv(File(_ledgerPath).readAsStringSync());
    sources =
        (jsonDecode(File(_sourcesPath).readAsStringSync())
                as Map<String, dynamic>)['sources']
            as Map<String, dynamic>;
  });

  group('מבנה הקובץ', () {
    test('כל מפתח הוא מחרוזת לא ריקה וכל ערך הוא רשימת מחרוזות', () {
      expect(raw, isNotEmpty);
      for (final entry in raw.entries) {
        expect(entry.key.trim(), isNotEmpty, reason: 'מפתח ריק');
        expect(entry.value, isA<List>(), reason: entry.key);
        for (final meaning in entry.value as List) {
          expect(meaning, isA<String>(), reason: entry.key);
        }
      }
    });

    test('אין רשימות ריקות, פירושים ריקים או כפילויות זהות בתוך מפתח', () {
      for (final entry in raw.entries) {
        final meanings = (entry.value as List).cast<String>();
        expect(meanings, isNotEmpty, reason: 'רשימה ריקה: ${entry.key}');
        for (final meaning in meanings) {
          expect(_isBlank(meaning), isFalse, reason: 'פירוש ריק: ${entry.key}');
        }
        expect(
          meanings.toSet().length,
          meanings.length,
          reason: 'כפילות: ${entry.key}',
        );
      }
    });
  });

  group('רשימת האישורים הידניים', () {
    test('מקורות חסומים ואסורים אינם יכולים לאשר רשומה', () {
      expect((sources['jewishbooks'] as Map)['status'], 'blocked');
      expect((sources['dicta-lead'] as Map)['status'], 'lead_only');
      for (final row in ledger.where(_included)) {
        final source = sources[row['source']] as Map<String, dynamic>?;
        expect(source, isNotNull, reason: 'מקור לא מוכר: ${row['key']}');
        expect(
          source!['status'],
          'allowed',
          reason: '${row['key']} ← ${row['source']}',
        );
      }
      for (final row in ledger) {
        expect(
          row['source'],
          isNot(contains('jewishbooks')),
          reason: row['key'],
        );
      }
    });

    test('כל רשומה שנכנסה נושאת בודק מזוהה, תאריך ואסמכתה', () {
      for (final row in ledger.where(_included)) {
        final reason = '${row['key']} ← ${row['expansion']}';
        expect(row['reviewer']!.trim(), isNotEmpty, reason: reason);
        if (row['status'] == 'agent_approved') {
          // נבדק בידי סוכן, בהוראת בעל הפרויקט, ולא בידי אדם: מסומן כך במפורש
          expect(
            row['reviewer'],
            matches(RegExp(r'^agent:[\w.\-]+$')),
            reason: reason,
          );
        } else {
          expect(
            isAutomatedReviewer(row['reviewer']!),
            isFalse,
            reason: reason,
          );
        }
        expect(isValidDate(row['reviewed_at']!), isTrue, reason: reason);
        expect(row['reference']!.trim(), isNotEmpty, reason: reason);
      }
    });

    test('כל פירוש מאושר נמצא בקובץ, וכל תוספת נקייה מרעש', () {
      final bySignature = <String, Set<String>>{};
      raw.forEach((key, value) {
        bySignature
            .putIfAbsent(_signature(key), () => <String>{})
            .addAll((value as List).cast<String>().map(_signature));
      });
      for (final row in ledger.where(_included)) {
        final key = row['key']!;
        final meaning = row['expansion']!;
        final reason = '$key ← $meaning';
        expect(
          key,
          matches(RegExp('^[א-ת]{1,12}"[א-ת]{1,3}\$')),
          reason: reason,
        );
        expect(noiseReasons(key, meaning), isEmpty, reason: reason);
        expect(
          bySignature[_signature(key)],
          contains(_signature(meaning)),
          reason: reason,
        );
      }
    });

    test('פירוש שנדחה אינו חוזר לקובץ', () {
      final bySignature = <String, Set<String>>{};
      raw.forEach((key, value) {
        bySignature
            .putIfAbsent(_signature(key), () => <String>{})
            .addAll((value as List).cast<String>().map(_signature));
      });
      for (final row in ledger.where((r) => r['status'] == 'rejected')) {
        final reason = '${row['key']} ← ${row['expansion']}';
        // דחייה שחלה על פירוש שכבר היה במאגר המקורי אינה מוחקת אותו (לא נוגעים בערכים מקוריים)
        if (row['notes']!.contains('מאגר מקורי')) continue;
        expect(
          bySignature[_signature(row['key']!)] ?? <String>{},
          isNot(contains(_signature(row['expansion']!))),
          reason: reason,
        );
      }
    });
  });

  group('גלאי הרעש (דוגמאות קבועות לתוצאות פסולות)', () {
    test('דוגמאות מההערות על PR #3202', () {
      expect(
        noiseReasons('צמיער', 'צדיק מם יוד עין ריש'),
        contains('letter_names'),
      );
      expect(noiseReasons('אב', 'אלף בית'), contains('letter_names'));
      expect(noiseReasons('קמ', 'קוף מם'), contains('letter_names'));
      expect(
        noiseReasons('קכ"ג', 'מאה עשרים ושלוש'),
        contains('gematria_number'),
      );
      expect(
        noiseReasons('קכ"ג', 'פרק מאה עשרים ושלושה'),
        contains('gematria_number'),
      );
      expect(noiseReasons('א"ב', ''), contains('empty'));
      expect(noiseReasons('א"ב', '   '), contains('empty'));
      expect(noiseReasons('א"ב', '...'), contains('empty'));
      expect(noiseReasons('א"ב', '\u200f\u200e'), contains('empty'));
      expect(noiseReasons('א"ב', 'ְִֵ'), contains('empty'));
      expect(noiseReasons('רש"י', 'רש״י'), contains('same_as_key'));
      expect(noiseReasons('א"ב', '<b>אמר</b> בית'), contains('markup'));
      expect(noiseReasons('א"ב', 'אמר רבי ('), contains('truncated'));
      expect(noiseReasons('א"ב', 'null'), isNotEmpty);
    });

    test('בודק אוטומטי, תאריך לא תקין ופירוש לא מנורמל נפסלים', () {
      for (final who in [
        'agent', 'claude', 'claude_code', 'auto_approve', 'ChatGPT', 'Gemini',
        'Opus 5', 'קלוד', 'robot', 'review-bot', 'בדיקה אוטומטית', '', //
      ]) {
        expect(who.isEmpty || isAutomatedReviewer(who), isTrue, reason: who);
      }
      for (final who in ['מיכאל', 'Michael Levi', 'palmoni5', 'Maya']) {
        expect(isAutomatedReviewer(who), isFalse, reason: who);
      }
      expect(isValidDate('2026-10-27'), isTrue);
      for (final bad in [
        '2026-99-99',
        '2026-99-99xyz',
        '2026-02-31',
        '27/10/2026',
      ]) {
        expect(isValidDate(bad), isFalse, reason: bad);
      }
      for (final bad in ['פרק‏ א', 'פרק  א', ' פרק א.', 'פרק “א”', 'פרק־א']) {
        expect(
          noiseReasons('פ"א', bad),
          contains('not_normalised'),
          reason: bad,
        );
      }
      expect(noiseReasons('כ"ב', 'עשרים ושתיים'), contains('gematria_number'));
      expect(noiseReasons('כ"ב', 'עשרים ושניים'), contains('gematria_number'));
      expect(noiseReasons('פ"ד', 'בית דלת'), contains('letter_names'));
    });

    test('פירוש תקין אינו נפסל רק כי אחת ממילותיו היא שם אות', () {
      expect(noiseReasons('ב"ד', 'בית דין'), isEmpty);
      expect(noiseReasons('ב"ש', 'בית שמאי'), isEmpty);
      expect(noiseReasons('ת"ת', 'תלמוד תורה'), isEmpty);
      expect(noiseReasons('ר"ח', 'ראש חודש'), isEmpty);
    });

    test('קיצורי פרקים ודפים אמיתיים אינם נחשבים גימטריה', () {
      expect(noiseReasons('פ"א', 'פרק א'), isEmpty);
      expect(noiseReasons('ע"א', 'עמוד א'), isEmpty);
      expect(noiseReasons('ד"ה', 'דיבור המתחיל'), isEmpty);
    });
  });

  group('טעינה וחיפוש', () {
    late DictionaryLookupRepository repository;

    setUpAll(() async {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => raw.map(
          (k, v) => MapEntry(k, (v as List).cast<String>()),
        ),
      );
      await repository.ensureAcronymsLoaded();
    });

    test('חיפוש עובד עם גרשיים ובלעדיהם, ופירושים מרובים נשמרים', () {
      final multi = raw.entries
          .where((e) => (e.value as List).length >= 3)
          .take(25)
          .toList();
      expect(multi, isNotEmpty);
      for (final entry in multi) {
        final expected = (entry.value as List).cast<String>().toSet();
        final variants = {
          entry.key,
          entry.key.replaceAll('"', ''),
          entry.key.replaceAll('"', '״'),
        };
        for (final variant in variants) {
          final found = repository.findAcronym(variant);
          expect(found, isNotNull, reason: variant);
          expect(
            found!.meanings.toSet().containsAll(expected),
            isTrue,
            reason: variant,
          );
        }
      }
    });

    test('כל פירוש מאושר נמצא בחיפוש', () {
      for (final row in ledger.where(_included)) {
        final found = repository.findAcronym(row['key']!);
        expect(found, isNotNull, reason: row['key']);
        expect(
          found!.meanings.map(_signature),
          contains(_signature(row['expansion']!)),
          reason: row['key'],
        );
      }
    });
  });
}
