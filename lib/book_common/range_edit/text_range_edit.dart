/// היחידה שקצות הטווח זזים בה.
enum TextRangeUnit { words, paragraphs }

/// מיקום בטקסט: פסקה (מ-0) ואופסט utf16 בתוכה.
typedef TextPoint = ({int paragraph, int offset});

typedef TextRangeWord = ({int start, int end});

/// עריכת טווח בטקסט של פסקאות, בלי תלות במה שהטווח מסמן (הערה, סימון).
///
/// ביחידת [TextRangeUnit.words] הקצוות זזים במילים שלמות, ועם
/// [crossParagraphs] גם אל הפסקה הסמוכה. ביחידת [TextRangeUnit.paragraphs]
/// הטווח הוא פסקאות שלמות. [paragraphAt] נקרא רק לפסקאות שמוצגות או נערכות.
class TextRangeEdit {
  TextRangeEdit({
    required this.paragraphCount,
    required this._paragraphAt,
    required TextPoint start,
    required TextPoint end,
    TextRangeUnit unit = TextRangeUnit.words,
    this.crossParagraphs = true,
  }) : assert(paragraphCount > 0),
       _start = start,
       _end = end,
       _unit = unit,
       _savedStart = start,
       _savedEnd = end,
       _savedUnit = unit {
    _normalize();
    _savedStart = _start;
    _savedEnd = _end;
  }

  final int paragraphCount;

  /// בלי זה, ביחידת מילים הטווח נשאר בפסקה אחת.
  final bool crossParagraphs;

  final String Function(int index) _paragraphAt;
  final _texts = <int, String>{};
  final _words = <int, List<TextRangeWord>>{};

  TextPoint _start;
  TextPoint _end;
  TextRangeUnit _unit;
  TextPoint _savedStart;
  TextPoint _savedEnd;
  final TextRangeUnit _savedUnit;

  TextPoint get start => _start;

  /// סוף הטווח (לא כולל).
  TextPoint get end => _end;

  TextRangeUnit get unit => _unit;

  bool get isSingleParagraph => _start.paragraph == _end.paragraph;

  bool get changed =>
      _unit != _savedUnit || _start != _savedStart || _end != _savedEnd;

  String paragraph(int index) =>
      _texts.putIfAbsent(index, () => _paragraphAt(index));

  List<TextRangeWord> wordsOf(int index) => _words.putIfAbsent(index, () {
    return [
      for (final match in RegExp(r'\S+').allMatches(paragraph(index)))
        (start: match.start, end: match.end),
    ];
  });

  /// הטקסט שבטווח, כשהוא בפסקה אחת.
  String get text => paragraph(
    _start.paragraph,
  ).substring(_start.offset, isSingleParagraph ? _end.offset : null);

  void reset() {
    _start = _savedStart;
    _end = _savedEnd;
    _unit = _savedUnit;
  }

  /// מעבר ליחידה אחרת: פסקאות מכסות את הפסקאות שבטווח; מילים מכסות את כל
  /// המילים בהן (או רק בפסקה הראשונה, בלי [crossParagraphs]).
  set unit(TextRangeUnit value) {
    if (value == _unit) return;
    _unit = value;
    if (value == TextRangeUnit.words) {
      // פסקאות ריקות בקצוות אינן חלק מטווח של מילים.
      var first = _start.paragraph;
      var last = _end.paragraph;
      while (first < last && wordsOf(first).isEmpty) {
        first++;
      }
      while (last > first && wordsOf(last).isEmpty) {
        last--;
      }
      if (!crossParagraphs) last = first;
      _start = _paragraphStart(first);
      _end = _paragraphEnd(last);
    }
    _normalize();
  }

  // ---- קצה ההתחלה ----

  TextPoint? get _growStart => _unit == TextRangeUnit.paragraphs
      ? (_start.paragraph > 0 ? _paragraphStart(_start.paragraph - 1) : null)
      : _wordBefore(_start);

  TextPoint? get _shrinkStart {
    if (_unit == TextRangeUnit.paragraphs) {
      return _start.paragraph < _end.paragraph
          ? _paragraphStart(_start.paragraph + 1)
          : null;
    }
    final next = _wordStartAfter(_start);
    return next != null && _before(next, _end) && _hasWordBefore(next, _end)
        ? next
        : null;
  }

  // ---- קצה הסוף ----

