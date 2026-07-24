// אבחון משאבים: מריץ את האפליקציה האמיתית ומדמה שימוש טיפוסי — עלייה, פתיחת
// ספרי טקסט, גלילה, ריבוי טאבים, PDF, ניווט בין מסכים וחיפוש גלובלי — תוך
// רישום RSS פנימי, זמני פריימים וגבולות זמן של כל שלב ל-phases.jsonl.
// דוגם CPU/RAM חיצוני (tool/perf_probe/sample_resources.ps1) רץ במקביל,
// והניתוח המשולב נעשה ב-tool/perf_probe/analyze.dart.
//
// הרצה מלאה: tool/perf_probe/run_perf_probe.ps1

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/main.dart' as app;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:path/path.dart' as p;

final _probeDir = Directory(
  p.join(Directory.systemTemp.path, 'otzaria_perf_probe'),
);
final _phasesFile = File(p.join(_probeDir.path, 'phases.jsonl'));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('perf resource probe', timeout: Timeout.none, (tester) async {
    _probeDir.createSync(recursive: true);
    if (_phasesFile.existsSync()) _phasesFile.deleteSync();

    final rec = _PhaseRecorder(_phasesFile, binding);
    rec.writeMeta();

    // --- שלב 1: עלייה עד הפריים הראשון של האפליקציה ---
    rec.start('startup_to_app_widget');
    app.main(const <String>[]);
    await _waitUntil(
      tester,
      () => find.byType(App).evaluate().isNotEmpty,
      timeout: const Duration(minutes: 3),
      what: 'App widget',
    );
    await rec.end();

    final ctx = tester.element(find.byType(App));
    final tabsBloc = ctx.read<TabsBloc>();
    final navBloc = ctx.read<NavigationBloc>();

    // --- שלב 2: טעינת קטלוג הספרייה ---
    rec.start('library_catalog_load');
    final library = await DataRepository.instance.library;
    await rec.end();

    // --- שלב 3: התייצבות + חימומי מטמון נדחים (BooksCache וכו') ---
    rec.start('startup_settle_warmups');
    await _pumpFor(tester, const Duration(seconds: 15));
    await rec.end();

    final allBooks = library.getAllBooks();
    final textBooks = _pickTextBooks(allBooks, 6);
    final pdfBook = _pickPdfBook(allBooks);
    rec.note('books_selected', {
      'textBooks': textBooks.map((b) => b.title).toList(),
      'pdfBook': pdfBook?.title,
    });

    // --- שלב 4: פתיחת ספר טקסט ראשון והמתנה לטעינה ---
    await _runPhase(rec, 'open_text_book_first', () async {
      openBook(ctx, textBooks.first, 20, '', ignoreHistory: true);
      await _waitForCurrentTextBookLoaded(tester, tabsBloc);
      await _pumpFor(tester, const Duration(seconds: 2));
    });

    // --- שלב 5: גלילה בספר ---
    await _runPhase(rec, 'scroll_text_book', () async {
      final firstTab = tabsBloc.state.currentTab;
      if (firstTab is! TextBookTab) {
        rec.note('scroll_skipped', {'reason': 'current tab is not TextBook'});
        return;
      }
      // ה-controller נצמד רק אחרי שהרשימה נבנתה — ממתינים לו בנפרד.
      final attached = await _waitUntil(
        tester,
        () => firstTab.scrollController.isAttached,
        timeout: const Duration(seconds: 10),
        what: 'scrollController attached',
        failSilently: true,
      );
      if (!attached) {
        rec.note('scroll_skipped', {'reason': 'scrollController not attached'});
        return;
      }
      for (final target in [60, 140, 30, 200]) {
        if (!firstTab.scrollController.isAttached) break;
        firstTab.scrollController.scrollTo(
          index: target,
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
        );
        await _pumpFor(tester, const Duration(milliseconds: 1500));
      }
    });

    // --- שלב 6: פתיחת 5 ספרי טקסט נוספים ---
    await _runPhase(rec, 'open_5_more_text_books', () async {
      for (final book in textBooks.skip(1)) {
        openBook(ctx, book, 5, '', ignoreHistory: true);
        await _waitForCurrentTextBookLoaded(
          tester,
          tabsBloc,
          timeout: const Duration(seconds: 45),
        );
        await _pumpFor(tester, const Duration(milliseconds: 500));
      }
    });

    // --- שלב 7: החלפות טאבים מהירות ---
    await _runPhase(rec, 'rapid_tab_switching', () async {
      final tabCount = tabsBloc.state.tabs.length;
      for (var round = 0; round < 2; round++) {
        for (var i = 0; i < tabCount; i++) {
          tabsBloc.add(SetCurrentTab(i));
          await _pumpFor(tester, const Duration(milliseconds: 900));
        }
      }
    });

    // --- שלב 8: ניווט בין מסכים (ספרייה, הגדרות, חזרה לקריאה) ---
    await _runPhase(rec, 'navigate_screens', () async {
      for (final screen in [
        Screen.library,
        Screen.reading,
        Screen.settings,
        Screen.reading,
      ]) {
        navBloc.add(NavigateToScreen(screen));
        await _pumpFor(tester, const Duration(seconds: 2));
      }
    });

    // --- שלב 9: חיפוש גלובלי ראשון (מנוע Tantivy + UI תוצאות) ---
    const query1 = 'אמר רבי עקיבא';
    final searchTab = SearchingTab(SearchingTab.titleForQuery(query1), query1);
    await _runPhase(rec, 'global_search_first', () async {
      tabsBloc.add(AddTab(searchTab));
      await _waitForSearchDone(tester, searchTab);
      await _pumpFor(tester, const Duration(seconds: 5)); // ספירות facets
    });

    // --- שלב 10: חיפוש שני באותו טאב ---
    await _runPhase(rec, 'global_search_second', () async {
      searchTab.queryController.text = 'ואהבת לרעך כמוך';
      searchTab.searchBloc.add(UpdateSearchQuery('ואהבת לרעך כמוך'));
      await _waitForSearchDone(tester, searchTab);
      await _pumpFor(tester, const Duration(seconds: 3));
    });

    // --- שלב 11: סגירת כל הטאבים ---
    await _runPhase(rec, 'close_all_tabs', () async {
      tabsBloc.add(CloseAllTabs());
      await _pumpFor(tester, const Duration(seconds: 3));
    });

    // --- שלב 12: מנוחה (אינדיקציה לשחרור זיכרון אחרי סגירת טאבים) ---
    await _runPhase(rec, 'idle_after_close', () async {
      await _pumpFor(tester, const Duration(seconds: 8));
    });

    // --- שלבי PDF בסוף בכוונה: בהרצה קודמת התהליך קרס בדפדוף PDF, וכך
    // קריסה חוזרת לא מאבדת את נתוני שאר השלבים. ---
    if (pdfBook != null) {
      final pdfLoaded = <bool>[false];
      await _runPhase(rec, 'open_pdf_book', () async {
        openBook(ctx, pdfBook, 2, '', ignoreHistory: true);
        pdfLoaded[0] = await _waitUntil(
          tester,
          () {
            final tab = tabsBloc.state.currentTab;
            return tab is PdfBookTab && tab.pdfViewerController.isReady;
          },
          timeout: const Duration(seconds: 90),
          what: 'PDF viewer ready',
          failSilently: true,
        );
        await _pumpFor(tester, const Duration(seconds: 4));
      });

      await _runPhase(rec, 'pdf_page_flips', () async {
        final tab = tabsBloc.state.currentTab;
        if (!pdfLoaded[0] || tab is! PdfBookTab) {
          rec.note('pdf_flips_skipped', {'reason': 'pdf not ready'});
          return;
        }
        // מצב התצוגה קובע אם פרה-רנדר הכפולות פעיל — חיוני להשוואת הרצות.
        rec.note('pdf_layout_mode', {'mode': tab.savedLayoutMode?.name});
        for (final page in [6, 14, 25, 9]) {
          if (!tab.pdfViewerController.isReady) break;
          try {
            final total = tab.pdfViewerController.pageCount;
            await tab.pdfViewerController.goToPage(
              pageNumber: page.clamp(1, total),
            );
          } catch (e) {
            rec.note('pdf_goto_error', {'page': page, 'error': '$e'});
            break;
          }
          await _pumpFor(tester, const Duration(seconds: 3));
        }
      });

      // --- מצב תצוגת-ספר: מפעיל את פרה-רנדר הכפולות (החשוד בקריסת ההרצה
      // הראשונה). הטאב נוצר ידנית עם savedLayoutMode כדי שה-bloc יעלה ישר
      // במצב הזה. ---
      await _runPhase(rec, 'open_pdf_book_view', () async {
        final bookViewTab = PdfBookTab(book: pdfBook, pageNumber: 2)
          ..savedLayoutMode = PdfLayoutMode.bookView;
        tabsBloc.add(AddTab(bookViewTab));
        await _waitUntil(
          tester,
          () => bookViewTab.pdfViewerController.isReady,
          timeout: const Duration(seconds: 90),
          what: 'book-view PDF ready',
          failSilently: true,
        );
        await _pumpFor(tester, const Duration(seconds: 4));
      });

      await _runPhase(rec, 'pdf_book_view_flips', () async {
        final tab = tabsBloc.state.currentTab;
        if (tab is! PdfBookTab || !tab.pdfViewerController.isReady) {
          rec.note('book_view_flips_skipped', {'reason': 'pdf not ready'});
          return;
        }
        for (final page in [4, 8, 14, 6, 20]) {
          if (!tab.pdfViewerController.isReady) break;
          try {
            final total = tab.pdfViewerController.pageCount;
            await tab.pdfViewerController.goToPage(
              pageNumber: page.clamp(1, total),
            );
          } catch (e) {
            rec.note('book_view_goto_error', {'page': page, 'error': '$e'});
            break;
          }
          await _pumpFor(tester, const Duration(seconds: 3));
        }
      });

      await _runPhase(rec, 'final_idle', () async {
        await _pumpFor(tester, const Duration(seconds: 8));
        // אבחון הרינדור הרציף בתצוגת-ספר: מי מניע את הפריימים במנוחה —
        // שינויי מטריצה של ה-controller, או אנימציה אינסופית (ספינר) בעץ.
        final tab = tabsBloc.state.currentTab;
        if (tab is PdfBookTab && tab.pdfViewerController.isReady) {
          var notifies = 0;
          void countNotify() => notifies++;
          final controller = tab.pdfViewerController;
          final before = Matrix4.copy(controller.value);
          controller.addListener(countNotify);
          await _pumpFor(tester, const Duration(seconds: 3));
          controller.removeListener(countNotify);
          final after = controller.value;
          final delta = (after.getTranslation() - before.getTranslation());
          rec.note('book_view_idle_diag', {
            'controllerNotifies3s': notifies,
            'matrixChanged': before != after,
            'translationDx': delta.x,
            'translationDy': delta.y,
            'liveSpinners': find
                .byType(CircularProgressIndicator)
                .evaluate()
                .length,
          });
        }
      });
    } else {
      rec.note('pdf_skipped', {'reason': 'no PdfBook with existing file'});
    }

    // ===== הרחבות: צורת הדף, מפרשים מרובים, הדפסה =====
    await _runPhase(rec, 'extras_cleanup', () async {
      tabsBloc.add(CloseAllTabs());
      await _pumpFor(tester, const Duration(seconds: 3));
    });

    // --- צורת הדף: ברכות (תלמוד) במצב page shape ---
    final talmudBook = textBooks.where((b) => b.title == 'ברכות').firstOrNull;
    if (talmudBook != null) {
      await _runPhase(rec, 'page_shape_open', () async {
        final tab = TextBookTab(
          book: talmudBook,
          index: 10,
          showPageShapeView: true,
        );
        tabsBloc.add(AddTab(tab));
        await _waitForCurrentTextBookLoaded(tester, tabsBloc);
        await _pumpFor(tester, const Duration(seconds: 10));
      });
    } else {
      rec.note('page_shape_skipped', {'reason': 'ברכות not in picked books'});
    }

    // --- כל המפרשים הזמינים על בראשית ---
    await _runPhase(rec, 'all_commentators_open', () async {
      openBook(ctx, textBooks.first, 20, '', ignoreHistory: true);
      await _waitForCurrentTextBookLoaded(tester, tabsBloc);
      final tab = tabsBloc.state.currentTab;
      if (tab is TextBookTab) {
        final st = tab.bloc.state;
        if (st is TextBookLoaded) {
          rec.note('available_commentators', {
            'count': st.availableCommentators.length,
          });
          tab.bloc.add(UpdateCommentators(List.of(st.availableCommentators)));
        }
      }
      await _pumpFor(tester, const Duration(seconds: 12));
    });

    await _runPhase(rec, 'scroll_all_commentators', () async {
      final tab = tabsBloc.state.currentTab;
      if (tab is! TextBookTab || !tab.scrollController.isAttached) {
        rec.note('scroll_all_commentators_skipped', {
          'reason': 'scrollController not attached',
        });
        return;
      }
      for (final target in [50, 110, 70]) {
        if (!tab.scrollController.isAttached) break;
        tab.scrollController.scrollTo(
          index: target,
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
        );
        await _pumpFor(tester, const Duration(seconds: 2));
      }
    });

    // --- הדפסה: תצוגה מקדימה עם המפרשים הפעילים (המסלול הכבד) ---
    await _runPhase(rec, 'print_preview', () async {
      final tab = tabsBloc.state.currentTab;
      if (tab is! TextBookTab || tab.bloc.state is! TextBookLoaded) {
        rec.note('print_skipped', {'reason': 'no loaded text book'});
        return;
      }
      final st = tab.bloc.state as TextBookLoaded;
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final showTeamim = ctx.read<SettingsBloc>().state.showTeamim;
      unawaited(
        showDialog<bool>(
          context: navigator.context,
          barrierDismissible: false,
          builder: (_) => PrintingScreen(
            data: Future.value(st.content.join('\n')),
            bookId: st.book.title,
            book: st.book,
            links: st.links,
            activeCommentators: st.activeCommentators,
            startLine: st.visibleIndices.isNotEmpty
                ? st.visibleIndices.first
                : 0,
            removeNikud: st.removeNikud,
            removeTaamim: !showTeamim,
            tableOfContents: st.tableOfContents,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 20));
    });

    await _runPhase(rec, 'print_close_and_cleanup', () async {
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      if (navigator.canPop()) navigator.pop();
      await _pumpFor(tester, const Duration(seconds: 2));
      tabsBloc.add(CloseAllTabs());
      await _pumpFor(tester, const Duration(seconds: 3));
    });

    rec.writeSummaryMarker();
  });
}

