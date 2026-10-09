import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';

import '../helpers/memory_settings_cache.dart';
import '../support/shaper_test_init.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

/// ספר בן 20 שורות: כותרת ספר, ושלושה פרקים בשורות 1, 7 ו-12.
const _bookText = [
  '<h1>תהילים</h1>',
  '<h2>פרק א</h2>',
  'א1',
  'א2',
  'א3',
  'א4',
  'א5',
  '<h2>פרק ב</h2>',
  'ב1',
  'ב2',
  'ב3',
  'ב4',
  '<h2>פרק ג</h2>',
  'ג1',
  'ג2',
  'ג3',
  'ג4',
  'ג5',
  'ג6',
  'ג7',
];

final _toc = [
  TocEntry(text: 'תהילים', index: 0, level: 1),
  TocEntry(text: 'פרק א', index: 1, level: 2),
  TocEntry(text: 'פרק ב', index: 7, level: 2),
  TocEntry(text: 'פרק ג', index: 12, level: 2),
];

void main() {
  // התצוגה המקדימה מעצבת את הטקסט במעצב הנייטיבי; בלעדיו אין מה לבדוק כאן.
  final shaperPath = findNativeShaperLibrary();
  final skip = shaperPath == null ? 'the native shaper is not built' : null;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    ShaperLibrary.path = shaperPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async => '/tmp');
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    int? endLine,
    List<String>? availableCommentators,
    List<String> activeCommentators = const [],
    BookProtection? protection,
  }) async {
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
              bookId: 'תהילים',
              startLine: 1,
              endLine: endLine,
              tableOfContents: _toc,
              availableCommentators: availableCommentators,
              activeCommentators: activeCommentators,
              protection: protection,
            ),
          ),
        ),
      ),
    );
    // טווח השורות נקבע אחרי קריאת הטקסט (async); התצוגה המקדימה אינה נדרשת.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets('endLine מסמן מראש את הטווח כבחירת כותרות — פרק א עד פרק ב', (
    tester,
  ) async {
    await pumpScreen(tester, endLine: 12);

    expect(find.text('11 שורות נבחרו מתוך 20'), findsOneWidget);
    expect(find.text('פרק א'), findsWidgets);
    expect(find.text('פרק ב'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  }, skip: skip != null);

  testWidgets('רמה 2 — הטווח נחתך ל-15 שורות ו"שמור ל-PDF" מוסתר', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      endLine: 20,
      protection: const BookProtection(level: 2),
    );

    expect(find.text('15 שורות נבחרו מתוך 20'), findsOneWidget);
    expect(find.text(PdfMessages.printLimitedByPublisher(15)), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate((w) => w is AppDropdownField).first,
    );
    // התצוגה המקדימה ממשיכה לרנדר ברקע, ולכן אין להמתין ל-pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // התפריט פתוח: הפריט מופיע גם בשדה וגם ברשימה.
    expect(find.text('הדפס'), findsAtLeastNWidgets(2));
    expect(find.text('שמור ל-PDF'), findsNothing);
    expect(find.text('שמור ל-Word'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, skip: skip != null);

  testWidgets('בלי endLine — ברירת המחדל הקיימת: הכותרת שסביב השורה', (
    tester,
  ) async {
    await pumpScreen(tester);

    // פרק א בלבד (שורות 1–6)
    expect(find.text('6 שורות נבחרו מתוך 20'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, skip: skip != null);
  testWidgets(
    'SDK commentator picker changes selection and survives include toggle',
    (tester) async {
      await pumpScreen(
        tester,
        availableCommentators: ['רש"י', 'אבן עזרא'],
        activeCommentators: ['רש"י'],
      );
      await tester.ensureVisible(find.text('כלול מפרשים'));
      await tester.tap(find.text('כלול מפרשים'));
      await tester.pump();
      final chips = find.byType(FilterChip);
      expect(chips, findsNWidgets(2));
      expect(tester.widget<FilterChip>(chips.at(0)).selected, isTrue);
      expect(tester.widget<FilterChip>(chips.at(1)).selected, isFalse);
      await tester.ensureVisible(find.text('אבן עזרא'));
      await tester.tap(find.text('אבן עזרא'));
      await tester.pump();
      expect(tester.widget<FilterChip>(chips.at(1)).selected, isTrue);
      await tester.ensureVisible(find.text('כלול מפרשים'));
      await tester.tap(find.text('כלול מפרשים'));
      await tester.pump();
      expect(chips, findsNothing);
      await tester.tap(find.text('כלול מפרשים'));
      await tester.pump();
      expect(tester.widget<FilterChip>(chips.at(1)).selected, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
    skip: skip != null,
  );
  testWidgets('SDK with no linked commentators has no selectable chips', (
    tester,
  ) async {
    await pumpScreen(tester, availableCommentators: []);
    await tester.ensureVisible(find.text('כלול מפרשים'));
    await tester.tap(find.text('כלול מפרשים'));
    await tester.pump();
    expect(find.byType(FilterChip), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, skip: skip != null);
}
