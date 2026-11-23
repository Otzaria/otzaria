import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/printing_raster_idle.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

/// מבנה כמו בגמרא במסד (למשל כתובות): כל עמוד הוא כותרת אחות באותה רמה,
/// "דף טו." בשורה 10 ו"דף טו:" בשורה 20 (נתוני המסד: 363 ו-381).
final _bookText = [
  '<h1>כתובות</h1>',
  for (var i = 1; i < 10; i++) 'ש$i',
  '<h2>דף טו.</h2>',
  for (var i = 11; i < 20; i++) 'ש$i',
  '<h2>דף טו:</h2>',
  for (var i = 21; i < 30; i++) 'ש$i',
];

final _toc = [
  TocEntry(text: 'כתובות', index: 0, level: 1),
  TocEntry(text: 'דף טו.', index: 10, level: 2),
  TocEntry(text: 'דף טו:', index: 20, level: 2),
];

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async => '/tmp');
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(Duration.zero);
    }
  }

  testWidgets(
    '#3183 — בחירת "דף טו." כסוף כשההתחלה "דף טו:" מיישרת את ההתחלה',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
              home: PrintingScreen(
                data: Future.value(_bookText.join('\n')),
                bookId: 'כתובות',
                // נפתח מעמוד טו ע"ב — ברירת המחדל: התחלה וסוף על "דף טו:".
                startLine: 20,
                tableOfContents: _toc,
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      final fields = find.byWidgetPredicate(
        (w) =>
            w is AppDropdownField &&
            w.runtimeType.toString().contains('_RangeAnchor'),
      );
      expect(fields, findsNWidgets(2));
      expect(
        find.descendant(of: fields, matching: find.text('דף טו:')),
        findsNWidgets(2),
      );

      // פותחים את בורר הסוף ובוחרים "דף טו.".
      await tester.tap(fields.at(1));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('דף טו.').last);
      await settle(tester);

      // הציפייה: הטווח אינו ריק, ושני הבוררים מציגים "דף טו.".
      expect(
        find.descendant(of: fields, matching: find.text('דף טו.')),
        findsNWidgets(2),
        reason: 'ההתחלה נשארה "דף טו:" והטווח ריק',
      );
      await tester.pumpWidget(const SizedBox());
      await drainPrintingRasterQueue(tester);
    },
  );
}