  TextPoint? get _growEnd => _unit == TextRangeUnit.paragraphs
      ? (_end.paragraph < paragraphCount - 1
            ? _paragraphEnd(_end.paragraph + 1)
            : null)
      : _wordAfter(_end);

  TextPoint? get _shrinkEnd {
    if (_unit == TextRangeUnit.paragraphs) {
      return _end.paragraph > _start.paragraph
          ? _paragraphEnd(_end.paragraph - 1)
          : null;
    }
    final previous = _wordEndBefore(_end);
    return previous != null &&
            _before(_start, previous) &&
            _hasWordBefore(_start, previous)
        ? previous
        : null;
  }

  bool get canGrowStart => _growStart != null;
  bool get canShrinkStart => _shrinkStart != null;
  bool get canGrowEnd => _growEnd != null;
  bool get canShrinkEnd => _shrinkEnd != null;
  bool get canMoveEarlier => canGrowStart && (canShrinkEnd || _isOneUnit);
  bool get canMoveLater => canGrowEnd && (canShrinkStart || _isOneUnit);

  void growStart() => _start = _growStart ?? _start;
  void shrinkStart() => _start = _shrinkStart ?? _start;
  void growEnd() => _end = _growEnd ?? _end;
  void shrinkEnd() => _end = _shrinkEnd ?? _end;

  /// הזזת הטווח כולו במילה או בפסקה אחת אחורה, באותו אורך.
  void moveEarlier() {
    if (!canMoveEarlier) return;
    if (_isOneUnit) {
      final start = _growStart!;
      _start = start;
      _end = _unit == TextRangeUnit.paragraphs
          ? _paragraphEnd(start.paragraph)
          : _wordEndOf(start);
      return;
    }
    growStart();
    shrinkEnd();
  }

  /// הזזת הטווח כולו במילה או בפסקה אחת קדימה, באותו אורך.
  void moveLater() {
    if (!canMoveLater) return;
    if (_isOneUnit) {
      final end = _growEnd!;
      _end = end;
      _start = _unit == TextRangeUnit.paragraphs
          ? _paragraphStart(end.paragraph)
          : _wordStartOf(end);
      return;
    }
    growEnd();
    shrinkStart();
  }

  /// מעבר לפסקה [index]: כולה, או כל המילים שבה.
  void goToParagraph(int index) {
    final target = index.clamp(0, paragraphCount - 1);
    _start = _paragraphStart(target);
    _end = _paragraphEnd(target);
    _normalize();
  }

  /// המילה הראשונה והאחרונה בטווח, כשהוא בפסקה אחת.
  ({int first, int last}) get wordSpan {
    final words = wordsOf(_start.paragraph);
    final from = words.indexWhere((w) => w.end > _start.offset);
    final to = words.lastIndexWhere((w) => w.start < _end.offset);
    return (
      first: from < 0 ? 0 : from,
      last: to < from ? words.length - 1 : to,
    );
  }

  void setWordSpan(int from, int to) {
    final words = wordsOf(_start.paragraph);
    if (words.isEmpty) return;
    final a = from.clamp(0, words.length - 1);
    final b = to.clamp(a, words.length - 1);
    _start = (paragraph: _start.paragraph, offset: words[a].start);
    _end = (paragraph: _start.paragraph, offset: words[b].end);
  }

  /// המילה שהטווח מתחיל בה ([atStart]) או מסתיים בה.
  String edgeWord({required bool atStart}) {
    if (atStart) {
      final words = wordsOf(_start.paragraph);
      final word = words.where((w) => w.end > _start.offset).firstOrNull;
      return word == null
          ? ''
          : paragraph(_start.paragraph).substring(word.start, word.end);
    }
    final words = wordsOf(_end.paragraph);
    final word = words.where((w) => w.start < _end.offset).lastOrNull;
    return word == null
        ? ''
        : paragraph(_end.paragraph).substring(word.start, word.end);
  }

  bool get _isOneUnit => _unit == TextRangeUnit.paragraphs
      ? isSingleParagraph
      : isSingleParagraph && wordSpan.first == wordSpan.last;

  TextPoint _paragraphStart(int index) => _unit == TextRangeUnit.paragraphs
      ? (paragraph: index, offset: 0)
      : (paragraph: index, offset: wordsOf(index).firstOrNull?.start ?? 0);

  TextPoint _paragraphEnd(int index) => _unit == TextRangeUnit.paragraphs
      ? (paragraph: index, offset: paragraph(index).length)
      : (paragraph: index, offset: wordsOf(index).lastOrNull?.end ?? 0);

