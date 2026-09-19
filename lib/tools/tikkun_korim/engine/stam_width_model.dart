/// מודל רוחב לגופן הסת"ם: advance לכל נקודת-קוד, ביחידות em. נמדד פעם אחת
/// ב-UI isolate ומועבר למנוע, שנשאר Dart טהור וניתן להרצה ב-`Isolate.run`.
library;

import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// מלוא אות קטנה — הרווח שבין תיבה לתיבה בספר תורה. נמדד מן היו"ד שבכתב
/// עצמו, ולכן הקצאת הרווח בעימוד מתאימה את עצמה לגופן.
const int kTikkunSmallLetterCode = 0x05D9;

/// שיעור רוחב העמוד: "למשפחותיכם" שלוש פעמים (רמב"ם הל' ספר תורה ז,י).
const String kTikkunColumnShiurWord = 'למשפחותיכם';
const int kTikkunColumnShiurCount = 3;

/// יחס רוחב הטור לשיעור, לפי מניין השורות שהשיטה מכריזה עליו. נמדד מהתאמת
/// מניין השורות בעמוד לטבלת השיטה, ויצא זהה בשלושת גופני הסת"ם.
const Map<int, double> kTikkunColumnFactorByLines = {42: 1.155, 51: 1.037};
const double kTikkunFallbackColumnFactor = 1.155;

/// מניין השורות של שיטת ברירת המחדל, כשאין שיטה נבחרת (הפטרה, נביאים).
const int kTikkunDefaultLinesPerPage = 42;

/// תקציב התחלתי, עד שהגופן נמדד — המצב הזה מוצג רק בזמן הטעינה הראשונה.
const double kTikkunInitialLineWidthEm = 21.0;

/// היחס של שיטה שמכריזה על [linesPerPage] שורות בעמוד.
double tikkunColumnFactorFor(int linesPerPage) =>
    kTikkunColumnFactorByLines[linesPerPage] ?? kTikkunFallbackColumnFactor;

/// חלקו של רוחב הטור שרווח הפתיחה תופס — זהה ל-`contentWidth * 0.66` במרנדר.
const double kTikkunBigGapFraction = 0.66;

/// שיעור הרווח שבין פרשה לפרשה — "כמו תשע אותיות: אשר אשר אשר" (רמב"ם ז,י).
/// נמדד מן הכתב עצמו ולא ממספר תווים, כי רוחב האות משתנה בין גופני סת"ם.
const String kTikkunSetumaGapWord = 'אשר';
const int kTikkunSetumaGapWordCount = 3;

/// יחס הרוחב המזערי שחייב להישאר בשורה אחרי סתומה, לשיעור הרווח עצמו.
const double kTikkunMinAfterSetumaRatio = 12 / 9;

/// טווח הניקוד והטעמים — סימנים משולבים שאינם מקדמים את הכתיבה.
const int _kCombiningStart = 0x0591;
const int _kCombiningEnd = 0x05C7;

/// מחבר הגרפמות (CGJ) — תו בקרה חסר-רוחב שהמסד משתמש בו כדי לשמור על סדר
/// הטעמים במילה שנושאת את שתי מערכות הטעמים של עשרת הדברות.
const int _kCombiningGraphemeJoiner = 0x034F;

/// טווח ה-PUA שהמנוע משתמש בו לסימוני זעירא/רבתי/כתיב-קרי.
const int _kPuaStart = 0xE000;
const int _kPuaEnd = 0xE0FF;

/// טבלת רוחב של גופן סת"ם אחד. [id] הוא משפחת הגופן — הוא גם מפתח פסילת
/// המטמון של השורות, כי הפריסה תלויה בגופן.
class StamWidthModel {
  final String id;

  /// advance לכל נקודת-קוד, ביחידות em.
  final Map<int, double> advances;

  /// advance לנקודת-קוד שאינה בטבלה.
  final double fallbackAdvance;

  /// יחס רוחב הטור לשיעור, לפי השיטה הנבחרת.
  final double columnFactor;

