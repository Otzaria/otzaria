import 'dart:math';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// אינדקס הפריט העליון הנראה.
///
/// `ItemPositionsListener.itemPositions.value` מוחזק כ-`Set` שסדר האיטרציה
/// שלו תואם לסדר ההכנסה (ולא לאינדקס). אחרי גלילות, `.first.index` עלול
/// להחזיר את הפריט התחתון. לכן יש לחשב את המינימום מפורשות.
///
/// אם הקולקציה ריקה מוחזר 0 (פריט "ראשון" סביר כשאין מה לראות).
int topmostVisibleIndex(Iterable<ItemPosition> positions) {
  if (positions.isEmpty) return 0;
  return positions.map((p) => p.index).reduce(min);
}

/// אינדקס הפריט התחתון הנראה (מקסימום, מאותה סיבה כמו [topmostVisibleIndex]).
int bottommostVisibleIndex(Iterable<ItemPosition> positions) {
  if (positions.isEmpty) return 0;
  return positions.map((p) => p.index).reduce(max);
}
