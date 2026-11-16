import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';
import 'package:otzaria/theme/theme_exports.dart';
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
import '../test_helpers/capture_file_saves.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

class _Commentary extends Link {
  _Commentary(String title, String label, int? at, this.text)
    : super(
        heRef: '$title, $label',
        index1: 3,
        path2: '$title.txt',
        index2: 1,
        connectionType: 'COMMENTARY',
        anchorStart: at,
        anchorLabel: label,
      );

  final String text;

  @override
  Future<String> get content async => text;
}

class _SourceBook extends TextBook {
  _SourceBook(this.testLinks, {super.versionTitle}) : super(title: 'בראשית');

  final List<Link> testLinks;

  @override
  Future<List<Link>> get links async => testLinks;
}

// חילוץ PDF מחזיר את תווי הסוגריים של הגליפים המהופכים ב־RTL.
String _pdfMarker(Link link) => String.fromCharCodes(
  anchorMarkerText(link)!.runes.map(
    (rune) => switch (rune) {
      0x28 => 0x29,
      0x29 => 0x28,
      0x5B => 0x5D,
      0x5D => 0x5B,
      0x7B => 0x7D,
      0x7D => 0x7B,
      _ => rune,
    },
  ),
);

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
  List<Link> links = const [],
  List<String> commentators = const [],
  TextBook? sourceBook,
  Future<void> Function(WidgetTester)? verifyPdf,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final picker = _CapturingFilePicker();
  captureFileSaves(picker, (bytes) => picker.bytes = bytes);
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
            book: sourceBook,
            links: links,
            activeCommentators: commentators,
            initialIncludeCommentaries: links.isNotEmpty,
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
  final originalPdfiumPath = Pdfrx.pdfiumModulePath;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<int>('key-print-destination', 1);
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
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

  testWidgets('ציוני מפרשים נבחרים מופיעים ב-PDF וב-Word לפני הסרת ניקוד', (
    tester,
  ) async {
    BookProtectionRepository.instance.debugRepositoryFor = (_) async => null;
    const firstWord = 'רִאשׁוֹן';
    const noteBody = 'גוף הערה';
    const raw = '$firstWord<sup class="footnote-marker">1</sup> שֵׁנִי';
    final noteAt = visibleCharCount('$firstWord<sup>1</sup>');
    final notes =
        (BookNotesBuilder()..add(2, 0, '1', noteBody, charPos: noteAt)).build();
    BookNotesRepository.instance.debugLoader =
        (title, {categoryId, required source}) async =>
            title == 'בראשית' ? notes : BookNotes.empty;
    DivineNamesRepository.instance.debugLoader =
        (title, {categoryId, required source}) async => DivineNameSpans.empty;
    addTearDown(() {
      BookProtectionRepository.instance.debugReset();
      BookNotesRepository.instance
        ..debugLoader = null
        ..clear();
      DivineNamesRepository.instance
        ..debugLoader = null
        ..clear();
    });
    final first = _Commentary('ראשון', 'א', 0, 'פירוש ראשון');
    final second = _Commentary(
      'שני',
      'ב',
      visibleCharCount(raw.substring(0, raw.indexOf('שֵׁנִי'))) +
          noteBody.length,
      'פירוש שני',
    );
    final insideNote = _Commentary(
      'בהערה',
      'ו',
      noteAt + 3,
      'פירוש בגוף ההערה',
    );
    final empty = _Commentary('ריק', 'ג', 2, '');
    final unselected = _Commentary('לא נבחר', 'ד', 4, 'פירוש לא נבחר');
    final unanchored = _Commentary('ללא עוגן', 'ה', null, 'פירוש ללא עוגן');
    final links = [first, second, insideNote, empty, unselected, unanchored];
    late PrintingSwitchRow markerRow;

    final xml = await _exportWord(
      tester,
      const TextDisplayProfile(nikud: MarkVisibility.hide),
      book: ['<h1>ספר בדיקה</h1>', '<h2>פרק א</h2>', raw],
      sourceBook: _SourceBook(links),
      links: links,
      commentators: ['ראשון', 'שני', 'בהערה', 'ריק', 'ללא עוגן'],
      verifyPdf: (tester) async {
        Future<String> pdfText(String name) async {
          final dynamic state = tester.state(find.byType(PrintingScreen));
          return (await tester.runAsync(() async {
            final bytes =
                await (state.createPdf(PdfPageFormat.a4) as Future<Uint8List>);
            final output =
                Platform.environment['OTZARIA_PRINT_TEST_ARTIFACT_DIR'];
            if (output != null) {
              await Directory(output).create(recursive: true);
              await File('$output/$name.pdf').writeAsBytes(bytes);
            }
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
          }))!;
        }

        final before = await pdfText('before');
        expect(before, contains('גוף הערה'));
        expect(before, isNot(contains(_pdfMarker(first))));
        await tester.ensureVisible(find.text('כלול ציוני מפרשים'));
        await tester.tap(find.text('כלול ציוני מפרשים'));
        await tester.pump();
        markerRow = tester.widget<PrintingSwitchRow>(
          find.ancestor(
            of: find.text('כלול ציוני מפרשים'),
            matching: find.byType(PrintingSwitchRow),
          ),
        );
        final after = await pdfText('after');
        expect(after, contains(_pdfMarker(first)));
        expect(after, contains(_pdfMarker(second)));
        expect(after, contains(_pdfMarker(insideNote)));
        expect(after, isNot(contains(_pdfMarker(empty))));
        expect(after, isNot(contains(_pdfMarker(unselected))));
        expect(after, contains('פירוש ללא עוגן'));
        expect(after, isNot(contains('פירוש לא נבחר')));
      },
    );
    final text = XmlDocument.parse(
      xml,
    ).findAllElements('w:t').map((element) => element.innerText).join();
    expect(text, contains(anchorMarkerText(first)!));
    expect(text, contains(anchorMarkerText(second)!));
    expect(text, contains(anchorMarkerText(insideNote)!));
    expect(text, isNot(contains(anchorMarkerText(empty)!)));
    for (final (seed, brightness) in [
      (AppSeedColors.defaultLight, Brightness.light),
      (AppSeedColors.defaultDark, Brightness.dark),
      (AppSeedColors.white, Brightness.light),
    ]) {
      final theme = AppThemeData.light(
        AppThemeData.createColorScheme(seed, brightness),
        compactMenuMode: false,
        variant: AppThemeVariant.ofSeed(seed),
      );
      for (final width in [360.0, 1200.0]) {
        for (final scale in [1.0, 1.3]) {
          tester.view.physicalSize = Size(width, 120);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: markerRow),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('כלול ציוני מפרשים').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('מהדורה חלופית אינה מציעה ציוני הנוסח הראשי', (tester) async {
    await _exportWord(
      tester,
      const TextDisplayProfile(),
      sourceBook: _SourceBook(const [], versionTitle: 'Another edition'),
      links: [_Commentary('מפרש', 'א', 0, 'פירוש')],
      commentators: ['מפרש'],
      verifyPdf: (tester) async {
        expect(find.text('כלול ציוני מפרשים'), findsNothing);
      },
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
  });

  testWidgets('הסתרת פיסוק בפרופיל הייצוא מוחלת בהדפסה', (tester) async {
    const profile = TextDisplayProfile(punctuation: MarkVisibility.hide);
    final xml = await _exportWord(tester, profile);
    expect(xml, contains(applyTextDisplayProfile(_verse, profile)));
    expect(xml, isNot(contains(',')), reason: 'הפיסוק לא הוסר');
  });

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
  });

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
  });

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
      protectionResolver: (_) async => BookProtection.none,
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
  });

  testWidgets('בלוקים מוכנים מחילים החלפת שמות בגוף ובהערה ב-Word', (
    tester,
  ) async {
    final marked = '${divineNameMarkerOpen(5)}אלהים</span>';
    final xml = await _exportWord(
      tester,
      const TextDisplayProfile(divineNames: DivineNamesDisplay.substitute),
      blocks: [
        PrintBlock(
          kind: PrintBlockKind.commentary,
          text:
              '$marked<sup class="footnote-marker">א</sup><i class="footnote">$marked</i>',
        ),
      ],
      verifyPdf: (tester) async {
        final dynamic state = tester.state(find.byType(PrintingScreen));
        final text = await tester.runAsync(() async {
          final bytes =
              await (state.createPdf(PdfPageFormat.a4) as Future<Uint8List>);
          final document = await PdfDocument.openData(bytes);
          try {
            return (await document.pages.first.loadText())!.fullText;
          } finally {
            await document.dispose();
          }
        });
        expect(text!.split('אלקים'), hasLength(3));
        expect(text, isNot(contains('אלהים')));
      },
    );
    final text = XmlDocument.parse(
      xml,
    ).findAllElements('w:t').map((node) => node.innerText).join(' ');
    expect(text.split('אלקים'), hasLength(3));
    expect(text, isNot(contains('אלהים')));
    expect(xml, isNot(contains('divine-name')));
  });

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
    });
  }
}
