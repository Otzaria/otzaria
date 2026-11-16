import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// רשומת AltToc בקאש הגלובלי. הטוקנים מחושבים פעם אחת בבניית הקאש,
/// כדי שהסינון לכל שאילתה יעבור רק על הרשומות המנורמלות.
class AltTocFlatEntry {
  /// מזהה הספר ב-DB.
  final int bookId;

  /// שם הספר (כפי שמופיע ב-`book.title`).
  final String bookTitle;

  /// `book.orderIndex` של הספר — משמש למיון תוצאות, בלי לחפש שוב ב-cache.
  final double bookOrderIndex;

  /// הנתיב המלא של הערך, יחסי לספר (ללא שם הספר). למשל:
  ///   "פרשת לך לך עליה ו"
  final String reference;

  /// ה-`lineIndex` בספר שאליו יש לנווט; 0 אם הערך אינו מקושר לשורה.
  final int segment;

  /// רמת הערך (1 = שורש, 2 = ילד, ...).
  final int level;

  /// `line.id` הגלובלי של השורה המקושרת, אם קיים; 0 אם לא.
  final int dbLineId;

  /// טוקנים מנורמלים של [reference], המחושבים פעם אחת בבניית הקאש.
  final List<String> refTokens;

  const AltTocFlatEntry({
    required this.bookId,
    required this.bookTitle,
    required this.bookOrderIndex,
    required this.reference,
    required this.segment,
    required this.level,
    required this.dbLineId,
    required this.refTokens,
  });
}

/// מילת שאילתה מול טוקני AltToc. עם [variants]: גם ו/י אחת בפנים המילה ("חידושי" =
/// "חדושי") וה"א שלפני ראשי-תיבות ("הרן" = "רן"), אך לא הכפלה ("דיינים" אינו "דינים").
final class AltTocQueryWord {
  AltTocQueryWord(this.text, {this.variants = false})
    : canComeFromTitle = text.length >= 3,
      isWord = text.length >= 3 && !_isHebrewNumeral(text);

  final String text;
  final bool variants;

  /// רק מילה כזו יכולה לבוא משם הספר המארח.
  final bool canComeFromTitle;

  /// מילה ולא מספר מיקום ("קיט") — הערך עצמו חייב לכסות מילה כזו.
  final bool isWord;

  bool matches(String token) {
    if (token == text) return true;
    if (!variants) return false;
    final diff = token.length - text.length;
    if (diff == 1) return _spellsWithExtra(token, text);
    if (diff == -1) return _spellsWithExtra(text, token);
    return false;
  }

  bool inTokens(List<String> tokens) {
    if (!variants) return tokens.contains(text);
    for (final token in tokens) {
      if (matches(token)) return true;
    }
    return false;
  }
}

const int _he = 0x05D4, _vav = 0x05D5, _yod = 0x05D9;

/// [longer] הוא [shorter] עם ה"א לפני ראשי-תיבות, או עם ו/י אחת בפנים המילה.
bool _spellsWithExtra(String longer, String shorter) {
  final n = shorter.length;
  if (n == 0) return false;
  if (longer.codeUnitAt(0) == _he && longer.endsWith(shorter)) {
    return sagesTakingDefiniteArticle.contains(shorter);
  }
  if (n < 3) return false;
  var k = 0;
  while (k < n && longer.codeUnitAt(k) == shorter.codeUnitAt(k)) {
    k++;
  }
  // לא בראש המילה ולא בסופה, ולא ליד אותה אות (הכפלה).
  if (k == 0 || k >= n) return false;
  final c = longer.codeUnitAt(k);
  if (c != _vav && c != _yod) return false;
  if (longer.codeUnitAt(k - 1) == c || longer.codeUnitAt(k + 1) == c) {
    return false;
  }
  for (var j = k; j < n; j++) {
    if (longer.codeUnitAt(j + 1) != shorter.codeUnitAt(j)) return false;
  }
  return isBookTitleSpellingVariant(longer, shorter);
}

/// מספר עברי תקין ("קיט", "רמב", "טו"): מאות, עשרות ואחדות בסדר יורד.
bool _isHebrewNumeral(String token) {
  if (token.endsWith('טו') || token.endsWith('טז')) {
    return token.length == 2 ||
        _isHebrewNumeral(token.substring(0, token.length - 2));
  }
  var last = 1000;
  for (var i = 0; i < token.length; i++) {
    final v = _letterValue(token.codeUnitAt(i));
    if (v == 0) return false;
    // ת חוזרת במאות (תת); בעשרות ובאחדות אות אחת לכל היותר.
    if (v > last ||
        (v == last && v != 400) ||
        (v < 100 && last < 100 && _place(v) == _place(last))) {
      return false;
    }
    last = v;
  }
  return true;
}

