import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show UserRegexMatcher;

const int _maxSearchResults = 1000;
const int _searchChunkSize = 128;

// הקשר קצר מגבול תצוגת ה-snippet במסך (220 תווים), כדי שהתצוגה לא תחתוך
// שוב סביב ההופעה הראשונה ותעלים הופעות מאוחרות באותה שורה.
const int _snippetContextChars = 90;

/// חלון טקסט סביב [match] בגבולות מילים, תחום ב-[lowerBound]..[upperBound]
/// (חצי הדרך להופעות השכנות) — כך שכל תוצאה מציגה ומדגישה רק את ההופעה שלה.
String _snippetAroundMatch(
  String line,
  ({int start, int end}) match, {
  required int lowerBound,
  required int upperBound,
}) {
  // גבול שמותיר ליד ההופעה רק שבר מילה קוטם את התוצאה ל"אחכם!" — צד כזה
  // מקבל את ההקשר המלא גם אם הוא חופף לשכנה (issue #1229).
  if (!_hasNeighborWord(
    line,
    start: lowerBound,
    end: match.start,
  )) {
    lowerBound = 0;
  }
  if (!_hasNeighborWord(
    line,
    start: match.end,
    end: upperBound,
    before: false,
  )) {
    upperBound = line.length;
  }
  var start = match.start - _snippetContextChars;
  var end = match.end + _snippetContextChars;
  if (start <= lowerBound) {
    start = lowerBound;
  } else {
    final space = line.lastIndexOf(' ', start);
    start = space < lowerBound ? lowerBound : space + 1;
  }
  if (end >= upperBound) {
    end = upperBound;
  } else {
    final space = line.indexOf(' ', end);
    end = space == -1 || space > upperBound ? upperBound : space;
  }
  return line.substring(start, end).trim();
}

/// האם בקטע שבין הגבול להופעה יש מילה שלמה, ולא רק חלק ממילה שנחתך בגבול.
bool _hasNeighborWord(
  String line, {
  required int start,
  required int end,
  bool before = true,
}) {
  final side = line.substring(start, end);
  final trimmed = side.trim();
  if (trimmed.isEmpty) return false;

  if (before) {
    if (!side.endsWith(' ')) return false;
    return start == 0 || line[start - 1] == ' ' || trimmed.contains(' ');
  }

  if (!side.startsWith(' ')) return false;
  return end == line.length || line[end] == ' ' || trimmed.contains(' ');
}

final RegExp _whitespaceRun = RegExp(r'\s+');

/// ניקוי שורה לחיפוש: הסרת הערות/HTML/ניקוד ואז כיווץ רצפי רווח לרווח יחיד.
/// הכיווץ חיוני — הסרת תגים ("x </b> y") והמרת מקף/פסק לרווח ב-removeVolwels
/// מייצרות רווח כפול, והחיפוש הליטרלי לא מוצא שאילתה עם רווח בודד.
String cleanLineForSearch(String rawLine) => utils
    .collapseWhitespace(
      utils.removeVolwels(
        utils.stripHtmlForSearch(notes.stripInlineNotesForSearch(rawLine)),
      ),
    )
    .trim();

String _normalizeQueryWhitespace(String query) =>
    query.replaceAll(_whitespaceRun, ' ');

void _updateAddress(List<String> address, String line) {
  if (line.length < 4) {
    address.add(line);
    return;
  }

  final index = address.indexWhere(
    (e) => e.length >= 4 && e.substring(0, 4) == line.substring(0, 4),
  );

  if (index != -1) {
    address.removeRange(index, address.length);
  }
  address.add(line);
}

/// ביטוי עובר לשורה הבאה רק במפריד שבין מילים, ולכן מילה אחת אינה נמשכת.
@visibleForTesting
bool queryCanCrossLines(String query) {
  final normalized = normalizeLiteralQuery(query);
  // Rust split_whitespace מזהה גם NEL, ש-\s של Dart משאיר בשאילתה.
  return normalized.contains(' ') || normalized.contains('\u0085');
}

bool _isHeadingLine(String rawLine) => rawLine.trimLeft().startsWith('<h');

