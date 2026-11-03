import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/shaper_test_init.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

/// פלטפורמת הדפסה שרק שומרת את onLayout, כדי שהבדיקה תפיק את הפלט בעצמה.
class _CapturingPrintingPlatform extends PrintingPlatform {
  LayoutCallback? onLayout;
  final job = Completer<bool>();

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) {
    this.onLayout = onLayout;
    return job.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// גופן "מותקן במחשב": עותק של קובץ TrueType אמיתי מחוץ לנכסי האפליקציה.
const _systemFamily = 'גופן מהמחשב';
const _systemFontFile = 'fonts/Tinos-Regular.ttf';
const _systemPostScriptName = 'Tinos-Regular';
const _bundledDefaultPostScriptName = 'TaameyDavidCLM-Medium';

/// גופן מחשב בקווי מתאר CFF (OTF), שחבילת pdf אינה קוראת כ-pw.Font.
const _cffFamily = 'גופן CFF מהמחשב';
const _cffPostScriptName = 'OtzariaAshurit-Regular';

/// גופן שהסריקה מצאה, אבל הקובץ שלו נמחק מאז.
const _missingFamily = 'גופן שהוסר';

/// שמות הגופנים המוטמעים ב-PDF, בלי תגית ה-subset.
Set<String> _embeddedFonts(Uint8List pdf) => RegExp(
  r'/BaseFont\s*/(?:[A-Z]{6}\+)?([^\s/<>\[\]()]+)',
).allMatches(String.fromCharCodes(pdf)).map((m) => m.group(1)!).toSet();

Future<T> _settle<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  late T result;
  unawaited(
    future.then((value) {
      result = value;
      done = true;
    }),
  );
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  expect(done, isTrue, reason: 'הפעולה לא הסתיימה');
  return result;
}

/// בוחר את [family] בבורר הגופן של המסך, מדפיס ומחזיר את ה-PDF שנשלח למדפסת.
Future<Uint8List> _printWithFont(
  WidgetTester tester,
  PrintingScreen screen,
  String family,
) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final platform = _CapturingPrintingPlatform();
  PrintingPlatform.instance = platform;
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  await tester.pumpWidget(
    RepositoryProvider<SettingsRepository>.value(
      value: _FakeSettingsRepository(),
      child: BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.5)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }

  final fontField = tester.widget<AppDropdownField<String>>(
    find.descendant(
      of: find.widgetWithText(PrintingDropdownRow, 'גופן'),
      matching: find.byType(AppDropdownField<String>),
    ),
  );
  expect(
    fontField.entries.map((e) => e.value),
    contains(family),
    reason: 'הגופן לא מוצע ברשימת הגופנים של ההדפסה',
  );
  fontField.onSelected!(family);
  await tester.pump();

  await tester.tap(find.text('הדפסה'));
  await tester.pump();
  final onLayout = platform.onLayout;
  expect(onLayout, isNotNull);
  final output = await _settle(
    tester,
    Future.value(onLayout!(PdfPageFormat.a4)),
  );
  platform.job.complete(false);
  await tester.pump(const Duration(milliseconds: 300));
  await _settle(tester, Future<void>.value());
  await tester.pumpWidget(const SizedBox());
  return output;
}

