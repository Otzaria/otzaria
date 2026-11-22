// זיהוי ממוקד של הספינר שנשאר חי בטאב PDF במצב תצוגת-ספר (מקור הרינדור
// הרציף ~48fps במנוחה): פותח את הטאב, ממתין, ומדפיס את שרשרת האבות של כל
// CircularProgressIndicator חי בעץ.
//
// הרצה: tool/perf_probe/run_perf_probe.ps1 -Target integration_test/pdf_bookview_idle_probe_test.dart

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
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:path/path.dart' as p;

import 'support/perf_pdf_reader.dart';

final _outFile = File(
  p.join(Directory.systemTemp.path, 'otzaria_perf_probe', 'spinner_diag.json'),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'pdf book-view idle spinner diag',
    timeout: const Timeout(Duration(minutes: 8)),
    (
      tester,
    ) async {
      _outFile.parent.createSync(recursive: true);
      if (_outFile.existsSync()) _outFile.deleteSync();

      app.main(const <String>[]);
      await _waitUntil(
        tester,
        () => find.byType(App).evaluate().isNotEmpty,
        description: 'application widget',
        timeout: const Duration(minutes: 3),
      );

      final ctx = tester.element(find.byType(App));
      final tabsBloc = ctx.read<TabsBloc>();
      final library = await DataRepository.instance.library;
      await _pumpFor(tester, const Duration(seconds: 8));
      tabsBloc.add(CloseAllTabs());
      await _pumpFor(tester, const Duration(seconds: 2));

      final pdfBook = library
          .getAllBooks()
          .whereType<PdfBook>()
          .where((b) => b.title.contains('ברכות') && File(b.path).existsSync())
          .firstOrNull;
      if (pdfBook == null) {
        _write({'error': 'no PDF book found'});
        throw StateError(
          'No existing PDF book containing ברכות in the library',
        );
      }

      // שחזור התרחיש המלא: טאב PDF רגיל פתוח ברקע (מתחרה על ה-worker של
      // pdfrx), ורק אז נפתח טאב תצוגת-הספר שבו נצפה הרינדור הרציף.
      final regularTab = PdfBookTab(book: pdfBook, pageNumber: 2);
      tabsBloc.add(AddTab(regularTab));
      ctx.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
      await _waitUntil(
        tester,
        () => regularTab.pdfViewerController.isReady,
        description: 'background PDF controller',
        timeout: const Duration(seconds: 90),
      );
      await _pumpFor(tester, const Duration(seconds: 5));

      final tab = PdfBookTab(book: pdfBook, pageNumber: 2)
        ..savedLayoutMode = PdfLayoutMode.bookView;
      tabsBloc.add(AddTab(tab));
      await _waitUntil(
        tester,
        () => tab.pdfViewerController.isReady,
        description: 'book-view PDF controller',
        timeout: const Duration(seconds: 90),
      );
      // זמן התייצבות ארוך — לוודא שהספינר שנצפה איננו טעינה לגיטימית שטרם תמה.
      await _pumpFor(tester, const Duration(seconds: 25));
      if (regularTab.savedLayoutMode != PdfLayoutMode.regularView ||
          tab.savedLayoutMode != PdfLayoutMode.bookView) {
        throw StateError(
          'The diagnostic requires regularView behind bookView; '
          'the installed profile overrode one of these layout modes.',
        );
      }

      final diag = <String, Object?>{
        'controllerReady': tab.pdfViewerController.isReady,
        'linksLoading': tab.linksLoadingNotifier.value,
        'pdfScreenMounted': find.byType(PdfBookScreen).evaluate().isNotEmpty,
        'layoutMode': tab.savedLayoutMode?.name,
        'visibleRenderState':
            tab.pdfViewerController.visibleRenderState.value.name,
        'spinners': <Map<String, Object?>>[],
      };
      for (final el in find.byType(CircularProgressIndicator).evaluate()) {
        final chain = <String>[];
        el.visitAncestorElements((ancestor) {
          chain.add(ancestor.widget.runtimeType.toString());
          return chain.length < 30;
        });
        (diag['spinners'] as List).add({'ancestors': chain});
      }

      // דגימת קצב פריימים בפועל במנוחה, לאימות שהספינר הוא שמניע את הרינדור.
      var frames = 0;
      void onTimings(List<FrameTiming> t) => frames += t.length;
      binding.addTimingsCallback(onTimings);
      try {
        await _pumpFor(tester, const Duration(seconds: 4));
      } finally {
        binding.removeTimingsCallback(onTimings);
      }
      diag['framesIn4s'] = frames;

      _write(diag);
    },
  );
}

void _write(Map<String, Object?> data) {
  _outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data),
    flush: true,
  );
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  required Duration timeout,
}) => waitForPdfProbeCondition(
  condition,
  description,
  timeout: timeout,
  advance: () async {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  },
);
