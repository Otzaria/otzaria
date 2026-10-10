import 'dart:convert';

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
import 'package:otzaria/printing/export_restriction_service.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
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

const _book = ['<h1>בראשית</h1>', '<h2>פרק א</h2>', 'בראשית ברא אלהים'];

/// מייצא את הספר ל-Word ממסך ההדפסה ומחזיר את word/document.xml.
Future<String> _exportWord(WidgetTester tester) async {
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
            data: Future.value(_book.join('\n')),
            bookId: 'בראשית',
            startLine: 1,
            tableOfContents: [
              TocEntry(text: 'בראשית', index: 0, level: 1),
              TocEntry(text: 'פרק א', index: 1, level: 2),
            ],
            displayProfile: const TextDisplayProfile(),
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
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<int>('key-print-destination', 1);
    ShaperLibrary.path = shaperPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async => '/tmp');
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  testWidgets('ייצוא Word ממסך ההדפסה שומר את <h2> ככותרת', (tester) async {
    final xml = await _exportWord(tester);
    final paragraph = RegExp(
      r'<w:p>(?:(?!</w:p>).)*פרק א(?:(?!</w:p>).)*</w:p>',
      dotAll: true,
    ).firstMatch(xml)!.group(0)!;
    expect(paragraph, contains('w:val="Heading2"'));
  }, skip: shaperPath == null);
}