int _place(int v) => v >= 100 ? 2 : (v >= 10 ? 1 : 0);

int _letterValue(int c) {
  const values = [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    0,
    20,
    30,
    0,
    40,
    0,
    50,
    60,
    70,
    0,
    80,
    0,
    90,
    100,
    200,
    300,
    400,
  ];
  final i = c - 0x05D0;
  return i < 0 || i >= values.length ? 0 : values[i];
}

/// האם מילים משם הספר המארח ("פסחים" ב"קובץ שיטות קמאי על פסחים") יכולות
/// להשלים את השאילתה: רק כשהערך עצמו מכסה שתי מילות שאילתה, אחת מהן מילה.
bool altTocHostTitleMayComplete({
  required int pathCovered,
  required bool pathCoversWord,
}) => pathCovered >= 2 && pathCoversWord;

/// מילות השאילתה ([AltTocQueryWord.canComeFromTitle]) שבנושא הספר המארח — מה שאחרי "על"
/// האחרון בשמו, או כל השם — ורק כשהשאילתה קוראת לנושא כולו ("בבא" אינו "בבא קמא").
Set<String> altTocHostTitleWords(
  List<String> queryTokens,
  List<String> titleTokens, {
  bool variants = false,
}) {
  final on = titleTokens.lastIndexOf('על');
  final subject = on >= 0 && on + 1 < titleTokens.length
      ? titleTokens.sublist(on + 1)
      : titleTokens;
  final words = [
    for (final token in queryTokens) AltTocQueryWord(token, variants: variants),
  ];
  final named = <String>{};
  for (final part in subject) {
    var found = false;
    for (final word in words) {
      if (!word.matches(part)) continue;
      found = true;
      if (word.canComeFromTitle) named.add(word.text);
    }
    if (!found) return const {};
  }
  return named;
}

/// מילות [hostTitleWords] שאינן בנתיב הערך — מה שהגיע בפועל משם הספר. [reference]
/// כמו ב-[qualifyAltTocReference].
Set<String> altTocSuppliedTitleWords(
  Set<String> hostTitleWords,
  String title,
  String reference,
) {
  if (hostTitleWords.isEmpty) return const {};
  final path = reference.startsWith('$title ')
      ? reference.substring(title.length + 1)
      : reference == title
      ? ''
      : reference;
  final tokens = normalizeForFindRefMatch(path).split(' ');
  final supplied = {
    for (final word in hostTitleWords)
      if (!AltTocQueryWord(word, variants: true).inTokens(tokens)) word,
  };
  return supplied.isEmpty ? const {} : supplied;
}

/// התאמות חדשות חייבות לשמור על מספר הדף שבסיומת, גם בלי "דף" בשאילתה.
bool altTocExpandedDafMatches(
  List<String> refTokens,
  List<String> queryTokens,
) {
  if (!refTokens.contains('דף') || queryTokens.contains('דף')) return true;
  final tokens = queryTokens.where((t) => t != 'עמוד').toList();
  bool isNumber(String token) =>
      hebrewTokenAlternatives(token).any(_isHebrewNumeral);
  if (tokens.isEmpty) return true;
  const units = [
    'כלל',
    'מאמר',
    'פרק',
    'משנה',
    'פסוק',
    'הלכה',
    'דין',
    'אות',
    'פסקה',
    'סק',
    'סעיף',
    'קטן',
    'סימן',
    'סי',
    'חלק',
    'שער',
    'כרך',
    'שאלה',
    'תשובה',
    'פרשה',
    'פרשת',
    'עליה',
  ];

  bool isUnit(String token) =>
      AltTocQueryWord(token, variants: true).inTokens(units);
  var start = tokens.length - 1;
  if (start > 0 &&
      (tokens.last == 'א' || tokens.last == 'ב') &&
      !isUnit(tokens[start - 1]) &&
      isNumber(tokens[start - 1])) {
    start--;
  }
  if (!isNumber(tokens[start]) || start > 0 && isUnit(tokens[start - 1])) {
    return true;
  }
  final citation = parseDafCitation(tokens.sublist(start));
  return citation == null || nearestDafInPathMatches(refTokens, citation);
}

