import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/search/models/search_match_policy.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

const int _maxSearchResults = 1000;
const int _searchChunkSize = 128;

// הקשר קצר מגבול תצוגת ה-snippet במסך (220 תווים), כדי שהתצוגה לא תחתוך
// שוב סביב ההופעה הראשונה ותעלים הופעות מאוחרות באותה שורה.
const int _snippetContextChars = 90;

/// חלון טקסט סביב [match] בגבולות מילים, תחום ב-[lowerBound]..[upperBound]
/// (חצי הדרך להופעות השכנות) — כך שכל תוצאה מציגה ומדגישה רק את ההופעה שלה.
String _snippetAroundMatch(
  String line,
  Match match, {
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
String cleanLineForSearch(String rawLine) => _collapseWhitespace(
  utils.removeVolwels(
    utils.stripHtmlIfNeeded(notes.stripInlineNotesForSearch(rawLine)),
  ),
).trim();

/// כמו `replaceAll(_whitespaceRun, ' ')` בלי regex, ובלי העתקה כשאין מה
/// לכווץ — רץ על כל שורות הספר בחיפוש הראשון.
String _collapseWhitespace(String s) {
  StringBuffer? out;
  var copied = 0;
  for (var i = 0; i < s.length; i++) {
    if (!_isRegExpSpace(s.codeUnitAt(i))) continue;
    var end = i + 1;
    while (end < s.length && _isRegExpSpace(s.codeUnitAt(end))) {
      end++;
    }
    if (end - i > 1 || s.codeUnitAt(i) != 0x20) {
      (out ??= StringBuffer())
        ..write(s.substring(copied, i))
        ..write(' ');
      copied = end;
    }
    i = end - 1;
  }
  if (out == null) return s;
  out.write(s.substring(copied));
  return out.toString();
}

/// התווים ש-`\s` של RegExp מתאים להם.
bool _isRegExpSpace(int c) => c <= 0x20
    ? c == 0x20 || (c >= 0x09 && c <= 0x0D)
    : c == 0xA0 ||
          (c >= 0x1680 &&
              (c == 0x1680 ||
                  (c >= 0x2000 && c <= 0x200A) ||
                  c == 0x2028 ||
                  c == 0x2029 ||
                  c == 0x202F ||
                  c == 0x205F ||
                  c == 0x3000 ||
                  c == 0xFEFF));

String _normalizeQueryWhitespace(String query) =>
    query.replaceAll(_whitespaceRun, ' ').trim();

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

bool _isHeadingLine(String rawLine) => rawLine.trimLeft().startsWith('<h');

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
  for (final match in pattern.allMatches(joined)) {
    if (match.start >= lineEnd) break;
    if (match.end <= lineEnd + 1) continue;
    var start = match.start - _snippetContextChars;
    var end = match.end + _snippetContextChars;
    start = start <= 0 ? 0 : joined.lastIndexOf(' ', start) + 1;
    if (end >= joined.length) {
      end = joined.length;
    } else {
      final space = joined.indexOf(' ', end);
      end = space == -1 ? joined.length : space;
    }
    return (offset: match.start, snippet: joined.substring(start, end).trim());
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
      partialWordMatch: !wholeWord,
    );
    offset = ranges.isEmpty ? -1 : ranges.first.first;
  }
  if (offset <= 0) return 0;
  return (offset / clean.length).clamp(0.0, 1.0);
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
/// [pattern] מוזרק בבדיקות בלבד — בייצור נבנה מהמנוע.
bool queryMatchesInlineNoteOnly(
  String rawLine,
  String query, {
  bool wholeWord = true,
  @visibleForTesting RegExp? pattern,
}) {
  if (!rawLine.contains('footnote')) return false;
  final regExp =
      pattern ?? buildLiteralPattern(query, wholeWord: wholeWord)?.regExp;
  if (regExp == null) return false;

  final noteBody = notes.notesForLines([rawLine], const [0]).join(' ');
  final cleanNote = utils
      .removeVolwels(utils.stripHtmlIfNeeded(noteBody))
      .replaceAll(_whitespaceRun, ' ');
  if (!regExp.hasMatch(cleanNote)) return false;

  final cleanMain = utils
      .removeVolwels(utils.stripHtmlIfNeeded(notes.stripInlineNotes(rawLine)))
      .replaceAll(_whitespaceRun, ' ');
  return !regExp.hasMatch(cleanMain);
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
  SectionSearchWorkerRuntime(this._mainSendPort);

  final SendPort _mainSendPort;
  Map<String, dynamic>? _queuedRequest;
  bool _isProcessing = false;

  // Cache של ספר אחד (LRU=1): התוכן הגולמי והשורות לאחר ניקוי. הניקוי
  // (הסרת ניקוד/HTML/הערות) אינו תלוי בשאילתה, ולכן מחושב פעם אחת לכל ספר
  // ולא מחדש בכל הקלדה. מתחלף כשמגיע תוכן עם מזהה שונה.
  int? _cachedContentId;
  List<String>? _cachedRawContent;
  List<String>? _cachedCleanLines;

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
          final pattern = compileLiteralPattern(
            request['patternSource'] as String,
          );

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

          for (int i = 0; i < rangeEnd; i++) {
            if (i < rangeStart) {
              // הכותרות שלפני הטווח עדיין בונות את כתובת התוצאות שבתוכו.
              final rawLine = sourceLines[i];
              if (rawLine.contains('<h') && !rawLine.startsWith('<h1')) {
                _updateAddress(address, rawLine);
              }
              continue;
            }
            if (results.length >= _maxSearchResults) {
              if (pattern
                  .allMatches(cleanLines[i])
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

            if (rawLine.contains('<h') && !rawLine.startsWith('<h1')) {
              _updateAddress(address, rawLine);
            }

            // תוצאה לכל הופעה בשורה — לא אחת לשורה — כדי ששתי הופעות
            // באותו קטע יופיעו שתיהן ברשימת התוצאות. המטריאליזציה מוגבלת
            // לקיבולת שנותרה, עם התאמה עודפת אחת שמשמשת רק כגבול ל-snippet.
            final remainingCapacity = _maxSearchResults - results.length;
            final lineMatches = pattern
                .allMatches(cleanLines[i])
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
                  cleanLines[i],
                  match,
                  lowerBound: m > 0
                      ? (lineMatches[m - 1].end + match.start) ~/ 2
                      : 0,
                  upperBound: m < lineMatches.length - 1
                      ? (match.end + lineMatches[m + 1].start) ~/ 2
                      : cleanLines[i].length,
                ),
                'address': cleanAddress,
                'query': query,
                'matchOffset': match.start,
                'lineLength': cleanLines[i].length,
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
            if (i + 1 < rangeEnd) {
              final crossing = crossLineMatch(
                pattern,
                rawLine: rawLine,
                rawNextLine: sourceLines[i + 1],
                line: cleanLines[i],
                nextLine: cleanLines[i + 1],
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
                  'lineLength': cleanLines[i].length,
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

  /// מנקה את כל שורות הספר פעם אחת ושומר ב-cache. הניקוי כבד ואינו תלוי
  /// בשאילתה, ולכן מבוצע רק כשמתחלף הספר. ה-yield התקופתי מונע חסימה ארוכה
  /// של ה-isolate ומאפשר לקלוט בקשות חדשות בזמן הבנייה.
  /// מחזיר `false` אם הבנייה הופסקה באמצע כי בינתיים הגיעה בקשה לתוכן אחר
  /// (contentId שונה); במקרה כזה לא נשמר cache חלקי. שינוי שאילתה בלבד על
  /// אותו ספר אינו מפסיק את הבנייה — היא עדיין שימושית לשאילתה החדשה.
  Future<bool> _buildCache(int? contentId, List<String> content) async {
    final clean = List<String>.filled(content.length, '', growable: false);
    for (int i = 0; i < content.length; i++) {
      clean[i] = cleanLineForSearch(content[i]);
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

@visibleForTesting
Future<void> resetSectionSearchWorkerForTesting() {
  return _SearchWorkerHost.instance.resetForTesting();
}
