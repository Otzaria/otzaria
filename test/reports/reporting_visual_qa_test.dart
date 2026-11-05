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
import 'package:otzaria/widgets/misc/phone_report_tab.dart';
import 'package:otzaria/widgets/misc/reporting_numbers_widget.dart';
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
  testWidgets(description, body, timeout: const Timeout(Duration(minutes: 1)));
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
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
        await waitForBookReportMetadata(
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
        await waitForBookReportMetadata(
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
        await capture(tester, 'book-report-low-${language.code}-quote');
        final quote = find.byKey(const ValueKey('report-location-quote'));
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

  visualTest(
    'saved software edit keeps fields, attachments, actions and validation accessible in a low English window',
    (tester) async {
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
      await tester.runAsync(() => service.queueReport(original));
      await mount(
        tester,
        SettingsLanguage.english,
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
          language: SettingsLanguage.english,
        ),
      );
      await tester.ensureVisible(queue);
      await tester.tap(queue);
      await nativeWork(tester);
      final edit = find.text('Edit');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await nativeWork(tester);
      expect(find.byType(AppReportEditFields), findsOneWidget);
      await capture(tester, 'software-queue-edit-low-en-top');
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      final save = find.descendant(
        of: find.byType(AppDialog),
        matching: find.text('Save'),
      );
      expect(save.hitTestable(), findsOneWidget);
      await enter(tester, 'app-report-edit-email', 'invalid@');
      final removeImage = find.byKey(const ValueKey('app-report-image-remove'));
      await tester.ensureVisible(removeImage);
      await tester.pumpAndSettle();
      expect(removeImage.hitTestable(), findsOneWidget);
      expect(save.hitTestable(), findsOneWidget);
      await capture(tester, 'software-queue-edit-low-en-attachments');
      await tester.tap(save);
      await nativeWork(tester);
      expect(find.byType(AppReportEditFields), findsNothing);
      expect(find.text('The email address is invalid.'), findsOneWidget);
      expect(
        (await tester.runAsync(service.getPendingReports))!.single.toJson(),
        original.toJson(),
      );
      await clearSnack(tester);
    },
  );

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
    'telephone route remains reachable and clipboard success/failure are English',
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
      final telephoneTab = find.widgetWithText(
        Tab,
        resolveSettingsText(
          'דיווח דרך קו אוצריא',
          language: SettingsLanguage.english,
        ),
      );
      expect(telephoneTab, findsOneWidget);
      await tester.tap(telephoneTab);
      await nativeWork(tester);
      expect(find.byType(PhoneReportTab), findsOneWidget);
      expect(find.byType(ReportingNumbersWidget), findsOneWidget);
      expect(find.text('(+972) 077-4636-198'), findsOneWidget);
      String? copied;
      var failCopy = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                if (failCopy) {
                  throw PlatformException(code: 'qa_clipboard_failure');
                }
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
      final copy = find.byTooltip('Copy phone number');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await nativeWork(tester);
      expect(copied, '(+972) 077-4636-198');
      expect(find.textContaining('Copied to clipboard:'), findsOneWidget);
      await clearSnack(tester);
      failCopy = true;
      await tester.tap(copy);
      await nativeWork(tester);
      final messages = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .where((text) => text.toLowerCase().contains('clipboard'))
          .toList();
      expect(messages, isNotEmpty);
      expect(
        messages.any((text) => RegExp(r'[\u0590-\u05ff]').hasMatch(text)),
        isFalse,
      );
      expect(find.text('שגיאה בהעתקה ללוח'), findsNothing);
      await clearSnack(tester);
      Navigator.of(tester.element(find.byType(TabbedReportDialog))).pop();
      await tester.pumpAndSettle();
      await tester.runAsync(draft.close);
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
