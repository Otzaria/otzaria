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
    if (visible == full) {
      return CorrectionProjection._(full, nikud, teamim, full, null);
    }
    final offsets = List<int>.generate(full.length, (index) => index);
    utils.removeMarks(
      full,
      nikud: nikud,
      teamim: teamim,
      sourceOffsets: offsets,
    );
    offsets.add(full.length);
    return CorrectionProjection._(
      full,
      nikud,
      teamim,
      visible,
      Int32List.fromList(offsets),
    );
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
