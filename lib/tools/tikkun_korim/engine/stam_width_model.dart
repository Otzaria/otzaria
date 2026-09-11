/// מודל רוחב לגופן הסת"ם: advance לכל נקודת-קוד, ביחידות em. נמדד פעם אחת
/// ב-UI isolate ומועבר למנוע, שנשאר Dart טהור וניתן להרצה ב-`Isolate.run`.
library;

import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// תקציב רוחב השורה ביחידות em של גופן הסת"ם: רוחב תוכן הטור ברוחב הייחוס
/// חלקי גודל גופן הסת"ם באותו קנה מידה (מאומת ב-stam_width_model_test).
const double kTikkunLineWidthEm = 23.116;

/// ההקצאה לרווח שאחרי כל מילה — כ-1/36 מתקציב השורה, כך שצפיפות המילים
/// בשורה נשמרת. הרווח המרונדר בפועל נגזר ממנה בחלוקת השארית.
const double kTikkunWordGapAllowanceEm = kTikkunLineWidthEm / 36;

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

  const StamWidthModel({
    required this.id,
    required this.advances,
    required this.fallbackAdvance,
  });

  /// מודל אחיד — לבדיקות ולמסלולים שאין בהם מדידה אמיתית.
  const StamWidthModel.uniform({
    this.id = 'uniform',
    double advance = 0.55,
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
  double wordWidthEm(String stam) {
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
    if (word.isGap) return setumaGapEm;
    if (word.isBigGap) return bigGapEm;
    return wordWidthEm(word.stam) + kTikkunWordGapAllowanceEm;
  }

  /// שיעור הפרשה: שלוש פעמים "אשר" ושני רווחי מילה שביניהן.
  double get setumaGapEm =>
      wordWidthEm(kTikkunSetumaGapWord) * kTikkunSetumaGapWordCount +
      kTikkunWordGapAllowanceEm * (kTikkunSetumaGapWordCount - 1);

  double get minAfterSetumaEm => setumaGapEm * kTikkunMinAfterSetumaRatio;

  double get bigGapEm => kTikkunLineWidthEm * kTikkunBigGapFraction;
}
