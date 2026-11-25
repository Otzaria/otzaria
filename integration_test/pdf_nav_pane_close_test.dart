// issues #1255 / #1258: ניווט מה-outline ואז גלגלת שסוגרת את חלונית הניווט
// חייבים להשאיר את המסמך בעמוד היעד — גם בזמן מעקב היציבות של הפתיחה, וגם
// כשהזום משתנה עם רוחב הקורא. רץ על הספרייה האמיתית (שבת.pdf).
//
// הרצה: flutter test integration_test/pdf_nav_pane_close_test.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:pdfrx/pdfrx.dart';

final _outFile = File(
  r'C:\Users\User\AppData\Local\Temp\claude\C--otzaria\387f1be1-d3ca-4f0a-a6d5-23b4b5e8315e\scratchpad\pdf_nav_pane_close.json',
);

final _log = <String>[];
final _debugLines = <String>[];

void _note(String s) {
  final line = '${DateTime.now().toIso8601String().substring(11, 23)} $s';
  _log.add(line);
  // ignore: avoid_print
  print('[PROBE] $line');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'ניווט ב-PDF וסגירת חלונית הניווט אינם מקפיצים את העמוד',
    timeout: Timeout.none,
    (tester) async {
      final origDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null &&
            (message.contains('stable-layout') ||
                message.contains('⚠️') ||
                message.contains('goToPage'))) {
          _debugLines.add(
            '${DateTime.now().toIso8601String().substring(11, 23)} $message',
          );
        }
        origDebugPrint(message, wrapWidth: wrapWidth);
      };

      app.main(const <String>[]);
      await _waitUntil(
        tester,
        () => find.byType(App).evaluate().isNotEmpty,
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
          .where((b) => b.title == 'שבת' && File(b.path).existsSync())
          .firstOrNull;
      if (pdfBook == null) {
        _write({'error': 'no שבת pdf'});
        return;
      }
      _note('pdf: ${pdfBook.path}');

      await _scenario(
        tester,
        tabsBloc,
        ctx,
        pdfBook,
        name: 'S0 immediate (tracking active), nav 81->97, wheel',
        startPage: 81,
        navTo: 97,
        closeVia: 'wheel',
        settle: const Duration(milliseconds: 300),
      );
      await _scenario(
        tester,
        tabsBloc,
        ctx,
        pdfBook,
        name: 'S1 settled, nav 81->97, close pane via notifier',
        startPage: 81,
        navTo: 97,
        closeVia: 'notifier',
      );
      await _scenario(
        tester,
        tabsBloc,
        ctx,
        pdfBook,
        name: 'S2 settled, nav 81->97, close pane via wheel',
        startPage: 81,
        navTo: 97,
        closeVia: 'wheel',
      );
      await _scenario(
        tester,
        tabsBloc,
        ctx,
        pdfBook,
        name: 'S3 settled, open at 97, no nav, close pane via notifier',
        startPage: 97,
        navTo: null,
        closeVia: 'notifier',
      );
      tabsBloc.add(CloseAllTabs());
      await _pumpFor(tester, const Duration(seconds: 1));
      _write({'log': _log, 'debug': _debugLines});
      debugPrint = origDebugPrint;
    },
  );
}

Future<void> _scenario(
  WidgetTester tester,
  TabsBloc tabsBloc,
  BuildContext ctx,
  PdfBook pdfBook, {
  required String name,
  required int startPage,
  required int? navTo,
  required String closeVia,
  Duration settle = const Duration(seconds: 10),
}) async {
  _note('=== $name ===');
  final tab = PdfBookTab(book: pdfBook, pageNumber: startPage);
  tabsBloc.add(AddTab(tab));
  ctx.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
  await _waitUntil(
    tester,
    () => tab.pdfViewerController.isReady,
    timeout: const Duration(seconds: 90),
  );
  final c = tab.pdfViewerController;
  String st() =>
      'page=${c.pageNumber} top=${c.visibleRect.top.toStringAsFixed(0)} '
      'zoom=${c.currentZoom.toStringAsFixed(3)} '
      'vw=${c.viewSize.width.toStringAsFixed(0)} '
      'left=${tab.showLeftPane.value} spin=${_spinnerCount()}';
  await _pumpFor(tester, settle);
  _note('settled ${st()}');

  tab.toggleNavPaneNotifier.value++;
  await _pumpFor(tester, const Duration(milliseconds: 800));
  _note('pane opened ${st()}');
  if (navTo != null) {
    final outline = tester.widget<OutlineView>(find.byType(OutlineView).first);
    // ignore: unawaited_futures
    outline.onNavigateToPage!(navTo);
    await _pumpFor(tester, const Duration(milliseconds: 1200));
    _note('after nav ${st()}');
  }

  if (closeVia == 'wheel') {
    final center = tester.getCenter(find.byType(PdfViewer).first);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    _note('wheel sent ${st()}');
  } else {
    tab.toggleNavPaneNotifier.value++;
    _note('notifier toggled ${st()}');
  }
  // דגימה פר-פריים.
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _note('f${i + 1} ${st()}');
  }
  await _pumpFor(tester, const Duration(seconds: 1));
  _note('final ${st()}');
  expect(c.pageNumber, navTo ?? startPage, reason: name);
  tabsBloc.add(CloseAllTabs());
  await _pumpFor(tester, const Duration(seconds: 1));
}

int _spinnerCount() => find.byType(CircularProgressIndicator).evaluate().length;

void _write(Map<String, Object?> data) {
  _outFile.parent.createSync(recursive: true);
  _outFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data),
    flush: true,
  );
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
