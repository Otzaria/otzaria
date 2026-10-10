part of 'seforim_repository.dart';

/// ביט לכל טוקן לפי ה-hash שלו: ערך שחסר בו ביט של טוקן בשאילתה אינו מכיל
/// את הטוקן, וכך רוב הספרייה נפסלת בלי השוואת מחרוזות.
int altTocTokenMask(Iterable<String> tokens) {
  var mask = 0;
  for (final token in tokens) {
    mask |= 1 << (token.hashCode & 63);
  }
  return mask;
}

/// כל ערכי ה-AltToc בספרייה, בסדר `alt_toc_entry.id`, במערכים טיפוסיים:
/// הקאש חי לאורך חיי ה-worker, ואובייקט לכל ערך יקר פי 5 בזיכרון ובבנייה.
/// ערך מזוהה במיקומו (0..[length]); טקסט וטוקניו נשמרים פעם אחת לכל `textId`.
final class AltTocFlatIndex {
  AltTocFlatIndex._({
    required this._books,
    required this._bookSlots,
    required this._texts,
    required this._textTokens,
    required this._ids,
    required this._bookOf,
    required this._parents,
    required this._textOf,
    required this._levels,
    required this._lineIds,
    required this._segments,
    required this._refMasks,
    required this._refTokenCounts,
    required this._dafNumbers,
    required this._dafTokens,
    required this._bookStarts,
    required this._bookEntries,
  });

  static final AltTocFlatIndex empty = AltTocFlatIndex._(
    books: const [],
    bookSlots: const {},
    texts: const [],
    textTokens: const [],
    ids: Int32List(0),
    bookOf: Int32List(0),
    parents: Int32List(0),
    textOf: Int32List(0),
    levels: Int32List(0),
    lineIds: Int32List(0),
    segments: Int32List(0),
    refMasks: Int64List(0),
    refTokenCounts: Uint16List(0),
    dafNumbers: Int32List(0),
    dafTokens: const [],
    bookStarts: Int32List(1),
    bookEntries: Int32List(0),
  );

  final List<AltTocBook> _books;
  final Map<int, int> _bookSlots;
  final List<String> _texts;
  final List<List<String>> _textTokens;
  final Int32List _ids;
  final Int32List _bookOf;

  /// מיקום ההורה, או -1.
  final Int32List _parents;
  final Int32List _textOf;
  final Int32List _levels;
  final Int32List _lineIds;
  final Int32List _segments;
  final Int64List _refMasks;
  final Uint16List _refTokenCounts;

  /// הטוקן שאחרי ה-"דף" האחרון בנתיב, כאינדקס ב-[_dafTokens]; שלילי אם אין.
  final Int32List _dafNumbers;
  final List<String> _dafTokens;

  /// טווחי הערכים לכל ספר; המזהים ממוינים לפי מיקום בחיפוש הראשון בספר.
  final Int32List _bookStarts;
  final Int32List _bookEntries;

  int get length => _ids.length;

  AltTocBook bookOf(int i) => _books[_bookOf[i]];

  /// מיקום ההורה, או -1.
  int parentOf(int i) => _parents[i];

  String textOf(int i) => _texts[_textOf[i]];

  int segmentOf(int i) => _segments[i];

  int levelOf(int i) => _levels[i];

  /// [altTocTokenMask] של [refTokensOf] לכל ערך — לקריאה בלבד; סריקה ישירה
  /// של המערך זולה מקריאה לכל ערך.
  Int64List get refMasks => _refMasks;

  /// `refTokensOf(i).length`, בלי לבנות את הרשימה.
  int refTokenCountOf(int i) => _refTokenCounts[i];

  /// הטוקן שאחרי ה-"דף" האחרון ב-[refTokensOf] — מספר הדף שבו בודק
  /// `nearestDafInPathMatches`; null אם אין כזה.
  String? dafNumberOf(int i) {
    final slot = _dafNumbers[i];
    return slot < 0 ? null : _dafTokens[slot];
  }

  /// [dafNumberOf] כאינדקס ב-[dafTokens], או שלילי — השוואת מספרים בסריקה.
  int dafNumberSlotOf(int i) => _dafNumbers[i];

