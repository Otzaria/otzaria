import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/official_pages_builder.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_roof_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_width_measurer.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';

part 'tikkun_korim_event.dart';
part 'tikkun_korim_state.dart';

/// שם פרשת השבוע הקרובה כפי שהלוח מחזיר אותו (עם ניקוד ואפשר מחובר).
String defaultUpcomingParashaName(DateTime date) {
  final daysUntilShabbat = date.weekday == DateTime.saturday
      ? 0
      : (DateTime.saturday - date.weekday) % 7;
  final shabbat = JewishCalendar.fromDateTime(
    date.add(Duration(days: daysUntilShabbat)),
  );
  return (HebrewDateFormatter()..hebrewFormat = true).formatParsha(shabbat);
}

class TikkunKorimBloc extends Bloc<TikkunKorimEvent, TikkunKorimState> {
  final TikkunKorimRepository repository;
  final TikkunDataSource data;
  final TikkunSettingsStore settingsStore;
  final String Function(DateTime) upcomingParasha;

  /// מודל הרוחב של גופן הסת"ם — נמדד ב-UI isolate ומוזרק לבדיקות.
  final StamWidthModel Function(String fontFamily) widthModelOf;

  /// מדידת גג דהלת"ם בגופן — רסטור ב-UI isolate, ולכן מוזרק לבדיקות.
  final Future<void> Function(String fontFamily) measureRoofs;

  /// מונה בקשות — תוצאה של טעינה ישנה מושלכת.
  int _requestId = 0;

  /// השורה הגלויה העליונה ובאיזה עמוד — לשמירת המקום בהחלפת שיטה.
  ({int column, int line}) _visible = (column: 0, line: 0);

  /// המיקום המדויק של השורה העליונה — נשמר עם הניווט ובסימניות.
  TikkunPosition? _position;

  TikkunKorimBloc({
    required this.repository,
    required this.data,
    this.settingsStore = const TikkunSettingsStore(),
    this.upcomingParasha = defaultUpcomingParashaName,
    this.widthModelOf = measureStamWidthModel,
    this.measureRoofs = measureStamRoofMetrics,
  }) : super(const TikkunKorimState(isLoading: true)) {
    on<TikkunStarted>(_onStarted);
    on<TikkunSectionChanged>(_onSectionChanged);
    on<TikkunMethodChanged>(_onMethodChanged);
    on<TikkunBookChanged>(_onBookChanged);
    on<TikkunParashaChanged>(_onParashaChanged);
    on<TikkunAliyaSelected>(_onAliyaSelected);
    on<TikkunChapterSelected>(_onChapterSelected);
    on<TikkunHaftarahChanged>(_onHaftarahChanged);
    on<TikkunReadingChanged>(_onReadingChanged);
    on<TikkunColumnSelected>(_onColumnSelected);
    on<TikkunNextColumn>(_onNextColumn);
    on<TikkunPrevColumn>(_onPrevColumn);
    on<TikkunSettingsUpdated>(_onSettingsUpdated);
    on<TikkunPeekToggled>(_onPeekToggled);
    on<TikkunVisibleLineChanged>(_onVisibleLineChanged);
    on<TikkunBookmarkAdded>(_onBookmarkAdded);
    on<TikkunBookmarkRemoved>(_onBookmarkRemoved);
    on<TikkunBookmarkOpened>(_onBookmarkOpened);
    on<TikkunScrollHandled>(
      (_, emit) => emit(state.copyWith(clearScroll: true)),
    );
  }

  /// רוחב הטור נגזר מן השיטה, ולכן הוא חלק ממודל הרוחב שהעימוד נחתך לפיו.
  StamWidthModel get _widths => widthModelOf(
    state.settings.stamFontFamily,
  ).withColumnFactor(tikkunColumnFactorFor(_linesPerPage));

  int get _linesPerPage =>
      TikkunData.torahLayouts[state.nav.methodId]?.linesPerPage ??
      kTikkunDefaultLinesPerPage;

  // ── טעינה ──────────────────────────────────────────────────────────────