/// [source] עם חלופת `\n` ל-[crossLineMatch]: הסריקה נעצרת במעבר השורה במקום
/// לעבור על כל השורה הבאה, והתאמות שמתחילות לפניו אינן משתנות.
@visibleForTesting
RegExp crossLinePattern(String source) =>
    compileLiteralPattern('(?:$source)|\\n');

/// התאמה של [pattern] שמתחילה בסוף השורה הנקייה [line] ונמשכת בתחילת
/// [nextLine], בלי סימון ממוספר בקצוות — אותו כלל כמו במנוע. כותרת או שורה
/// ריקה עוצרות ביטוי. מחזירה את ההיסט בשורה ואת קטע שתי השורות.
@visibleForTesting
({int offset, String snippet})? crossLineMatch(
  RegExp pattern, {
  required String rawLine,
  required String rawNextLine,
  required String line,
  required String nextLine,
}) => _crossLineMatchWith(
  (joined) => pattern.allMatches(joined).map((m) => (m.start, m.end)),
  rawLine: rawLine,
  rawNextLine: rawNextLine,
  line: line,
  nextLine: nextLine,
);

({int offset, String snippet})? _crossLineMatchWith(
  Iterable<(int, int)> Function(String joined) find, {
  required String rawLine,
  required String rawNextLine,
  required String line,
  required String nextLine,
}) {
  if (line.isEmpty ||
      nextLine.isEmpty ||
      _isHeadingLine(rawLine) ||
      _isHeadingLine(rawNextLine)) {
    return null;
  }
  final lineEnd = utils.crossLineContentRange(line).end;
  final nextStart = utils.crossLineContentRange(nextLine).start;
  final joined =
      '${line.substring(0, lineEnd)}\n${nextLine.substring(nextStart)}';
  for (final (matchStart, matchEnd) in find(joined)) {
    if (matchStart >= lineEnd) break;
    if (matchEnd <= lineEnd + 1) continue;
    var start = matchStart - _snippetContextChars;
    var end = matchEnd + _snippetContextChars;
    start = start <= 0 ? 0 : joined.lastIndexOf(' ', start) + 1;
    if (end >= joined.length) {
      end = joined.length;
    } else {
      final space = joined.indexOf(' ', end);
      end = space == -1 ? joined.length : space;
    }
    return (offset: matchStart, snippet: joined.substring(start, end).trim());
  }
  return null;
}

/// מיקום יחסי (0..1) של ההתאמה ל-[query] בשורת המקור [rawLine], לאחר ניקוי
/// זהה לחיפוש. משמש לדיוק גלילה אל המילה בתוך פסקה ארוכה. 0 אם אין התאמה.
/// [matchOffset] — היסט הופעה ספציפית בשורה הנקייה (ראה
/// TextSearchResult.matchOffset); בלעדיו נלקחת ההופעה הראשונה.
/// שאר הפרמטרים הם פרמטרי ההדגשה של הספר, כך שההופעה נמצאת באותה תבנית שמודגשת.
/// [pattern] מוזרק בבדיקות בלבד — בייצור נבנה מהמנוע.
double matchFractionInLine(
  String rawLine,
  String query, {
  int? matchOffset,
  bool wholeWord = true,
  Map<String, Map<String, bool>> searchOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  bool isFuzzy = false,
  int searchDistance = 0,
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  @visibleForTesting RegExp? pattern,
}) {
  final clean = cleanLineForSearch(rawLine);
  if (clean.isEmpty) return 0;
  int offset;
  if (matchOffset != null) {
    offset = matchOffset;
  } else if (pattern != null) {
    offset = pattern.firstMatch(clean)?.start ?? -1;
  } else {
    final ranges = utils.computeHighlightRanges(
      clean,
      query,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      isFuzzy: isFuzzy,
      searchDistance: searchDistance,
      matchPolicy: matchPolicy,
      isSearchResultLine: true,
      partialWordMatch: literalPartialWordMatch(query, wholeWord: wholeWord),
    );
    offset = ranges.isEmpty ? -1 : ranges.first.first;
  }
  if (offset <= 0) return 0;
  return (offset / clean.length).clamp(0.0, 1.0);
}