  /// כל הטוקנים ש-[dafNumberSlotOf] מצביע עליהם.
  List<String> get dafTokens => _dafTokens;

  int get textCount => _texts.length;

  /// הטקסט של הערך, כאינדקס ב-[textTokensAt] (טקסט חוזר — אינדקס אחד).
  int textSlotOf(int i) => _textOf[i];

  List<String> textTokensAt(int slot) => _textTokens[slot];

  /// טוקני [referenceOf] המנורמל: הנרמול אינו חוצה את הרווח שבין הורה לילד,
  /// ולכן הם שרשור טוקני הטקסטים לאורך השרשרת.
  List<String> refTokensOf(int i) {
    final parent = _parents[i];
    final own = _textTokens[_textOf[i]];
    if (parent < 0) return own;
    return [...refTokensOf(parent), ...own];
  }

  String _pathOf(int i) {
    final parent = _parents[i];
    final parentPath = parent < 0 ? '' : _pathOf(parent);
    final text = _texts[_textOf[i]];
    return parentPath.isEmpty ? text : '$parentPath $text';
  }

  /// הנתיב המלא, יחסי לספר — כמו [AltTocIndexEntry.reference].
  String referenceOf(int i) {
    final parent = _parents[i];
    if (_texts[_textOf[i]].isEmpty) return parent < 0 ? '' : _pathOf(parent);
    return _pathOf(i);
  }

  Map<String, dynamic> flatRowOf(int i) {
    final book = bookOf(i);
    return {
      'bookId': book.id,
      'bookTitle': book.title,
      'bookOrderIndex': book.orderIndex,
      'reference': referenceOf(i),
      'segment': _segments[i],
      'level': _levels[i],
      'dbLineId': _lineIds[i],
    };
  }

  final Set<int> _sortedBooks = {};

  @visibleForTesting
  int get debugSortedBookCount => _sortedBooks.length;

  List<String> _ownTokensOf(int i) => _textTokens[_textOf[i]];

  Map<String, dynamic> _tocRowOf(int i) => {
    'reference': referenceOf(i),
    'segment': _segments[i],
    'level': _levels[i],
    'dbLineId': _lineIds[i],
  };

  List<int> _entriesOfBook(int bookId) {
    final slot = _bookSlots[bookId];
    if (slot == null) return const [];
    return Int32List.sublistView(
      _bookEntries,
      _bookStarts[slot],
      _bookStarts[slot + 1],
    );
  }

  List<int> _orderedMatches(int bookId, List<int> entries, List<int> matches) {
    if (matches.isEmpty || _sortedBooks.contains(bookId)) return matches;
    // מסננים אחרי מיון הטווח המלא: מיון התוצאות בלבד משנה סדר שוויונות.
    final first = entries.first;
    final span = entries.last - first + 1;
    final selected = span <= 4 * entries.length ? Uint8List(span) : null;
    final sparse = selected == null ? matches.toSet() : const <int>{};
    if (selected != null) {
      for (final i in matches) {
        selected[i - first] = 1;
      }
    }
    final sorted = entries.toList();
    _sortAltTocForBook(
      sorted,
      compareKeys: (a, b) {
        final segment = _segments[a].compareTo(_segments[b]);
        if (segment != 0) return segment;
        final level = _levels[a].compareTo(_levels[b]);
        return level != 0 ? level : _ids[a].compareTo(_ids[b]);
      },
      compareSegments: (a, b) => _segments[a].compareTo(_segments[b]),
    );
    entries.setAll(0, sorted);
    _sortedBooks.add(bookId);
    if (selected == null) {
      return [
        for (final i in entries)
          if (sparse.contains(i)) i,
      ];
    }
    return [
      for (final i in entries)
        if (selected[i - first] != 0) i,
    ];
  }
}

enum _AltTocIndexPhase {
  start,
  textIds,
  texts,
  tokens,
  entries,
  lineSetup,
  lines,
  finish,
  done,
}

/// בניית [AltTocFlatIndex] במקטעים סינכרוניים קצרים, כדי ש-worker ישלב בקשות
/// אחרות ביניהם. אותם ערכים ואותו סדר כמו ה-JOIN של
/// `alt_toc_entry`/`alt_toc_structure`/`book`/`tocText` לפי `e.id`.
class AltTocFlatIndexBuild {
  AltTocFlatIndexBuild._(
    this._repo,
    this._rowsPerStep,
    this._textsPerStep,
    this._linesPerStep,
  );

