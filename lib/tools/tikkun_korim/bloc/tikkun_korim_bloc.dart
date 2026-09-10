import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';
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

  /// טעינת גופני גוטמן מהמערכת — חייבת להסתיים לפני המדידה הראשונה.
  final Future<void> Function() prepareFonts;

  /// מונה בקשות — תוצאה של טעינה ישנה מושלכת.
  int _requestId = 0;

  TikkunKorimBloc({
    required this.repository,
    required this.data,
    this.settingsStore = const TikkunSettingsStore(),
    this.upcomingParasha = defaultUpcomingParashaName,
    this.widthModelOf = measureStamWidthModel,
    this.prepareFonts = TikkunStamFonts.prepare,
  }) : super(const TikkunKorimState()) {
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
    on<TikkunScrollHandled>(
      (_, emit) => emit(state.copyWith(clearScroll: true)),
    );
  }

  StamWidthModel get _widths => widthModelOf(state.settings.stamFontFamily);

  // ── טעינה ──────────────────────────────────────────────────────────────

  Future<void> _onStarted(
    TikkunStarted event,
    Emitter<TikkunKorimState> emit,
  ) async {
    await prepareFonts();
    final settings = settingsStore.load();
    var nav = settingsStore.loadNavState();
    if (settings.startupMode != 'lastPosition') {
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
    emit(state.copyWith(settings: settings, nav: nav));
    await _reload(emit);
  }

  Future<void> _reload(
    Emitter<TikkunKorimState> emit, {
    bool keepColumn = false,
  }) async {
    final requestId = ++_requestId;
    repository.useDecalogueTaam(state.settings.decalogueTaam);
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      switch (state.nav.section) {
        case TikkunSection.torah:
          await _loadTorah(emit, keepColumn: keepColumn);
        case TikkunSection.neviim:
        case TikkunSection.ketuvim:
          await _loadTanachBook(emit);
        case TikkunSection.haftarot:
          await _loadHaftarah(emit);
        case TikkunSection.torahReadings:
          await _loadReading(emit);
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
    Emitter<TikkunKorimState> emit, {
    bool keepColumn = false,
  }) async {
    final pages = await repository.torahPages(state.nav.methodId, _widths);
    if (keepColumn) {
      final index = state.nav.currentColumnIndex.clamp(
        0,
        pages.isEmpty ? 0 : pages.length - 1,
      );
      emit(
        state.copyWith(
          pages: pages,
          clearHeader: true,
          chapterToLineIdx: const {},
          nav: state.nav.copyWith(currentColumnIndex: index),
        ),
      );
      return;
    }
    final location = _findParashaLocation(pages, state.nav.parashaName);
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

  Future<void> _loadTanachBook(Emitter<TikkunKorimState> emit) async {
    final book = _currentTanachBook();
    if (book == null) {
      emit(state.copyWith(pages: const [], clearHeader: true));
      return;
    }
    final processed = await repository.processedBook(book.name, _widths);
    final page = TikkunPage(
      startLineIdx: 0,
      endLineIdx: processed.allLines.length,
      lines: processed.allLines,
    );
    final targetLine = processed.chapterToLineIdx[state.nav.tanachChapter] ?? 0;
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
  }

  TanachBook? _currentTanachBook() {
    final books = data.booksOfSection(state.nav.section);
    if (books.isEmpty) return null;
    for (final book in books) {
      if (book.id == state.nav.tanachBookId) return book;
    }
    return books.first;
  }

  Future<void> _loadHaftarah(Emitter<TikkunKorimState> emit) async {
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
    emit(
      state.copyWith(
        pages: [
          TikkunPage(startLineIdx: 0, endLineIdx: lines.length, lines: lines),
        ],
        chapterToLineIdx: const {},
        clearAliya: true,
        headerTitle: haftarah.name,
        headerSubtitle:
            'הפטרה: ${_formatRanges(segments)}${fallback ? ' (כמנהג אשכנז)' : ''}',
        nav: state.nav.copyWith(
          currentColumnIndex: 0,
          haftarahId: haftarah.id,
        ),
        scrollToLine: 0,
        scrollRequestId: state.scrollRequestId + 1,
      ),
    );
  }

  Future<void> _loadReading(Emitter<TikkunKorimState> emit) async {
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
    emit(
      state.copyWith(
        pages: [
          TikkunPage(startLineIdx: 0, endLineIdx: lines.length, lines: lines),
        ],
        chapterToLineIdx: const {},
        clearAliya: true,
        headerTitle: reading.name,
        headerSubtitle: 'קריאה: ${_formatRanges(segments)}',
        nav: state.nav.copyWith(
          currentColumnIndex: 0,
          torahReadingId: reading.id,
        ),
        scrollToLine: 0,
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
    emit(state.copyWith(nav: state.nav.copyWith(methodId: event.methodId)));
    await _persistNav();
    await _reload(emit);
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

    if (state.nav.section.isTanachBook) {
      int? chapter;
      for (final entry in state.chapterToLineIdx.entries) {
        if (entry.value <= event.lineIdx &&
            (chapter == null ||
                entry.value >= state.chapterToLineIdx[chapter]!)) {
          chapter = entry.key;
        }
      }
      if (chapter != null && chapter != state.nav.tanachChapter) {
        emit(state.copyWith(nav: state.nav.copyWith(tanachChapter: chapter)));
        await _persistNav();
      }
      return;
    }
    if (state.nav.section != TikkunSection.torah) return;

    String? parasha;
    int? aliyaIdx;
    for (var j = event.lineIdx; j >= 0; j--) {
      final line = lines[j];
      if (parasha == null && line.parashaName != null) {
        parasha = line.parashaName;
      }
      if (aliyaIdx == null && line.aliyaIdx != null) aliyaIdx = line.aliyaIdx;
      if (parasha != null && aliyaIdx != null) break;
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
    await _persistNav();
  }

  Future<void> _persistNav() => settingsStore.saveNavState(state.nav);

  /// סגירת הכרטיסייה משחררת את התורה המעובדת ואת מטמון הספרים.
  @override
  Future<void> close() {
    repository.clearCaches();
    return super.close();
  }
}