/// הדגשת רג'קס מעוגן בקטעי תוצאה, עם עיבוד משותף לשורה אחת בלבד.
class UserRegexSnippetHighlighter {
  ({
    (String, String, utils.HolyNameStyle?) key,
    String line,
    String shown,
    List<List<int>> ranges,
    List<({int start, int end, int delta})>? names,
  })?
  _cachedLine;

  /// null כשאין עוגני שורה או שהקטע אינו בשורה. [holyNameStyle] null משאיר שמות ככתבם.
  List<List<int>>? rangesFor({
    required String line,
    required String snippet,
    required int matchOffset,
    required String query,
    utils.HolyNameStyle? holyNameStyle,
  }) {
    final pattern = UserRegexQuery.plan(query)?.pattern;
    if (pattern == null ||
        (!pattern.contains(r'\A') && !pattern.contains(r'\z'))) {
      _cachedLine = null;
      return null;
    }
    String show(String text) => SnippetBuilder.htmlToPlainText(
      holyNameStyle == null
          ? text
          : utils.replaceHolyNames(text, style: holyNameStyle),
    );
    final key = (line, query, holyNameStyle);
    var cached = _cachedLine;
    if (cached == null || cached.key != key) {
      final clean = cleanLineForSearch(line);
      final renamed = holyNameStyle == null
          ? clean
          : utils.replaceHolyNames(clean, style: holyNameStyle);
      final full = SnippetBuilder.htmlToPlainText(renamed);
      _cachedLine = cached = (
        key: key,
        line: clean,
        shown: full,
        // פענוח HTML עשוי לשנות גם אורכים מחוץ לשמות הקודש.
        names: full != renamed
            ? null
            : holyNameStyle == null
            ? const <({int start, int end, int delta})>[]
            : [
                for (final name in utils.findReplaceableHolyNames(clean))
                  (
                    start: name.start,
                    end: name.end,
                    delta:
                        utils
                            .replaceHolyNames(name[0]!, style: holyNameStyle)
                            .length -
                        (name.end - name.start),
                  ),
              ],
        ranges: utils.computeHighlightRanges(
          full,
          query,
          isSearchResultLine: true,
        ),
      );
    }
    final start = cached.line.lastIndexOf(
      snippet,
      matchOffset.clamp(0, cached.line.length),
    );
    if (start < 0) return null;
    final shown = show(snippet);
    final names = cached.names;
    var prefix = start;
    if (names == null) {
      prefix = start == 0 ? 0 : show(cached.line.substring(0, start)).length;
    } else {
      for (final name in names) {
        if (name.start >= start) break;
        if (name.end > start) {
          prefix = show(cached.line.substring(0, start)).length;
          break;
        }
        prefix += name.delta;
      }
    }
    final at = names != null && cached.shown.startsWith(shown, prefix)
        ? prefix
        : cached.shown.indexOf(shown, prefix == 0 ? 0 : prefix - 1);
    if (at < 0) return null;
    return [
      for (final range in cached.ranges)
        if (range[0] >= at && range[1] <= at + shown.length)
          [range[0] - at, range[1] - at],
    ];
  }
}

/// מיקום יחסי (0..1) בשורה [rawLine] של הסמן בסוגריים שנפתח בכותרת [title]
/// (`[דף ו טור א]` לכותרת "דף ו"), כמו [matchFractionInLine]. 0 כשאין סמן.
double bracketMarkerFractionInLine(String rawLine, String title) {
  final key = title.trim();
  final clean = cleanLineForSearch(rawLine);
  if (key.isEmpty || clean.isEmpty) return 0;
  final offset =
      RegExp('\\[${RegExp.escape(key)}[\\] ]').firstMatch(clean)?.start ?? 0;
  return (offset / clean.length).clamp(0.0, 1.0);
}

/// מיקום יחסי (0..1) של המילים שעליהן נכתבה [note] בשורת המקור [rawLine],
/// במרחב הנקי של [matchFractionInLine]. 0 להערת שורה שלמה או לעוגן שלא נמצא.
double noteAnchorFractionInLine(String rawLine, PersonalNote? note) {
  if (note == null || !note.isWordAnchored) return 0;
  final range = locateAnchor(
    rawLine: rawLine,
    anchorText: note.anchorText!,
    prefix: note.anchorPrefix,
    suffix: note.anchorSuffix,
    hintStart: note.anchorStart,
  );
  final clean = cleanLineForSearch(rawLine);
  if (range == null || range.start <= 0 || clean.isEmpty) return 0;
  final before = cleanLineForSearch(rawLine.substring(0, range.start));
  return (before.length / clean.length).clamp(0.0, 1.0);
}

