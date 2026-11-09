import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/services/plugin_file_drop_service.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/reports/bloc/book_report_draft_cubit.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/reports/view_scope.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart';
import 'package:otzaria/settings/panels/error_reports_panel.dart';
import 'package:otzaria/settings/panels/reports_card.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

import 'reporting_test_pump.dart';

class _Collector extends AppReportCollector {
  @override
  Future<AppReportAttachments> collect() async => const AppReportAttachments(
    diagnostics: {'appVersion': 'QA screenshot', 'platform': 'Linux'},
    errorLog: 'Sample diagnostic log for a rendering test.',
  );
}

void visualTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await reportIo(tester, UserStateDatabase.instance.flushWrites);
      // Saving the sender email writes Hive from a form callback. Hive retains
      // that write's Future, so close it while its FakeAsync zone still pumps.
      // An outer tearDown cannot run late listeners in an already-finished zone.
      await reportIo(tester, Hive.close);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final clients = <http.Client>[];
  final screenshotRoot =
      Platform.environment['REPORT_QA_OUTPUT_DIR'] ?? 'build/report-forms-qa';
  const boundaryKey = ValueKey('qa-rendered-app-boundary');

  setUpAll(() async {
    // Load real bundled fonts and icon faces. Flutter tests otherwise use Ahem.
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final loadedFonts = <String>{};
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final family = entry['family'] as String;
      if (family == 'Rubik' ||
          family == 'FrankRuhlCLM' ||
          family.contains('FluentSystemIcons') ||
          family.contains('OtzariaIcons')) {
        final loader = FontLoader(family);
        for (final font in (entry['fonts'] as List).cast<Map>()) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
        loadedFonts.add(family);
      }
    }
    expect(loadedFonts, containsAll(['Rubik', 'FrankRuhlCLM']));
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final sdkFonts = flutterRoot == null
        ? p.normalize(
            p.join(
              p.dirname(Platform.resolvedExecutable),
              '..',
              '..',
              'material_fonts',
            ),
          )
        : p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts');
    final roboto = FontLoader('Roboto');
    for (final name in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
      roboto.addFont(
        File('$sdkFonts/$name').readAsBytes().then(ByteData.sublistView),
      );
    }
    await roboto.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '$sdkFonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await material.load();
    await Directory(screenshotRoot).create(recursive: true);
    await File(p.join(screenshotRoot, 'rendering-context.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'renderer': 'Flutter widget tests',
        'hostPlatform': Platform.operatingSystem,
        'commit': Platform.environment['REPORT_QA_COMMIT'],
        'dartVersion': Platform.version,
        'fonts': ['Roboto', 'Rubik', 'FrankRuhlCLM', 'bundled icon faces'],
        'pixelRatio': 1.5,
        'capture':
            'Actual reporting/settings widgets with temporary SQLite data',
        'nativeWindowsRun': false,
      }),
    );
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qa_reporting_visual_');
    Hive.init(temp.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    RunnerWindowChannel.debugSupportedOverride = false;
    AppPaths.debugOverrideDataRootPath(temp.path);
    UserStateDatabase.instance.overridePath(p.join(temp.path, 'user_state.db'));
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      p.join(temp.path, 'databases'),
    );
    await Settings.setValue<String>(
      SettingsRepository.keyFontFamily,
      'FrankRuhlCLM',
    );
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
    await Settings.setValue<bool>(
      SettingsRepository.keyQueueErrorReportsWhenOffline,
      true,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      '',
    );
  });

  tearDown(() async {
    UiSnack.hide();
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await PersonalNotesDatabase.instance.close();
    PluginSystemDatabase.instance.resetForTests();
    UserStateDatabase.instance.close();
    await Hive.close();
    RunnerWindowChannel.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  ThemeData theme() {
    final base = AppThemeData.light(
      AppThemeData.createColorScheme(
        AppSeedColors.defaultLight,
        Brightness.light,
      ),
      compactMenuMode: false,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Rubik'],
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Rubik'],
      ),
    );
  }

  Future<void> mount(
    WidgetTester tester,
    SettingsLanguage language,
    Widget child, {
    Size size = const Size(1100, 760),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => Settings.setValue<String>(
        SettingsRepository.keySettingsLanguage,
        language.code,
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: const [
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          theme: theme(),
          home: SettingsTextScope(
            language: language,
            child: Directionality(
              textDirection: language.textDirection,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> nativeWork(WidgetTester tester) async {
    // Sending and saving render a spinner while native SQLite work completes.
    // A fake-time-only settle cannot finish that I/O on a busy runner.
    for (var attempt = 0; attempt < 200; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame) {
        return;
      }
    }
    fail('The reporting UI must settle after native I/O completes.');
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    if (name.startsWith('book-report-low-')) {
      final header = tester.getRect(find.byType(AppDialogHeader));
      final viewport = tester.getRect(find.byKey(boundaryKey));
      expect(header.top, greaterThanOrEqualTo(viewport.top));
      expect(header.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(header.left, greaterThanOrEqualTo(viewport.left));
      expect(header.right, lessThanOrEqualTo(viewport.right));
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    await tester.runAsync(() async {
      final rendered = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$screenshotRoot/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      rendered.dispose();
    });
    expect(
      tester.takeException(),
      isNull,
      reason: 'The real widget must render without overflow or assertions.',
    );
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> click(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await nativeWork(tester);
  }

  Future<void> clearSnack(WidgetTester tester) async {
    UiSnack.hide();
    await tester.pumpAndSettle();
  }

  visualTest(
    'settings really hides the empty draft area and updates first/last draft',
    (tester) async {
      await mount(
        tester,
        SettingsLanguage.hebrew,
        const Scaffold(
          body: SingleChildScrollView(
            child: Center(child: SizedBox(width: 900, child: ReportsCard())),
          ),
        ),
      );
      await nativeWork(tester);
      expect(find.byKey(const ValueKey('report-drafts-section')), findsNothing);
      await capture(tester, 'settings-no-drafts-he');

      await tester.runAsync(() async {
        await ReportDraftStore.instance.write(
          id: 'qa-book',
          kind: ReportDraftStore.bookKind,
          title: 'משנה אבות',
          revision: 0,
          payload: {
            'target': {
              'bookTitle': 'משנה אבות',
              'currentRef': 'פרק א, משנה א',
              'lineNumber': 12,
            },
            'form': {
              'details': 'יש לבדוק את האיות במילים שסומנו; ההצעה עדיין חלקית.',
            },
          },
        );
        await ReportDraftStore.instance.write(
          id: 'qa-app',
          kind: ReportDraftStore.appKind,
          title: 'החיפוש אינו מחזיר תוצאות',
          revision: 0,
          payload: {
            'description':
                'טיוטה חלקית: יש לצרף צילום מסך לאחר חזרה לחלון החיפוש.',
          },
        );
      });
      await nativeWork(tester);
      expect(
        find.byKey(const ValueKey('report-drafts-section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('report-draft-qa-book')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('report-draft-qa-app')), findsOneWidget);
      await capture(tester, 'settings-with-drafts-he');

      for (final id in ['qa-book', 'qa-app']) {
        final discard = find.byKey(ValueKey('discard-draft-$id'));
        await tester.ensureVisible(discard);
        await tester.tap(discard);
        await nativeWork(tester);
      }
      expect(find.byKey(const ValueKey('report-drafts-section')), findsNothing);
      await capture(tester, 'settings-after-last-draft-removed-he');
    },
  );

  for (final language in SettingsLanguage.values) {
    visualTest(
      'focus without typing creates no book draft in ${language.code}',
      (tester) async {
        late BuildContext openContext;
        await mount(
          tester,
          language,
          Scaffold(
            body: Builder(
              builder: (context) {
                openContext = context;
                return const SizedBox();
              },
            ),
          ),
        );
        Future<void>? reporting;
        await tester.runAsync(() async {
          reporting = ErrorReportHelper.showErrorReportDialog(
            context: openContext,
            selectedText: 'טקסט',
            state: null,
            fontSize: 18,
            bookTitle: 'ספר בדיקה',
            reportBook: TextBook(title: 'ספר בדיקה'),
            savedSelectedIndex: 0,
            reportContent: const ['טקסט מקורי לבדיקה'],
          );
        });
        await waitForReportDialog(
          tester,
          dialog: find.byType(TabbedReportDialog),
        );
        expect(find.byType(TabbedReportDialog), findsOneWidget);
        final details = find.byKey(const ValueKey('report-details-field'));
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pump();
        final editor = tester.widget<EditableText>(
          find.descendant(of: details, matching: find.byType(EditableText)),
        );
        editor.controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('book-report-save-draft')));
        await finishReportDialog(
          tester,
          dialog: find.byType(TabbedReportDialog),
          reporting: reporting!,
        );
        expect(find.byType(TabbedReportDialog), findsNothing);
        expect(
          await tester.runAsync(() => ReportDraftStore.instance.list()),
          isEmpty,
        );
      },
    );

    visualTest(
      'book report and pinned actions render in a low ${language.code} window',
      (tester) async {
        late BuildContext openContext;
        await mount(
          tester,
          language,
          Scaffold(
            body: Builder(
              builder: (context) {
                openContext = context;
                return const SizedBox();
              },
            ),
          ),
          size: const Size(1100, 360),
        );
        Future<void>? reporting;
        await tester.runAsync(() async {
          reporting = ErrorReportHelper.showErrorReportDialog(
            context: openContext,
            selectedText: 'העמידו תלמידים',
            state: null,
            fontSize: 20,
            bookTitle: 'משנה אבות',
            reportBook: TextBook(title: 'משנה אבות'),
            savedSelectedIndex: 11,
            reportContent: [
              ...List.filled(11, 'הקשר קודם'),
              'הוו מתונים בדין והעמידו תלמידים הרבה ועשו סייג לתורה.',
            ],
          );
        });
        await waitForReportDialog(
          tester,
          dialog: find.byType(TabbedReportDialog),
        );
        expect(find.byType(TabbedReportDialog), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.byType(TabbedReportDialog))),
          language.textDirection,
        );
        expect(
          Localizations.localeOf(
            tester.element(find.byType(TabbedReportDialog)),
          ).languageCode,
          language.code,
        );
        if (language == SettingsLanguage.english) {
          expect(
            MaterialLocalizations.of(
              tester.element(find.byType(TabbedReportDialog)),
            ).copyButtonLabel,
            'Copy',
          );
        }
        final quote = find.byKey(const ValueKey('report-location-quote'));
        await tester.ensureVisible(quote);
        await tester.pumpAndSettle();
        expect(quote.hitTestable(), findsOneWidget);
        await capture(tester, 'book-report-low-${language.code}-quote');
        final quoteText = tester.widget<Text>(quote);
        expect(
          quoteText.textDirection,
          TextDirection.rtl,
          reason:
              'A Hebrew quote keeps its reading direction inside English form labels.',
        );
        expect(
          quoteText.textSpan!.toPlainText(),
          'הוו מתונים בדין והעמידו תלמידים הרבה ועשו סייג לתורה.',
        );
        final quoteParagraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: quote, matching: find.byType(RichText)),
        );
        expect(quoteParagraph.textDirection, TextDirection.rtl);
        final details = find.byKey(const ValueKey('report-details-field'));
        await tester.ensureVisible(details);
        await tester.enterText(
          details,
          language == SettingsLanguage.english
              ? 'Please compare this wording with the source edition. The marked words locate the report exactly.'
              : 'יש להשוות את הנוסח למהדורת המקור. המילים שסומנו מציינות במדויק את מקום הדיווח.',
        );
        await tester.pump();
        await capture(tester, 'book-report-low-${language.code}-details');
        final leave = find.byKey(const ValueKey('book-report-save-draft'));
        expect(leave.hitTestable(), findsOneWidget);
        await tester.tap(leave);
        await finishReportDialog(
          tester,
          dialog: find.byType(TabbedReportDialog),
          reporting: reporting!,
        );
        expect(
          (await tester.runAsync(() => ReportDraftStore.instance.list()))!,
          hasLength(1),
        );
        UiSnack.hide();
        await tester.pump(const Duration(seconds: 5));
      },
    );
  }

  visualTest(
    'software form renders English labels and preserves typed Hebrew in a low window',
    (tester) async {
      late BuildContext openContext;
      await mount(
        tester,
        SettingsLanguage.english,
        Scaffold(
          body: Builder(
            builder: (context) {
              openContext = context;
              return const SizedBox();
            },
          ),
        ),
        size: const Size(1100, 420),
      );
      Future<AppReportDeliveryResult?>? reporting;
      await tester.runAsync(() async {
        reporting = showAppReportDialog(
          openContext,
          createBloc: () => AppReportBloc(
            trigger: AppReportTrigger.manual,
            collector: _Collector(),
            redactor: AppReportRedactor(environment: const {}),
            appVersion: '0.9.98',
          ),
        );
      });
      await waitForReportDialog(
        tester,
        dialog: find.byType(AppReportDialog),
      );
      expect(find.byType(AppReportDialog), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('app-report-title')),
        'שגיאה לאחר חיפוש',
      );
      await tester.pump();
      await capture(tester, 'software-report-low-en');
      final descriptionLabel = find.text('What happened?');
      expect(descriptionLabel, findsOneWidget);
      await tester.ensureVisible(descriptionLabel);
      await tester.pumpAndSettle();
      expect(descriptionLabel.hitTestable(), findsOneWidget);
      await capture(tester, 'software-report-low-en-description');
      final imagePrompt = find.text(
        PluginFileDropService.isSupported
            ? 'Paste, drop, or click to choose an image'
            : 'Paste or click to choose an image',
      );
      expect(imagePrompt, findsOneWidget);
      await tester.ensureVisible(imagePrompt);
      await tester.pumpAndSettle();
      expect(imagePrompt.hitTestable(), findsOneWidget);
      await capture(tester, 'software-report-low-en-attachments');
      expect(
        Localizations.localeOf(
          tester.element(find.byType(AppReportDialog)),
        ).languageCode,
        'en',
      );
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
      final titleField = find.byKey(const ValueKey('app-report-title'));
      await tester.ensureVisible(titleField);
      await tester.pumpAndSettle();
      final titleEditor = tester.widget<EditableText>(
        find.descendant(of: titleField, matching: find.byType(EditableText)),
      );
      titleEditor.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: titleEditor.controller.text.length,
      );
      await tester.pump();
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final position = tester.getCenter(titleField);
      await gesture.moveTo(position);
      await gesture.down(position);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      for (final label in ['Cut', 'Copy', 'Paste', 'Select All']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Copy'));
      await nativeWork(tester);
      expect(copied, 'שגיאה לאחר חיפוש');
      expect(titleEditor.controller.text, 'שגיאה לאחר חיפוש');
      final leave = find.byKey(const ValueKey('app-report-save-draft'));
      expect(leave.hitTestable(), findsOneWidget);
      await tester.tap(leave);
      await finishReportDialog(
        tester,
        dialog: find.byType(AppReportDialog),
        reporting: reporting!,
      );
      final records = await tester.runAsync(
        () => ReportDraftStore.instance.list(),
      );
      expect(records!.single.payload['title'], 'שגיאה לאחר חיפוש');
      UiSnack.hide();
      await tester.pump(const Duration(seconds: 5));
    },
  );

  visualTest(
    'actual app form shows validation, rejection, draft and queue feedback in English',
    (tester) async {
      await tester.runAsync(
        () => Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false),
      );
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{"error":"invalid","field":"title"}', 422);
      });
      clients.add(client);
      final service = AppReportService(client: client);
      await mount(
        tester,
        SettingsLanguage.english,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppReportDialog(
                context,
                createBloc: () => AppReportBloc(
                  trigger: AppReportTrigger.manual,
                  service: service,
                  collector: _Collector(),
                  redactor: AppReportRedactor(environment: const {}),
                  appVersion: 'qa',
                ),
              ),
              child: const Text('open actual report'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open actual report'));
      await nativeWork(tester);
      await click(tester, 'app-report-send');
      expect(find.text('Enter a report title.'), findsOneWidget);
      await clearSnack(tester);
      await enter(tester, 'app-report-title', 'כותרת המשתמש נשמרת');
      await click(tester, 'app-report-send');
      expect(
        find.text('Describe the problem so we can investigate it.'),
        findsOneWidget,
      );
      await clearSnack(tester);
      await enter(tester, 'app-report-description', 'תיאור המשתמש אינו מתורגם');
      await click(tester, 'app-report-send');
      expect(
        find.text('Enter a valid email address so we can contact you.'),
        findsOneWidget,
      );
      await clearSnack(tester);
      await enter(tester, 'app-report-email', 'invalid@');
      await click(tester, 'app-report-send');
      expect(find.text('The email address is invalid.'), findsOneWidget);
      await clearSnack(tester);
      await enter(tester, 'app-report-email', 'qa@example.com');
      await click(tester, 'app-report-send');
      expect(
        find.text(
          'Sending did not finish. Your content remains in the draft and can be edited or queued.',
        ),
        findsOneWidget,
      );
      expect(requests, 1);
      expect(
        Settings.getValue<String>(SettingsRepository.keyErrorReportSenderEmail),
        'qa@example.com',
      );
      await clearSnack(tester);
      await click(tester, 'app-report-save-draft');
      expect(find.byType(AppReportDialog), findsNothing);
      expect(
        find.text(
          'The draft was saved. It will reopen next time you open the report form.',
        ),
        findsOneWidget,
      );
      final draft = (await tester.runAsync(
        () => ReportDraftStore.instance.list(),
      ))!.single;
      expect(draft.payload['title'], 'כותרת המשתמש נשמרת');
      expect(draft.payload['description'], 'תיאור המשתמש אינו מתורגם');
      await clearSnack(tester);
      await tester.tap(find.text('open actual report'));
      await nativeWork(tester);
      await click(tester, 'app-report-queue');
      expect(find.byType(AppReportDialog), findsNothing);
      expect(
        find.text(
          'The report was queued. You can manage or export it in Settings.',
        ),
        findsOneWidget,
      );
      expect(
        (await tester.runAsync(
          () => service.getPendingReports(),
        ))!.single.title,
        'כותרת המשתמש נשמרת',
      );
      expect(
        await tester.runAsync(() => ReportDraftStore.instance.list()),
        isEmpty,
      );
      expect(requests, 1);
      await clearSnack(tester);
      await tester.pump(const Duration(seconds: 7));
    },
  );

  visualTest('עריכת כותרת בתור שומרת dump ישן של 12 MiB', (tester) async {
    final raw = Uint8List(12 * 1024 * 1024)
      ..setRange(0, 4, ascii.encode('MDMP'));
    final original = AppReport(
      schema: 1,
      reportId: 'legacy-dump-edit',
      type: AppReportType.crash,
      trigger: AppReportTrigger.crashPrompt,
      title: 'קריסה',
      appVersion: 'qa',
      platform: 'windows',
      createdAt: DateTime.utc(2026, 11, 5),
      minidump: AppReportMinidump(
        gzipBytes: Uint8List.fromList(gzip.encode(raw)),
        fileName: 'legacy-crash.dmp',
      ),
    );
    final service = AppReportService();
    await tester.runAsync(() => service.queueReport(original));
    await mount(
      tester,
      SettingsLanguage.hebrew,
      Scaffold(
        body: SingleChildScrollView(
          child: AppReportsPanel(
            isOfflineMode: true,
            crashReportMode: AppCrashReportMode.ask,
            onCrashReportModeChanged: (_) {},
            service: service,
          ),
        ),
      ),
    );
    await nativeWork(tester);
    final queue = find.text('ניהול דיווחים שמורים');
    await tester.ensureVisible(queue);
    await tester.tap(queue);
    await nativeWork(tester);
    final edit = find.text('ערוך');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await nativeWork(tester);
    await enter(tester, 'app-report-edit-title', 'קריסה מתוקנת');
    await tester.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text('שמור'),
      ),
    );
    await nativeWork(tester);
    final saved = (await tester.runAsync(service.getPendingReports))!.single;
    expect(saved.title, 'קריסה מתוקנת');
    expect(saved.schema, 1);
    expect(saved.minidump!.toJson(), original.minidump!.toJson());
    expect(saved.validate(), isNull);
    await clearSnack(tester);
  });

  for (final language in [SettingsLanguage.hebrew, SettingsLanguage.english]) {
    visualTest(
      'saved software edit keeps fields, attachments, actions and validation accessible in a low ${language.code} window',
      (tester) async {
        String label(String text) =>
            resolveSettingsText(text, language: language);
        final image = AppReportImage(
          fileName: 'screenshot.png',
          mimeType: 'image/png',
          bytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOwSdnyHwAEiAJU2GM8WwAAAABJRU5ErkJggg==',
          ),
        );
        final original = AppReport(
          reportId: 'qa-edit-software',
          type: AppReportType.bug,
          trigger: AppReportTrigger.manual,
          title: 'תוכן המשתמש נשאר בעברית',
          description: List.filled(12, 'תיאור ארוך שנשמר בתור').join('\n'),
          stepsToReproduce: List.filled(12, 'שלב נוסף לשחזור').join('\n'),
          reporterEmail: 'qa@example.com',
          appVersion: 'qa',
          platform: 'linux',
          createdAt: DateTime.utc(2026, 11, 5),
          images: [image],
        );
        final service = AppReportService();
        final queued = (await tester.runAsync(
          () => service.queueReport(original),
        ))!;
        expect(queued.toJson(), original.toJson()..['schema'] = queued.schema);
        await mount(
          tester,
          language,
          Scaffold(
            body: SingleChildScrollView(
              child: AppReportsPanel(
                isOfflineMode: true,
                crashReportMode: AppCrashReportMode.ask,
                onCrashReportModeChanged: (_) {},
                service: service,
              ),
            ),
          ),
          size: const Size(1100, 360),
        );
        await nativeWork(tester);
        final queue = find.text(
          resolveSettingsText(
            'ניהול דיווחים שמורים',
            language: language,
          ),
        );
        await tester.ensureVisible(queue);
        await tester.tap(queue);
        await nativeWork(tester);
        final edit = find.text(label('ערוך'));
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await nativeWork(tester);
        expect(find.byType(AppReportEditFields), findsOneWidget);
        await capture(tester, 'software-queue-edit-low-${language.code}-top');
        expect(find.text(label('כותרת')), findsOneWidget);
        expect(find.text(label('תיאור')), findsOneWidget);
        final save = find.descendant(
          of: find.byType(AppDialog),
          matching: find.text(label('שמור')),
        );
        final cancel = find.descendant(
          of: find.byType(AppDialog),
          matching: find.text(label('ביטול')),
        );
        expect(save.hitTestable(), findsOneWidget);
        expect(cancel.hitTestable(), findsOneWidget);
        final editScroll = find.ancestor(
          of: find.byType(AppReportEditFields),
          matching: find.byType(PanelScrollableContent),
        );
        expect(editScroll, findsOneWidget);
        expect(
          tester.widget<PanelScrollableContent>(editScroll).thumbVisibility,
          isTrue,
        );
        final outerPosition = tester
            .state<ScrollableState>(
              find
                  .descendant(of: editScroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        expect(outerPosition.maxScrollExtent, greaterThan(0));
        for (final fieldName in ['title', 'description', 'steps', 'email']) {
          final field = find.byKey(ValueKey('app-report-edit-$fieldName'));
          final decoration = tester
              .widget<InputDecorator>(
                find.descendant(
                  of: field,
                  matching: find.byType(InputDecorator),
                ),
              )
              .decoration;
          expect(decoration.filled, isTrue, reason: fieldName);
          expect(
            decoration.fillColor,
            AppSurfaces.card(tester.element(field)),
            reason: fieldName,
          );
          if (fieldName == 'description' || fieldName == 'steps') {
            final fieldPosition = tester
                .state<ScrollableState>(
                  find.descendant(of: field, matching: find.byType(Scrollable)),
                )
                .position;
            expect(
              fieldPosition.maxScrollExtent,
              closeTo(0, 0.01),
              reason:
                  '$fieldName grows with its text instead of scrolling inside.',
            );
          }
        }
        final description = find.byKey(
          const ValueKey('app-report-edit-description'),
        );
        final visibleDescription = tester
            .getRect(description)
            .intersect(
              tester.getRect(editScroll),
            );
        expect(visibleDescription.height, greaterThan(0));
        final beforeWheel = outerPosition.pixels;
        final mouse = TestPointer(41, PointerDeviceKind.mouse)
          ..hover(visibleDescription.center);
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
        await tester.pump();
        expect(
          outerPosition.pixels,
          greaterThan(beforeWheel),
          reason:
              'A wheel event over the long field must move the dialog body.',
        );
        expect(save.hitTestable(), findsOneWidget);
        expect(cancel.hitTestable(), findsOneWidget);
        await enter(tester, 'app-report-edit-email', 'invalid@');
        final removeImage = find.byKey(
          const ValueKey('app-report-image-remove'),
        );
        await tester.ensureVisible(removeImage);
        await tester.pumpAndSettle();
        expect(removeImage.hitTestable(), findsOneWidget);
        expect(save.hitTestable(), findsOneWidget);
        expect(cancel.hitTestable(), findsOneWidget);
        await capture(
          tester,
          'software-queue-edit-low-${language.code}-attachments',
        );
        await tester.tap(save);
        await nativeWork(tester);
        expect(find.byType(AppReportEditFields), findsNothing);
        expect(
          find.text(label(ReportMessages.appReportInvalidEmail)),
          findsOneWidget,
        );
        expect(
          (await tester.runAsync(service.getPendingReports))!.single.toJson(),
          queued.toJson(),
        );
        await clearSnack(tester);
      },
    );
  }

  visualTest(
    'saved free-text book edit scrolls long content and keeps English fields and pinned actions',
    (tester) async {
      final report = DirectErrorReport(
        id: 'qa-book-edit',
        senderEmail: 'qa@example.com',
        subject: 'דיווח טעות',
        bookTitle: 'ספר בדיקה',
        currentRef: 'פרק א',
        lineNumber: 12,
        selectedText: List.filled(12, 'הטקסט המקורי שנבחר').join('\n'),
        errorDetails: List.filled(12, 'פירוט ארוך של הטעות').join('\n'),
        contextText: List.filled(12, 'הקשר מקורי ארוך').join('\n'),
        createdAt: DateTime.utc(2026, 11, 5),
      );
      final service = DirectErrorReportService();
      await tester.runAsync(() => service.queueReport(report));
      await mount(
        tester,
        SettingsLanguage.english,
        const Scaffold(
          body: SingleChildScrollView(
            child: ErrorReportsPanel(isOfflineMode: true),
          ),
        ),
        size: const Size(1100, 360),
      );
      await nativeWork(tester);
      final queue = find.text(
        resolveSettingsText(
          'ניהול דיווחים שמורים',
          language: SettingsLanguage.english,
        ),
      );
      await tester.ensureVisible(queue);
      await tester.tap(queue);
      await nativeWork(tester);
      final edit = find.text('Edit').last;
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await nativeWork(tester);
      expect(find.byType(AppDialog), findsOneWidget);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('book-report-edit-scroll')),
      );
      final selectedLabel = tester.getRect(find.text('The Selected Text'));
      expect(
        selectedLabel.top,
        greaterThanOrEqualTo(viewport.top),
        reason:
            'The floating label must not be clipped by the scroll viewport.',
      );
      expect(selectedLabel.bottom, lessThanOrEqualTo(viewport.bottom));
      await capture(tester, 'book-queue-edit-low-en-top');
      for (final label in [
        'The Selected Text',
        'What needs to be corrected?',
        'Context',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final dialog = find.byType(AppDialog);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(3));
      final contextField = fields.at(2);
      await tester.ensureVisible(contextField);
      await tester.enterText(contextField, 'הקשר מדויק לאחר עריכה');
      await tester.pumpAndSettle();
      final save = find.descendant(of: dialog, matching: find.text('Save'));
      expect(save.hitTestable(), findsOneWidget);
      expect(contextField.hitTestable(), findsOneWidget);
      await capture(tester, 'book-queue-edit-low-en-context');
      await tester.tap(save);
      await nativeWork(tester);
      expect(find.byType(AppDialog), findsNothing);
      expect(
        find.text(
          resolveSettingsText(
            ReportMessages.reportUpdated,
            language: SettingsLanguage.english,
          ),
        ),
        findsOneWidget,
      );
      final updated = (await tester.runAsync(
        service.getPendingReports,
      ))!.single;
      expect(updated.contextText, 'הקשר מדויק לאחר עריכה');
      expect(updated.errorDetails, report.errorDetails);
      expect(updated.selectedText, report.selectedText);
      await clearSnack(tester);

      final editAgain = find.text('Edit').last;
      await tester.ensureVisible(editAgain);
      await tester.tap(editAgain);
      await nativeWork(tester);
      await enter(tester, 'book-report-edit-details', '');
      await tester.tap(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.text('Save'),
        ),
      );
      await nativeWork(tester);
      expect(
        find.text(
          resolveSettingsText(
            ReportMessages.detailsRequired,
            language: SettingsLanguage.english,
          ),
        ),
        findsOneWidget,
      );
      expect(
        (await tester.runAsync(service.getPendingReports))!.single.toJson(),
        updated.toJson(),
      );
      await clearSnack(tester);
    },
  );

  visualTest(
    'every known report-service template and form failure resolves to English',
    (tester) async {
      final sourceMessages = [
        ReportMessages.correctionNotSupportedByServer('אוצריא'),
        ReportMessages.bodyTooLarge(700),
        ReportMessages.duplicateReport('אוצריא'),
        ReportMessages.queuedOffline('אוצריא'),
        ReportMessages.queuedAfterFailure('אוצריא'),
        ReportMessages.serverPermanentFailure(422),
        ReportMessages.serverTransientFailure(503),
        ReportMessages.noInternet,
        ReportMessages.serverTimeout,
        ReportMessages.offlineQueueDisabled,
        ReportMessages.sendFailed,
        ReportMessages.pendingReportIdConflict,
      ];
      final translated = <String>[];
      await mount(
        tester,
        SettingsLanguage.english,
        Scaffold(
          body: Builder(
            builder: (context) {
              translated.clear();
              translated.addAll(
                sourceMessages.map(
                  (message) => reportFeedbackText(context, message),
                ),
              );
              for (final field in [
                'title',
                'description',
                'reporterEmail',
                'attachments.images',
                'attachments.minidump',
                'attachments.diagnostics',
                'attachments.errorLog',
                'attachments',
                'draftLoad',
                'draftSave',
                'draftFinalize',
                'delivery',
              ]) {
                translated.add(
                  appReportInvalidFieldMessage(
                    field,
                    emailEmpty: false,
                    context: context,
                  ),
                );
              }
              return const SizedBox();
            },
          ),
        ),
      );
      expect(translated, hasLength(sourceMessages.length + 12));
      for (final result in translated) {
        expect(
          RegExp(r'[\u0590-\u05ff]').hasMatch(result),
          isFalse,
          reason: result,
        );
        expect(result, isNot(contains('{target}')));
        expect(result, isNot(contains('{status}')));
        expect(result, isNot(contains('{limit}')));
      }
      expect(translated[1], contains('700'));
      expect(translated[5], contains('422'));
      expect(translated[6], contains('503'));
    },
  );

  visualTest(
    'book reporting keeps drafts without the retired telephone route',
    (tester) async {
      final draft = BookReportDraftCubit(
        target: const {
          'bookTitle': 'אבות',
          'libraryVersion': '1234',
          'source': {
            'bookId': 7,
            'lineIndex': 11,
            'heRef': 'אבות א:א',
            'originalLine': 'דוגמה',
          },
        },
        initialForm: const {'mode': 'freeText', 'details': ''},
      );
      await mount(
        tester,
        SettingsLanguage.english,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: reportDialogBuilder(
                  context,
                  (_) => TabbedReportDialog(
                    selectedText: 'טקסט לדוגמה',
                    fontSize: 18,
                    bookTitle: 'אבות',
                    currentLineNumber: 12,
                    directReportTargetLabel: 'Otzaria',
                    draft: draft,
                  ),
                ),
              ),
              child: const Text('open book report'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open book report'));
      await nativeWork(tester);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(RegularReportTab), findsOneWidget);
      expect(find.textContaining('077-4636-198'), findsNothing);
      expect(
        find.byKey(const ValueKey('book-report-save-draft')),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(TabbedReportDialog))).pop();
      await tester.pumpAndSettle();
      await tester.runAsync(draft.close);
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