// ---------------------------------------------------------------------------
// בחירת ספרים
// ---------------------------------------------------------------------------

List<TextBook> _pickTextBooks(List<Book> allBooks, int count) {
  final textBooks = allBooks.whereType<TextBook>().toList();
  const preferred = ['בראשית', 'תהלים', 'ברכות', 'שמות', 'משלי', 'דברים'];
  final picked = <TextBook>[];
  for (final title in preferred) {
    if (picked.length >= count) break;
    final match = textBooks.where((b) => b.title == title);
    if (match.isNotEmpty) picked.add(match.first);
  }
  // השלמה מספרים מפוזרים לאורך הקטלוג אם הכותרים המועדפים לא נמצאו.
  if (picked.length < count && textBooks.isNotEmpty) {
    final step = (textBooks.length / (count + 1)).floor().clamp(1, 1 << 30);
    for (var i = 0; i < textBooks.length && picked.length < count; i += step) {
      final candidate = textBooks[i];
      if (!picked.contains(candidate)) picked.add(candidate);
    }
  }
  return picked;
}

PdfBook? _pickPdfBook(List<Book> allBooks) {
  final pdfBooks = allBooks
      .whereType<PdfBook>()
      .where((b) => File(b.path).existsSync())
      .toList();
  if (pdfBooks.isEmpty) return null;
  final preferred = pdfBooks.where((b) => b.title.contains('ברכות'));
  return preferred.isNotEmpty ? preferred.first : pdfBooks.first;
}