/// שבר המיקום של ההופעה בשורה כשטקסט השורה עצמו אינו זמין — למשל אחרי ששוחרר
/// עותק שורות הספר. מחזיר 0 כשאין נתונים, ואז הגלילה מתייחסת לתחילת הקטע.
double matchFractionFromLineLength({int? matchOffset, int? lineLength}) {
  if (matchOffset == null || lineLength == null) return 0;
  if (matchOffset <= 0 || lineLength <= 0) return 0;
  return (matchOffset / lineLength).clamp(0.0, 1.0);
}

/// האם תוצאת החיפוש [query] נחתה בגוף הערת שוליים של [rawLine] בלבד —
/// המונח נמצא בהערה אך לא בטקסט הראשי. משמש לפתיחת חלונית ההערות בפתיחת
/// תוצאה, כשהספר לבדו אינו מציג את ההתאמה (גוף ההערה מוסר מהטקסט הראשי).
/// שאילתה שרצה במנוע נבדקת בפרמטרי ההדגשה של הספר, כמו [matchFractionInLine].
/// [pattern] מוזרק בבדיקות בלבד — בייצור נבנה מהמנוע.
bool queryMatchesInlineNoteOnly(
  String rawLine,
  String query, {
  bool wholeWord = true,
  List<BookNote> dbNotes = const [],
  Map<String, Map<String, bool>> searchOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  bool isFuzzy = false,
  int searchDistance = 0,
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  @visibleForTesting RegExp? pattern,
}) {
  if (!rawLine.contains('footnote') && dbNotes.isEmpty) return false;
  final literal =
      pattern != null ||
      InBookSearchRouting.canRunAsSimpleSearch(
        searchMode: isFuzzy ? SearchMode.fuzzy : SearchMode.exact,
        distance: searchDistance,
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        matchPolicy: matchPolicy,
      );
  final regExp = literal
      ? pattern ?? buildLiteralPattern(query, wholeWord: wholeWord)?.regExp
      : null;
  if (literal && regExp == null) return false;
  bool matches(String clean) =>
      regExp?.hasMatch(clean) ??
      utils
          .computeHighlightRanges(
            clean,
            query,
            searchOptions: searchOptions,
            alternativeWords: alternativeWords,
            spacingValues: spacingValues,
            isFuzzy: isFuzzy,
            searchDistance: searchDistance,
            matchPolicy: matchPolicy,
            isSearchResultLine: true,
          )
          .isNotEmpty;

  final noteBody = [
    ...notes.notesForLines([rawLine], const [0]),
    ...dbNotes.map(BookNotes.toInlineHtml),
  ].join(' ');
  final cleanNote = utils
      .removeVolwels(utils.stripHtmlForSearch(noteBody))
      .replaceAll(_whitespaceRun, ' ');
  if (!matches(cleanNote)) return false;

  final cleanMain = utils
      .removeVolwels(utils.stripHtmlForSearch(notes.stripInlineNotes(rawLine)))
      .replaceAll(_whitespaceRun, ' ');
  return !matches(cleanMain);
}

class _SearchWorkerHost {
  _SearchWorkerHost._();

  static final _SearchWorkerHost instance = _SearchWorkerHost._();

  ReceivePort? _receivePort;
  SendPort? _workerSendPort;
  Isolate? _isolate;
  Future<void>? _startFuture;
  Completer<void>? _startCompleter;
  int _nextRequestId = 0;
  final Map<int, Completer<({List<TextSearchResult> results, bool truncated})>>
  _pending = {};

  // מעקב אחר התוכן האחרון שנשלח ל-worker. כל עוד מדובר באותו אובייקט תוכן
  // (אותו ספר פתוח) שולחים רק את השאילתה — לא את הספר כולו — וה-worker
  // משתמש ב-cache שלו לפי המזהה.
  List<String>? _lastSentContent;
  int _lastContentId = 0;