  Future<void> _onStarted(
    TikkunStarted event,
    Emitter<TikkunKorimState> emit,
  ) async {
    final settings = settingsStore.load();
    var nav = settingsStore.loadNavState();
    final restore = settings.startupMode == 'lastPosition';
    if (!restore) {
      final resolved = data.resolveParasha(upcomingParasha(DateTime.now()));
      if (resolved != null) {
        nav = nav.copyWith(
          section: TikkunSection.torah,
          bookId: resolved.bookId,
          parashaName: resolved.parashaName,
          currentColumnIndex: 0,
        );
      }
    }
    emit(
      state.copyWith(
        settings: settings,
        nav: nav,
        bookmarks: settingsStore.loadBookmarks(),
      ),
    );
    await _reload(emit, target: restore ? nav.position : null);
  }

  /// [target] — מיקום לפתוח בו; בלעדיו נפתחים בראש הפרשה/הפרק/הקטע.
  Future<void> _reload(
    Emitter<TikkunKorimState> emit, {
    TikkunPosition? target,
  }) async {
    final requestId = ++_requestId;
    repository.useDecalogueTaam(state.settings.decalogueTaam);
    await measureRoofs(state.settings.stamFontFamily);
    emit(
      state.copyWith(
        isLoading: true,
        clearError: true,
        lineWidthEm: _widths.lineWidthEm,
      ),
    );
    try {
      switch (state.nav.section) {
        case TikkunSection.torah:
          await _loadTorah(emit, target);
        case TikkunSection.neviim:
        case TikkunSection.ketuvim:
          await _loadTanachBook(emit, target);
        case TikkunSection.haftarot:
          await _loadHaftarah(emit, target);
        case TikkunSection.torahReadings:
          await _loadReading(emit, target);
      }
    } catch (error) {
      if (requestId != _requestId) return;
      emit(
        state.copyWith(
          isLoading: false,
          error: ToolsMessages.tikkunLoadError(error),
          pages: const [],
        ),
      );
      return;
    }
    if (requestId != _requestId) return;
    emit(state.copyWith(isLoading: false));
  }

  Future<void> _loadTorah(
    Emitter<TikkunKorimState> emit,
    TikkunPosition? target,
  ) async {
    final pages = await repository.torahPages(state.nav.methodId, _widths);
    final location =
        (target == null ? null : tikkunLocatePosition(pages, target)) ??
        _findParashaLocation(pages, state.nav.parashaName);
    _position = tikkunPositionAt(
      pages,
      location.pageIdx,
      location.lineInPage,
    );
    emit(
      state.copyWith(
        pages: pages,
        clearHeader: true,
        chapterToLineIdx: const {},
        clearAliya: true,
        nav: state.nav.copyWith(currentColumnIndex: location.pageIdx),
        scrollToLine: location.lineInPage,
        scrollRequestId: state.scrollRequestId + 1,
      ),
    );
    // התצוגה אינה מדווחת על שורה שהיא גללה אליה — מסנכרנים את הבוררים כאן.
    if (target != null) _syncSelectors(location.lineInPage, emit);
  }

  /// השורה של [target] בעמוד יחיד, או [fallback].
  int _lineOf(TikkunPage page, TikkunPosition? target, int fallback) {
    final found = target == null ? null : tikkunLocatePosition([page], target);
    final line = found?.lineInPage ?? fallback;
    _position = tikkunPositionAt([page], 0, line);
    return line;
  }

