import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:otzaria/search_feedback/search_feedback_events.dart';

/// מקטע בתור: קובץ JSONL שהשורה הראשונה בו היא ה-ClientContext.
class SearchFeedbackSegment {
  SearchFeedbackSegment(this.name, {required this.events, required this.bytes});

  String name;
  int events;
  int bytes;
}

/// כשלים רצופים של מקטע מסוים, נשמרים על הדיסק כדי שיצטברו גם בין הפעלות.
class SearchFeedbackStrikeRecord {
  const SearchFeedbackStrikeRecord({
    required this.kind,
    required this.count,
    required this.firstAt,
  });

  final String kind;
  final int count;
  final DateTime firstAt;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'count': count,
    'firstAt': firstAt.toUtc().toIso8601String(),
  };

  static SearchFeedbackStrikeRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final count = json['count'];
    final firstAt = DateTime.tryParse('${json['firstAt']}');
    if (kind is! String || count is! int || firstAt == null) return null;
    return SearchFeedbackStrikeRecord(
      kind: kind,
      count: count,
      firstAt: firstAt,
    );
  }
}

/// אצווה שנקראה מהדיסק: ה-context והאירועים כשורות JSON גולמיות.
class SearchFeedbackStoredBatch {
  const SearchFeedbackStoredBatch({
    required this.segmentName,
    required this.contextJson,
    required this.eventLines,
  });

  final String segmentName;
  final String contextJson;
  final List<String> eventLines;

  /// אותה אצווה בלי [key] ב-context.
  SearchFeedbackStoredBatch withoutContextKey(String key) {
    final context = jsonDecode(contextJson) as Map<String, dynamic>
      ..remove(key);
    return SearchFeedbackStoredBatch(
      segmentName: segmentName,
      contextJson: searchFeedbackJsonEncode(context),
      eventLines: eventLines,
    );
  }
}

/// תור מתמשך בקובצי JSONL (הוספה בלבד); כל מקטע = אצווה אחת עם context אחיד.
/// משותף לכל החלונות (תהליכים): מקטע נלקח לשליחה בשינוי שם, ומחיקה סובלנית.
class SearchFeedbackQueue {
  SearchFeedbackQueue(
    this._directory, {
    required this._clock,
    this.maxEvents = 5000,
    this.maxBytes = 5 * 1024 * 1024,
    this.segmentEvents = SearchFeedbackLimits.eventsPerBatch,
    this.segmentBytes =
        SearchFeedbackLimits.batchBytes -
        SearchFeedbackLimits.batchEnvelopeReserve,
  });

  static const String _prefix = 'seg-';
  static const String _extension = '.jsonl';
  static const String _claimedExtension = '.claimed.jsonl';
  static const String strikesFileName = 'strikes.json';

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final int maxEvents;
  final int maxBytes;
  final int segmentEvents;
  final int segmentBytes;

  final List<SearchFeedbackSegment> _segments = [];
  SearchFeedbackSegment? _open;
  String? _openContext;
  bool _loaded = false;
  int _sequence = 0;
  Future<void> _tail = Future.value();
  final Map<String, SearchFeedbackStrikeRecord> _strikes = {};

  int get eventCount => _segments.fold(0, (sum, s) => sum + s.events);

  int get byteCount => _segments.fold(0, (sum, s) => sum + s.bytes);

  bool get isEmpty => eventCount == 0;

