/// The Tur and the four parts of the Shulchan Arukh share their simanim: the
/// toolbar button opens the other book at the siman being read.
library;

import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/text/ref_key.dart';

const String _tur = 'טור';
const String _shulchanAruch = 'שולחן ערוך';
const List<String> _parts = ['אורח חיים', 'יורה דעה', 'אבן העזר', 'חושן משפט'];

// "הקדמה" and other words are not simanim; the longest siman (תקפח) has four letters.
final RegExp _siman = RegExp(r'^[א-ת]{1,4}$');

String _shulchanAruchPart(String part) => '$_shulchanAruch, $part';

/// The books [book] switches to: the Shulchan Arukh parts for the Tur, the Tur
/// for a Shulchan Arukh part, and nothing for any other or unofficial book.
List<String> turShulchanAruchPairTitles(TextBook book) {
  if (!book.source.isOfficial) return const [];
  if (book.title == _tur) {
    return [for (final p in _parts) _shulchanAruchPart(p)];
  }
  return _parts.any((p) => book.title == _shulchanAruchPart(p))
      ? const [_tur]
      : const [];
}

/// The books of [turShulchanAruchPairTitles] for [book] that are in the
/// library.
Future<List<TextBook>> findTurShulchanAruchPairs(TextBook book) async {
  final titles = turShulchanAruchPairTitles(book);
  if (titles.isEmpty) return const [];
  final library = await DataRepository.instance.library;
  return library
      .getAllBooks()
      .whereType<TextBook>()
      .where((b) => b.source.isOfficial && titles.contains(b.title))
      .toList();
}

/// The book and siman that line [heRef] of [title] points to in the other
/// book: its title, and the ref key of the siman's first seif there (`null`
/// outside a siman, e.g. an introduction). `null` when [heRef] is not a line
/// of the Tur or the Shulchan Arukh.
({String title, String? refKey})? turShulchanAruchTarget(
  String title,
  String heRef,
) {
  // אבן העזר כתוב לפעמים עם רווח כפול אחרי הפסיק.
  final parts = [
    for (final p in heRef.split(',')) p.trim().replaceAll(RegExp(r'\s+'), ' '),
  ];
  if (parts.length < 2 || !_parts.contains(parts[1])) return null;
  final part = parts[1];
  final siman = parts.length > 2 && _siman.hasMatch(parts[2]) ? parts[2] : null;
  if (title == _tur && parts[0] == _tur) {
    return (
      title: _shulchanAruchPart(part),
      refKey: siman == null ? null : buildRefKey('$siman א'),
    );
  }
  if (title == _shulchanAruchPart(part) && parts[0] == _shulchanAruch) {
    return (
      title: _tur,
      refKey: siman == null ? null : buildRefKey('$part $siman א'),
    );
  }
  return null;
}

/// Headings above a siman have no heRef; the siman is in the lines under them.
const int _headingLinesToSkip = 4;

/// Where [book] at line [index] switches to among [targets] (the books from
/// [turShulchanAruchPairTitles] that are in the library): the book and the
/// line to open, or `null` when the line's part is not among [targets].
Future<({TextBook book, int index})?> resolveTurShulchanAruchTarget(
  TextBook book,
  int index,
  List<TextBook> targets,
) async {
  ({String title, String? refKey})? target;
  for (var i = index; i <= index + _headingLinesToSkip && target == null; i++) {
    final heRef = await heRefFromDbLine(book, i);
    if (heRef != null) target = turShulchanAruchTarget(book.title, heRef);
  }
  if (target == null) {
    // בלי מיקום (כותרת הספר): ספר יעד יחיד נפתח מתחילתו.
    return targets.length == 1 ? (book: targets.single, index: 0) : null;
  }
  final title = target.title;
  final targetBook = targets.where((b) => b.title == title).firstOrNull;
  if (targetBook == null) return null;
  final refKey = target.refKey;
  final line = refKey == null
      ? null
      : await PluginRefLineResolver().resolve(book: targetBook, ref: refKey);
  if (refKey != null && line == null) return null;
  return (book: targetBook, index: line ?? 0);
}