  ({int pageIdx, int lineInPage}) _findParashaLocation(
    List<TikkunPage> pages,
    String parashaName,
  ) {
    for (var p = 0; p < pages.length; p++) {
      final lines = pages[p].lines;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].parashaName == parashaName) {
          return (pageIdx: p, lineInPage: i);
        }
      }
    }
    return (pageIdx: 0, lineInPage: 0);
  }

  Future<void> _loadTanachBook(
    Emitter<TikkunKorimState> emit,
    TikkunPosition? target,
  ) async {
    final book = _currentTanachBook();
    if (book == null) {
      _position = null;
      emit(state.copyWith(pages: const [], clearHeader: true));
      return;
    }
    final processed = await repository.processedBook(book.name, _widths);
    final page = TikkunPage(
      startLineIdx: 0,
      endLineIdx: processed.allLines.length,
      lines: processed.allLines,
    );
    final targetLine = _lineOf(
      page,
      target,
      processed.chapterToLineIdx[state.nav.tanachChapter] ?? 0,
    );
    emit(
      state.copyWith(
        pages: [page],
        chapterToLineIdx: processed.chapterToLineIdx,
        clearHeader: true,
        clearAliya: true,
        nav: state.nav.copyWith(currentColumnIndex: 0),
        scrollToLine: targetLine,
        scrollRequestId: state.scrollRequestId + 1,
      ),
    );
    if (target != null) _syncSelectors(targetLine, emit);
  }

  TanachBook? _currentTanachBook() {
    final books = data.booksOfSection(state.nav.section);
    if (books.isEmpty) return null;
    for (final book in books) {
      if (book.id == state.nav.tanachBookId) return book;
    }
    return books.first;
  }

  Future<void> _loadHaftarah(
    Emitter<TikkunKorimState> emit,
    TikkunPosition? target,
  ) async {
    _position = null;
    final list = haftarotForCurrentLand();
    if (list.isEmpty) {
      emit(state.copyWith(pages: const [], clearHeader: true));
      return;
    }
    final haftarah = list.firstWhere(
      (h) => h.id == state.nav.haftarahId,
      orElse: () => list.first,
    );
    if (!haftarah.hasNusach(state.settings.nusach)) {
      emit(
        state.copyWith(
          pages: const [],
          chapterToLineIdx: const {},
          clearAliya: true,
          headerTitle: haftarah.name,
          headerSubtitle: ToolsMessages.tikkunNoHaftarahForNusach,
          nav: state.nav.copyWith(
            currentColumnIndex: 0,
            haftarahId: haftarah.id,
          ),
        ),
      );
      return;
    }
    final segments = haftarah.forNusach(state.settings.nusach);
    // ברוב הערכים אין נתון ספרדי ייעודי ו-forNusach נופל לאשכנז — מציינים זאת.
    final fallback =
        state.settings.nusach == 'sephard' && haftarah.sephard.isEmpty;
    final lines = await repository.haftarahLines(
      haftarah,
      state.settings.nusach,
      _widths,
    );
    final page = TikkunPage(
      startLineIdx: 0,
      endLineIdx: lines.length,
      lines: lines,
    );
    emit(
      state.copyWith(
        pages: [page],
        chapterToLineIdx: const {},
        clearAliya: true,
        headerTitle: haftarah.name,
        headerSubtitle:
            'הפטרה: ${_formatRanges(segments)}${fallback ? ' (כמנהג אשכנז)' : ''}',
        nav: state.nav.copyWith(
          currentColumnIndex: 0,
          haftarahId: haftarah.id,
        ),
        scrollToLine: _lineOf(page, target, 0),
        scrollRequestId: state.scrollRequestId + 1,
      ),
    );
  }

  Future<void> _loadReading(
    Emitter<TikkunKorimState> emit,
    TikkunPosition? target,
  ) async {
    _position = null;
    final list = _readingsForLand();
    if (list.isEmpty) {
      emit(state.copyWith(pages: const [], clearHeader: true));
      return;
    }
    final reading = list.firstWhere(
      (r) => r.id == state.nav.torahReadingId,
      orElse: () => list.first,
    );
    final lines = await repository.readingLines(reading, _widths);
    final segments = repository.engine.computeContinuousSegments(
      reading.aliyot,
    );
    final page = TikkunPage(
      startLineIdx: 0,
      endLineIdx: lines.length,
      lines: lines,
    );
    emit(
      state.copyWith(
        pages: [page],
        chapterToLineIdx: const {},
        clearAliya: true,
        headerTitle: reading.name,
        headerSubtitle: 'קריאה: ${_formatRanges(segments)}',
        nav: state.nav.copyWith(
          currentColumnIndex: 0,
          torahReadingId: reading.id,
        ),
        scrollToLine: _lineOf(page, target, 0),
        scrollRequestId: state.scrollRequestId + 1,
      ),
    );
  }

  /// הקריאות המתאימות למנהג שנבחר ('both' תמיד נכלל).
  List<TorahReading> readingsForCurrentLand() => _readingsForLand();

  /// ההפטרות המתאימות לארץ שנבחרה ('both' תמיד נכלל).
  List<Haftarah> haftarotForCurrentLand() => data.haftarot
      .where(
        (h) => h.land == 'both' || h.land == state.settings.nusachLand,
      )
      .toList();

  List<TorahReading> _readingsForLand() => data.torahReadings
      .where(
        (r) =>
            (r.land == 'both' || r.land == state.settings.nusachLand) &&
            (r.nusach == null || r.nusach == state.settings.nusach),
      )
      .toList();

  String _formatRanges(List<VerseRange> ranges) {
    if (ranges.isEmpty) return '';
    final firstBook = ranges.first.book;
    final sameBook = ranges.every((r) => r.book == firstBook);
    final parts = <String>[];
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      final from = '${toHebrewNumeral(r.fromCh)}, ${toHebrewNumeral(r.fromVs)}';
      final to = '${toHebrewNumeral(r.toCh)}, ${toHebrewNumeral(r.toVs)}';
      final range = (r.fromCh == r.toCh && r.fromVs == r.toVs)
          ? from
          : '$from – $to';
      parts.add(i == 0 || !sameBook ? '${r.book} $range' : range);
    }
    return parts.join('; ');
  }

  // ── אירועי הסרגל ───────────────────────────────────────────────────────

  Future<void> _onSectionChanged(
    TikkunSectionChanged event,
    Emitter<TikkunKorimState> emit,
  ) async {
    if (event.section == state.nav.section) return;
    var nav = state.nav.copyWith(
      section: event.section,
      currentColumnIndex: 0,
    );
    switch (event.section) {
      case TikkunSection.neviim:
      case TikkunSection.ketuvim:
        final books = data.booksOfSection(event.section);
        nav = nav.copyWith(
          tanachBookId: books.isEmpty ? null : books.first.id,
          tanachChapter: 1,
        );
      case TikkunSection.haftarot:
        final list = haftarotForCurrentLand();
        if (list.isNotEmpty) nav = nav.copyWith(haftarahId: list.first.id);
      case TikkunSection.torahReadings:
        final list = _readingsForLand();
        if (list.isNotEmpty) nav = nav.copyWith(torahReadingId: list.first.id);
      case TikkunSection.torah:
        break;
    }
    emit(state.copyWith(nav: nav));
    await _persistNav();
    await _reload(emit);
  }

  Future<void> _onMethodChanged(
    TikkunMethodChanged event,
    Emitter<TikkunKorimState> emit,
  ) async {
    if (event.methodId == state.nav.methodId) return;
    final column = state.nav.currentColumnIndex;
    final verseKey = state.nav.section == TikkunSection.torah
        ? tikkunVerseKeyAt(
            state.pages,
            column,
            _visible.column == column ? _visible.line : 0,
          )
        : null;
    emit(state.copyWith(nav: state.nav.copyWith(methodId: event.methodId)));
    // בשיטה אחרת השורות נשברות אחרת — ההיסט בשורות אינו תקף בה.
    await _reload(
      emit,
      target: verseKey == null ? null : (verseKey: verseKey, lineOffset: 0),
    );
    await _persistNav();
  }

  Future<void> _onBookChanged(
    TikkunBookChanged event,
    Emitter<TikkunKorimState> emit,
  ) async {
    if (state.nav.section == TikkunSection.torah) {
      final book = data.chumashim.firstWhere(
        (b) => b.id == event.bookId,
        orElse: () => data.chumashim.first,
      );
      final parasha = book.parashot.contains(state.nav.parashaName)
          ? state.nav.parashaName
          : (book.parashot.isEmpty
                ? state.nav.parashaName
                : book.parashot.first);
      emit(
        state.copyWith(
          nav: state.nav.copyWith(bookId: book.id, parashaName: parasha),
        ),
      );
    } else {
      emit(
        state.copyWith(
          nav: state.nav.copyWith(
            tanachBookId: event.bookId,
            tanachChapter: 1,
          ),
        ),
      );
    }
    await _persistNav();
    await _reload(emit);
  }

  Future<void> _onParashaChanged(
    TikkunParashaChanged event,
    Emitter<TikkunKorimState> emit,
  ) async {
    emit(
      state.copyWith(
        nav: state.nav.copyWith(parashaName: event.parashaName),
        clearAliya: true,
      ),
    );
    await _persistNav();
    await _reload(emit);
  }

  Future<void> _onAliyaSelected(
    TikkunAliyaSelected event,
    Emitter<TikkunKorimState> emit,
  ) async {
    if (event.aliyaIdx == null) {
      emit(state.copyWith(clearAliya: true));
      await _reload(emit);
      return;
    }
    final book = data.chumashim.firstWhere(
      (b) => b.id == state.nav.bookId,
      orElse: () => data.chumashim.first,
    );
    final aliyot = data.aliyotOf(book.name, state.nav.parashaName);
    if (event.aliyaIdx! < 0 || event.aliyaIdx! >= aliyot.length) return;

    // העליות כבר מסומנות על השורות בעת העימוד; מחפשים את הסימון בתוך
    // הפרשה הנוכחית במקום לאתר מחדש את מילות הפתיחה.
    var inParasha = false;
    for (var p = 0; p < state.pages.length; p++) {
      final lines = state.pages[p].lines;
      for (var i = 0; i < lines.length; i++) {
        final lineParasha = lines[i].parashaName;
        if (lineParasha != null) {
          inParasha =
              data.normalizeParashaName(lineParasha) ==
              data.normalizeParashaName(state.nav.parashaName);
        }
        if (!inParasha ||
            (lines[i].aliyaIdx != event.aliyaIdx &&
                lines[i].maftirIdx != event.aliyaIdx)) {
          continue;
        }
        emit(
          state.copyWith(
            aliyaIdx: event.aliyaIdx,
            nav: state.nav.copyWith(currentColumnIndex: p),
            scrollToLine: i,
            scrollRequestId: state.scrollRequestId + 1,
          ),
        );
        _position = tikkunPositionAt(state.pages, p, i);
        await _persistNav();
        return;
      }
    }
  }

  Future<void> _onChapterSelected(
    TikkunChapterSelected event,
    Emitter<TikkunKorimState> emit,
  ) async {
    final lineIdx = state.chapterToLineIdx[event.chapter];
    emit(
      state.copyWith(
        nav: state.nav.copyWith(tanachChapter: event.chapter),
        scrollToLine: lineIdx ?? state.scrollToLine,
        scrollRequestId: lineIdx == null
            ? state.scrollRequestId
            : state.scrollRequestId + 1,
      ),
    );
    if (lineIdx != null) _position = tikkunPositionAt(state.pages, 0, lineIdx);
    await _persistNav();
  }

  Future<void> _onHaftarahChanged(
    TikkunHaftarahChanged event,
    Emitter<TikkunKorimState> emit,
  ) async {
    emit(state.copyWith(nav: state.nav.copyWith(haftarahId: event.haftarahId)));
    await _persistNav();
    await _reload(emit);
  }

  Future<void> _onReadingChanged(
    TikkunReadingChanged event,
    Emitter<TikkunKorimState> emit,
  ) async {
    emit(
      state.copyWith(nav: state.nav.copyWith(torahReadingId: event.readingId)),
    );
    await _persistNav();
    await _reload(emit);
  }

  Future<void> _onColumnSelected(
    TikkunColumnSelected event,
    Emitter<TikkunKorimState> emit,
  ) async {
    if (state.pages.isEmpty) return;
    final index = event.index.clamp(0, state.pages.length - 1);
    if (index == state.nav.currentColumnIndex) return;
    emit(
      state.copyWith(
        nav: state.nav.copyWith(currentColumnIndex: index),
        scrollToLine: 0,
        scrollRequestId: state.scrollRequestId + 1,
      ),
    );
    // המסך לא ידווח על שורה 0 של העמוד החדש — הוא כבר סימן אותה כמדווחת.
    await _onVisibleLineChanged(const TikkunVisibleLineChanged(0), emit);
    await _persistNav();
  }

  Future<void> _onNextColumn(
    TikkunNextColumn event,
    Emitter<TikkunKorimState> emit,
  ) => _onColumnSelected(
    TikkunColumnSelected(state.nav.currentColumnIndex + 1),
    emit,
  );

  Future<void> _onPrevColumn(
    TikkunPrevColumn event,
    Emitter<TikkunKorimState> emit,
  ) => _onColumnSelected(
    TikkunColumnSelected(state.nav.currentColumnIndex - 1),
    emit,
  );

  Future<void> _onSettingsUpdated(
    TikkunSettingsUpdated event,
    Emitter<TikkunKorimState> emit,
  ) async {
    final previous = state.settings;
    emit(state.copyWith(settings: event.settings));
    await settingsStore.save(event.settings);
    // גופן הסת"ם קובע את חיתוך השורות — שינוי שלו מחייב עימוד מחדש.
    final needsReload =
        previous.stamFontFamily != event.settings.stamFontFamily ||
        previous.decalogueTaam != event.settings.decalogueTaam ||
        (state.nav.section == TikkunSection.haftarot &&
            previous.nusach != event.settings.nusach) ||
        (state.nav.section == TikkunSection.torahReadings &&
            previous.nusachLand != event.settings.nusachLand);
    if (needsReload) await _reload(emit);
  }

  void _onPeekToggled(
    TikkunPeekToggled event,
    Emitter<TikkunKorimState> emit,
  ) {
    emit(state.copyWith(peekSecondColumn: !state.peekSecondColumn));
  }

  /// סנכרון בוררי הסרגל למיקום הגלילה, בלי לטעון מחדש.
  Future<void> _onVisibleLineChanged(
    TikkunVisibleLineChanged event,
    Emitter<TikkunKorimState> emit,
  ) async {
    final lines = state.currentLines;
    if (event.lineIdx < 0 || event.lineIdx >= lines.length) return;
    final position = tikkunPositionAt(
      state.pages,
      state.nav.currentColumnIndex,
      event.lineIdx,
    );
    final moved = position != _position;
    _position = position;
    final navBefore = state.nav;
    _syncSelectors(event.lineIdx, emit);
    if (moved || state.nav != navBefore) await _persistNav();
  }

  /// מעדכן את בוררי הפרק/הפרשה/העליה לפי השורה [lineIdx] בעמוד הנוכחי.
  void _syncSelectors(int lineIdx, Emitter<TikkunKorimState> emit) {
    _visible = (column: state.nav.currentColumnIndex, line: lineIdx);

    if (state.nav.section.isTanachBook) {
      int? chapter;
      for (final entry in state.chapterToLineIdx.entries) {
        if (entry.value <= lineIdx &&
            (chapter == null ||
                entry.value >= state.chapterToLineIdx[chapter]!)) {
          chapter = entry.key;
        }
      }
      if (chapter != null && chapter != state.nav.tanachChapter) {
        emit(state.copyWith(nav: state.nav.copyWith(tanachChapter: chapter)));
      }
      return;
    }
    if (state.nav.section != TikkunSection.torah) return;

    // הפרשה והעליה מסומנות רק בשורת הפתיחה — החיפוש חוצה עמודים קודמים.
    String? parasha;
    int? aliyaIdx;
    search:
    for (var col = state.nav.currentColumnIndex; col >= 0; col--) {
      final pageLines = state.pages[col].lines;
      final from = col == state.nav.currentColumnIndex
          ? lineIdx
          : pageLines.length - 1;
      for (var j = from; j >= 0; j--) {
        final line = pageLines[j];
        aliyaIdx ??= line.aliyaIdx;
        if (line.parashaName != null) {
          parasha = line.parashaName;
          break search;
        }
      }
    }
    if (parasha == null || parasha == state.nav.parashaName) {
      if (aliyaIdx != state.aliyaIdx) {
        emit(
          aliyaIdx == null
              ? state.copyWith(clearAliya: true)
              : state.copyWith(aliyaIdx: aliyaIdx),
        );
      }
      return;
    }
    final bookId = data.chumashim
        .firstWhere(
          (b) => b.parashot.contains(parasha),
          orElse: () => data.chumashim.first,
        )
        .id;
    emit(
      state.copyWith(
        nav: state.nav.copyWith(parashaName: parasha, bookId: bookId),
        aliyaIdx: aliyaIdx,
        clearAliya: aliyaIdx == null,
      ),
    );
  }

  Future<void> _persistNav() =>
      settingsStore.saveNavState(state.nav.withPosition(_position));

  // ── סימניות ────────────────────────────────────────────────────────────

  Future<void> _onBookmarkAdded(
    TikkunBookmarkAdded event,
    Emitter<TikkunKorimState> emit,
  ) async {
    if (state.pages.isEmpty) return;
    final nav = state.nav.withPosition(_position);
    if (state.bookmarks.any((b) => b.samePlaceAs(nav))) {
      UiSnack.show(ToolsMessages.tikkunBookmarkExists);
      return;
    }
    final bookmark = TikkunBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _describePosition(),
      nav: nav,
    );
    final bookmarks = [...state.bookmarks, bookmark];
    emit(state.copyWith(bookmarks: bookmarks));
    await settingsStore.saveBookmarks(bookmarks);
  }

  Future<void> _onBookmarkRemoved(
    TikkunBookmarkRemoved event,
    Emitter<TikkunKorimState> emit,
  ) async {
    final bookmarks = [
      for (final b in state.bookmarks)
        if (b.id != event.id) b,
    ];
    emit(state.copyWith(bookmarks: bookmarks));
    await settingsStore.saveBookmarks(bookmarks);
  }

  Future<void> _onBookmarkOpened(
    TikkunBookmarkOpened event,
    Emitter<TikkunKorimState> emit,
  ) async {
    final saved = event.bookmark.nav;
    final target = saved.position;
    // נפתחים בשיטה הנוכחית; ההיסט בשורות תקף רק בשיטה שבה נשמרה הסימניה.
    final sameMethod = saved.methodId == state.nav.methodId;
    emit(
      state.copyWith(
        nav: saved.copyWith(methodId: state.nav.methodId),
        clearAliya: true,
      ),
    );
    await _reload(
      emit,
      target: target == null || sameMethod
          ? target
          : (verseKey: target.verseKey, lineOffset: 0),
    );
    await _persistNav();
  }

  /// שם הסימניה: הספר, הפרק והפסוק, ובתורה גם הפרשה.
  String _describePosition() {
    final position = _position;
    final verse = position == null
        ? ''
        : '${toHebrewNumeral(position.verseKey ~/ 1000 % 1000)}, '
              '${toHebrewNumeral(position.verseKey % 1000)}';
    switch (state.nav.section) {
      case TikkunSection.torah:
        final index = position == null ? -1 : position.verseKey ~/ 1000000;
        final book = index >= 0 && index < data.chumashim.length
            ? data.chumashim[index].name
            : '';
        return '$book $verse · ${state.nav.parashaName}'.trim();
      case TikkunSection.neviim:
      case TikkunSection.ketuvim:
        return '${_currentTanachBook()?.name ?? ''} $verse'.trim();
      case TikkunSection.haftarot:
      case TikkunSection.torahReadings:
        final title = state.headerTitle ?? state.nav.section.label;
        return verse.isEmpty ? title : '$title ($verse)';
    }
  }

  /// סגירת הכרטיסייה משחררת את התורה המעובדת ואת מטמון הספרים.
  @override
  Future<void> close() {
    repository.clearCaches();
    return super.close();
  }
}