  /// מריץ את [action] אחרי כל הפעולות הקודמות; כשל אינו שובר את התור.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> load() => _serialized(_ensureLoaded);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final dir = await _directory();
    _segments.clear();
    if (await dir.exists()) {
      final files = <File>[
        await for (final entity in dir.list())
          if (entity is File && _isSegmentName(p.basename(entity.path))) entity,
      ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final file in files) {
        final String text;
        try {
          text = await file.readAsString();
        } on FileSystemException {
          continue; // נלקח או נמחק בתהליך אחר.
        }
        final lines = const LineSplitter().convert(text);
        final events = lines.length > 1 ? lines.length - 1 : 0;
        if (events == 0) {
          if (await _isStale(file)) {
            await _deleteFile(dir, p.basename(file.path));
          }
          continue;
        }
        _segments.add(
          SearchFeedbackSegment(
            p.basename(file.path),
            events: events,
            bytes: utf8.encode(text).length,
          ),
        );
      }
    }
    await _loadStrikes(dir);
    _loaded = true;
  }

  Future<void> _loadStrikes(Directory dir) async {
    _strikes.clear();
    final file = File(p.join(dir.path, strikesFileName));
    if (!await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final names = {for (final s in _segments) s.name};
      for (final entry in json.entries) {
        final record = SearchFeedbackStrikeRecord.fromJson(entry.value);
        if (record != null && names.contains(entry.key)) {
          _strikes[entry.key as String] = record;
        }
      }
    } on FormatException {
      // קובץ פגום — מתחילים את הספירה מחדש.
    }
  }

  Future<void> _saveStrikes(Directory dir) async {
    final file = File(p.join(dir.path, strikesFileName));
    if (_strikes.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await dir.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        for (final entry in _strikes.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  /// סופר כשל נוסף מסוג [kind] למקטע; סוג אחר מתחיל ספירה חדשה.
  Future<SearchFeedbackStrikeRecord> addStrike(
    String name,
    String kind,
    DateTime now,
  ) => _serialized(() async {
    await _ensureLoaded();
    final previous = _strikes[name];
    final record = previous != null && previous.kind == kind
        ? SearchFeedbackStrikeRecord(
            kind: kind,
            count: previous.count + 1,
            firstAt: previous.firstAt,
          )
        : SearchFeedbackStrikeRecord(kind: kind, count: 1, firstAt: now);
    _strikes[name] = record;
    await _saveStrikes(await _directory());
    return record;
  });

  /// מאפס את ספירת הכשלים של מקטע.
  Future<void> clearStrikes(String name) => _serialized(() async {
    await _ensureLoaded();
    if (_strikes.remove(name) == null) return;
    await _saveStrikes(await _directory());
  });

  static bool _isSegmentName(String name) =>
      name.startsWith(_prefix) && name.endsWith(_extension);

  /// מוסיף אירוע. context שונה מהמקטע הפתוח פותח מקטע חדש.
  Future<void> append(
    Map<String, Object?> event,
    Map<String, Object?> context,
  ) => _serialized(() async {
    await _ensureLoaded();
    final line = searchFeedbackJsonEncode(event);
    final lineBytes = line.length + 1;
    if (lineBytes > segmentBytes) return;
    final contextJson = searchFeedbackJsonEncode(context);
    final dir = await _directory();
    await dir.create(recursive: true);

    var open = _open;
    if (open != null && !await File(p.join(dir.path, open.name)).exists()) {
      // תהליך אחר לקח את המקטע לשליחה — ממשיכים במקטע חדש.
      _segments.remove(open);
      open = null;
    }
    if (open == null ||
        _openContext != contextJson ||
        open.events >= segmentEvents ||
        open.bytes + lineBytes > segmentBytes + contextJson.length + 1) {
      open = SearchFeedbackSegment(_newName(), events: 0, bytes: 0);
      _segments.add(open);
      _open = open;
      _openContext = contextJson;
      await File(p.join(dir.path, open.name)).writeAsString('$contextJson\n');
      open.bytes = contextJson.length + 1;
    }
    await File(
      p.join(dir.path, open.name),
    ).writeAsString('$line\n', mode: FileMode.append);
    open
      ..events += 1
      ..bytes += lineBytes;
    await _enforceCaps(dir);
  });

  /// מוחק מקטעים ותיקים עד שהתור חוזר לתקרות.
  Future<void> _enforceCaps(Directory dir) async {
    while (_segments.length > 1 &&
        (eventCount > maxEvents || byteCount > maxBytes)) {
      final oldest = _segments.removeAt(0);
      await _deleteFile(dir, oldest.name);
      if (_strikes.remove(oldest.name) != null) await _saveStrikes(dir);
    }
  }

  String _newName() {
    final micros = _clock().toUtc().microsecondsSinceEpoch;
    final seq = (_sequence++ % 10000).toString().padLeft(4, '0');
    return '$_prefix${micros.toString().padLeft(17, '0')}-$pid-$seq$_extension';
  }

  /// מקטע ריק ישן; מקטע ריק טרי עשוי להיות פתוח לכתיבה בתהליך אחר.
  Future<bool> _isStale(File file) async {
    try {
      final modified = await file.lastModified();
      return _clock().difference(modified) > const Duration(hours: 1);
    } on FileSystemException {
      return false;
    }
  }

  /// סוגר את המקטע הפתוח וקורא שוב את התיקייה (כולל מקטעים של חלונות אחרים).
  Future<List<String>> sealAndList() => _serialized(() async {
    _open = null;
    _openContext = null;
    _loaded = false;
    await _ensureLoaded();
    return [for (final segment in _segments) segment.name];
  });

  /// לוקח מקטע לשליחה בשינוי שם אטומי; `null` כשתהליך אחר כבר לקח אותו.
  Future<String?> claim(String name) => _serialized(() async {
    if (name.endsWith(_claimedExtension)) return name;
    final dir = await _directory();
    final claimed =
        '${name.substring(0, name.length - _extension.length)}'
        '$_claimedExtension';
    try {
      await File(p.join(dir.path, name)).rename(p.join(dir.path, claimed));
    } on FileSystemException {
      _segments.removeWhere((s) => s.name == name);
      return null;
    }
    for (final segment in _segments) {
      if (segment.name == name) segment.name = claimed;
    }
    if (_open?.name == name) _open = null;
    final strike = _strikes.remove(name);
    if (strike != null) {
      _strikes[claimed] = strike;
      await _saveStrikes(dir);
    }
    return claimed;
  });

  /// קורא מקטע לשליחה. שורות פגומות ואירועים מלפני [notBefore] מושמטים;
  /// null = המקטע כבר אינו קיים.
  Future<SearchFeedbackStoredBatch?> read(String name, {DateTime? notBefore}) =>
      _serialized(() async {
        final dir = await _directory();
        final file = File(p.join(dir.path, name));
        if (!await file.exists()) return null;
        final List<String> lines;
        try {
          lines = const LineSplitter().convert(await file.readAsString());
        } on FileSystemException {
          return null;
        }
        if (lines.isEmpty) return null;
        // שורה ראשונה שאינה ClientContext (כתיבה מתחרה) — האצווה נזרקת.
        if (!_isContextLine(lines.first)) {
          return SearchFeedbackStoredBatch(
            segmentName: name,
            contextJson: '{}',
            eventLines: const [],
          );
        }
        final contextJson = lines.first;
        return SearchFeedbackStoredBatch(
          segmentName: name,
          contextJson: contextJson,
          eventLines: [
            for (final line in lines.skip(1))
              if (_isFreshEvent(line, notBefore)) line,
          ],
        );
      });

  static bool _isContextLine(String line) {
    try {
      final json = jsonDecode(line);
      return json is Map && json['app'] == 'otzaria';
    } on FormatException {
      return false;
    }
  }

  static bool _isFreshEvent(String line, DateTime? notBefore) {
    try {
      final json = jsonDecode(line);
      if (json is! Map) return false;
      if (notBefore == null) return true;
      final time = DateTime.tryParse('${json['clientTime']}');
      return time != null && !time.isBefore(notBefore);
    } on FormatException {
      return false;
    }
  }

  /// מסיר מקטע שנשלח (או שהוחלט לוותר עליו).
  Future<void> remove(String name) => _serialized(() async {
    final dir = await _directory();
    _segments.removeWhere((s) => s.name == name);
    if (_open?.name == name) _open = null;
    await _deleteFile(dir, name);
    if (_strikes.remove(name) != null) await _saveStrikes(dir);
  });

  /// מפצל מקטע לשניים במקומו בסדר התור; מקטע של אירוע אחד מוסר.
  Future<void> split(String name) => _serialized(() async {
    final dir = await _directory();
    final file = File(p.join(dir.path, name));
    final index = _segments.indexWhere((s) => s.name == name);
    if (index < 0 || !await file.exists()) return;
    final lines = const LineSplitter().convert(await file.readAsString());
    final events = lines.skip(1).toList();
    _segments.removeAt(index);
    if (_open?.name == name) _open = null;
    await file.delete();
    if (_strikes.remove(name) != null) await _saveStrikes(dir);
    if (events.length < 2) return;
    final half = events.length ~/ 2;
    final base = name.substring(0, name.length - _extension.length);
    final parts = [events.sublist(0, half), events.sublist(half)];
    for (var i = 0; i < parts.length; i++) {
      final partName = '$base${i == 0 ? 'a' : 'b'}$_extension';
      final text = '${[lines.first, ...parts[i]].join('\n')}\n';
      await File(p.join(dir.path, partName)).writeAsString(text);
      _segments.insert(
        index + i,
        SearchFeedbackSegment(
          partName,
          events: parts[i].length,
          bytes: utf8.encode(text).length,
        ),
      );
    }
  });

  /// מוחק את כל התור מהדיסק.
  Future<void> purge() => _serialized(() async {
    final dir = await _directory();
    _segments.clear();
    _strikes.clear();
    _open = null;
    _openContext = null;
    _loaded = true;
    if (!await dir.exists()) return;
    await _saveStrikes(dir);
    await for (final entity in dir.list()) {
      if (entity is File && _isSegmentName(p.basename(entity.path))) {
        await _deleteFile(dir, p.basename(entity.path));
      }
    }
  });

  static Future<void> _deleteFile(Directory dir, String name) async {
    try {
      await File(p.join(dir.path, name)).delete();
    } on FileSystemException {
      // כבר נמחק או נלקח בתהליך אחר.
    }
  }
}