  /// ביחידת פסקאות הטווח מכסה פסקאות שלמות; טווח הפוך או ריק מתכווץ לפסקה.
  void _normalize() {
    final first = _start.paragraph.clamp(0, paragraphCount - 1);
    var last = _end.paragraph.clamp(first, paragraphCount - 1);
    if (!crossParagraphs && _unit == TextRangeUnit.words) last = first;
    if (_unit == TextRangeUnit.paragraphs) {
      _start = (paragraph: first, offset: 0);
      _end = (paragraph: last, offset: paragraph(last).length);
      return;
    }
    final startOffset = _start.offset.clamp(0, paragraph(first).length);
    final endOffset = (_end.paragraph == last ? _end.offset : 1 << 30).clamp(
      0,
      paragraph(last).length,
    );
    _start = (paragraph: first, offset: startOffset);
    _end = (paragraph: last, offset: endOffset);
    if (!_before(_start, _end) || !_hasWordBefore(_start, _end)) {
      _start = _paragraphStart(first);
      _end = _paragraphEnd(first);
    }
  }

  static bool _before(TextPoint a, TextPoint b) =>
      a.paragraph < b.paragraph ||
      (a.paragraph == b.paragraph && a.offset < b.offset);

  /// יש מילה שמתחילה לפני [to] ונגמרת אחרי [from].
  bool _hasWordBefore(TextPoint from, TextPoint to) {
    for (var p = from.paragraph; p <= to.paragraph; p++) {
      for (final word in wordsOf(p)) {
        final afterFrom = p > from.paragraph || word.end > from.offset;
        final beforeTo = p < to.paragraph || word.start < to.offset;
        if (afterFrom && beforeTo) return true;
      }
    }
    return false;
  }

  TextPoint? _wordBefore(TextPoint at) {
    final here = wordsOf(at.paragraph).where((w) => w.start < at.offset);
    if (here.isNotEmpty) {
      return (paragraph: at.paragraph, offset: here.last.start);
    }
    if (!crossParagraphs) return null;
    for (var p = at.paragraph - 1; p >= 0; p--) {
      final words = wordsOf(p);
      if (words.isNotEmpty) return (paragraph: p, offset: words.last.start);
    }
    return null;
  }

  TextPoint? _wordStartAfter(TextPoint at) {
    final here = wordsOf(at.paragraph).where((w) => w.start > at.offset);
    if (here.isNotEmpty) {
      return (paragraph: at.paragraph, offset: here.first.start);
    }
    if (!crossParagraphs) return null;
    for (var p = at.paragraph + 1; p < paragraphCount; p++) {
      final words = wordsOf(p);
      if (words.isNotEmpty) return (paragraph: p, offset: words.first.start);
    }
    return null;
  }

  TextPoint? _wordAfter(TextPoint at) {
    final here = wordsOf(at.paragraph).where((w) => w.end > at.offset);
    if (here.isNotEmpty) {
      return (paragraph: at.paragraph, offset: here.first.end);
    }
    if (!crossParagraphs) return null;
    for (var p = at.paragraph + 1; p < paragraphCount; p++) {
      final words = wordsOf(p);
      if (words.isNotEmpty) return (paragraph: p, offset: words.first.end);
    }
    return null;
  }

  TextPoint? _wordEndBefore(TextPoint at) {
    final here = wordsOf(at.paragraph).where((w) => w.end < at.offset);
    if (here.isNotEmpty) {
      return (paragraph: at.paragraph, offset: here.last.end);
    }
    if (!crossParagraphs) return null;
    for (var p = at.paragraph - 1; p >= 0; p--) {
      final words = wordsOf(p);
      if (words.isNotEmpty) return (paragraph: p, offset: words.last.end);
    }
    return null;
  }

  TextPoint _wordEndOf(TextPoint wordStart) {
    final word = wordsOf(
      wordStart.paragraph,
    ).firstWhere((w) => w.start == wordStart.offset);
    return (paragraph: wordStart.paragraph, offset: word.end);
  }

  TextPoint _wordStartOf(TextPoint wordEnd) {
    final word = wordsOf(
      wordEnd.paragraph,
    ).lastWhere((w) => w.end == wordEnd.offset);
    return (paragraph: wordEnd.paragraph, offset: word.start);
  }
}