  Future<({List<TextSearchResult> results, bool truncated})> search({
    required List<String> content,
    required String query,
    required String patternSource,
    ({int start, int? end})? range,
  }) async {
    await _ensureStarted();

    final requestId = ++_nextRequestId;
    final completer =
        Completer<({List<TextSearchResult> results, bool truncated})>();
    _pending[requestId] = completer;

    final bool contentChanged = !identical(content, _lastSentContent);
    if (contentChanged) {
      _lastSentContent = content;
      _lastContentId++;
    }

    final message = <String, dynamic>{
      'type': 'search',
      'requestId': requestId,
      'contentId': _lastContentId,
      'query': query,
      'patternSource': patternSource,
      'rangeStart': range?.start,
      'rangeEnd': range?.end,
    };
    if (contentChanged) {
      message['content'] = content;
    }

    _workerSendPort!.send(message);

    return completer.future;
  }

  Future<void> _ensureStarted() {
    if (_workerSendPort != null) {
      return Future.value();
    }

    final existingStart = _startFuture;
    if (existingStart != null) {
      return existingStart;
    }

    final completer = Completer<void>();
    _startCompleter = completer;
    _startFuture = completer.future;
    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage);

    Isolate.spawn<SendPort>(
          _searchWorkerMain,
          _receivePort!.sendPort,
        )
        .then((isolate) {
          _isolate = isolate;
        })
        .catchError((Object error, StackTrace stackTrace) {
          _startFuture = null;
          final startCompleter = _startCompleter;
          _startCompleter = null;
          _receivePort?.close();
          _receivePort = null;
          if (startCompleter != null && !startCompleter.isCompleted) {
            startCompleter.completeError(error, stackTrace);
          }
        });

    return completer.future;
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _workerSendPort = message;
      final startCompleter = _startCompleter;
      _startCompleter = null;
      _startFuture = null;
      if (startCompleter != null && !startCompleter.isCompleted) {
        startCompleter.complete();
      }
      return;
    }

    if (message is! Map) {
      return;
    }

    final requestId = message['requestId'] as int?;
    if (requestId == null) {
      return;
    }

    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return;
    }

    final type = message['type'] as String?;
    switch (type) {
      case 'result':
        final rawResults = message['results'] as List<dynamic>? ?? const [];
        completer.complete((
          results: rawResults
              .cast<Map<dynamic, dynamic>>()
              .map(
                (raw) => TextSearchResult(
                  index: raw['index'] as int,
                  snippet: raw['snippet'] as String,
                  address: raw['address'] as String,
                  query: raw['query'] as String,
                  matchOffset: raw['matchOffset'] as int?,
                  lineLength: raw['lineLength'] as int?,
                  continuesToNextLine:
                      raw['continuesToNextLine'] as bool? ?? false,
                ),
              )
              .toList(growable: false),
          truncated: message['truncated'] as bool? ?? false,
        ));
        break;
      case 'canceled':
        completer.complete((
          results: const <TextSearchResult>[],
          truncated: false,
        ));
        break;
      case 'error':
        completer.completeError(
          StateError(message['message'] as String? ?? 'Search worker failed'),
        );
        break;
    }
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete((
          results: const <TextSearchResult>[],
          truncated: false,
        ));
      }
    }
    _pending.clear();
    _receivePort?.close();
    _receivePort = null;
    _workerSendPort = null;
    _startFuture = null;
    _startCompleter = null;
    _nextRequestId = 0;
    _lastSentContent = null;
    _lastContentId = 0;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

void _searchWorkerMain(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);
  final runtime = SectionSearchWorkerRuntime(mainSendPort);
  commandPort.listen(runtime.onMessage);
}

@visibleForTesting
class SectionSearchWorkerRuntime {
  SectionSearchWorkerRuntime(
    this._mainSendPort, {
    this.cleanLine = cleanLineForSearch,
  });

  final String Function(String) cleanLine;

  final SendPort _mainSendPort;
  Map<String, dynamic>? _queuedRequest;
  bool _isProcessing = false;

