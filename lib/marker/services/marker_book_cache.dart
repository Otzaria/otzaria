import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_paint.dart';
import 'package:otzaria/marker/services/marker_realign.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/services/marker_text_format.dart';
import 'package:otzaria/marker/storage/marker_changes.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/services/plugin_highlight_anchor_service.dart';

/// סימוני הספרים הפתוחים בחלון, לציור. ספר נטען בבקשה הראשונה ומחדש רק בשינוי
/// מ-[MarkerChanges]; הציור לכל פסקה נשמר עד שינוי בספר, בפלטה או בנראות.
class MarkerBookCache {
  MarkerBookCache({
    MarkerRepository? repository,
    MarkerChanges? changes,
    MarkerSettings? settings,
    this._anchorService = const PluginHighlightAnchorService(),
  }) : _repository = repository ?? MarkerRepository(),
       _changesSource = changes ?? MarkerChanges.instance,
       _settingsSource = settings;

  static MarkerBookCache _instance = MarkerBookCache();
  static MarkerBookCache get instance => _instance;

  /// בדיקות מחליפות את המטמון ומחזירות את הקודם; זה שהוחלף נסגר ב-[dispose].
  @visibleForTesting
  static set instance(MarkerBookCache cache) => _instance = cache;

  static const int _maxBooks = 64;

  final MarkerRepository _repository;
  final MarkerChanges _changesSource;
  final MarkerSettings? _settingsSource;
  final PluginHighlightAnchorService _anchorService;

  final LinkedHashMap<_BookKey, _BookEntry> _entries = LinkedHashMap();
  final Map<String, _BookNotifier> _notifiers = {};
  StreamSubscription<MarkerChange>? _changes;
  bool _listeningToSettings = false;
  int _revision = 0;

  MarkerSettings get _settings => _settingsSource ?? MarkerSettings.instance;

  /// עולה בכל שינוי שמשפיע על הציור, בכל ספר.
  int get revision => _revision;

  /// מודיע כשהציור של [bookTitle] משתנה.
  Listenable listenable(String bookTitle) => _notifierOf(bookTitle).paint;

  /// מודיע על כל שינוי בסימוני [bookTitle], גם בהערה או בתגית.
  Listenable contentListenable(String bookTitle) =>
      _notifierOf(bookTitle).content;

  _BookNotifier _notifierOf(String bookTitle) {
    _attach();
    return _notifiers.putIfAbsent(bookTitle, _BookNotifier.new);
  }

