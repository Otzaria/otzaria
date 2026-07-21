import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
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

final RegExp _whitespaceRun = RegExp(r'\s+');

/// ניקוי שורה לחיפוש: הסרת הערות/HTML/ניקוד ואז כיווץ רצפי רווח לרווח יחיד.
/// הכיווץ חיוני — הסרת תגים ("x </b> y") והמרת מקף/פסק לרווח ב-removeVolwels
/// מייצרות רווח כפול, והחיפוש הליטרלי לא מוצא שאילתה עם רווח בודד.
String cleanLineForSearch(String rawLine) => utils
    .removeVolwels(
        utils.stripHtmlIfNeeded(notes.stripInlineNotesForSearch(rawLine)))
    .replaceAll(_whitespaceRun, ' ')
    .trim();

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

/// מיקום יחסי (0..1) של ההתאמה ל-[query] בשורת המקור [rawLine], לאחר ניקוי
/// זהה לחיפוש. משמש לדיוק גלילה אל המילה בתוך פסקה ארוכה. 0 אם אין התאמה.
/// [matchOffset] — היסט הופעה ספציפית בשורה הנקייה (ראה
/// TextSearchResult.matchOffset); בלעדיו נלקחת ההופעה הראשונה.
/// [pattern] מוזרק בבדיקות בלבד — בייצור נבנה מהמנוע.
double matchFractionInLine(
  String rawLine,
  String query, {
  int? matchOffset,
  @visibleForTesting RegExp? pattern,
}) {
  final clean = cleanLineForSearch(rawLine);
  if (clean.isEmpty) return 0;
  int offset;
  if (matchOffset != null) {
    offset = matchOffset;
  } else {
    final regExp = pattern ?? buildLiteralPattern(query)?.regExp;
    if (regExp == null) return 0;
    offset = regExp.firstMatch(clean)?.start ?? -1;
  }
  if (offset <= 0) return 0;
  return (offset / clean.length).clamp(0.0, 1.0);
}

/// האם תוצאת החיפוש [query] נחתה בגוף הערת שוליים של [rawLine] בלבד —
/// המונח נמצא בהערה אך לא בטקסט הראשי. משמש לפתיחת חלונית ההערות בפתיחת
/// תוצאה, כשהספר לבדו אינו מציג את ההתאמה (גוף ההערה מוסר מהטקסט הראשי).
/// [pattern] מוזרק בבדיקות בלבד — בייצור נבנה מהמנוע.
bool queryMatchesInlineNoteOnly(
  String rawLine,
  String query, {
  @visibleForTesting RegExp? pattern,
}) {
  if (!rawLine.contains('footnote')) return false;
  final regExp = pattern ?? buildLiteralPattern(query)?.regExp;
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
  final Map<int, Completer<List<TextSearchResult>>> _pending = {};

  // מעקב אחר התוכן האחרון שנשלח ל-worker. כל עוד מדובר באותו אובייקט תוכן
  // (אותו ספר פתוח) שולחים רק את השאילתה — לא את הספר כולו — וה-worker
  // משתמש ב-cache שלו לפי המזהה.
  List<String>? _lastSentContent;
  int _lastContentId = 0;

  Future<List<TextSearchResult>> search({
    required List<String> content,
    required String query,
    required String patternSource,
  }) async {
    await _ensureStarted();

    final requestId = ++_nextRequestId;
    final completer = Completer<List<TextSearchResult>>();
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
    ).then((isolate) {
      _isolate = isolate;
    }).catchError((Object error, StackTrace stackTrace) {
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
        completer.complete(
          rawResults
              .cast<Map<dynamic, dynamic>>()
              .map(
                (raw) => TextSearchResult(
                  index: raw['index'] as int,
                  snippet: raw['snippet'] as String,
                  address: raw['address'] as String,
                  query: raw['query'] as String,
                  matchOffset: raw['matchOffset'] as int?,
                ),
              )
              .toList(growable: false),
        );
        break;
      case 'canceled':
        completer.complete(const []);
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
        completer.complete(const []);
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
          final pattern =
              compileLiteralPattern(request['patternSource'] as String);

          // ודא שה-cache תואם לתוכן המבוקש; אחרת בנה אותו פעם אחת.
          // בקשה ללא contentId (תאימות לאחור) נחשבת תמיד כתוכן חדש.
          final bool cacheValid = contentId != null &&
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

          for (int i = 0; i < cleanLines.length; i++) {
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
              cleanAddress ??= utils
                  .removeVolwels(utils.stripHtmlIfNeeded(address.join(', ')));
              results.add({
                'index': i,
                'snippet': _snippetAroundMatch(
                  cleanLines[i],
                  match,
                  lowerBound:
                      m > 0 ? (lineMatches[m - 1].end + match.start) ~/ 2 : 0,
                  upperBound: m < lineMatches.length - 1
                      ? (match.end + lineMatches[m + 1].start) ~/ 2
                      : cleanLines[i].length,
                ),
                'address': cleanAddress,
                'query': query,
                'matchOffset': match.start,
              });
              if (results.length >= _maxSearchResults) {
                break;
              }
            }
            if (results.length >= _maxSearchResults) {
              break;
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
Future<List<TextSearchResult>> searchInContent({
  required List<String> content,
  required String query,
  @visibleForTesting String? patternSource,
}) async {
  if (content.isEmpty) return [];

  final source = patternSource ?? buildLiteralPattern(query)?.source;
  if (source == null) return [];

  return _SearchWorkerHost.instance.search(
    content: content,
    query: query,
    patternSource: source,
  );
}

@visibleForTesting
Future<void> resetSectionSearchWorkerForTesting() {
  return _SearchWorkerHost.instance.resetForTesting();
}