// ---------------------------------------------------------------------------
// המתנות
// ---------------------------------------------------------------------------

/// מריץ שלב מדוד; חריגה בשלב נרשמת כהערה ולא מפילה את שאר התרחיש.
Future<void> _runPhase(
  _PhaseRecorder rec,
  String name,
  Future<void> Function() body,
) async {
  rec.start(name);
  try {
    await body();
  } catch (e, st) {
    rec.note('phase_error', {
      'phase': name,
      'error': '$e',
      'stack': st.toString().split('\n').take(6).join(' | '),
    });
  } finally {
    await rec.end();
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<bool> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String what,
  bool failSilently = false,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return true;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!failSilently) {
    fail('Timed out after $timeout waiting for: $what');
  }
  return false;
}

Future<void> _waitForCurrentTextBookLoaded(
  WidgetTester tester,
  TabsBloc tabsBloc, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  await _waitUntil(
    tester,
    () {
      final tab = tabsBloc.state.currentTab;
      return tab is TextBookTab && tab.bloc.state is TextBookLoaded;
    },
    timeout: timeout,
    what: 'TextBookLoaded of current tab',
    failSilently: true,
  );
}

Future<void> _waitForSearchDone(WidgetTester tester, SearchingTab tab) async {
  // רגע לתחילת החיפוש (initState של מסך החיפוש מפעיל אותו).
  await _pumpFor(tester, const Duration(seconds: 1));
  await _waitUntil(
    tester,
    () {
      final s = tab.searchBloc.state;
      return s.searchQuery.isNotEmpty && !s.isLoading;
    },
    timeout: const Duration(minutes: 2),
    what: 'search results',
    failSilently: true,
  );
}