  final SeforimRepository _repo;
  final int _rowsPerStep;
  final int _textsPerStep;
  final int _linesPerStep;

  _AltTocIndexPhase _phase = _AltTocIndexPhase.start;
  late sqlite3.Database _db;
  int _cursor = 0;
  int _firstEntryId = 0;
  int _maxEntryId = 0;
  List<int> _pendingTextIds = const [];

  final Map<int, int> _bookIdByStructure = {};
  final List<AltTocBook> _books = [];
  final Map<int, int> _bookSlots = {};
  final Map<int, int> _textSlots = {};
  final List<String> _texts = [];
  final List<List<String>> _textTokens = [];
  Int64List _textMasks = Int64List(0);

  /// לכל טקסט: הטוקן שאחרי ה-"דף" האחרון בו (ראו [AltTocFlatIndex.dafNumberOf])
  /// והטוקן הראשון — שניהם כאינדקס ב-[_dafTokens].
  Int32List _textDaf = Int32List(0);
  Int32List _textFirst = Int32List(0);
  final Map<String, int> _dafSlots = {};
  final List<String> _dafTokens = [];
  final _AltTocTokenPool _tokens = _AltTocTokenPool();

  /// שורה בלי אינדקס `line(bookId, …)` נפתרת לפי rowid, ואיתו רק שורות של
  /// ספרים בעלי מבנה (כמו הסריקה לפי ספר).
  bool _hasLineBookIndex = false;
  bool _joinLines = false;
  final Set<int> _altBookIds = {};

  int _count = 0;
  Int32List _ids = Int32List(0);
  Int32List _bookOf = Int32List(0);
  Int32List _parentIds = Int32List(0);
  Int32List _textOf = Int32List(0);
  Int32List _levels = Int32List(0);
  Int32List _lineIds = Int32List(0);
  Int32List _segments = Int32List(0);

  final Map<int, int> _lineIndexes = {};
  List<List<int>> _lineSlices = const [];
  String? _lineSliceSql;

  AltTocFlatIndex? _index;

  /// ריק עד שהבנייה הושלמה.
  AltTocFlatIndex get index => _index ?? AltTocFlatIndex.empty;

  bool get isDone => _phase == _AltTocIndexPhase.done;

  /// שלב הנרמול (טוקני הטקסטים) — בניגוד לשלבי המסד.
  bool get isNormalizing => _phase == _AltTocIndexPhase.tokens;

  /// מבצע מקטע אחד. מחזיר true כשהבנייה הושלמה.
  Future<bool> step() async {
    switch (_phase) {
      case _AltTocIndexPhase.start:
        await _start();
      case _AltTocIndexPhase.textIds:
        _readTextIds();
      case _AltTocIndexPhase.texts:
        _readTexts();
      case _AltTocIndexPhase.tokens:
        _tokenizeTexts();
      case _AltTocIndexPhase.entries:
        _readEntries();
      case _AltTocIndexPhase.lineSetup:
        await _planLineSlices();
      case _AltTocIndexPhase.lines:
        _readLineSlice();
      case _AltTocIndexPhase.finish:
        _finish();
      case _AltTocIndexPhase.done:
        break;
    }
    return isDone;
  }