/// פילטר גלובלי משותף ל-main ול-worker; [hostTitleWords] רק בלי [maxRefTokens], ו-[dafCitation]
/// מחייב התאמה מיקומית. [variants] רק כשהכתיב שבשאילתה לא מצא דבר ([altTocFlatMatchesAll]).
bool altTocFlatMatches(
  List<String> refTokens,
  List<String> queryTokens, {
  int? maxRefTokens,
  DafCitation? dafCitation,
  Set<String> hostTitleWords = const {},
  bool variants = false,
}) {
  if (maxRefTokens != null && refTokens.length > maxRefTokens) return false;
  if (dafCitation != null && !nearestDafInPathMatches(refTokens, dafCitation)) {
    return false;
  }
  final covered = <String>{};
  var fromTitle = false;
  for (final token in queryTokens) {
    // הסיומת נבדקה מיקומית; כתיבים שקולים של דף/עמוד אינם טוקנים זהים.
    if (dafCitation != null && token == 'דף') break;
    final word = AltTocQueryWord(token, variants: variants);
    if (word.inTokens(refTokens)) {
      covered.add(token);
    } else if (maxRefTokens == null && hostTitleWords.contains(token)) {
      fromTitle = true;
    } else {
      return false;
    }
  }
  if ((fromTitle || variants) &&
      !altTocExpandedDafMatches(refTokens, queryTokens)) {
    return false;
  }
  return !fromTitle ||
      altTocHostTitleMayComplete(
        // ה"דף" שנבדק מיקומית הוא מילה שהערך מכסה.
        pathCovered: covered.length + (dafCitation == null ? 0 : 1),
        pathCoversWord: covered.any((t) => AltTocQueryWord(t).isWord),
      );
}

/// התאמות [match] בכתיב שבשאילתה, ורק אם אין כאלה — גם בכתיב מלא/חסר, כדי שכתיב
/// זהה ("שלוח", "דינים") לא יפנה מקום לחלופי.
List<T> altTocFlatMatchesAll<T>(List<T> Function(bool variants) match) {
  final exact = match(false);
  return exact.isNotEmpty ? exact : match(true);
}

/// מפתח תוצאה לצמצום ה-fallback הגלובלי; [reference] כפי שהוא מוצג (עם שם הספר).
typedef AltTocResultKey = ({
  int bookId,
  String title,
  num segment,
  String reference,
});

/// בלי שם ספר כל שורות הספר שוות-רלוונטיות, והרחבת ה-cap לשוויון הציפה ספר
/// אחד בעשרות שורות ("סעיף א") — לכן לכל ספר רק הראשונות.
const int globalAltTocDiversityCap = 2;

/// תקרת השורות לכל ספר ב-fallback הגלובלי. ציון דף אינו מוגבל: סדר התצוגה
/// (אורך) מעדיף את "דף א:" ואת "דף ב." על "דף ב:" המבוקש.
int globalAltTocPerBookCap(
  List<String> queryTokens, {
  required bool singleWord,
}) =>
    singleWord ||
        queryTokens.contains('דף') ||
        queryLooksDafCitation(queryTokens)
    ? findRefMaxResultCap
    : globalAltTocDiversityCap;

/// בקשת ה-fallback הגלובלי: השאילתה, והמצב שמשפיע על הבחירה ב-worker.
class GlobalAltTocRequest {
  const GlobalAltTocRequest({
    required this.queryTokens,
    this.preferBavli = false,
    this.maxRefTokens,
    this.occupied = const [],
    this.replaceable = const [],
    this.hiddenBookIds = const {},
    this.bookRanks = const {},
    this.perBookCap = findRefMaxResultCap,
    this.substringQuota = 0,
    this.limit = findRefMaxResultCap,
  });

  final List<String> queryTokens;

  /// שם בבלי שזוהה ואחריו מספר יחיד, כפי שנקבע ב-main.
  final bool preferBavli;

  /// מגביל את אורך הערך (מסלול מילה בודדת); `null` = ללא הגבלה.
  final int? maxRefTokens;

  /// תוצאות שכבר נאספו: התאמה שחוזרת עליהן היא כפילות (כמו ב-`_dedupeRefs`).
  final List<AltTocResultKey> occupied;