/// גופן מהמחשב שנבחר במסך ההדפסה מוטמע ב-PDF, ולא מוחלף בשקט בגופן המובנה
/// הראשון (issue #3589).
void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late PrintingPlatform originalPlatform;
  late Directory fontsDir;
  late String systemFontPath;
  late String cffFontPath;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<int>('key-print-destination', 2);
    originalPlatform = PrintingPlatform.instance;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async => '/tmp');
    fontsDir = Directory.systemTemp.createTempSync('otzaria-system-fonts-');
    systemFontPath = File(
      _systemFontFile,
    ).copySync('${fontsDir.path}${Platform.pathSeparator}system.ttf').path;
    final ashurit = resolvedTestPackageRoot('otzaria_ashurit')!;
    cffFontPath = File(
      '${ashurit.path}/lib/OtzariaAshurit-Regular.otf',
    ).copySync('${fontsDir.path}${Platform.pathSeparator}system.otf').path;
  });

  tearDownAll(() {
    PrintingPlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    fontsDir.deleteSync(recursive: true);
  });

  setUp(() async {
    AppFonts.debugResetSystemFontsCache();
    await AppFonts.debugStoreScan(
      SystemFontScanResult(
        fonts: const [
          FontInfo(value: _systemFamily, label: _systemFamily),
          FontInfo(value: _cffFamily, label: _cffFamily),
          FontInfo(value: _missingFamily, label: _missingFamily),
        ],
        families: {
          _systemFamily: SystemFontFamilyFaces(
            family: _systemFamily,
            regularPath: systemFontPath,
          ),
          _cffFamily: SystemFontFamilyFaces(
            family: _cffFamily,
            regularPath: cffFontPath,
          ),
          _missingFamily: SystemFontFamilyFaces(
            family: _missingFamily,
            regularPath: '${fontsDir.path}${Platform.pathSeparator}gone.ttf',
          ),
        },
        allFamilies: const {},
        aliases: const {},
      ),
    );
  });

  tearDown(AppFonts.debugResetSystemFontsCache);

  Future<Set<String>> printWithSystemFont(
    WidgetTester tester,
    PrintingScreen screen, {
    String family = _systemFamily,
  }) async {
    // גופני המחשב מוצעים רק בדסקטופ — כמו אצל המדווח.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      return _embeddedFonts(
        await _printWithFont(tester, screen, family),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('הדפסת טווח מהספר בגופן מהמחשב', (tester) async {
    final fonts = await printWithSystemFont(
      tester,
      PrintingScreen(
        data: Future.value(
          ['בראשית', 'בְּרֵאשִׁית בָּרָא אֱלֹהִים', 'ויאמר'].join('\n'),
        ),
        bookId: 'בראשית',
        startLine: 1,
        endLine: 3,
      ),
    );
    expect(fonts, contains(_systemPostScriptName));
    expect(fonts, isNot(contains(_bundledDefaultPostScriptName)));
  });

  testWidgets('הדפסה מכרטיסיית המפרשים בגופן מהמחשב', (tester) async {
    final fonts = await printWithSystemFont(
      tester,
      PrintingScreen(
        data: Future.value(''),
        bookId: 'רש"י',
        documentTitle: 'רש"י על בראשית',
        prebuiltBlocks: const [
          PrintBlock(kind: PrintBlockKind.commentaryTitle, text: 'רש"י'),
          PrintBlock(kind: PrintBlockKind.commentary, text: 'בְּרֵאשִׁית'),
        ],
      ),
    );
    expect(fonts, contains(_systemPostScriptName));
    expect(fonts, isNot(contains(_bundledDefaultPostScriptName)));
  });

  PrintingScreen bookScreen() => PrintingScreen(
    data: Future.value(['בראשית', 'בְּרֵאשִׁית בָּרָא'].join('\n')),
    bookId: 'בראשית',
    startLine: 1,
    endLine: 2,
  );

  testWidgets('גופן CFF מהמחשב: גוף הטקסט בגופן שנבחר, וההדפסה לא נכשלת', (
    tester,
  ) async {
    final fonts = await printWithSystemFont(
      tester,
      bookScreen(),
      family: _cffFamily,
    );
    expect(fonts, contains(_cffPostScriptName));
    // הכותרת ושולי העמוד נכתבים ב-pw.Font, שקורא רק TrueType.
    expect(fonts, contains(_bundledDefaultPostScriptName));
  });

  testWidgets('קובץ גופן המחשב שהוסר — ההדפסה בגופן המובנה', (tester) async {
    final fonts = await printWithSystemFont(
      tester,
      bookScreen(),
      family: _missingFamily,
    );
    expect(fonts, contains(_bundledDefaultPostScriptName));
  });
}
