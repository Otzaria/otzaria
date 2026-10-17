import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';

import '../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

/// כל כתיבה להגדרות הייתה נכשלת כאן: Fake זורק על כל מתודה שלא מומשה.
class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

const _bookText = ['בראשית', 'בראשית ברא אלהים', 'ויאמר יהוה'];

/// מסך ההדפסה עם מופעי השמות: ברירת המחדל לפי פרופיל ערוץ הייצוא, שינוי
/// להדפסה הזו בלבד, וההחלפה בבלוקי הטקסט.
void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final spans =
      (DivineNameSpansBuilder()..add(1, 11, 16, DivineNameKind.elohim)).build();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async => '/tmp');
    DivineNamesRepository.instance.debugLoader =
        (title, {categoryId, required source}) async => spans;
    BookNotesRepository.instance.debugLoader =
        (title, {categoryId, required source}) async => BookNotes.empty;
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    DivineNamesRepository.instance
      ..debugLoader = null
      ..clear();
    BookNotesRepository.instance
      ..debugLoader = null
      ..clear();
    PrintingScreen.debugOnPrintBlocks = null;
  });

  final printed = <String>[];
  setUp(() {
    printed.clear();
    DivineNamesRepository.instance.clear();
    BookNotesRepository.instance.clear();
    PrintingScreen.debugOnPrintBlocks = (blocks) => printed
      ..clear()
      ..addAll(blocks.map((b) => b['text'] ?? ''));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      // התצוגה המקדימה מתוזמנת ב-Timer של 250ms.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    TextDisplayProfile profile,
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
              bookId: 'בראשית',
              book: TextBook(title: 'בראשית'),
              startLine: 1,
              endLine: 3,
              displayProfile: profile,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  PrintingSwitchRow divineSwitch(WidgetTester tester) =>
      tester.widget<PrintingSwitchRow>(
        find.widgetWithText(PrintingSwitchRow, 'שאר שמות הקודש בכינוי'),
      );

  testWidgets('ברירת המחדל לפי ההגדרה: בכינוי — השם מוחלף בהדפסה', (
    tester,
  ) async {
    const profile = TextDisplayProfile(
      divineNames: DivineNamesDisplay.substitute,
    );
    await pumpScreen(tester, profile);

    expect(divineSwitch(tester).value, isTrue);
    expect(printed, contains('בראשית ברא אלקים'));
    expect(printed, contains('ויאמר יקוק'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ברירת המחדל ככתבם; שינוי בהדפסה בלבד, ההגדרה לא משתנה', (
    tester,
  ) async {
    const profile = TextDisplayProfile();
    await pumpScreen(tester, profile);

    expect(divineSwitch(tester).value, isFalse);
    expect(printed, contains('בראשית ברא אלהים'));

    divineSwitch(tester).onChanged(true);
    await settle(tester);
    expect(divineSwitch(tester).value, isTrue);
    expect(printed, contains('בראשית ברא אלקים'));
    // הפרופיל שהועבר לא השתנה, ושום דבר לא נכתב להגדרות (ה-Fake היה זורק).
    expect(profile.divineNames, DivineNamesDisplay.asIs);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('הערת שוליים מהמסד חוזרת לשורה המודפסת, אחרי החלפת השמות', (
    tester,
  ) async {
    BookNotesRepository.instance.debugLoader =
        (title, {categoryId, required source}) async =>
            (BookNotesBuilder()
                  ..add(1, 0, null, 'הערה מהמסד אלהים', charPos: 6)
                  ..addDivineName(1, 0, 11, 16, DivineNameKind.elohim))
                .build();
    addTearDown(
      () => BookNotesRepository.instance.debugLoader =
          (title, {categoryId, required source}) async => BookNotes.empty,
    );

    await pumpScreen(
      tester,
      const TextDisplayProfile(divineNames: DivineNamesDisplay.substitute),
    );
    expect(
      printed,
      contains(
        allOf(
          startsWith('בראשיתהערה מהמסד אלקים'),
          endsWith('ברא אלקים'),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('מופעים שנטענים באיחור — הפלט מחכה להם, והבורר מופיע', (
    tester,
  ) async {
    final pending = Completer<DivineNameSpans>();
    DivineNamesRepository.instance.debugLoader =
        (title, {categoryId, required source}) => pending.future;
    addTearDown(
      () => DivineNamesRepository.instance.debugLoader =
          (title, {categoryId, required source}) async => spans,
    );

    await pumpScreen(
      tester,
      const TextDisplayProfile(divineNames: DivineNamesDisplay.substitute),
    );
    expect(printed, isEmpty, reason: 'הפלט לא נבנה לפני שהמופעים נטענו');
    expect(
      find.widgetWithText(PrintingSwitchRow, 'שאר שמות הקודש בכינוי'),
      findsNothing,
    );

    pending.complete(spans);
    await settle(tester);
    expect(divineSwitch(tester).value, isTrue);
    expect(printed, contains('בראשית ברא אלקים'));
    await tester.pumpWidget(const SizedBox());
  });
}
