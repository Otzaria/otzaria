/// גישה טיפוסית לטבלאות שנוצרו מקוד ה-JS של התוסף. הפענוח נעשה פעם אחת
/// ונשמר במטמון; המקור הוא קבצי ה-`*.g.dart` ואין לערוך אותם ידנית.
library;

import 'package:otzaria/tools/tikkun_korim/data/aliyot_index.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/decalogue_taamim.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/haftarot_index.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/parasha_index.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/special_sections.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/tanach_structure.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/torah_layouts.g.dart';
import 'package:otzaria/tools/tikkun_korim/data/torah_readings_index.g.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();
List<Object?> _list(Object? v) => (v as List).cast<Object?>();
List<String> _strings(Object? v) =>
    (v as List).map((e) => e as String).toList(growable: false);

/// השירות שמניחים שיטה פנויה לפניהן ואחריהן (קסת הסופר טז, א-ב). מקומו
/// הראוי של הדגל הוא בנתוני הקטעים, וכשיתווסף שם הוא גובר.
const Set<String> _kBlankLineAround = {'shirat_hayam', 'shirat_haazinu'};

class TikkunData {
  TikkunData._();

  // --- שיטות חלוקת ספר התורה ---
  static Map<String, TorahLayoutMethod>? _layouts;

  static Map<String, TorahLayoutMethod> get torahLayouts =>
      _layouts ??= _parseLayouts();

  static Map<String, TorahLayoutMethod> _parseLayouts() {
    final out = <String, TorahLayoutMethod>{};
    for (final entry in kTorahLayouts.entries) {
      final m = _map(entry.value);
      out[entry.key] = TorahLayoutMethod(
        id: entry.key,
        name: m['name'] as String,
        fullName: m['fullName'] as String,
        totalPages: m['totalPages'] as int,
        linesPerPage: m['linesPerPage'] as int,
        pages: _list(m['pages'])
            .map((p) {
              final d = _map(p);
              return PageDefinition(
                num: d['num'] as int,
                sheet: d['sheet'] as int,
                book: d['book'] as String,
                parasha: d['parasha'] as String,
                firstWord: d['firstWord'] as String?,
                lastWord: d['lastWord'] as String?,
                isSpecial: d['isSpecial'] as String?,
              );
            })
            .toList(growable: false),
      );
    }
    return out;
  }

  // --- קטעים מיוחדים ---
  static List<SpecialSection>? _sections;

  static List<SpecialSection> get specialSections =>
      _sections ??= kSpecialSections.map(_parseSection).toList(growable: false);

  static SpecialSection _parseSection(Object? raw) {
    final m = _map(raw);
    final trim = m['trim'] == null
        ? const <String, Object?>{}
        : _map(m['trim']);
    return SpecialSection(
      id: m['id'] as String,
      name: m['name'] as String,
      book: m['book'] as String,
      fromCh: m['fromCh'] as int,
      fromVs: m['fromVs'] as int,
      toCh: m['toCh'] as int,
      toVs: m['toVs'] as int,
      layout: m['layout'] as String,
      cssClass: m['cssClass'] as String?,
      justifyLineBefore: m['justifyLineBefore'] as bool? ?? false,
      blankLineBefore:
          m['blankLineBefore'] as bool? ?? _kBlankLineAround.contains(m['id']),
      blankLineAfter:
          m['blankLineAfter'] as bool? ?? _kBlankLineAround.contains(m['id']),
      manualRows: m['manualRows'] == null
          ? const []
          : _list(m['manualRows'])
                .map(
                  (row) => _list(row)
                      .map((cell) {
                        final c = _map(cell);
                        return ManualRowSpec(
                          width: c['w'] as int,
                          count: c['n'] as int,
                        );
                      })
                      .toList(growable: false),
                )
                .toList(growable: false),
      extraBreaks: m['extraBreaks'] == null
          ? const []
          : _list(m['extraBreaks']).map(_strings).toList(growable: false),
      suppressBreaks: m['suppressBreaks'] == null
          ? const []
          : _list(m['suppressBreaks']).map(_strings).toList(growable: false),
      trimStartKeepLast: trim['startKeepLast'] as int?,
      trimEndKeepFirst: trim['endKeepFirst'] as int?,
      pairSeparator: m['pairSeparator'] as String?,
      pairOrder: m['pairOrder'] as String? ?? 'words_then_sep',
      raw: m,
    );
  }

  // --- עליות הפרשות ---
  static Map<String, Map<String, List<ParashaAliya>>>? _aliyot;
  static Map<String, Map<String, List<ParashaAliya>>>? _weekdayAliyot;

  static Map<String, Map<String, List<ParashaAliya>>> get aliyotIndex =>
      _aliyot ??= _parseAliyot(kAliyotIndex);

  /// עליות כהן/לוי/ישראל של שני וחמישי — תת-קבוצה של העליה הראשונה.
  static Map<String, Map<String, List<ParashaAliya>>> get weekdayAliyotIndex =>
      _weekdayAliyot ??= _parseAliyot(kWeekdayAliyotIndex);

  static Map<String, Map<String, List<ParashaAliya>>> _parseAliyot(
    Map<String, Object?> raw,
  ) {
    return {
      for (final book in raw.entries)
        book.key: {
          for (final parasha in _map(book.value).entries)
            parasha.key: _list(
              parasha.value,
            ).map(_parseParashaAliya).toList(growable: false),
        },
    };
  }