  /// התאמות TOC חלקיות שכבר נאספו: `_dedupeRefs` מחליף אותן בהתאמה המלאה
  /// הראשונה שחוזרת עליהן, והיא נשלחת תמיד — גם מעבר לתקרות.
  final List<AltTocResultKey> replaceable;

  final Set<int> hiddenBookIds;

  /// דירוג הספרים והכותרת שממנה חושב. ספר חסר (או שכותרתו שונה) אינו
  /// מדורג כאן ונשלח במלואו, והדירוג ב-main מכריע.
  final Map<int, ({String title, FindRefBookRank rank})> bookRanks;

  /// תקרת השורות לכל ספר, לפי סדר הדירוג בתוך הספר.
  final int perBookCap;

  /// כמה התאמות תת-מחרוזת נשמרות מעבר ל-[limit] (ראו [findRefSubstringTailQuota]).
  final int substringQuota;

  /// מספר השורות הראשונות בדירוג שנשלחות; מעבר לו הדירוג ב-main לא יציג אותן.
  final int limit;

  bool get suppressDescendants => maxRefTokens == null;

  /// [includeBookRanks] = false כשה-worker כבר מחזיק את [bookRanks].
  Map<String, Object?> encode({bool includeBookRanks = true}) => {
    'queryTokens': queryTokens,
    'preferBavli': preferBavli,
    'maxRefTokens': maxRefTokens,
    'occupied': [for (final key in occupied) encodeAltTocResultKey(key)],
    'replaceable': [for (final key in replaceable) encodeAltTocResultKey(key)],
    'hidden': hiddenBookIds.toList(),
    if (includeBookRanks) ...{
      'rankIds': bookRanks.keys.toList(),
      'rankTitles': [for (final r in bookRanks.values) r.title],
      'rankTiers': [for (final r in bookRanks.values) r.rank.foundationalTier],
      'rankEras': [for (final r in bookRanks.values) r.rank.eraOrder],
    },
    'perBookCap': perBookCap,
    'substringQuota': substringQuota,
    'limit': limit,
  };

  /// [bookRanks] משמש כשההודעה נשלחה בלי הטבלה.
  factory GlobalAltTocRequest.decode(
    Map<dynamic, dynamic> args, {
    Map<int, ({String title, FindRefBookRank rank})> bookRanks = const {},
  }) {
    final ids = args['rankIds'] as List?;
    if (ids != null) {
      final titles = args['rankTitles'] as List;
      final tiers = args['rankTiers'] as List;
      final eras = args['rankEras'] as List;
      bookRanks = {
        for (var i = 0; i < ids.length; i++)
          ids[i] as int: (
            title: titles[i] as String,
            rank: (
              foundationalTier: tiers[i] as int?,
              eraOrder: eras[i] as int,
            ),
          ),
      };
    }
    return GlobalAltTocRequest(
      queryTokens: (args['queryTokens'] as List).cast<String>(),
      preferBavli: args['preferBavli'] as bool? ?? false,
      maxRefTokens: args['maxRefTokens'] as int?,
      occupied: [
        for (final map in args['occupied'] as List)
          decodeAltTocResultKey(map as Map),
      ],
      replaceable: [
        for (final map in args['replaceable'] as List)
          decodeAltTocResultKey(map as Map),
      ],
      hiddenBookIds: (args['hidden'] as List).cast<int>().toSet(),
      bookRanks: bookRanks,
      perBookCap: args['perBookCap'] as int,
      substringQuota: args['substringQuota'] as int,
      limit: args['limit'] as int,
    );
  }
}

