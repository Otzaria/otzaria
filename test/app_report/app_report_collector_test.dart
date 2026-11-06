import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/diagnostics/app_context_snapshot.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/info/os_version.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final now = DateTime(2026, 9, 17, 12);
  final redactor = AppReportRedactor(
    environment: const {'USERPROFILE': r'C:\Users\Moshe', 'USERNAME': 'Moshe'},
  );

  setUp(() => tmp = Directory.systemTemp.createTempSync('otzaria_collector_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String entry(String title, DateTime at, [String body = '']) =>
      '=== $title ${at.toIso8601String()} ===\nVersion: 1\n$body\n';

  test('אבחון: מקטע שנכשל נרשם כשגיאה ושאר המקטעים נאספים ומוסתרים', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      appInfoLoader: () async => throw StateError('library not loaded'),
      currentContext: () => {'screen': 'reading', 'tabs': 3},
      errorLogPath: p.join(tmp.path, 'missing.txt'),
      clock: () => now,
    );
    final diagnostics = await collector.collectDiagnostics();
    expect(diagnostics['appInfo'], {'error': 'Bad state: library not loaded'});
    expect(diagnostics['system'], containsPair('arch', isA<String>()));
    expect(diagnostics['context'], {'screen': 'reading', 'tabs': 3});
    expect(diagnostics['startupTimeline'], contains('lines'));
    expect(() => jsonEncode(diagnostics), returnsNormally);
  });

  test('אבחון: תוצאת חימום WebView2 נכללת במצב', () async {
    WebView2CreationDiagnostics.prewarmOutcome = 'ok 12ms';
    addTearDown(WebView2CreationDiagnostics.debugReset);
    final diagnostics = await AppReportCollector(
      redactor: redactor,
      clock: () => now,
    ).collectDiagnostics();
    expect(diagnostics['state'], containsPair('webview2Prewarm', 'ok 12ms'));
  });

  test('אבחון: פרופיל המשתמש מוסתר בכל המבנה', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      appInfoLoader: () async => {
        'app': {'dataRootPath': r'C:\Users\Moshe\AppData\Roaming\otzaria'},
      },
      clock: () => now,
    );
    final diagnostics = await collector.collectDiagnostics();
    expect((diagnostics['appInfo'] as Map)['app'], {
      'dataRootPath': r'%USERPROFILE%\AppData\Roaming\otzaria',
    });
  });

  test('לוג: רק השבוע האחרון, מסודר כרונולוגית, עם לוג הסגירה', () async {
    final errors = File(p.join(tmp.path, 'errors.txt'))
      ..writeAsStringSync(
        'tail of a cut block\n'
        '${entry('Old', now.subtract(const Duration(days: 8)))}'
        '${entry('Recent A', now.subtract(const Duration(days: 2)), r'Path: C:\Users\Moshe\x')}'
        '${entry('Recent B', now.subtract(const Duration(hours: 1)))}',
      );
    final shutdown = File(p.join(tmp.path, 'shutdown.log'))
      ..writeAsStringSync(
        '${now.subtract(const Duration(days: 30)).toIso8601String()} | old\n'
        '${now.subtract(const Duration(days: 1)).toIso8601String()} | forced\n',
      );
    final collector = AppReportCollector(
      redactor: redactor,
      errorLogPath: errors.path,
      shutdownLogPath: shutdown.path,
      clock: () => now,
    );
    final log = await collector.collectErrorLog();
    expect(log, isNot(contains('Old')));
    expect(log, isNot(contains('tail of a cut block')));
    expect(log.indexOf('Recent A'), lessThan(log.indexOf('Recent B')));
    expect(log, contains(r'%USERPROFILE%\x'));
    expect(log, contains('| forced'));
    expect(log, isNot(contains('| old')));
  });

  test('לוג: קבצים חסרים מחזירים טקסט ריק', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      errorLogPath: tmp.path,
      shutdownLogPath: p.join(tmp.path, 'none.log'),
      clock: () => now,
    );
    final log = await collector.collectErrorLog();
    expect(log, isEmpty);
  });

  test('recentErrorLogExcerpt שומר את החדשות בגבול הגודל', () {
    final content = [
      for (var i = 0; i < 10; i++)
        entry('E$i', now.subtract(Duration(hours: 10 - i)), 'x' * 100),
    ].join();
    final excerpt = recentErrorLogExcerpt(
      content,
      since: now.subtract(const Duration(days: 7)),
      maxBytes: 450,
    );
    expect(excerpt, contains('E9'));
    expect(excerpt, isNot(contains('E0')));
    expect(utf8.encode(excerpt).length, lessThanOrEqualTo(450));
  });

  test('detectArch: אמולציית x64 על ARM', () {
    expect(
      AppReportCollector.detectArch(
        abi: Abi.windowsX64,
        environment: const {'PROCESSOR_IDENTIFIER': 'ARMv8 (64-bit) Family 8'},
      ),
      'x64-on-arm64',
    );
    expect(
      AppReportCollector.detectArch(
        abi: Abi.windowsX64,
        environment: const {'PROCESSOR_IDENTIFIER': 'Intel64 Family 6'},
      ),
      'x64',
    );
    expect(AppReportCollector.detectArch(abi: Abi.windowsArm64), 'arm64');
  });

  test('osVersion: הדיווח והאבחון מתקנים Windows 11 שמדווח כ-Windows 10', () {
    expect(
      AppReportCollector.osVersion(
        raw: '"Windows 10 Pro" 10.0 (Build 26100)',
        isWindows: true,
      ),
      '"Windows 11 Pro" 10.0 (Build 26100)',
    );
    expect(AppReportCollector.systemInfo()['osVersion'], displayOsVersion());
  });

  test('systemInfo כולל את נתוני הזיכרון', () {
    final info = AppReportCollector.systemInfo(
      memory: () => {'totalRamMb': 8000, 'processPeakCommitMb': 3100},
    );
    expect(info['memory'], {'totalRamMb': 8000, 'processPeakCommitMb': 3100});
  });

  test('אבחון: אוסף שנבנה כמו בתוכנה כולל את התוספים המותקנים', () async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    // ספרייה חסרה בתיקייה הזמנית: מקטע הספרייה אינו נוגע בספרייה האמיתית.
    await Settings.setValue(
      SettingsRepository.keyLibraryPath,
      p.join(tmp.path, 'books'),
    );
    AppPaths.debugOverrideDataRootPath(tmp.path);
    addTearDown(() async {
      await PluginSystemDatabase.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
    });
    await PluginRegistryRepository().savePlugin(
      InstalledPlugin(
        pluginId: 'demo.plugin',
        name: 'Demo',
        version: '1.0.0',
        installPath: tmp.path,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: PluginManifest.fromJson(const {
          'id': 'demo.plugin',
          'name': 'Demo',
          'version': '1.0.0',
          'entrypoint': 'index.html',
        }),
        installedAt: now,
        updatedAt: now,
      ),
    );

    final diagnostics = await AppReportCollector(
      redactor: redactor,
      clock: () => now,
    ).collectDiagnostics();
    final plugins = (diagnostics['appInfo'] as Map)['plugins'] as Map;
    expect(plugins['installedCount'], 1);
    expect((plugins['installed'] as List).single['id'], 'demo.plugin');
  });

  group('הקשר החלון', () {
    InstalledPlugin plugin() => InstalledPlugin(
      pluginId: 'demo.plugin',
      name: 'Demo',
      version: '2.3.4',
      installPath: tmp.path,
      entrypointPath: 'index.html',
      enabled: true,
      pinned: false,
      manifest: PluginManifest.fromJson(const {
        'id': 'demo.plugin',
        'name': 'Demo',
        'version': '2.3.4',
        'entrypoint': 'index.html',
      }),
      installedAt: now,
      updatedAt: now,
    );

    setUp(() async {
      await PluginRuntimeDispatcher.instance.prepareForAppRestart();
      PluginRuntimeDispatcher.instance.resetVisibilityForTesting();
      PluginRuntimeDispatcher.instance.discardLimitsOverride = null;
      DeveloperDiagnostics.instance.contextProvider = () => describeAppContext(
        screen: Screen.reading,
        tabs: TabsState(
          tabs: [ToolTab(toolId: 'demo.plugin', title: r'C:\Users\Moshe\Demo')],
          currentTabIndex: 0,
        ),
        pluginState: PluginSystemLoaded([plugin()]),
      );
    });
    tearDown(() async {
      DeveloperDiagnostics.instance.contextProvider = null;
      await PluginRuntimeDispatcher.instance.prepareForAppRestart();
      PluginRuntimeDispatcher.instance.resetVisibilityForTesting();
    });

    test('נאסף מהחלון הנוכחי, כולל התוסף הפתוח, ומוסתר', () async {
      final diagnostics = await AppReportCollector(
        redactor: redactor,
        appInfoLoader: () async => {},
        clock: () => now,
      ).collectDiagnostics();
      expect(diagnostics['context'], {
        'screen': 'reading',
        'tabs': 1,
        'tabsByType': {'ToolTab': 1},
        'currentTab': 'ToolTab',
        'currentTitle': r'%USERPROFILE%\Demo',
        'pluginResources': {
          'registered': 0,
          'live': 0,
          'suspended': 0,
          'released': 0,
          'discardCandidates': 0,
          'eligible': 0,
          'exempt': 0,
          'firstBlockerCounts': <String, int>{},
          'limits': {
            'maxLiveSuspended': PluginDiscardLimits.forPlatform(
              defaultTargetPlatform,
            ).maxLiveSuspended,
            'maxSuspendedAgeMs': PluginDiscardLimits.forPlatform(
              defaultTargetPlatform,
            ).maxSuspendedAge.inMilliseconds,
          },
          'instances': <Map<String, Object?>>[],
          'detailsTruncated': false,
        },
        'plugins': [
          {
            'id': 'demo.plugin',
            'version': '2.3.4',
            'source': 'packaged',
            'enabled': true,
          },
        ],
      });
    });

    test('קריסה מהפעלה קודמת: בלי הקשר החלון הנוכחי', () async {
      final diagnostics = await AppReportCollector(
        redactor: redactor,
        appInfoLoader: () async => {},
        includeCurrentContext: false,
        clock: () => now,
      ).collectDiagnostics();
      expect(diagnostics.containsKey('context'), isFalse);
      expect(diagnostics.containsKey('inputFocus'), isFalse);
    });

    test('כרטיסיית חיפוש: השאילתה לא נכנסת לכותרת', () {
      final tab = SearchingTab(
        SearchingTab.titleForQuery('שאילתה פרטית'),
        null,
      );
      addTearDown(tab.dispose);
      final context = describeAppContext(
        screen: Screen.search,
        tabs: TabsState(tabs: [tab], currentTabIndex: 0),
        pluginState: const PluginSystemLoaded([]),
      );
      expect(context['currentTab'], 'SearchingTab');
      expect(context['currentTitle'], isNull);
    });

    Map<String, Object?> contextOf(OpenedTab tab) => describeAppContext(
      screen: Screen.reading,
      tabs: TabsState(tabs: [tab], currentTabIndex: 0),
      pluginState: PluginSystemLoaded([plugin()]),
    );

    test('חלונית מפוצלת: התוסף שבחלונית מדווח', () {
      final text = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
      addTearDown(text.dispose);
      final context = contextOf(
        CombinedTab(
          rightTab: text,
          leftTab: ToolTab(toolId: 'demo.plugin', title: 'Demo'),
        ),
      );
      expect(context['currentTab'], 'CombinedTab');
      expect(context['currentTitle'], 'משולב: בראשית | Demo');
      expect(context['plugins'], [
        {
          'id': 'demo.plugin',
          'version': '2.3.4',
          'source': 'packaged',
          'enabled': true,
        },
      ]);
    });

    test('ספר אישי: הכותרת, שהיא לרוב שם הקובץ, לא נכנסת', () {
      final pdf = PdfBookTab(
        book: PdfBook(
          title: 'מסמך פרטי',
          path: 'private.pdf',
          source: BookSource.user,
        ),
        pageNumber: 1,
      );
      final text = TextBookTab(
        book: TextBook(title: 'סיכום פרטי', source: BookSource.user),
        index: 0,
      );
      addTearDown(pdf.dispose);
      addTearDown(text.dispose);
      expect(contextOf(pdf)['currentTitle'], isNull);
      expect(contextOf(text)['currentTitle'], isNull);
      expect(
        contextOf(
          CombinedTab(
            rightTab: text,
            leftTab: ToolTab(toolId: 'demo.plugin', title: 'Demo'),
          ),
        )['currentTitle'],
        isNull,
      );
    });

    test('ספר רשמי: הכותרת נשמרת', () {
      final pdf = PdfBookTab(
        book: PdfBook(title: 'ספר רשמי', path: 'official.pdf'),
        pageNumber: 1,
      );
      addTearDown(pdf.dispose);
      expect(contextOf(pdf)['currentTitle'], 'ספר רשמי');
    });

    for (final isPdf in [false, true]) {
      for (final isPrivate in [false, true]) {
        for (final isCombined in [false, true]) {
          test(
            'מפרשים ${isPdf ? 'PDF' : 'טקסט'} '
            '${isPrivate ? 'אישי' : 'רשמי'} '
            '${isCombined ? 'בפיצול' : 'עצמאי'}: פרטיות כותרת המקור בדוח',
            () async {
              await Settings.init(cacheProvider: MemorySettingsCache());
              final source = isPrivate ? BookSource.user : BookSource.official;
              final OpenedTab commentators = isPdf
                  ? PdfCommentatorsTab(
                      sourceTab: PdfBookTab(
                        book: PdfBook(
                          title: 'כותרת המקור',
                          path: 'book.pdf',
                          source: source,
                        ),
                        pageNumber: 1,
                      ),
                      disposeSourceTabOnDispose: true,
                    )
                  : CommentatorsTab(
                      sourceTab: TextBookTab(
                        book: TextBook(title: 'כותרת המקור', source: source),
                        index: 0,
                      ),
                      disposeSourceTabOnDispose: true,
                    );
              final tab = isCombined
                  ? CombinedTab(
                      rightTab: ToolTab(toolId: 'demo.plugin', title: 'Demo'),
                      leftTab: commentators,
                    )
                  : commentators;
              addTearDown(tab.dispose);
              final diagnostics = await AppReportCollector(
                redactor: redactor,
                appInfoLoader: () async => {},
                currentContext: () => contextOf(tab),
                clock: () => now,
              ).collectDiagnostics();
              final context = diagnostics['context'] as Map;
              expect(context['currentTitle'], isPrivate ? isNull : tab.title);
              expect(
                jsonEncode(diagnostics).contains('כותרת המקור'),
                !isPrivate,
              );
            },
          );
        }
      }
    }

    group('חיפוש בספר (#3574)', () {
      const query = 'שאילתה פרטית מאוד';
      const bookLine = 'טקסט הספר הסודי';

      TextBookTab loadedTab({
        required String searchText,
        BookSource source = BookSource.official,
        String highlightText = '',
        int? permanentHighlightLine,
      }) {
        final book = TextBook(title: 'ספר הבדיקה', source: source);
        return TextBookTab(
          book: book,
          index: 0,
          blocOverride: _FakeTextBookBloc(
            TextBookLoaded(
              book: book,
              showLeftPane: false,
              content: const [bookLine, 'קצר', ''],
              fontSize: 18,
              showSplitView: false,
              activeCommentators: const ['רש"י', 'תוספות'],
              commentatorGroups: const [],
              availableCommentators: const [],
              links: const [],
              visibleLinks: const [],
              linksByLine: const {},
              tableOfContents: const [],
              removeNikud: false,
              removePunctuation: false,
              visibleIndices: const [0],
              selectedIndex: 0,
              pinLeftPane: false,
              continuousReadingMode: true,
              highlightText: highlightText,
              permanentHighlightLine: permanentHighlightLine,
              searchText: searchText,
              searchMode: SearchMode.advanced,
              searchDistance: 3,
              searchWholeWord: false,
              searchResultLines: const {0, 2},
              searchOptions: const {
                'שאילתה_0': {
                  'חלק ממילה': true,
                  'קידומות': true,
                  'אפשרות-סודית': true,
                },
                'פרטית_1': {'חלק ממילה': true, 'סיומות': false},
              },
              alternativeWords: const {
                1: ['חלופה'],
              },
              spacingValues: const {'0-1': '5', '1-2': ' '},
              matchPolicy: const SearchMatchPolicy(
                proximityScope: SearchScope.sameParagraph,
                wordMatchMode: WordMatchMode.atLeast,
              ),
            ),
          ),
        );
      }

      test('חיפוש פעיל: מצב, אפשרויות ותצוגה — בלי השאילתה ובלי הספר', () {
        final tab = loadedTab(searchText: query);
        addTearDown(tab.dispose);
        final context = contextOf(tab);
        expect(context['readers'], [
          {
            'kind': 'text',
            'state': 'loaded',
            'view': 'combined',
            'continuousReading': true,
            'commentators': 2,
            'lines': 3,
            'maxLineChars': bookLine.length,
            'partiallyLoaded': false,
            'removeNikud': false,
            'pinpointHighlight': false,
            'searchActive': true,
            'search': {
              'mode': 'advanced',
              'origin': 'inBook',
              'distance': 3,
              'queryChars': query.length,
              'queryWords': 3,
              'slashWrapped': false,
              'hasQuotes': false,
              'wholeWord': false,
              'partialWordHighlight': true,
              'wordOptions': {
                'word.partial': 2,
                'word.prefixes': 1,
                'other': 1,
              },
              'alternativeWords': 1,
              'customSpacing': 1,
              'matchPolicy': {
                'querySemantics': 'regular',
                'proximityScope': 'sameParagraph',
                'wordMatchMode': 'atLeast',
                'wordMatchCount': 2,
              },
              'resultLines': 2,
            },
          },
        ]);
        final encoded = jsonEncode(context);
        for (final secret in [
          query,
          'שאילתה',
          'פרטית',
          'מאוד',
          'חלופה',
          'אפשרות-סודית',
          'חלק ממילה',
          bookLine,
          'קצר',
          'תוספות',
          'רש"י',
        ]) {
          expect(encoded.contains(secret), isFalse, reason: secret);
        }
      });

      test('בלי חיפוש: searchActive=false ובלי פרטי חיפוש', () {
        final tab = loadedTab(searchText: '');
        addTearDown(tab.dispose);
        final reader = (contextOf(tab)['readers'] as List).single as Map;
        expect(reader['searchActive'], isFalse);
        expect(reader.containsKey('search'), isFalse);
      });

      test('שורה צהובה: אורך ההדגשה ומספר מילותיה, בלי הטקסט', () {
        const highlight = 'הדגשה מתוצאת חיפוש';
        final tab = loadedTab(
          searchText: '',
          highlightText: highlight,
          permanentHighlightLine: 1,
        );
        addTearDown(tab.dispose);
        final context = contextOf(tab);
        final reader = (context['readers'] as List).single as Map;
        expect(reader['highlightChars'], highlight.length);
        expect(reader['highlightWords'], 3);
        expect(jsonEncode(context).contains('הדגשה'), isFalse);
      });

      test('ספר אישי: הכותרת מוסתרת גם כשמצב החיפוש מדווח', () {
        final tab = loadedTab(searchText: query, source: BookSource.user);
        addTearDown(tab.dispose);
        final context = contextOf(tab);
        expect(context['currentTitle'], isNull);
        expect(
          ((context['readers'] as List).single as Map)['searchActive'],
          isTrue,
        );
        expect(jsonEncode(context).contains('ספר הבדיקה'), isFalse);
      });

      test('טאב שטרם נטען ו-PDF: מצב החיפוש מהתצורה, בלי השאילתה', () {
        final text = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 0,
          searchText: '/$query/',
          searchMode: SearchMode.fuzzy,
          showPageShapeView: true,
        );
        final pdf = PdfBookTab(
          book: PdfBook(title: 'ספר רשמי', path: 'official.pdf'),
          pageNumber: 1,
          searchText: '"$query"',
        );
        final tab = CombinedTab(rightTab: text, leftTab: pdf);
        addTearDown(tab.dispose);
        final context = contextOf(tab);
        final readers = (context['readers'] as List).cast<Map>();
        expect(readers[0]['state'], 'initial');
        expect(readers[0]['view'], 'pageShape');
        expect((readers[0]['search'] as Map)['mode'], 'fuzzy');
        expect((readers[0]['search'] as Map)['slashWrapped'], isTrue);
        expect(readers[1]['kind'], 'pdf');
        expect((readers[1]['search'] as Map)['hasQuotes'], isTrue);
        final encoded = jsonEncode(context);
        for (final word in query.split(' ')) {
          expect(encoded.contains(word), isFalse, reason: word);
        }
      });

      test('כרטיסייה שאינה קורא: אין מפתח readers', () {
        final context = contextOf(ToolTab(toolId: 'demo.plugin', title: 'X'));
        expect(context.containsKey('readers'), isFalse);
      });
    });
  });
}

class _FakeTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _FakeTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