  /// הסימונים של הספר אם כבר נטענו; אחרת מתחיל טעינה ומחזיר null.
  List<MarkerHighlight>? marksOf(
    String bookTitle,
    String? bookUid, {
    bool pdf = false,
  }) {
    _attach();
    final key = (title: bookTitle, uid: bookUid, pdf: pdf);
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry;
      return entry.marks;
    }
    unawaited(ensureLoaded(bookTitle, bookUid, pdf: pdf));
    return null;
  }

  Future<List<MarkerHighlight>> ensureLoaded(
    String bookTitle,
    String? bookUid, {
    bool pdf = false,
  }) {
    _attach();
    final key = (title: bookTitle, uid: bookUid, pdf: pdf);
    final entry = _entries[key];
    if (entry != null && entry.marks != null) return Future.value(entry.marks);
    return (entry ?? _put(key)).loading ??= _load(key);
  }

  _BookEntry _put(_BookKey key) {
    final entry = _BookEntry();
    _entries[key] = entry;
    while (_entries.length > _maxBooks) {
      final evicted = _entries.keys.first;
      _entries.remove(evicted);
      _forgetNotifier(evicted.title);
    }
    return entry;
  }

  Future<List<MarkerHighlight>> _load(_BookKey key) async {
    final entry = _entries[key] ?? _put(key);
    final generation = ++entry.generation;
    List<MarkerHighlight> marks;
    try {
      final loaded = await _repository.loadBook(
        bookTitle: key.title,
        bookUid: key.uid,
        pdf: key.pdf,
      );
      marks = [
        for (final mark in loaded)
          if (!_isOtherBook(mark, key.uid)) mark,
      ];
    } catch (error, stackTrace) {
      // הקורא ממשיך עם מה שכבר הוצג; מסך המרקר מציג את השגיאה בעצמו.
      debugPrint('MarkerBookCache: loading "${key.title}" failed: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);
      marks = entry.marks ?? const [];
    }
    if (generation != entry.generation) return marks;
    if (!identical(_entries[key], entry)) {
      // הספר נדחק מהמטמון בזמן הטעינה: מי שמחכה לו יבקש אותו שוב.
      if (marks.isNotEmpty) _notify(key.title);
      return marks;
    }
    final changed = marks.isNotEmpty || (entry.marks?.isNotEmpty ?? false);
    entry
      ..marks = List.unmodifiable(marks)
      ..loading = null
      ..paint.clear();
    // ספר בלי סימונים לא צויר וגם לא יצויר; הודעה הייתה רק בונה מחדש.
    if (changed) _notify(key.title);
    return marks;
  }

  /// מזהי ההדגשות של התוסף הישן שיובאו, בכל הספרים וגם כאלה שנמחקו מאז.
  /// המזהים ייחודיים, ולכן גם ספר ששמו השתנה אינו מצייר את עותק התוסף.
  Set<String>? _legacy;
  Future<void>? _legacyLoading;

  Future<void> _loadLegacy() async {
    try {
      final ids = await _repository.allImportedLegacyIds();
      final before = _legacy;
      _legacy = ids;
      if (ids.isNotEmpty || (before?.isNotEmpty ?? false)) _notifyAll();
    } catch (error) {
      // כשל אינו מסתיר דבר: הדגשות התוסף פשוט מצוירות כמקודם.
      debugPrint('MarkerBookCache: reading the old plugin ids failed: $error');
      _legacy ??= const {};
    } finally {
      _legacyLoading = null;
    }
  }

  /// סימון עם uid של ספר אחר באותה כותרת אינו שייך לספר הזה.
  static bool _isOtherBook(MarkerHighlight mark, String? bookUid) =>
      markerOtherBook(mark.bookUid, bookUid);

  bool _visible(String bookTitle, bool pdf) =>
      _settings.showHighlights && !_settings.isBookHidden(bookTitle, pdf: pdf);

  /// מה לצייר בפסקה [sectionIndex] של הספר.
  List<PluginHighlight> paint({
    required String bookTitle,
    String? bookUid,
    required int sectionIndex,
    required Brightness brightness,
    bool pdf = false,
  }) {
    if (!_visible(bookTitle, pdf)) return const [];
    final marks = marksOf(bookTitle, bookUid, pdf: pdf);
    if (marks == null || marks.isEmpty) return const [];
    final entry = _entries[(title: bookTitle, uid: bookUid, pdf: pdf)]!;
    return entry.paint.putIfAbsent(
      (section: sectionIndex, brightness: brightness),
      () => markerSectionPaint(
        highlights: marks,
        sectionIndex: sectionIndex,
        palette: _settings.palette,
        brightness: brightness,
      ),
    );
  }

  /// הסימונים שיש להם מקטע בפסקה, בכל מצב עוגן.
  List<MarkerHighlight> marksInSection({
    required String bookTitle,
    String? bookUid,
    required int sectionIndex,
    bool pdf = false,
  }) => [
    for (final mark
        in marksOf(bookTitle, bookUid, pdf: pdf) ?? const <MarkerHighlight>[])
      if (mark.segments.any((s) => s.sectionIndex == sectionIndex)) mark,
  ];

  /// מזהי ההדגשות של התוסף הישן שיובאו. נטענים רק כשיש לתוסף מה לצייר;
  /// עד אז הרשימה ריקה.
  Set<String> legacyIds() {
    _attach();
    final ids = _legacy;
    if (ids != null) return ids;
    _legacyLoading ??= _loadLegacy();
    return const {};
  }

  /// מעגן מחדש את סימוני הפסקה מול [sourceText] ושומר עוגן שהשתנה. סימון
  /// שלא נמצא בוודאות נשמר במקומו עם מצב "דורש תיקון", ואינו מוזז.
  /// [display] — שורת המקור והתצוגה שלה, לעיצוב הטקסט ברשימות
  /// ([MarkerSegment.html]) של סימון שעוד אין לו.
  void reanchorSection({
    required String bookTitle,
    String? bookUid,
    required int sectionIndex,
    required String sourceText,
    bool pdf = false,
    ({String raw, String processed}) Function()? display,
  }) {
    // טקסט ריק הוא טעינה שלא הושלמה, לא פסקה שהטקסט שלה נמחק.
    if (sourceText.isEmpty) return;
    final key = (title: bookTitle, uid: bookUid, pdf: pdf);
    final entry = _entries[key];
    final marks = entry?.marks;
    if (entry == null || marks == null) return;
    final changed = <String, List<MarkerSegment>>{};
    final next = <MarkerHighlight>[];
    ({String raw, String processed})? shown;
    for (final mark in marks) {
      var segments = mark.segments;
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        if (segment.sectionIndex != sectionIndex) continue;
        var resolved = _resolve(segment, sourceText);
        final current = resolved ?? segment;
        // רק עוגן שנמצא במקומו: טקסט שנמחק או זז בספר אינו מחפש מקום חדש.
        if (display != null &&
            !pdf &&
            segments.length == 1 &&
            current.status == MarkerAnchorStatus.active &&
            current.start == segment.start &&
            current.end == segment.end &&
            _textChecked.add('${mark.id}:${mark.version}')) {
          shown ??= display();
          resolved =
              realignMarkerSegment(
                segment: current,
                markText: mark.text,
                rawLine: shown.raw,
              ) ??
              resolved;
        }
        final placed = resolved ?? segment;
        // עיצוב שאי אפשר לחשב (טקסט שהתצוגה מסתירה) אינו מנוסה בכל פריים.
        if (display != null &&
            placed.html == null &&
            placed.status == MarkerAnchorStatus.active &&
            _htmlTried.add('${mark.id}:${mark.version}:${placed.start}')) {
          shown ??= display();
          final html = markerSegmentHtml(
            bookId: bookTitle,
            sectionIndex: sectionIndex,
            rawText: shown.raw,
            processedHtml: shown.processed,
            range: placed.range,
          );
          if (html != null) resolved = placed.copyWith(html: html);
        }
        if (resolved == null) continue;
        if (identical(segments, mark.segments)) segments = [...segments];
        segments[i] = resolved;
      }
      if (identical(segments, mark.segments)) {
        next.add(mark);
      } else {
        changed[mark.id] = segments;
        next.add(mark.copyWith(segments: List.unmodifiable(segments)));
      }
    }
    if (changed.isEmpty) return;
    entry
      ..marks = List.unmodifiable(next)
      ..paint.clear();
    _notify(bookTitle);
    // סימון שנמצא רק לפי הכותרת אולי שייך לספר אחר באותו שם; התוצאה שלו
    // משמשת לציור כאן, אבל אינה נשמרת.
    changed.removeWhere(
      (id, _) =>
          marks.firstWhere((mark) => mark.id == id).bookUid != bookUid ||
          bookUid == null,
    );
    if (changed.isEmpty) return;
    unawaited(
      _repository
          .saveAnchors(
            changed,
            versions: {
              for (final mark in marks)
                if (changed.containsKey(mark.id)) mark.id: mark.version,
            },
          )
          .catchError((Object error) {
            debugPrint('MarkerBookCache: saving anchors failed: $error');
          }),
    );
  }

  /// סימונים שהטקסט שלהם כבר הושווה לעוגן ([realignMarkerSegment]), לפי
  /// מזהה וגרסה: הבדיקה נעשית פעם אחת לכל גרסה של סימון.
  final Set<String> _textChecked = {};

  /// מקטעים שהעיצוב שלהם כבר חושב, לפי מזהה, גרסה ומקום.
  final Set<String> _htmlTried = {};

  MarkerSegment? _resolve(MarkerSegment segment, String sourceText) {
    PluginHighlightAnchorResult result;
    try {
      result = _anchorService.resolve(
        anchor: segment.range,
        sourceText: sourceText,
      );
    } on FormatException {
      result = const PluginHighlightAnchorResult(
        status: 'failed_to_anchor',
        range: null,
        strategy: 'invalid-normalization-profile',
        confidence: 0,
      );
    }
    var status = MarkerAnchorStatus.fromWire(result.status);
    var range = result.range ?? segment.range;
    // סימון שזז אינו מועבר למקום שאף אחד מצדדיו אינו תואם את מה שסומן: גם
    // מילה שמופיעה פעם אחת בפסקה יכולה להיות מילה אחרת, אחרי שהמקור נמחק.
    if (result.range != null &&
        !_offsetStrategies.contains(result.strategy) &&
        !_contextAgrees(segment.range, range)) {
      status = MarkerAnchorStatus.stale;
      range = segment.range;
    }
    if (status == segment.status &&
        jsonEncode(range.toJson()) == jsonEncode(segment.range.toJson())) {
      return null;
    }
    return segment.copyWith(range: range, status: status);
  }

  static const int _minContextMatch = 3;

  /// הטקסט נמצא במקומו; אין מה לבדוק בהקשר.
  static const Set<String> _offsetStrategies = {
    'exact-offset',
    'source-hash-offset',
  };

  static bool _contextAgrees(
    PluginTextRangeAnchor before,
    PluginTextRangeAnchor after,
  ) {
    int common(List<String> a, List<String> b) {
      var n = 0;
      while (n < a.length && n < b.length && a[n] == b[n]) {
        n++;
      }
      return n;
    }

    // צד שהיה בקצה הפסקה תואם רק אם הוא עדיין בקצה.
    bool side(List<String> old, List<String> fresh) {
      final need = min(_minContextMatch, old.length);
      return need == 0 ? fresh.isEmpty : common(old, fresh) >= need;
    }

    // הנרמול מתעלם מניקוד וטעמים, כמו האיתור עצמו.
    List<String> text(PluginAnchorContext context) =>
        (context.normalized.isNotEmpty ? context.normalized : context.raw)
            .characters
            .toList();
    final oldBefore = text(before.beforeText);
    final oldAfter = text(before.afterText);
    // עוגן בלי הקשר בכלל (סימון ישן שיובא מהתוסף) אינו נותן ראיה נגד.
    if (oldBefore.isEmpty && oldAfter.isEmpty) return true;
    return side(
          oldBefore.reversed.toList(),
          text(after.beforeText).reversed.toList(),
        ) ||
        side(oldAfter, text(after.afterText));
  }

  void _attach() {
    // מזהי התוסף הישן נטענים עם הספר הראשון, כדי שהעותק שלו לא יהבהב.
    if (_legacy == null) _legacyLoading ??= _loadLegacy();
    _changes ??= _changesSource.stream.listen(_onChange);
    if (!_listeningToSettings) {
      _listeningToSettings = true;
      _paintInputs = _currentPaintInputs();
      _hiddenBooks = _settings.hiddenBooks.toSet();
      _settings.addListener(_onSettingsChanged);
    }
  }

  /// שינוי עם רשימת מזהים מעדכן רק את הסימונים האלה; בלי רשימה (ייבוא,
  /// הודעה ישנה) הספר נטען מחדש.
  void _onChange(MarkerChange change) {
    // ייבוא ושחזור רושמים מזהים של התוסף הישן.
    if (change.isAll && _legacy != null) {
      _legacy = null;
      _legacyLoading ??= _loadLegacy();
    }
    for (final key in _entries.keys.toList()) {
      if (!change.affects(key.title, key.uid)) continue;
      final entry = _entries[key]!;
      final savedIds = change.savedIds;
      if (savedIds == null || entry.marks == null || entry.loading != null) {
        entry.loading = _load(key);
      } else if (change.saved case final saved?) {
        _applyDelta(key, entry, saved, change.removedIds);
      } else {
        unawaited(_fetchDelta(key, entry, savedIds, change.removedIds));
      }
    }
  }

  /// שינוי מחלון אחר: קוראים מהמסד רק את הסימונים שנשמרו.
  Future<void> _fetchDelta(
    _BookKey key,
    _BookEntry entry,
    Set<String> savedIds,
    Set<String> removedIds,
  ) async {
    final generation = entry.generation;
    List<MarkerHighlight> saved;
    try {
      saved = savedIds.isEmpty ? const [] : await _repository.getMany(savedIds);
    } catch (error) {
      debugPrint('MarkerBookCache: reading changed marks failed: $error');
      if (identical(_entries[key], entry)) entry.loading = _load(key);
      return;
    }
    // טעינה מלאה שהתחילה בינתיים קוראת את המצב העדכני בעצמה.
    if (generation != entry.generation || !identical(_entries[key], entry)) {
      return;
    }
    if (entry.loading != null || entry.marks == null) return;
    // סימון שנמחק בין ההודעה לקריאה פשוט לא נמצא.
    final found = {for (final mark in saved) mark.id};
    _applyDelta(key, entry, saved, {
      ...removedIds,
      ...savedIds.difference(found),
    });
  }

  void _applyDelta(
    _BookKey key,
    _BookEntry entry,
    List<MarkerHighlight> saved,
    Set<String> removedIds,
  ) {
    bool belongs(MarkerHighlight mark) =>
        mark.pdf == key.pdf &&
        (mark.bookTitle == key.title ||
            (key.uid != null && mark.bookUid == key.uid)) &&
        !_isOtherBook(mark, key.uid);
    final fresh = {for (final mark in saved) mark.id: mark};
    final next = <MarkerHighlight>[];
    var repaint = false;
    for (final mark in entry.marks!) {
      final update = fresh.remove(mark.id);
      if (removedIds.contains(mark.id) ||
          (update != null && !belongs(update))) {
        repaint = true;
      } else if (update == null) {
        next.add(mark);
      } else {
        repaint = repaint || !_samePaint(mark, update);
        next.add(update);
      }
    }
    for (final mark in fresh.values) {
      if (!belongs(mark)) continue;
      next.add(mark);
      repaint = true;
    }
    if (repaint) next.sort(_byPosition);
    entry.marks = List.unmodifiable(next);
    if (repaint) {
      entry.paint.clear();
      _notify(key.title);
    } else {
      _notifiers[key.title]?.content.changed();
    }
  }

  /// מה שהציור תלוי בו; הערה, תגית או מועדף אינם מציירים מחדש.
  static bool _samePaint(MarkerHighlight a, MarkerHighlight b) =>
      a.colorId == b.colorId &&
      a.colorHex == b.colorHex &&
      listEquals(a.segments, b.segments);

  /// הסדר שהמסד מחזיר: לפי הפסקה הראשונה ואז לפי זמן היצירה.
  static int _byPosition(MarkerHighlight a, MarkerHighlight b) {
    final bySection = a.segments.first.sectionIndex.compareTo(
      b.segments.first.sectionIndex,
    );
    return bySection != 0 ? bySection : a.createdAt.compareTo(b.createdAt);
  }

  /// מה שהציור תלוי בו מתוך ההגדרות; שינוי בשאר (כמו סדר הרשימה) אינו
  /// מצייר מחדש את הספרים הפתוחים, והסתרת ספר מציירת מחדש רק אותו.
  Object? _paintInputs;
  Set<String> _hiddenBooks = const {};

  void _onSettingsChanged() {
    final inputs = _currentPaintInputs();
    final hidden = _settings.hiddenBooks.toSet();
    final toggled = hidden
        .difference(_hiddenBooks)
        .union(_hiddenBooks.difference(hidden));
    _hiddenBooks = hidden;
    if (inputs != _paintInputs) {
      _paintInputs = inputs;
      _invalidatePaint();
    } else if (toggled.isNotEmpty) {
      // הנראות נבדקת לפני הזיכרון של הציור, ולכן אין מה לנקות.
      _revision++;
      for (final key in toggled) {
        _notifiers[MarkerSettings.bookOfHiddenKey(key).title]?.changed();
      }
    }
  }

  Object _currentPaintInputs() => (_settings.palette, _settings.showHighlights);

  void _invalidatePaint() {
    for (final entry in _entries.values) {
      entry.paint.clear();
    }
    _notifyAll();
  }

  void _notifyAll() {
    _revision++;
    for (final notifier in _notifiers.values) {
      notifier.changed();
    }
  }

  void _notify(String bookTitle) {
    _revision++;
    _notifiers[bookTitle]?.changed();
  }

  /// שוכח את כל מה שנטען — אחרי שהמסד הוחלף (העברת ספרייה, שחזור).
  void clear() {
    _entries.clear();
    _legacy = null;
    _invalidatePaint();
    for (final title in _notifiers.keys.toList()) {
      _forgetNotifier(title);
    }
  }

  /// מודיע של ספר שאיש אינו מאזין לו ואינו במטמון — כדי שלא יצטברו.
  void _forgetNotifier(String title) {
    if (_entries.keys.any((key) => key.title == title)) return;
    if (_notifiers[title]?.idle ?? false) _notifiers.remove(title);
  }

  @visibleForTesting
  void dispose() {
    _changes?.cancel();
    _changes = null;
    if (_listeningToSettings) _settings.removeListener(_onSettingsChanged);
    _listeningToSettings = false;
    _entries.clear();
  }
}

typedef _BookKey = ({String title, String? uid, bool pdf});

class _BookEntry {
  List<MarkerHighlight>? marks;
  Future<List<MarkerHighlight>>? loading;
  int generation = 0;
  final Map<({int section, Brightness brightness}), List<PluginHighlight>>
  paint = {};
}

class _BookNotifier {
  final _Notifier paint = _Notifier();
  final _Notifier content = _Notifier();

  bool get idle => !paint.hasListeners && !content.hasListeners;

  void changed() {
    paint.changed();
    content.changed();
  }
}

class _Notifier extends ChangeNotifier {
  void changed() => notifyListeners();

  @override
  bool get hasListeners => super.hasListeners;
}