/// מהתאמות ה-AltToc הגלובליות (בסדר הקאש) רק מה שהדירוג של main יכול להציג.
/// [referenceOf] — הנתיב עם שם הספר; [rankOf] ברירת מחדל: הטבלה שבבקשה.
List<T> selectGlobalAltTocMatches<T>(
  List<T> matches, {
  required GlobalAltTocRequest request,
  required int Function(T) bookIdOf,
  required String Function(T) bookTitleOf,
  required double Function(T) orderIndexOf,
  required int Function(T) segmentOf,
  required String Function(T) referenceOf,
  FindRefBookRank? Function(int bookId, String title)? rankOf,
}) {
  final query = FindRefRankQuery(
    request.queryTokens,
    preferBavli: request.preferBavli,
  );
  final entriesByBook = <int, List<T>>{};
  for (final m in matches) {
    final id = bookIdOf(m);
    if (request.hiddenBookIds.contains(id)) continue;
    (entriesByBook[id] ??= <T>[]).add(m);
  }
  if (entriesByBook.isEmpty) return const [];

  Map<int, List<AltTocResultKey>> byBookId(List<AltTocResultKey> keys) {
    final out = <int, List<AltTocResultKey>>{};
    for (final k in keys) {
      if (entriesByBook.containsKey(k.bookId)) (out[k.bookId] ??= []).add(k);
    }
    return out;
  }

  final occupiedByBook = byBookId(request.occupied);
  final replaceableByBook = byBookId(request.replaceable);
  final resolveRank =
      rankOf ??
      (bookId, title) {
        final known = request.bookRanks[bookId];
        return known != null && known.title == title ? known.rank : null;
      };

  _BookRows<T> rowsOf(_GlobalAltTocBook<T> book) =>
      book.rows ??= _rankedBookRows(
        book,
        query: query,
        occupied: occupiedByBook[book.id] ?? const [],
        replaceable: replaceableByBook[book.id] ?? const [],
        suppressDescendants: request.suppressDescendants,
        perBookCap: request.perBookCap,
        segmentOf: segmentOf,
        referenceOf: referenceOf,
      );

  final extra = <FindRefRankKey<T>>[];
  final slices = <_GlobalAltTocSlice<T>>[];
  for (final MapEntry(key: id, value: entries) in entriesByBook.entries) {
    final title = bookTitleOf(entries.first);
    final book = _GlobalAltTocBook<T>(
      id: id,
      title: title,
      orderIndex: orderIndexOf(entries.first),
      entries: entries,
      query: query,
      rank: resolveRank(id, title),
    );
    if (replaceableByBook.containsKey(id)) extra.addAll(rowsOf(book).replacers);
    if (book.rank == null) {
      extra.addAll(rowsOf(book).ranked);
      continue;
    }
    for (final supplied in _subsetsOf(book.hostTitleWords)) {
      slices.add(_GlobalAltTocSlice(book, citationMatch: true, supplied));
      if (query.isDafCitation) {
        slices.add(_GlobalAltTocSlice(book, citationMatch: false, supplied));
      }
    }
  }
  int compareSlices(_GlobalAltTocSlice<T> a, _GlobalAltTocSlice<T> b) =>
      compareFindRefRelevance(a.key, b.key, query);
  slices.sort((a, b) {
    final c = compareSlices(a, b);
    return c != 0 ? c : a.book.id.compareTo(b.book.id);
  });

  // פרוסות שוות-רלוונטיות מתמזגות לפי סדר התצוגה; כל קבוצה נחותה מקודמתה.
  final ranked = <FindRefRankKey<T>>[];
  var substringRows = 0;
  for (var start = 0; start < slices.length;) {
    var end = start + 1;
    while (end < slices.length &&
        compareSlices(slices[end], slices[start]) == 0) {
      end++;
    }
    final needAll = ranked.length < request.limit;
    if (!needAll && substringRows >= request.substringQuota) break;
    final group = <FindRefRankKey<T>>[];
    for (final slice in slices.sublist(start, end)) {
      if (!needAll && !slice.key.isSubstringMatch(query.text)) continue;
      group.addAll(
        rowsOf(
          slice.book,
        ).ranked.where(
          (row) =>
              row.citationMatch == slice.key.citationMatch &&
              _sameSet(row.categoryTokens, slice.key.categoryTokens),
        ),
      );
    }
    // שורות שקולות בדירוג (ספרים שונים, אותו אורך ו-segment) — לפי הספר,
    // כדי שהבחירה בגבול [limit] תהיה קבועה.
    group.sort((a, b) {
      final c = compareFindRefRank(a, b, query);
      return c != 0 ? c : a.bookId.compareTo(b.bookId);
    });
    ranked.addAll(group);
    substringRows += group.where((r) => r.isSubstringMatch(query.text)).length;
    start = end;
  }

  final selected = ranked.take(request.limit).toList();
  final tailQuota =
      request.substringQuota -
      selected.where((r) => r.isSubstringMatch(query.text)).length;
  if (tailQuota > 0) {
    selected.addAll(
      ranked
          .skip(request.limit)
          .where((r) => r.isSubstringMatch(query.text))
          .take(tailQuota),
    );
  }
  final seen = Set<FindRefRankKey<T>>.identity()..addAll(selected);
  selected.addAll(extra.where(seen.add));
  return [for (final row in selected) row.item];
}

