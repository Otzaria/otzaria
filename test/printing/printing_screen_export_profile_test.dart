import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/printing/export_restriction_service.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/shaper_test_init.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

class _CapturingFilePicker extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  Uint8List? bytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.bytes = bytes;
    return null;
  }
}

const _verse =
    'בְּרֵאשִׁ֖ית, בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃';
const _book = ['<h1>בראשית</h1>', '<h2>פרק א</h2>', _verse];

/// מייצא את הספר ל-Word ממסך ההדפסה לפי [profile] ומחזיר את word/document.xml.
Future<String> _exportWord(
  WidgetTester tester,
  TextDisplayProfile profile, {
  List<String> book = _book,
  List<PrintBlock>? blocks,
  TextDisplayProfile? commentaryProfile,
  Future<void> Function(WidgetTester)? verifyPdf,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  ExportRestrictionService.setRestrictedTitlesForTesting(const []);
  final picker = _CapturingFilePicker();
  FilePickerPlatform.instance = picker;
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
          // סרגל ההגדרות של המסך גולש ברוחב הבדיקה בגודל גופן מלא.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.5)),
            child: child!,
          ),
          home: PrintingScreen(
            data: Future.value(book.join('\n')),
            bookId: 'בראשית',
            startLine: 1,
            tableOfContents: [
              TocEntry(text: 'בראשית', index: 0, level: 1),
              TocEntry(text: 'פרק א', index: 1, level: 2),
            ],
            displayProfile: profile,
            commentaryDisplayProfile: commentaryProfile,
            prebuiltBlocks: blocks,
          ),
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
  await verifyPdf?.call(tester);
  await tester.tap(find.text('שמירה'));
  for (var i = 0; i < 300 && picker.bytes == null; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(picker.bytes, isNotNull, reason: 'לא נוצר קובץ Word');
  final archive = ZipDecoder().decodeBytes(picker.bytes!);
  final xml = utf8.decode(
    archive.findFile('word/document.xml')!.content as List<int>,
  );
  await tester.pumpWidget(const SizedBox());
  return xml;
}

void main() {
  // התצוגה המקדימה של מסך ההדפסה נבנית במעצב הנייטיבי.
  final shaperPath = findNativeShaperLibrary();
  final originalPdfiumPath = Pdfrx.pdfiumModulePath;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<int>('key-print-destination', 1);
    ShaperLibrary.path = shaperPath;
    if (Platform.isMacOS) {
      Pdfrx.pdfiumModulePath = File(
        'build/native_assets/macos/libpdfium.dylib',
      ).absolute.path;
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async => '/tmp');
  });

  tearDownAll(() {
    Pdfrx.pdfiumModulePath = originalPdfiumPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  setUp(() async {
    await Settings.setValue<String>(
      SettingsRepository.keyTextDisplayPolicy,
      jsonEncode(TextDisplayPolicy.empty.toJson()),
    );
  });

  testWidgets('הסרת ניקוד בלבד בהדפסה שומרת מתג וסוף פסוק', (tester) async {
    const profile = TextDisplayProfile(
      nikud: MarkVisibility.hide,
      teamim: TeamimVisibility.show,
    );
    final xml = await _exportWord(tester, profile);
    expect(xml, contains(applyTextDisplayProfile(_verse, profile)));
    expect(xml, contains('ֽ'), reason: 'המתג נמחק');
    expect(xml, contains('׃'), reason: 'סוף הפסוק נמחק');
  }, skip: shaperPath == null);

  testWidgets('הסתרת פיסוק בפרופיל הייצוא מוחלת בהדפסה', (tester) async {
    const profile = TextDisplayProfile(punctuation: MarkVisibility.hide);
    final xml = await _exportWord(tester, profile);
    expect(xml, contains(applyTextDisplayProfile(_verse, profile)));
    expect(xml, isNot(contains(',')), reason: 'הפיסוק לא הוסר');
  }, skip: shaperPath == null);

  testWidgets('הסתרת פיסוק שומרת על פיסוק כותרת הספר', (tester) async {
    final xml = await _exportWord(
      tester,
      const TextDisplayProfile(punctuation: MarkVisibility.hide),
      book: ['<h1>ספר, בדיקה</h1>', '<h2>פרק א</h2>', _verse],
    );
    expect(xml, contains('ספר, בדיקה'));
    expect(
      xml,
      contains(
        applyTextDisplayProfile(
          _verse,
          const TextDisplayProfile(punctuation: MarkVisibility.hide),
        ),
      ),
    );
  }, skip: shaperPath == null);

  testWidgets('הסתרת פיסוק ב-PDF שומרת פיסוק של כותרת h2 בגוף', (tester) async {
    await _exportWord(
      tester,
      const TextDisplayProfile(punctuation: MarkVisibility.hide),
      book: ['<h1>בראשית</h1>', '<h2>פרק, א</h2>', _verse],
      verifyPdf: (tester) async {
        final dynamic state = tester.state(find.byType(PrintingScreen));
        final text = await tester.runAsync(() async {
          final bytes =
              await (state.createPdf(PdfPageFormat.a4) as Future<Uint8List>);
          final doc = await PdfDocument.openData(bytes);
          try {
            final pages = <String>[];
            for (final page in doc.pages) {
              pages.add((await page.loadText())!.fullText);
            }
            return pages.join('\n');
          } finally {
            await doc.dispose();
          }
        });
        expect(text, contains(','), reason: 'רק כותרת h2 אמורה לשמור פסיק');
      },
    );
  }, skip: shaperPath == null);

  testWidgets('מפרש עם כותרת HTML שומר פיסוק ב-Word וב-PDF', (tester) async {
    const profile = TextDisplayProfile(punctuation: MarkVisibility.hide);
    final blocks = await buildCommentaryPrintBlocks(
      [
        LinkGroup(
          bookTitle: 'מפרש',
          links: [
            Link(
              heRef: 'ref',
              index1: 1,
              path2: 'מפרש.txt',
              index2: 1,
              connectionType: 'COMMENTARY',
            ),
          ],
        ),
      ],
      contentResolver: (_) async => '<h2>מפרש, בדיקה</h2>\n$_verse',
      keepHtml: true,
    );
    final xml = await _exportWord(
      tester,
      profile,
      blocks: blocks,
      commentaryProfile: profile,
      verifyPdf: (tester) async {
        final dynamic state = tester.state(find.byType(PrintingScreen));
        final text = await tester.runAsync(() async {
          final bytes =
              await (state.createPdf(PdfPageFormat.a4) as Future<Uint8List>);
          final doc = await PdfDocument.openData(bytes);
          try {
            final pages = <String>[];
            for (final page in doc.pages) {
              pages.add((await page.loadText())!.fullText);
            }
            return pages.join('\n');
          } finally {
            await doc.dispose();
          }
        });
        expect(text, contains(','), reason: 'כותרת המפרש איבדה את הפיסוק');
        expect(
          text,
          isNot(contains('<h2>')),
          reason: 'התגיות חייבות להימחק בפלט PDF',
        );
      },
    );
    expect(
      XmlDocument.parse(
        xml,
      ).findAllElements('w:t').map((e) => e.innerText).join('\n'),
      contains('מפרש, בדיקה'),
    );
    expect(xml, contains(applyTextDisplayProfile(_verse, profile)));
  }, skip: shaperPath == null);

  for (final commentaryPunctuation in MarkVisibility.values) {
    testWidgets('ייצוא מפרש מכבד פרופיל נפרד: $commentaryPunctuation', (
      tester,
    ) async {
      final body = TextDisplayProfile(
        nikud: MarkVisibility.hide,
        teamim: TeamimVisibility.show,
        punctuation: commentaryPunctuation == MarkVisibility.show
            ? MarkVisibility.hide
            : MarkVisibility.show,
        holyName: HolyNameDisplay.hehApostrophe,
      );
      final commentary = TextDisplayProfile(
        nikud: MarkVisibility.hide,
        teamim: TeamimVisibility.show,
        punctuation: commentaryPunctuation,
        holyName: HolyNameDisplay.asIs,
      );
      final policy = TextDisplayPolicy.empty.withSlot(
        TextDisplayBookClass.general,
        TextDisplaySlot.commentaryDisplay.copyWith(channel: TextChannel.export),
        TextDisplayPatch(
          punctuation: commentaryPunctuation,
          holyName: HolyNameDisplay.asIs,
        ),
      );
      await Settings.setValue<String>(
        SettingsRepository.keyTextDisplayPolicy,
        jsonEncode(policy.toJson()),
      );
      const text = '$_verse יהוה';
      final xml = await _exportWord(
        tester,
        body,
        blocks: [
          const PrintBlock(kind: PrintBlockKind.text, text: text),
          const PrintBlock(kind: PrintBlockKind.commentary, text: text),
        ],
      );
      final exportedText = XmlDocument.parse(
        xml,
      ).findAllElements('w:t').map((node) => node.innerText).join('\n');
      expect(exportedText, contains(applyTextDisplayProfile(text, body)));
      expect(exportedText, contains(applyTextDisplayProfile(text, commentary)));
      expect(xml, contains('ֽ'), reason: 'המתג חייב להישמר גם ללא ניקוד');
      expect(xml, contains('׃'), reason: 'סוף הפסוק חייב להישמר גם ללא ניקוד');
    }, skip: shaperPath == null);
  }
}