  static ParashaAliya _parseParashaAliya(Object? a) {
    final m = _map(a);
    final (fromCh, fromVs) = VerseRange.parseRef(m['from'] as String);
    final (toCh, toVs) = VerseRange.parseRef(m['to'] as String);
    final altFrom = m['altFrom'] as String?;
    final altTo = m['altTo'] as String?;
    return ParashaAliya(
      aliya: m['aliya'] as String,
      fromCh: fromCh,
      fromVs: fromVs,
      toCh: toCh,
      toVs: toVs,
      altFrom: altFrom == null ? null : VerseRange.parseRef(altFrom),
      altTo: altTo == null ? null : VerseRange.parseRef(altTo),
    );
  }

  // --- הפטרות ---
  static List<Haftarah>? _haftarot;

  static List<Haftarah> get haftarot => _haftarot ??= kHaftarotList
      .map((h) {
        final m = _map(h);
        return Haftarah(
          id: m['id'] as String,
          category: m['category'] as String,
          name: m['name'] as String,
          ashkenaz: _ranges(m['ashkenaz']),
          sephard: _ranges(m['sephard']),
          sephardNone: m['sephardNone'] == true,
          land: m['land'] as String? ?? 'both',
        );
      })
      .toList(growable: false);

  static List<VerseRange> _ranges(Object? raw) {
    if (raw == null) return const [];
    return _list(raw)
        .map((r) {
          final m = _map(r);
          final (fromCh, fromVs) = VerseRange.parseRef(m['from'] as String);
          final (toCh, toVs) = VerseRange.parseRef(m['to'] as String);
          return VerseRange(
            book: m['book'] as String,
            fromCh: fromCh,
            fromVs: fromVs,
            toCh: toCh,
            toVs: toVs,
          );
        })
        .toList(growable: false);
  }

  // --- קריאות למועדים ---
  static List<TorahReading>? _readings;

  static List<TorahReading> get torahReadings =>
      _readings ??= kTorahReadingsList
          .map((r) {
            final m = _map(r);
            return TorahReading(
              id: m['id'] as String,
              category: m['category'] as String,
              name: m['name'] as String,
              land: m['land'] as String? ?? 'both',
              nusach: m['nusach'] as String?,
              aliyot: _list(m['aliyot'])
                  .map((a) {
                    final v = _map(a);
                    final (fromCh, fromVs) = VerseRange.parseRef(
                      v['from'] as String,
                    );
                    final (toCh, toVs) = VerseRange.parseRef(v['to'] as String);
                    return ReadingAliya(
                      aliya: v['aliya'] as String,
                      aliyaLabel: v['aliyaLabel'] as String,
                      range: VerseRange(
                        book: v['book'] as String,
                        fromCh: fromCh,
                        fromVs: fromVs,
                        toCh: toCh,
                        toVs: toVs,
                      ),
                    );
                  })
                  .toList(growable: false),
            );
          })
          .toList(growable: false);

  static Map<String, String> get torahReadingsCategories =>
      kTorahReadingsCategories;

  // --- מבנה התנ"ך ---
  static Map<String, TanachBook>? _torahBooks;

  static Map<String, TanachBook> get torahBooks =>
      _torahBooks ??= <String, TanachBook>{
        for (final e in kTorahStructure.entries)
          e.key: TanachBook(
            id: e.key,
            name: _map(e.value)['name'] as String,
            chapters: 0,
            parashot: _strings(_map(e.value)['parashot']),
          ),
      };

  static List<String> get booksOrder => kBooksOrder;

  static Map<String, String> get parashaNameMapping => kParashaNameMapping;

  static Map<String, String> get aliyaDisplayNames => kAliyaDisplayNames;

  static Map<String, Object?> get combinedParashaMap => kCombinedParashaMap;

  static List<TanachBook>? _neviim;
  static List<TanachBook>? _ketuvim;

  static List<TanachBook> get neviim => _neviim ??= _tanachBooks(kTanachNeviim);

  static List<TanachBook> get ketuvim =>
      _ketuvim ??= _tanachBooks(kTanachKetuvim);

  static List<TanachBook> _tanachBooks(List<Object?> raw) => raw
      .map((b) {
        final m = _map(b);
        return TanachBook(
          id: m['id'] as String,
          name: m['name'] as String,
          chapters: m['chapters'] as int,
        );
      })
      .toList(growable: false);

  static TanachBook? tanachBookByName(String name) {
    for (final b in [...neviim, ...ketuvim]) {
      if (b.name == name) return b;
    }
    return null;
  }

  // --- מילות פתיחה של פרשות ---
  static Map<String, List<String>>? _openings;

  static Map<String, List<String>> get parashaOpenings => _openings ??= {
    for (final e in kParashaOpenings.entries) e.key: _strings(e.value),
  };

  static List<String> get allParashotOrder => kAllParashotOrder;

  static String normalizeParashaName(String uiName) =>
      kParashaNameMapping[uiName] ?? uiName;

  // --- טעם עליון / תחתון לעשרת הדברות ---
  static Map<String, DecaloguePlace>? _decalogue;

  static Map<String, DecaloguePlace> get decaloguePlaces => _decalogue ??= {
    for (final entry in kDecalogueTaamim.entries)
      entry.key: _parseDecaloguePlace(entry.key, _map(entry.value)),
  };

  static DecaloguePlace? decaloguePlaceOf(String bookName) =>
      decaloguePlaces[bookName];

  static DecaloguePlace _parseDecaloguePlace(
    String bookName,
    Map<String, Object?> m,
  ) => DecaloguePlace(
    bookName: bookName,
    chapter: m['chapter'] as int,
    fromVerse: m['fromVerse'] as int,
    toVerse: m['toVerse'] as int,
    words: _list(m['words'])
        .map((w) {
          final d = _map(w);
          return DecalogueWord(
            vFrom: d['vFrom'] as int,
            vTo: d['vTo'] as int,
            merged: d['merged'] as String,
            elyon: d['elyon'] as String,
            tachton: d['tachton'] as String,
          );
        })
        .toList(growable: false),
  );
}