class _GlobalAltTocBook<T> {
  _GlobalAltTocBook({
    required this.id,
    required this.title,
    required this.orderIndex,
    required this.entries,
    required FindRefRankQuery query,
    required this.rank,
  }) : normTitle = normalizeForFindRefMatch(title) {
    titleMatch = query.titleMatch(normTitle);
    hostTitleWords = altTocHostTitleWords(
      query.tokens,
      normTitle.split(' '),
      variants: true,
    );
  }

  final int id;
  final String title;
  final String normTitle;
  final double orderIndex;
  final List<T> entries;
  final FindRefBookRank? rank;
  late final ({
    bool exactMatch,
    bool startsWithMatch,
    List<bool> titleWordMatches,
  })
  titleMatch;

  /// [altTocHostTitleWords] של הספר; בדירוג רק מה שהגיע מהן בפועל, כמו ב-`_rankResults`.
  late final Set<String> hostTitleWords;

  /// שורות הספר אחרי הצמצום, בסדר הדירוג; מחושבות רק כשהגיעו לספר.
  _BookRows<T>? rows;

  FindRefRankKey<T> key(
    T item, {
    required bool citationMatch,
    String reference = '',
    num segment = 0,
    Set<String>? supplied,
  }) => FindRefRankKey<T>(
    item: item,
    normTitle: normTitle,
    fuzzyBookMatch: false,
    exactMatch: titleMatch.exactMatch,
    startsWithMatch: titleMatch.startsWithMatch,
    titleWordMatches: titleMatch.titleWordMatches,
    citationMatch: citationMatch,
    bookRank: rank ?? _unrankedBook,
    isOfficial: true,
    orderIndex: orderIndex,
    specificity: _altTocSpecificity,
    reference: reference,
    segment: segment,
    bookId: id,
    categoryTokens:
        supplied ?? altTocSuppliedTitleWords(hostTitleWords, title, reference),
  );
}

class _GlobalAltTocSlice<T> {
  _GlobalAltTocSlice(
    this.book,
    Set<String> supplied, {
    required bool citationMatch,
  }) : key = book.key(
         book.entries.first,
         citationMatch: citationMatch,
         supplied: supplied,
       );

  final _GlobalAltTocBook<T> book;

  /// מפתח הרלוונטיות של שורות הפרוסה — סדר התצוגה לא משתתף בו.
  final FindRefRankKey<T> key;
}

