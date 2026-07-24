// תחקור זיכרון שלא משתחרר: מתחבר ל-VM service של התהליך עצמו ומצלם
// פרופיל הקצאות (bytes לכל class, עם GC כפוי) בשלוש נקודות — לפני פתיחת
// טאבים, אחרי פתיחת 6 ספרים, ואחרי סגירת כולם. ההפרש בין baseline ל-after_close
// חושף אילו אובייקטים נשארים חיים; הפער בין ה-RSS לסך ה-heap של ה-isolates
// חושף כמה מהזיכרון הוא נייטיבי/לא-מוחזר.
//
// הרצה: tool/perf_probe/run_perf_probe.ps1 -Target integration_test/memory_retention_probe_test.dart

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/main.dart' as app;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart' as vms_io;

final _probeDir = Directory(
  p.join(Directory.systemTemp.path, 'otzaria_perf_probe'),
);
final _heapFile = File(p.join(_probeDir.path, 'heap.jsonl'));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('memory retention probe', timeout: Timeout.none, (tester) async {
    _probeDir.createSync(recursive: true);
    if (_heapFile.existsSync()) _heapFile.deleteSync();

    final heap = _HeapProbe(_heapFile);

    // --- עלייה ---
    app.main(const <String>[]);
    await _waitUntil(
      tester,
      () => find.byType(App).evaluate().isNotEmpty,
      timeout: const Duration(minutes: 3),
      what: 'App widget',
    );
    final ctx = tester.element(find.byType(App));
    final tabsBloc = ctx.read<TabsBloc>();
    final library = await DataRepository.instance.library;

    await heap.connect();
    await _pumpFor(tester, const Duration(seconds: 12));

    // --- נקודת בסיס: אחרי עלייה וחימומים, לפני טאבים ---
    // אם שוחזרו טאבים שמורים — סוגרים אותם קודם כדי שהבסיס יהיה נקי.
    tabsBloc.add(CloseAllTabs());
    await _pumpFor(tester, const Duration(seconds: 5));
    await heap.snapshot('baseline_gc', gc: true);

    // --- פתיחת 6 ספרים + גלילה בראשון (מפעילה חימום מלא) ---
    final books = _pickTextBooks(library.getAllBooks(), 6);
    heap.note({'books': books.map((b) => b.title).toList()});
    for (final book in books) {
      openBook(ctx, book, 20, '', ignoreHistory: true);
      await _waitForCurrentTextBookLoaded(tester, tabsBloc);
      await _pumpFor(tester, const Duration(milliseconds: 500));
    }
    final firstTab = tabsBloc.state.tabs.whereType<TextBookTab>().firstOrNull;
    if (firstTab != null && firstTab.scrollController.isAttached) {
      firstTab.scrollController.scrollTo(
        index: 120,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    }
    // המתנה שהחימום ברקע יתקדם ויאכלס את הזיכרון כמו בשימוש אמיתי.
    await _pumpFor(tester, const Duration(seconds: 15));
    await heap.snapshot('tabs_open', gc: false);

    // --- סגירת כל הטאבים ---
    tabsBloc.add(CloseAllTabs());
    await _pumpFor(tester, const Duration(seconds: 10));
    await heap.snapshot('after_close_gc', gc: true);

    await _pumpFor(tester, const Duration(seconds: 8));
    await heap.snapshot('after_close_gc2', gc: true);

    await heap.dispose();
  });
}

List<TextBook> _pickTextBooks(List<Book> allBooks, int count) {
  final textBooks = allBooks.whereType<TextBook>().toList();
  const preferred = ['בראשית', 'תהלים', 'ברכות', 'שמות', 'משלי', 'דברים'];
  final picked = <TextBook>[];
  for (final title in preferred) {
    if (picked.length >= count) break;
    final match = textBooks.where((b) => b.title == title);
    if (match.isNotEmpty) picked.add(match.first);
  }
  if (picked.length < count && textBooks.isNotEmpty) {
    final step = (textBooks.length / (count + 1)).floor().clamp(1, 1 << 30);
    for (var i = 0; i < textBooks.length && picked.length < count; i += step) {
      final candidate = textBooks[i];
      if (!picked.contains(candidate)) picked.add(candidate);
    }
  }
  return picked;
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
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return true;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out after $timeout waiting for: $what');
}

Future<void> _waitForCurrentTextBookLoaded(
  WidgetTester tester,
  TabsBloc tabsBloc, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final tab = tabsBloc.state.currentTab;
    if (tab is TextBookTab && tab.bloc.state is TextBookLoaded) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// מתחבר ל-VM service של התהליך הנוכחי ומצלם heap לפי isolate ולפי class.
class _HeapProbe {
  _HeapProbe(this.outFile);

  final File outFile;
  vms.VmService? _service;

  Future<void> connect() async {
    try {
      final info = await dev.Service.getInfo();
      final httpUri = info.serverUri;
      if (httpUri == null) {
        note({'error': 'VM service URI unavailable'});
        return;
      }
      final wsUri = httpUri.replace(
        scheme: 'ws',
        path: '${httpUri.path}ws',
      );
      _service = await vms_io.vmServiceConnectUri(wsUri.toString());
      note({'connected': wsUri.toString()});
    } catch (e) {
      note({'error': 'VM service connect failed: $e'});
    }
  }

  void note(Map<String, Object?> details) {
    _append({'type': 'note', ...details});
  }

  Future<void> snapshot(String label, {required bool gc}) async {
    final record = <String, Object?>{
      'type': 'heap',
      'label': label,
      'at': DateTime.now().millisecondsSinceEpoch,
      'rssMb': _mb(ProcessInfo.currentRss),
    };
    final service = _service;
    if (service == null) {
      record['error'] = 'not connected';
      _append(record);
      return;
    }

    try {
      final vm = await service.getVM();
      final isolates = <Map<String, Object?>>[];
      for (final ref in vm.isolates ?? const <vms.IsolateRef>[]) {
        final entry = <String, Object?>{'name': ref.name};
        try {
          final mem = await service.getMemoryUsage(ref.id!);
          entry['heapMb'] = _mb(mem.heapUsage ?? 0);
          entry['capacityMb'] = _mb(mem.heapCapacity ?? 0);
          entry['externalMb'] = _mb(mem.externalUsage ?? 0);
        } catch (e) {
          entry['memError'] = '$e';
        }
        try {
          final profile = await service.getAllocationProfile(
            ref.id!,
            gc: gc ? true : null,
          );
          final members = [...?profile.members]
            ..sort(
              (a, b) => (b.bytesCurrent ?? 0).compareTo(a.bytesCurrent ?? 0),
            );
          entry['topClasses'] = members
              .take(25)
              .where((m) => (m.bytesCurrent ?? 0) > 0)
              .map(
                (m) => {
                  'class': m.classRef?.name,
                  'bytesMb': _mb(m.bytesCurrent ?? 0),
                  'instances': m.instancesCurrent,
                },
              )
              .toList();
        } catch (e) {
          entry['allocError'] = '$e';
        }
        isolates.add(entry);
      }
      record['isolates'] = isolates;
    } catch (e) {
      record['error'] = '$e';
    }
    _append(record);
  }

  Future<void> dispose() async {
    await _service?.dispose();
  }

  void _append(Map<String, Object?> record) {
    outFile.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static double _mb(int bytes) => (bytes / (1024 * 1024) * 10).round() / 10;
}