// ---------------------------------------------------------------------------
// מדידה
// ---------------------------------------------------------------------------

class _PhaseRecorder {
  _PhaseRecorder(this.outFile, WidgetsBinding binding) {
    binding.addTimingsCallback(_onTimings);
  }

  final File outFile;
  String? _phase;
  int _startMs = 0;
  int _rssStart = 0;
  int _rssPeak = 0;
  Timer? _rssTimer;
  final List<FrameTiming> _timings = [];

  void _onTimings(List<FrameTiming> timings) {
    if (_phase != null) _timings.addAll(timings);
  }

  void writeMeta() {
    _append({
      'type': 'meta',
      'pid': pid,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      'cores': Platform.numberOfProcessors,
    });
  }

  void note(String name, Map<String, Object?> details) {
    _append({'type': 'note', 'name': name, ...details});
  }

  void start(String name) {
    assert(_phase == null, 'phase $_phase still active');
    _phase = name;
    _timings.clear();
    _startMs = DateTime.now().millisecondsSinceEpoch;
    _rssStart = ProcessInfo.currentRss;
    _rssPeak = _rssStart;
    _rssTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > _rssPeak) _rssPeak = rss;
    });
  }

  Future<void> end() async {
    // מרווח קצר כדי לאסוף timings של פריימים אחרונים שדווחו באיחור.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final endMs = DateTime.now().millisecondsSinceEpoch;
    _rssTimer?.cancel();
    final rssEnd = ProcessInfo.currentRss;
    if (rssEnd > _rssPeak) _rssPeak = rssEnd;

    final build = _timings
        .map((t) => t.buildDuration.inMicroseconds / 1000)
        .toList();
    final raster = _timings
        .map((t) => t.rasterDuration.inMicroseconds / 1000)
        .toList();
    final total = _timings
        .map((t) => t.totalSpan.inMicroseconds / 1000)
        .toList();

    _append({
      'type': 'phase',
      'name': _phase,
      'startMs': _startMs,
      'endMs': endMs,
      'durationMs': endMs - _startMs,
      'rssStartMb': _mb(_rssStart),
      'rssEndMb': _mb(rssEnd),
      'rssPeakMb': _mb(_rssPeak),
      'frames': {
        'count': _timings.length,
        'buildAvgMs': _avg(build),
        'buildP95Ms': _p95(build),
        'buildMaxMs': _max(build),
        'rasterAvgMs': _avg(raster),
        'rasterP95Ms': _p95(raster),
        'rasterMaxMs': _max(raster),
        'jankOver33Ms': total.where((ms) => ms > 33).length,
      },
    });
    _phase = null;
  }

  void writeSummaryMarker() {
    _append({
      'type': 'done',
      'endedAt': DateTime.now().millisecondsSinceEpoch,
      'maxRssMb': _mb(ProcessInfo.maxRss),
    });
  }

  void _append(Map<String, Object?> record) {
    outFile.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static double _mb(int bytes) => (bytes / (1024 * 1024) * 10).round() / 10;
  static double _round1(double v) => (v * 10).round() / 10;
  static double _avg(List<double> v) =>
      v.isEmpty ? 0 : _round1(v.reduce((a, b) => a + b) / v.length);
  static double _max(List<double> v) =>
      v.isEmpty ? 0 : _round1(v.reduce((a, b) => a > b ? a : b));
  static double _p95(List<double> v) {
    if (v.isEmpty) return 0;
    final sorted = [...v]..sort();
    return _round1(sorted[((sorted.length - 1) * 0.95).floor()]);
  }
}