  const StamWidthModel({
    required this.id,
    required this.advances,
    required this.fallbackAdvance,
    this.columnFactor = kTikkunFallbackColumnFactor,
  });

  StamWidthModel withColumnFactor(double factor) => factor == columnFactor
      ? this
      : StamWidthModel(
          id: id,
          advances: advances,
          fallbackAdvance: fallbackAdvance,
          columnFactor: factor,
        );

  /// מפתח פסילת המטמון: הפריסה תלויה גם בגופן וגם ברוחב הטור של השיטה.
  String get cacheKey => '$id@$columnFactor';

  /// מודל אחיד — לבדיקות ולמסלולים שאין בהם מדידה אמיתית.
  const StamWidthModel.uniform({
    this.id = 'uniform',
    double advance = 0.55,
    this.columnFactor = kTikkunFallbackColumnFactor,
  }) : advances = const {},
       fallbackAdvance = advance;

  double advanceOf(int codeUnit) {
    if (codeUnit == _kCombiningGraphemeJoiner) return 0;
    // הנו"ן המנוזרת נמצאת בתוך טווח הסימנים אך היא אות שנכתבת בכתב עצמו.
    if (codeUnit >= _kCombiningStart &&
        codeUnit <= _kCombiningEnd &&
        codeUnit != kNunHafukhaCode) {
      return 0;
    }
    if (codeUnit >= _kPuaStart && codeUnit <= _kPuaEnd) return 0;
    return advances[codeUnit] ?? fallbackAdvance;
  }

  /// רוחב מילת סת"ם ב-em, כולל מקדמי הגודל של זעירא ורבתי.
  double wordWidthEm(String stam) =>
      (_wordWidthCache[this] ??= {})[stam] ??= _measureWordEm(stam);

  /// העימוד חוזר על אותן מילים אלפי פעמים בכל מעבר איזון.
  static final Expando<Map<String, double>> _wordWidthCache = Expando();

  double _measureWordEm(String stam) {
    var total = 0.0;
    var factor = 1.0;
    for (var i = 0; i < stam.length; i++) {
      final code = stam.codeUnitAt(i);
      if (code == kZeiraStart) {
        factor = kTikkunZeiraFactor;
      } else if (code == kRabatiStart) {
        factor = kTikkunRabatiFactor;
      } else if (code == kZeiraEnd || code == kRabatiEnd) {
        factor = 1.0;
      } else {
        total += advanceOf(code) * factor;
      }
    }
    return total;
  }

  /// רוחב פריט בשורה — מילה עם הקצאת הרווח שאחריה, או רווח הלכתי.
  double itemWidthEm(LayoutWord word) {
    if (word.isGap) return setumaGapEm * word.gapFraction;
    if (word.isBigGap) return bigGapEm;
    return wordWidthEm(word.stam) + wordGapEm;
  }

  /// הרווח שאחרי כל תיבה: מלוא אות קטנה.
  double get wordGapEm => advanceOf(kTikkunSmallLetterCode);

  /// שיעור רוחב העמוד בכתב הזה.
  double get columnShiurEm =>
      wordWidthEm(kTikkunColumnShiurWord) * kTikkunColumnShiurCount +
      wordGapEm * (kTikkunColumnShiurCount - 1);

  /// תקציב רוחב השורה: השיעור ההלכתי, מוכפל ביחס של השיטה.
  double get lineWidthEm => columnShiurEm * columnFactor;

  /// שיעור הפרשה: שלוש פעמים "אשר" ושני רווחי מילה שביניהן.
  double get setumaGapEm =>
      wordWidthEm(kTikkunSetumaGapWord) * kTikkunSetumaGapWordCount +
      wordGapEm * (kTikkunSetumaGapWordCount - 1);

  double get minAfterSetumaEm => setumaGapEm * kTikkunMinAfterSetumaRatio;

  double get bigGapEm => lineWidthEm * kTikkunBigGapFraction;
}
