import 'dart:typed_data';

import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// הטקסט המלא של פסקה והטקסט הגלוי ממנו, כפי שהקורא מציג אותו (ניקוד וטעמים
/// מוסתרים לפי ההגדרות), עם מיפוי היסטים ביניהם.
class CorrectionProjection {
  final String full;
  final bool nikud;
  final bool teamim;

  /// הטקסט הגלוי: בדיוק מה ש-[utils.removeMarks] מחזיר, כמו בקורא.
  final String visible;

  /// היסט בטקסט המלא של כל תו גלוי, ובסוף אורך הטקסט המלא. null כשהכול גלוי.
  final Int32List? _toFull;

  CorrectionProjection._(
    this.full,
    this.nikud,
    this.teamim,
    this.visible,
    this._toFull,
  );

  factory CorrectionProjection(
    String full, {
    required bool nikud,
    required bool teamim,
  }) {
    final visible = utils.removeMarks(full, nikud: nikud, teamim: teamim);
    final toFull = visible == full
        ? null
        : _align(full, visible, nikud, teamim);
    // יישור שנכשל משאיר את הטקסט המלא גלוי: עדיף מסך עמוס מאשר עריכה שגויה.
    return toFull == null && visible != full
        ? CorrectionProjection._(full, nikud, teamim, full, null)
        : CorrectionProjection._(full, nikud, teamim, visible, toFull);
  }

  static final Map<int, String> _images = {};

  /// מה שהקורא מציג במקום יחידת קוד אחת (ריק כשהיא מוסתרת).
  static String _image(int unit, bool nikud, bool teamim) =>
      _images.putIfAbsent(
        unit | (nikud ? 1 << 16 : 0) | (teamim ? 1 << 17 : 0),
        () => utils.removeMarks(
          String.fromCharCode(unit),
          nikud: nikud,
          teamim: teamim,
        ),
      );

  /// מתאים כל תו גלוי ליחידה שבטקסט המלא, מהסוף להתחלה: כשהקורא מוחק רווח
  /// שלפני פסק, הרווח שנשאר גלוי הוא האחרון.
  static Int32List? _align(
    String full,
    String visible,
    bool nikud,
    bool teamim,
  ) {
    final toFull = Int32List(visible.length + 1);
    toFull[visible.length] = full.length;
    var j = visible.length - 1;
    for (var k = full.length - 1; k >= 0 && j >= 0; k--) {
      // הסרת טעמים בלבד מוחקת גם את הרווח או המקף שמיד לפני פסק.
      if (teamim &&
          !nikud &&
          full.codeUnitAt(k) == 0x05C0 &&
          k > 0 &&
          (full.codeUnitAt(k - 1) == 0x20 ||
              full.codeUnitAt(k - 1) == 0x05BE)) {
        k--;
        continue;
      }
      final image = _image(full.codeUnitAt(k), nikud, teamim);
      if (image.length == 1 && image.codeUnitAt(0) == visible.codeUnitAt(j)) {
        toFull[j--] = k;
      }
    }
    return j < 0 ? toFull : null;
  }

  /// ההיסט בטקסט המלא של התו הגלוי שב-[visibleOffset]. סימנים מוסתרים שאחרי
  /// תו שייכים אליו, ולכן נכנסים לטווח שמסתיים אחריו.
  int fullOffset(int visibleOffset) =>
      _toFull == null ? visibleOffset : _toFull[visibleOffset];

  /// ההיסט הגלוי הראשון שאינו לפני [fullOffset].
  int visibleOffset(int fullOffset) {
    final toFull = _toFull;
    if (toFull == null) return fullOffset.clamp(0, visible.length);
    var low = 0;
    var high = visible.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (toFull[middle] < fullOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  CorrectionProjection withHiding({
    required bool nikud,
    required bool teamim,
  }) => nikud == this.nikud && teamim == this.teamim
      ? this
      : CorrectionProjection(full, nikud: nikud, teamim: teamim);
}