/// כל תתי-הקבוצות של [words] — מילים מעטות משם הספר.
List<Set<String>> _subsetsOf(Set<String> words) {
  var subsets = <Set<String>>[const {}];
  for (final word in words) {
    subsets = [
      ...subsets,
      for (final subset in subsets) {...subset, word},
    ];
  }
  return subsets;
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

const FindRefBookRank _unrankedBook = (foundationalTier: null, eraOrder: 0);

final int _altTocSpecificity = findRefSpecificityRank(
  isSourceLine: false,
  isAltToc: true,
  tocLevel: 0,
);

/// שורות ספר אחד אחרי הצמצום.
typedef _BookRows<T> = ({
  /// [perBookCap] הראשונות בדירוג.
  List<FindRefRankKey<T>> ranked,

  /// התאמות שמחליפות התאמה חלקית שנאספה — נשלחות תמיד, מחוץ לתקרה.
  List<FindRefRankKey<T>> replacers,
});

/// הצמצום של ספר אחד, בדיוק כמו `_dedupeRefs` ו-`suppressDeeperVariants`
/// על שורותיו, ואז [perBookCap] השורות הראשונות בדירוג.
_BookRows<T> _rankedBookRows<T>(
  _GlobalAltTocBook<T> book, {
  required FindRefRankQuery query,
  required List<AltTocResultKey> occupied,
  required List<AltTocResultKey> replaceable,
  required bool suppressDescendants,
  required int perBookCap,
  required int Function(T) segmentOf,
  required String Function(T) referenceOf,
}) {
  // כמו ב-_dedupeRefs: כל מפתח ממופה למה שתפס אותו ראשון, גם כשהשורה נזרקת.
  // מפתח ה-segment שם הוא מחרוזת: 5.0 של תוצאה קיימת אינו 5 של ערך.
  const collected = -1, global = -2;
  final segments = <int, int>{};
  final references = <String, int>{};
  void claim(num segment, String reference, int slot) {
    if (segment case final int value) segments.putIfAbsent(value, () => slot);
    references.putIfAbsent(reference, () => slot);
  }

  for (final k in occupied) {
    if (k.title == book.title) claim(k.segment, k.reference, collected);
  }
  // התאמה חלקית (slot = אינדקס) מוחלפת בהתאמה הראשונה שמתנגשת בה.
  for (var i = 0; i < replaceable.length; i++) {
    final k = replaceable[i];
    if (k.title == book.title) claim(k.segment, k.reference, i);
  }
  final replaced = <int>{};
  final keptReferences = <String>{};
  final keptLengths = <int>{};
  var rows = <FindRefRankKey<T>>[];
  final replacers = <FindRefRankKey<T>>[];
  for (final e in book.entries) {
    final segment = segmentOf(e);
    final reference = referenceOf(e);
    final hit = segments[segment] ?? references[reference];
    claim(segment, reference, hit ?? global);
    if (hit != null && (hit < 0 || !replaced.add(hit))) continue;
    keptReferences.add(reference);
    keptLengths.add(reference.length);
    (hit == null ? rows : replacers).add(
      book.key(
        e,
        citationMatch: findRefCitationMatch(query.isDafCitation, reference),
        reference: reference,
        segment: segment,
      ),
    );
  }

  int compare(FindRefRankKey<T> a, FindRefRankKey<T> b) =>
      compareFindRefRank(a, b, query);
  if (!suppressDescendants || rows.length < 2) {
    return (
      ranked: _firstRanked(rows, perBookCap, compare),
      replacers: replacers,
    );
  }
  final top = _firstRanked(rows, perBookCap, compare);
  if (!top.any(
    (row) => _hasAncestorIn(row.reference, keptReferences, keptLengths),
  )) {
    return (ranked: top, replacers: replacers);
  }
  // בציון דף צאצאים עשויים להיות מדורגים לפני האב, ולכן מסננים את כולם
  // לפני הבחירה כדי שלא לדרג שוב ושוב את אותה רשימה.
  rows = [
    for (final row in rows)
      if (!_hasAncestorIn(row.reference, keptReferences, keptLengths)) row,
  ];
  return (
    ranked: _firstRanked(rows, perBookCap, compare),
    replacers: replacers,
  );
}

/// [count] הראשונות לפי [compare], ממוינות — בלי למיין את כל הרשימה.
List<E> _firstRanked<E>(List<E> items, int count, int Function(E, E) compare) {
  if (items.length <= count * 4) {
    items.sort(compare);
    return items.length > count ? items.sublist(0, count) : items;
  }
  final best = <E>[];
  for (final item in items) {
    if (best.length == count && compare(item, best.last) >= 0) continue;
    var at = best.length;
    while (at > 0 && compare(item, best[at - 1]) < 0) {
      at--;
    }
    best.insert(at, item);
    if (best.length > count) best.removeLast();
  }
  return best;
}

Map<String, Object> encodeAltTocResultKey(AltTocResultKey key) => {
  'bookId': key.bookId,
  'title': key.title,
  'segment': key.segment,
  'reference': key.reference,
};

AltTocResultKey decodeAltTocResultKey(Map<dynamic, dynamic> map) => (
  bookId: map['bookId'] as int,
  title: map['title'] as String,
  segment: map['segment'] as num,
  reference: map['reference'] as String,
);

/// מצרף את שם הספר ל-reference יחסי מ-AltToc, אלא אם כבר מתחיל בו.
String qualifyAltTocReference(String bookTitle, String reference) {
  if (bookTitle.isEmpty) return reference;
  if (reference == bookTitle) return reference;
  // "מתחיל ב-'$bookTitle '" בלי לבנות מחרוזת לכל ערך.
  if (reference.length > bookTitle.length &&
      reference.codeUnitAt(bookTitle.length) == 0x20 &&
      reference.startsWith(bookTitle)) {
    return reference;
  }
  return '$bookTitle $reference';
}

/// [lengths] — אורכי [siblings]: תחילית באורך אחר אינה יכולה להיות אחת מהם.
bool _hasAncestorIn(String reference, Set<String> siblings, Set<int> lengths) {
  for (
    var i = reference.indexOf(' ');
    i >= 0;
    i = reference.indexOf(' ', i + 1)
  ) {
    if (lengths.contains(i) && siblings.contains(reference.substring(0, i))) {
      return true;
    }
  }
  return false;
}
