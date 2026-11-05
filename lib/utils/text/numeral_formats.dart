/// מספרי-סידור לרשימות ממוספרות (Word ו-ODT מגדירים שמות שונים לאותם
/// פורמטים, אך המספרים עצמם זהים), ערכי הגימטריה של האותיות וספרות-תחתית.
library;

/// 1→a, 26→z, 27→aa … (bijective base-26).
String toLatinLetters(int n, {required bool upper}) {
  if (n <= 0) return '$n';
  final base = upper ? 65 : 97;
  final chars = <int>[];
  var x = n;
  while (x > 0) {
    x--;
    chars.add(base + (x % 26));
    x ~/= 26;
  }
  return String.fromCharCodes(chars.reversed);
}

/// ממיר מספר למספרה רומית (1–3999), אחרת מחזיר ספרות.
String toRomanNumeral(int n) {
  if (n <= 0 || n > 3999) return '$n';
  const vals = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const syms = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  final buf = StringBuffer();
  var x = n;
  for (var i = 0; i < vals.length; i++) {
    while (x >= vals[i]) {
      buf.write(syms[i]);
      x -= vals[i];
    }
  }
  return buf.toString();
}

/// ממיר מספר לאות עברית (גימטרייה) ללא גרשיים.
/// מדויק עד 499; מעבר לכך נופל לספרות (רשימות ארוכות כאלה נדירות).
String toHebrewNumeral(int n) {
  if (n <= 0 || n > 499) return '$n';
  const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  const hundreds = ['', 'ק', 'ר', 'ש', 'ת'];
  final buf = StringBuffer();
  var x = n;
  if (x >= 100) {
    buf.write(hundreds[x ~/ 100]);
    x %= 100;
  }
  if (x == 15) {
    buf.write('טו');
  } else if (x == 16) {
    buf.write('טז');
  } else {
    if (x >= 10) {
      buf.write(tens[x ~/ 10]);
      x %= 10;
    }
    if (x > 0) buf.write(ones[x]);
  }
  return buf.toString();
}

/// ערכי הגימטריה של האותיות, כולל הסופיות (ך=20).
const Map<String, int> hebrewLetterValues = {
  'א': 1,
  'ב': 2,
  'ג': 3,
  'ד': 4,
  'ה': 5,
  'ו': 6,
  'ז': 7,
  'ח': 8,
  'ט': 9,
  'י': 10,
  'כ': 20,
  'ך': 20,
  'ל': 30,
  'מ': 40,
  'ם': 40,
  'נ': 50,
  'ן': 50,
  'ס': 60,
  'ע': 70,
  'פ': 80,
  'ף': 80,
  'צ': 90,
  'ץ': 90,
  'ק': 100,
  'ר': 200,
  'ש': 300,
  'ת': 400,
};

/// סכום הגימטריה של [letters]; תו שאינו אות עברית נספר כאפס.
int gematriaToNumber(String letters) {
  var total = 0;
  for (final ch in letters.split('')) {
    total += hebrewLetterValues[ch] ?? 0;
  }
  return total;
}

/// ספרה רגילה ← ספרת-תחתית יוניקוד (U+2080–U+2089).
const Map<String, String> subscriptDigits = {
  '0': '₀',
  '1': '₁',
  '2': '₂',
  '3': '₃',
  '4': '₄',
  '5': '₅',
  '6': '₆',
  '7': '₇',
  '8': '₈',
  '9': '₉',
};