  // מטמון של ספר אחד: null מסמן שורה שטרם נוקתה, גם מחרוזת ריקה נשמרת.
  // הניקוי אינו תלוי בשאילתה; החלפת מזהה התוכן מפנה את כל השורות.
  int? _cachedContentId;
  List<String>? _cachedRawContent;
  List<String?>? _cachedCleanLines;

  /// אינדקסי השורות שמעדכנות את כתובת התוצאה (כותרות מתחת ל-h1), בסדר עולה.
  List<int>? _cachedHeadingLines;

  void onMessage(dynamic message) {
    if (message is! Map) {
      return;
    }

    final type = message['type'];
    if (type != 'search') {
      return;
    }

    _queuedRequest = Map<String, dynamic>.from(message);
    if (!_isProcessing) {
      unawaited(_processLoop());
    }
  }

  Future<void> _processLoop() async {
    _isProcessing = true;
    try {
      while (_queuedRequest != null) {
        final request = _queuedRequest!;
        _queuedRequest = null;
        final requestId = request['requestId'] as int;

        try {
          final contentId = request['contentId'] as int?;
          final query = _normalizeQueryWhitespace(request['query'] as String);
          final patternSource = request['patternSource'] as String;
          final pattern = compileLiteralPattern(patternSource);
          final crossPattern = queryCanCrossLines(query)
              ? crossLinePattern(patternSource)
              : null;

          // ודא שה-cache תואם לתוכן המבוקש; אחרת בנה אותו פעם אחת.
          // בקשה ללא contentId (תאימות לאחור) נחשבת תמיד כתוכן חדש.
          final bool cacheValid =
              contentId != null &&
              contentId == _cachedContentId &&
              _cachedCleanLines != null;
          if (!cacheValid) {
            final rawContent = request.containsKey('content')
                ? (request['content'] as List<dynamic>).cast<String>()
                : _cachedRawContent;
            if (rawContent == null) {
              throw StateError('לא התקבל תוכן לחיפוש (contentId=$contentId)');
            }
            final built = await _buildCache(contentId, rawContent);
            if (!built) {
              // הבנייה הופסקה כי הגיעה בקשה לתוכן אחר — הבקשה הנוכחית מיושנת.
              // מדווחים ביטול וממשיכים אל הבקשה החדשה בלולאה.
              _mainSendPort.send({
                'type': 'canceled',
                'requestId': requestId,
              });
              continue;
            }
          }

          final cleanLines = _cachedCleanLines!;
          final sourceLines = _cachedRawContent!;
          String cleanLineAt(int i) =>
              cleanLines[i] ??= cleanLine(sourceLines[i]);
          final headingLines = _cachedHeadingLines!;
          var nextHeading = 0;

          final results = <Map<String, dynamic>>[];
          final address = <String>[];
          bool canceled = false;
          bool truncated = false;

          final rangeStart = request['rangeStart'] as int? ?? 0;
          final requestedEnd = request['rangeEnd'] as int?;
          final rangeEnd =
              requestedEnd == null || requestedEnd > cleanLines.length
              ? cleanLines.length
              : requestedEnd;

          // הכותרות שלפני הטווח עדיין בונות את כתובת התוצאות שבתוכו.
          while (nextHeading < headingLines.length &&
              headingLines[nextHeading] < rangeStart) {
            _updateAddress(address, sourceLines[headingLines[nextHeading++]]);
          }

          for (int i = rangeStart; i < rangeEnd; i++) {
            final line = cleanLineAt(i);
            if (results.length >= _maxSearchResults) {
              if (pattern
                  .allMatches(line)
                  .any((match) => match.end > match.start)) {
                truncated = true;
                break;
              }
              if ((i + 1) % _searchChunkSize == 0) {
                await Future<void>.delayed(Duration.zero);
                if (_queuedRequest != null) {
                  canceled = true;
                  break;
                }
              }
              continue;
            }

            final rawLine = sourceLines[i];

            if (nextHeading < headingLines.length &&
                headingLines[nextHeading] == i) {
              _updateAddress(address, rawLine);
              nextHeading++;
            }

            // תוצאה לכל הופעה בשורה — לא אחת לשורה — כדי ששתי הופעות
            // באותו קטע יופיעו שתיהן ברשימת התוצאות. המטריאליזציה מוגבלת
            // לקיבולת שנותרה, עם התאמה עודפת אחת שמשמשת רק כגבול ל-snippet.
            final remainingCapacity = _maxSearchResults - results.length;
            final lineMatches = pattern
                .allMatches(line)
                .where((m) => m.end > m.start)
                .take(remainingCapacity + 1)
                .toList(growable: false);
            String? cleanAddress;
            for (int m = 0; m < lineMatches.length; m++) {
              final match = lineMatches[m];
              cleanAddress ??= utils.removeVolwels(
                utils.stripHtmlIfNeeded(address.join(', ')),
              );
              results.add({
                'index': i,
                'snippet': _snippetAroundMatch(
                  line,
                  (start: match.start, end: match.end),
                  lowerBound: m > 0
                      ? (lineMatches[m - 1].end + match.start) ~/ 2
                      : 0,
                  upperBound: m < lineMatches.length - 1
                      ? (match.end + lineMatches[m + 1].start) ~/ 2
                      : line.length,
                ),
                'address': cleanAddress,
                'query': query,
                'matchOffset': match.start,
                'lineLength': line.length,
              });
              if (results.length >= _maxSearchResults) {
                truncated = m < lineMatches.length - 1;
                break;
              }
            }
            if (results.length >= _maxSearchResults) {
              if (truncated) break;
              continue;
            }

            // ביטוי שנמשך לשורה הבאה נספר פעם אחת, בשורה שבה הוא מתחיל.
            if (crossPattern != null && i + 1 < rangeEnd) {
              final crossing = crossLineMatch(
                crossPattern,
                rawLine: rawLine,
                rawNextLine: sourceLines[i + 1],
                line: line,
                nextLine: cleanLineAt(i + 1),
              );
              if (crossing != null) {
                cleanAddress ??= utils.removeVolwels(
                  utils.stripHtmlIfNeeded(address.join(', ')),
                );
                results.add({
                  'index': i,
                  'snippet': crossing.snippet,
                  'address': cleanAddress,
                  'query': query,
                  'matchOffset': crossing.offset,
                  'lineLength': line.length,
                  'continuesToNextLine': true,
                });
                if (results.length >= _maxSearchResults) continue;
              }
            }

            if ((i + 1) % _searchChunkSize == 0) {
              await Future<void>.delayed(Duration.zero);
              if (_queuedRequest != null) {
                canceled = true;
                break;
              }
            }
          }

          if (canceled) {
            _mainSendPort.send({
              'type': 'canceled',
              'requestId': requestId,
            });
            continue;
          }

          _mainSendPort.send({
            'type': 'result',
            'requestId': requestId,
            'results': results,
            'truncated': truncated,
          });
        } catch (error) {
          _mainSendPort.send({
            'type': 'error',
            'requestId': requestId,
            'message': error.toString(),
          });
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// אוסף כותרות מכל הספר לכתובות התוצאות; השורות ינוקו רק בתוך טווח החיפוש.
  /// תוכן אחר שמגיע בנקודת yield מבטל את הבנייה בלי לשמור מטמון חלקי.
  Future<bool> _buildCache(int? contentId, List<String> content) async {
    final clean = List<String?>.filled(content.length, null, growable: false);
    final headingLines = <int>[];
    for (int i = 0; i < content.length; i++) {
      final rawLine = content[i];
      if (rawLine.contains('<h') && !rawLine.startsWith('<h1')) {
        headingLines.add(i);
      }
      if ((i + 1) % _searchChunkSize == 0) {
        await Future<void>.delayed(Duration.zero);
        final next = _queuedRequest;
        if (next != null && next['contentId'] != contentId) {
          return false;
        }
      }
    }
    _cachedContentId = contentId;
    _cachedRawContent = content;
    _cachedCleanLines = clean;
    _cachedHeadingLines = headingLines;
    return true;
  }
}

/// [patternSource] מוזרק בבדיקות בלבד (הן אינן יכולות לקרוא למנוע);
/// בייצור התבנית נבנית מהמנוע ב-isolate הראשי ונשלחת ל-worker.
///
/// [onTruncated] נקרא עם `true` כשנמצאו התאמות נוספות אחרי תקרת התוצאות.
/// [range] מצמצם את הסריקה לשורות `[start, end)`; `end` null = עד סוף הספר.
Future<List<TextSearchResult>> searchInContent({
  required List<String> content,
  required String query,
  bool wholeWord = true,
  ({int start, int? end})? range,
  @visibleForTesting String? patternSource,
  ValueChanged<bool>? onTruncated,
}) async {
  if (content.isEmpty) return [];

  final source =
      patternSource ?? buildLiteralPattern(query, wholeWord: wholeWord)?.source;
  if (source == null) return [];

  final outcome = await _SearchWorkerHost.instance.search(
    content: content,
    query: query,
    patternSource: source,
    range: range,
  );
  onTruncated?.call(outcome.truncated);
  return outcome.results;
}

// לפי תוכן הספר: המטמון משתחרר יחד עם התוכן כשהטאב נסגר.
final _userRegexCleanLines = Expando<List<String?>>();

/// `/…/` בספר במתאם הנייטיבי של המנוע (ב-isolate הראשי, בהפסקות קצרות);
/// null כש-[isCurrent] מדווח שהחיפוש הוחלף.
Future<({List<TextSearchResult> results, bool truncated})?>
searchUserRegexInContent({
  required List<String> content,
  required String query,
  required UserRegexMatcher matcher,
  bool crossesLines = false,
  ({int start, int? end})? range,
  bool Function()? isCurrent,
}) async {
  final cleanLines = _userRegexCleanLines[content] ??= List<String?>.filled(
    content.length,
    null,
  );
  String clean(int i) => cleanLines[i] ??= cleanLineForSearch(content[i]);
  List<({int start, int end})> find(String text) => [
    for (final m in matcher.findMatches(data: text))
      if (m.end > m.start) (start: m.start, end: m.end),
  ];

  final results = <TextSearchResult>[];
  final address = <String>[];
  var truncated = false;
  final rangeStart = range?.start ?? 0;
  final requestedEnd = range?.end;
  final rangeEnd = requestedEnd == null || requestedEnd > content.length
      ? content.length
      : requestedEnd;

  for (var i = 0; i < rangeEnd && !truncated; i++) {
    if ((i + 1) % _searchChunkSize == 0) {
      await Future<void>.delayed(Duration.zero);
      if (isCurrent != null && !isCurrent()) return null;
    }
    final rawLine = content[i];
    if (rawLine.contains('<h') && !rawLine.startsWith('<h1')) {
      _updateAddress(address, rawLine);
    }
    if (i < rangeStart) continue;

    final line = clean(i);
    final matches = find(line);
    String cleanAddress() =>
        utils.removeVolwels(utils.stripHtmlIfNeeded(address.join(', ')));
    for (var m = 0; m < matches.length; m++) {
      if (results.length >= _maxSearchResults) {
        truncated = true;
        break;
      }
      final match = matches[m];
      results.add(
        TextSearchResult(
          index: i,
          snippet: _snippetAroundMatch(
            line,
            match,
            lowerBound: m > 0 ? (matches[m - 1].end + match.start) ~/ 2 : 0,
            upperBound: m < matches.length - 1
                ? (match.end + matches[m + 1].start) ~/ 2
                : line.length,
          ),
          address: cleanAddress(),
          query: query,
          matchOffset: match.start,
          lineLength: line.length,
        ),
      );
    }
    if (truncated || !crossesLines || i + 1 >= rangeEnd) continue;
    final crossing = _crossLineMatchWith(
      (joined) => find(joined).map((m) => (m.start, m.end)),
      rawLine: rawLine,
      rawNextLine: content[i + 1],
      line: line,
      nextLine: clean(i + 1),
    );
    if (crossing == null) continue;
    if (results.length >= _maxSearchResults) {
      truncated = true;
      break;
    }
    results.add(
      TextSearchResult(
        index: i,
        snippet: crossing.snippet,
        address: cleanAddress(),
        query: query,
        matchOffset: crossing.offset,
        lineLength: line.length,
        continuesToNextLine: true,
      ),
    );
  }
  return (results: results, truncated: truncated);
}

@visibleForTesting
Future<void> resetSectionSearchWorkerForTesting() {
  return _SearchWorkerHost.instance.resetForTesting();
}