  Future<void> _start() async {
    final caps = await _repo._capabilities;
    if (!caps.hasAltToc) {
      _phase = _AltTocIndexPhase.done;
      return;
    }
    _db = await _repo._database.database;
    // MIN/MAX לבדם נקראים מקצות ה-rowid; יחד עם COUNT הם סורקים את הטבלה.
    final range = _db.select(
      'SELECT (SELECT MIN(id) FROM alt_toc_entry) AS lo, '
      '(SELECT MAX(id) FROM alt_toc_entry) AS hi, '
      '(SELECT COUNT(*) FROM alt_toc_entry) AS n',
    );
    final lo = range.first['lo'] as int?;
    if (lo == null) {
      _phase = _AltTocIndexPhase.done;
      return;
    }
    _firstEntryId = lo;
    _maxEntryId = range.first['hi'] as int;
    final capacity = range.first['n'] as int;
    _ids = Int32List(capacity);
    _bookOf = Int32List(capacity);
    _parentIds = Int32List(capacity);
    _textOf = Int32List(capacity);
    _levels = Int32List(capacity);
    _lineIds = Int32List(capacity);
    _segments = Int32List(capacity);

    for (final row in _db.select('SELECT id, bookId FROM alt_toc_structure')) {
      final bookId = row['bookId'] as int;
      _bookIdByStructure[row['id'] as int] = bookId;
      _altBookIds.add(bookId);
    }
    for (final row in _db.select(
      'SELECT id, title, orderIndex FROM book '
      'WHERE id IN (SELECT bookId FROM alt_toc_structure)',
    )) {
      _bookSlots[row['id'] as int] = _books.length;
      _books.add(
        AltTocBook(
          row['id'] as int,
          row['title'] as String,
          (row['orderIndex'] as num).toDouble(),
        ),
      );
    }
    _hasLineBookIndex = _repo._hasLineBookIndex(_db);
    // בלי `content` שורת `line` צרה, ו-JOIN לפי rowid זול פי 4 מסריקת האינדקס.
    _joinLines = caps.hasLines && !caps.hasColumn('line', 'content');
    _phase = _AltTocIndexPhase.textIds;
  }

  void _readTextIds() {
    _pendingTextIds = [
      for (final row
          in _db.select('SELECT DISTINCT textId FROM alt_toc_entry').rows)
        row[0] as int,
    ];
    _cursor = 0;
    _phase = _AltTocIndexPhase.texts;
  }

