import 'dart:collection';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// מטמון תמונות המוגבל בסך הבתים; התמונה שנעשה בה שימוש לפני הכל נזרקת ראשונה.
///
/// המטמון מחזיק עותק ([ui.Image.clone]) משלו, ולכן הקורא משחרר את התמונות
/// שלו בלי תלות במטמון, ותמונה שנזרקה לא נעלמת ממסך שמציג אותה.
class BoundedImageCache<K> {
  BoundedImageCache({required this.maxBytes, this.budget});

  final int maxBytes;
  final PdfImageCacheBudget? budget;
  final LinkedHashMap<K, ui.Image> _images = LinkedHashMap<K, ui.Image>();
  final _budgetEntries = <K, PdfImageCacheEntry>{};
  int _bytes = 0;
  int _generation = 0;
  bool _disposed = false;

  int get length => _images.length;
  int get bytes => _bytes;

  /// עולה בכל [clear]; [put] עם דור ישן מתעלם מהתמונה.
  int get generation => _generation;

  /// עותק של התמונה ששמורה תחת [key], שהקורא אחראי לשחרר; null אם אין.
  ui.Image? lookup(K key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image;
    _budgetEntries[key]?.touch();
    return image.clone();
  }

  /// שומר עותק של [image] תחת [key]. התמונה עצמה נשארת באחריות הקורא.
  void put(K key, ui.Image image, {int? generation}) {
    if (_disposed) return;
    if (generation != null && generation != _generation) return;
    final size = _sizeOf(image);
    // A rejected oversized replacement must not discard a valid cached image.
    if (size > maxBytes) return;
    _remove(key);
    while (_bytes + size > maxBytes && _images.isNotEmpty) {
      _remove(_images.keys.first);
    }
    final reservation = budget?.tryReserve(size * 2);
    if (budget != null && reservation == null) return;
    try {
      _images[key] = image.clone();
      _bytes += size;
      if (reservation != null) {
        final entry = reservation.commit(
          retainedBytes: size * 2,
          onEvict: () => _remove(key),
        );
        if (entry == null) {
          _remove(key);
        } else {
          _budgetEntries[key] = entry;
        }
      }
    } finally {
      reservation?.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void clear() {
    _generation++;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    for (final entry in _budgetEntries.values) {
      entry.dispose();
    }
    _budgetEntries.clear();
    _bytes = 0;
  }

  void _remove(K key) {
    _budgetEntries.remove(key)?.dispose();
    final image = _images.remove(key);
    if (image == null) return;
    _bytes -= _sizeOf(image);
    image.dispose();
  }

  static int _sizeOf(ui.Image image) => image.width * image.height * 4;
}