  void _readTexts() {
    final end = math.min(_cursor + _textsPerStep, _pendingTextIds.length);
    const chunkSize = 900; // מתחת ל-SQLITE_MAX_VARIABLE_NUMBER.
    for (var start = _cursor; start < end; start += chunkSize) {
      final chunk = _pendingTextIds.sublist(
        start,
        math.min(start + chunkSize, end),
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      for (final row
          in _db
              .select(
                'SELECT id, text FROM tocText WHERE id IN ($placeholders)',
                chunk,
              )
              .rows) {
        _textSlots[row[0] as int] = _texts.length;
        _texts.add(row[1] as String);
      }
    }
    _cursor = end;
    if (_cursor < _pendingTextIds.length) return;
    _pendingTextIds = const [];
    _cursor = _firstEntryId;
    _textMasks = Int64List(_texts.length);
    _textDaf = Int32List(_texts.length);
    _textFirst = Int32List(_texts.length);
    _phase = _AltTocIndexPhase.tokens;
  }

  void _tokenizeTexts() {
    final end = math.min(_textTokens.length + _textsPerStep, _texts.length);
    for (var slot = _textTokens.length; slot < end; slot++) {
      final tokens = _tokens.tokensOf(_texts[slot]);
      _textTokens.add(tokens);
      _textMasks[slot] = altTocTokenMask(tokens);
      final dafAt = tokens.lastIndexOf(_dafToken);
      _textDaf[slot] = dafAt < 0
          ? _noDafNumber
          : dafAt + 1 < tokens.length
          ? _dafSlot(tokens[dafAt + 1])
          : _pendingDafNumber;
      _textFirst[slot] = tokens.isEmpty ? _noDafNumber : _dafSlot(tokens.first);
    }
    if (_textTokens.length >= _texts.length) {
      _phase = _AltTocIndexPhase.entries;
    }
  }

  void _readEntries() {
    final upper = _cursor + _rowsPerStep;
    final join = _joinLines;
    final rows = _db.select(
      join
          ? 'SELECT e.id, e.structureId, e.textId, e.level, e.parentId, '
                'e.lineId, l.lineIndex, l.bookId '
                'FROM alt_toc_entry e LEFT JOIN line l ON l.id = e.lineId '
                'WHERE e.id >= ? AND e.id < ? ORDER BY e.id'
          : 'SELECT id, structureId, textId, level, parentId, lineId '
                'FROM alt_toc_entry WHERE id >= ? AND id < ? ORDER BY id',
      [_cursor, upper],
    );
    for (final r in rows.rows) {
      final bookSlot = _bookSlots[_bookIdByStructure[r[1] as int]];
      final textSlot = _textSlots[r[2] as int];
      // כמו ה-JOIN הפנימי: ערך בלי מבנה, ספר או טקסט אינו בקאש.
      if (bookSlot == null || textSlot == null) continue;
      final n = _count++;
      _ids[n] = r[0] as int;
      _bookOf[n] = bookSlot;
      _textOf[n] = textSlot;
      _levels[n] = r[3] as int;
      _parentIds[n] = r[4] as int? ?? -1;
      final lineId = r[5] as int?;
      _lineIds[n] = lineId ?? 0;
      if (join && r[6] != null) {
        if (!_hasLineBookIndex || _altBookIds.contains(r[7] as int)) {
          _segments[n] = r[6] as int;
        }
      }
    }
    _cursor = upper;
    if (_cursor <= _maxEntryId) return;
    _phase = join ? _AltTocIndexPhase.finish : _AltTocIndexPhase.lineSetup;
  }

  /// `INDEXED BY` חובה: בלעדיו SQLite בוחר rowid, ואז 185MB קריאות במקום 15MB.
  /// הספרים מחולקים לפי מספר שורות, כדי שכל מקטע יסרוק כ-[_linesPerStep].
  Future<void> _planLineSlices() async {
    _cursor = 0;
    _phase = _AltTocIndexPhase.lines;
    final needed = <int>[
      for (var i = 0; i < _count; i++)
        if (_lineIds[i] != 0) _lineIds[i],
    ];
    if (needed.isEmpty) {
      _phase = _AltTocIndexPhase.finish;
      return;
    }
    if (!_hasLineBookIndex) {
      final ids = needed.toSet().toList(growable: false);
      _lineSlices = [
        for (var i = 0; i < ids.length; i += _linesPerStep)
          ids.sublist(i, math.min(i + _linesPerStep, ids.length)),
      ];
      return;
    }
    final hasLineIndexOnEntries = _db
        .select(
          "SELECT 1 FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_alt_toc_entry_line'",
        )
        .isNotEmpty;
    // בלי אינדקס על lineId, EXISTS היה סורק את הטבלה לכל שורה.
    final entryFilter = hasLineIndexOnEntries
        ? 'EXISTS (SELECT 1 FROM alt_toc_entry e WHERE e.lineId = l.id)'
        : 'l.id IN (SELECT lineId FROM alt_toc_entry WHERE lineId IS NOT NULL)';
    final weightColumn =
        (await _repo._capabilities).hasColumn('book', 'totalLines')
        ? 'totalLines'
        : '0';
    final books = _db.select(
      'SELECT id, $weightColumn AS weight FROM book '
      'WHERE id IN (SELECT bookId FROM alt_toc_structure) ORDER BY id',
    );
    final slices = <List<int>>[];
    var current = <int>[];
    var weight = 0;
    for (final row in books) {
      current.add(row['id'] as int);
      final lines = row['weight'] as int? ?? 0;
      weight += lines > 0 ? lines : 1000;
      if (weight >= _linesPerStep || current.length >= 500) {
        slices.add(current);
        current = <int>[];
        weight = 0;
      }
    }
    if (current.isNotEmpty) slices.add(current);
    _lineSlices = slices;
    _lineSliceSql = entryFilter;
  }

  void _readLineSlice() {
    if (_cursor >= _lineSlices.length) {
      for (var i = 0; i < _count; i++) {
        final lineId = _lineIds[i];
        if (lineId != 0) _segments[i] = _lineIndexes[lineId] ?? 0;
      }
      _lineIndexes.clear();
      _phase = _AltTocIndexPhase.finish;
      return;
    }
    final slice = _lineSlices[_cursor++];
    final filter = _lineSliceSql;
    if (filter == null) {
      _lineIndexes.addAll(_repo._lineIndexesByIds(_db, slice));
      return;
    }
    final placeholders = List.filled(slice.length, '?').join(',');
    final rows = _db.select(
      'SELECT l.id AS id, l.lineIndex AS lineIndex '
      'FROM line l INDEXED BY idx_line_book_index '
      'WHERE l.bookId IN ($placeholders) AND $filter',
      slice,
    );
    for (final row in rows) {
      _lineIndexes[row['id'] as int] = row['lineIndex'] as int;
    }
  }

  /// מיקומי ההורים, מסכות הנתיבים ואינדקס הספרים — מעבר אחד על המערכים.
  void _finish() {
    final n = _count;
    final ids = Int32List.sublistView(_ids, 0, n);
    final parents = Int32List(n);
    // המזהים כמעט רציפים: טבלת מיקומים ישירה, ובמזהים דלילים — חיפוש בינארי.
    final span = n == 0 ? 0 : ids[n - 1] - ids[0] + 1;
    final positions = span <= 2 * n
        ? (Int32List(span)..fillRange(0, span, -1))
        : null;
    if (positions != null) {
      for (var i = 0; i < n; i++) {
        positions[ids[i] - ids[0]] = i;
      }
    }
    for (var i = 0; i < n; i++) {
      final parentId = _parentIds[i];
      if (parentId < 0) {
        parents[i] = -1;
      } else if (positions == null) {
        parents[i] = _positionOf(ids, parentId);
      } else {
        final offset = parentId - ids[0];
        parents[i] = offset < 0 || offset >= span ? -1 : positions[offset];
      }
    }
    _parentIds = Int32List(0);

    final masks = Int64List(n);
    final counts = Uint16List(n);
    final dafNumbers = Int32List(n);
    // 0 = טרם חושב, 1 = בחישוב (מעגל נשבר כשורש), 2 = מוכן.
    final state = Uint8List(n);
    void resolve(int i) {
      if (state[i] == 2) return;
      state[i] = 1;
      var parent = parents[i];
      if (parent >= 0 && state[parent] == 1) parent = parents[i] = -1;
      if (parent >= 0) resolve(parent);
      final text = _textOf[i];
      masks[i] = (parent < 0 ? 0 : masks[parent]) | _textMasks[text];
      counts[i] = (parent < 0 ? 0 : counts[parent]) + _textTokens[text].length;
      final own = _textDaf[text];
      final inherited = parent < 0 ? _noDafNumber : dafNumbers[parent];
      dafNumbers[i] = own != _noDafNumber
          ? own
          : inherited == _pendingDafNumber && _textFirst[text] >= 0
          ? _textFirst[text]
          : inherited;
      state[i] = 2;
    }

    for (var i = 0; i < n; i++) {
      resolve(i);
    }

    final bookOf = Int32List.sublistView(_bookOf, 0, n);
    final starts = Int32List(_books.length + 1);
    for (var i = 0; i < n; i++) {
      starts[bookOf[i] + 1]++;
    }
    for (var s = 0; s < _books.length; s++) {
      starts[s + 1] += starts[s];
    }
    final fill = Int32List.fromList(starts);
    final bookEntries = Int32List(n);
    for (var i = 0; i < n; i++) {
      bookEntries[fill[bookOf[i]]++] = i;
    }

    _index = AltTocFlatIndex._(
      books: _books,
      bookSlots: _bookSlots,
      texts: _texts,
      textTokens: _textTokens,
      ids: ids,
      bookOf: bookOf,
      parents: parents,
      textOf: Int32List.sublistView(_textOf, 0, n),
      levels: Int32List.sublistView(_levels, 0, n),
      lineIds: Int32List.sublistView(_lineIds, 0, n),
      segments: Int32List.sublistView(_segments, 0, n),
      refMasks: masks,
      refTokenCounts: counts,
      dafNumbers: dafNumbers,
      dafTokens: _dafTokens,
      bookStarts: starts,
      bookEntries: bookEntries,
    );
    _textSlots.clear();
    _bookIdByStructure.clear();
    _phase = _AltTocIndexPhase.done;
  }

  int _dafSlot(String token) =>
      _dafSlots[token] ??= (_dafTokens..add(token)).length - 1;

  static const _dafToken = 'דף';
  static const _noDafNumber = -1;

  /// "דף" הוא הטוקן האחרון עד כה, והמספר בטקסט של הצאצא.
  static const _pendingDafNumber = -2;

  /// [ids] ממוינים (סדר הסריקה); -1 כשההורה אינו בקאש.
  static int _positionOf(Int32List ids, int id) {
    var lo = 0;
    var hi = ids.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final value = ids[mid];
      if (value == id) return mid;
      if (value < id) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }
}
