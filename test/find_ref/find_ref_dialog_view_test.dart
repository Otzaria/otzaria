import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/find_ref_recent_store.dart';
import 'package:otzaria/find_ref/repository/db_commentator_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

/// מחזיר תוצאות קבועות לכל שאילתה — הדיאלוג נבדק על הפריסה, לא על המנוע.
class _FakeRepository implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;

  _FakeRepository(this.results, {this.error, this.commentators = const []});

  final List<DbReferenceResult> results;
  final Object? error;
  final List<DbCommentatorEntry> commentators;
  int calls = 0;

  @override
  void cancelPendingSearch() {}

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    calls++;
    if (error != null) throw error!;
    return results;
  }

  @override
  Future<List<DbCommentatorEntry>> getCommentatorsForResult(
    DbReferenceResult ref,
  ) async => commentators;

  @override
  Future<void> prewarmGlobalAltToc() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// מחזיר את התוצאות הראשונות מיד, ועוצר את החיפוש הבא עד שה-gate נפתח —
/// כדי שאפשר יהיה לבדוק מה מוצג בזמן שהשאילתה החדשה עוד רצה.
class _GatedRepository implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;

  _GatedRepository({required this.first, required this.second});

  final List<DbReferenceResult> first;
  final List<DbReferenceResult> second;
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  void cancelPendingSearch() {}

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    if (calls++ == 0) return first;
    await gate.future;
    return second;
  }

  @override
  Future<List<DbCommentatorEntry>> getCommentatorsForResult(
    DbReferenceResult ref,
  ) async => const [];

  @override
  Future<void> prewarmGlobalAltToc() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeHost implements FindRefDialogHost {
  final List<String> deepLinks = [];
  final List<String> textSearches = [];

  @override
  Future<bool> handleDeepLink(String uri) async {
    deepLinks.add(uri);
    // false: הדיאלוג לא ינסה לסגור את עצמו, והבדיקה נשארת על המסך.
    return false;
  }

  @override
  void openTextSearch(String query) => textSearches.add(query);
}

class _PopCounter extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

/// נכשל בקריאה הראשונה ומצליח בבאות.
class _FlakyRepository extends _FakeRepository {
  _FlakyRepository(super.results);

  int calls = 0;

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    if (calls++ == 0) throw Exception('DB down');
    return results;
  }
}

/// כמו [_GatedRepository], וסופר בקשות מפרשים. הבקשה הראשונה נזרקת
/// כשהקלדה חדשה מבטלת את החיפוש, כמו תור ה-worker בייצור.
class _CommentatorCountingRepository extends _GatedRepository {
  _CommentatorCountingRepository({required super.first, required super.second});

  int commentatorCalls = 0;
  Completer<List<DbCommentatorEntry>>? _firstCommentators;

  @override
  void cancelPendingSearch() {
    final pending = _firstCommentators;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const FindRefQueryCancelled());
    }
  }

  @override
  Future<List<DbCommentatorEntry>> getCommentatorsForResult(
    DbReferenceResult ref,
  ) {
    if (commentatorCalls++ == 0) {
      return (_firstCommentators = Completer()).future;
    }
    return Future.value(const []);
  }
}

/// תוצאות לפי השאילתה, כדי להבדיל בין סט ישן לחדש.
class _QueryRepository extends _FakeRepository {
  _QueryRepository(this.byQuery) : super(const []);

  final Map<String, List<DbReferenceResult>> byQuery;

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async => byQuery[ref] ?? const [];
}

DbReferenceResult _ref(String reference, {String path = 'תנ"ך, תורה'}) =>
    DbReferenceResult(
      title: 'בראשית',
      reference: reference,
      segment: 1,
      bookId: 1,
      bookPath: path,
    );

/// משך שממתין בנדיבות ל-debounce של 250ms שב-BLoC.
const _pastDebounce = Duration(milliseconds: 400);

Future<void> _pumpDialog(
  WidgetTester tester, {
  List<DbReferenceResult> results = const [],
  Size? screenSize,
  double textScale = 1.0,
  Object? error,
  FindRefRepository? repository,
  FindRefDialogHost? host,
  NavigatorObserver? observer,
}) async {
  if (screenSize != null) {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  FocusRepository().findRefSearchController.clear();
  final bloc = FindRefBloc(
    findRefRepository: repository ?? _FakeRepository(results, error: error),
  );
  addTearDown(bloc.close);

  // עץ ריק ביניים מכריח יצירה מחדש של ה-State — פתיחה חדשה של הדיאלוג,
  // ולא עדכון של הקיים.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [?observer],
      locale: const Locale('he', 'IL'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB85C38)),
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiProvider(
              providers: [
                Provider<FocusRepository>.value(value: FocusRepository()),
                BlocProvider<FindRefBloc>.value(value: bloc),
              ],
              child: host == null
                  ? const FindRefDialog()
                  : FindRefDialog(host: host),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

TextStyle? _titleStyleOf(WidgetTester tester, String reference) =>
    tester.widget<Text>(find.text(reference)).style;

List<String> _chipLabels(WidgetTester tester) => [
  ...tester
      .widgetList<InputChip>(find.byType(InputChip))
      .map((chip) => (chip.label as Text).data!),
  ...tester
      .widgetList<ActionChip>(find.byType(ActionChip))
      .map((chip) => (chip.label as Text).data!),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    FindRefRecentStore.clear();
    // איפוס היסט הדוגמאות כדי שהחלון המוצג יהיה צפוי בכל בדיקה.
    FindRefDialog.resetExamplesRotationForTesting();
    // המתג נקרא מההגדרות בבניית ה-State, ולכן בדיקה שמפעילה אותו הייתה
    // משפיעה על הבדיקות שאחריה.
    Settings.setValue<bool>('key-find-ref-include-personal-books', false);
  });

  testWidgets('מצב הפתיחה מציג כותרת, הסבר ודוגמאות', (tester) async {
    await _pumpDialog(tester);

    expect(find.text('איתור מקורות'), findsOneWidget);
    expect(find.text('איתור מקור מדויק'), findsOneWidget);
    expect(find.text('דוגמאות'), findsOneWidget);
    expect(_chipLabels(tester), contains('בראשית פרק א'));
    expect(find.text('סגור'), findsOneWidget);
  });

  testWidgets('לחיצה על הצעה ממלאת את השדה ומריצה איתור', (tester) async {
    await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);

    // ההצעה נלקחת מהמסך ולא מקודדת קשיח — סדר הדוגמאות מתחלף בין פתיחות.
    final label = _chipLabels(tester)[1];
    final chip = find.widgetWithText(ActionChip, label);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(FocusRepository().findRefSearchController.text, label);
    expect(find.text('מקור אחד'), findsOneWidget);
  });

  testWidgets('כשיש איתורים אחרונים הם מוצגים במקום הדוגמאות', (tester) async {
    FindRefRecentStore.remember('בראשית פרק א');
    FindRefRecentStore.remember('רמב"ם תשובה ב');

    await _pumpDialog(tester);

    expect(find.text('האיתורים האחרונים'), findsOneWidget);
    expect(find.text('דוגמאות'), findsNothing);
    expect(_chipLabels(tester), ['רמב"ם תשובה ב', 'בראשית פרק א']);
  });

  // issue #1288 — לא הייתה דרך לנקות את רשימת האיתורים האחרונים מהמסך.
  testWidgets('ניקוי האיתורים האחרונים מוחק אותם ומחזיר את הדוגמאות', (
    tester,
  ) async {
    FindRefRecentStore.remember('בראשית פרק א');
    FindRefRecentStore.remember('רמב"ם תשובה ב');

    await _pumpDialog(tester, screenSize: const Size(1200, 900));
    expect(find.text('האיתורים האחרונים'), findsOneWidget);

    await tester.tap(find.byTooltip('נקה'));
    await tester.pumpAndSettle();

    expect(FindRefRecentStore.load(), isEmpty);
    expect(find.text('האיתורים האחרונים'), findsNothing);
    expect(find.text('דוגמאות'), findsOneWidget);
    expect(find.byTooltip('נקה'), findsNothing);
  });

  testWidgets('הסרת איתור אחרון בודד משאירה את השאר, והאחרון מחזיר דוגמאות', (
    tester,
  ) async {
    FindRefRecentStore.remember('בראשית פרק א');
    FindRefRecentStore.remember('רמב"ם תשובה ב');

    await _pumpDialog(tester, screenSize: const Size(1200, 900));

    Finder deleteOf(String label) => find.descendant(
      of: find.widgetWithText(InputChip, label),
      matching: find.byTooltip('הסר'),
    );
    await tester.tap(deleteOf('רמב"ם תשובה ב'));
    await tester.pumpAndSettle();

    expect(FindRefRecentStore.load(), ['בראשית פרק א']);
    expect(_chipLabels(tester), ['בראשית פרק א']);
    expect(find.text('האיתורים האחרונים'), findsOneWidget);

    await tester.tap(deleteOf('בראשית פרק א'));
    await tester.pumpAndSettle();

    expect(FindRefRecentStore.load(), isEmpty);
    expect(find.text('דוגמאות'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('בהיעדר איתורים אחרונים הדוגמאות מתחלפות בין פתיחות', (
    tester,
  ) async {
    await _pumpDialog(tester);
    final first = _chipLabels(tester);

    await _pumpDialog(tester);
    final second = _chipLabels(tester);

    expect(first, isNotEmpty);
    expect(second, isNot(equals(first)));
  });

  testWidgets('החלפת הדוגמאות אינה כותבת להגדרות', (tester) async {
    const legacyKey = 'key-find-ref-examples-offset';
    await Settings.setValue<int?>(legacyKey, null);

    await _pumpDialog(tester);
    await _pumpDialog(tester);

    expect(Settings.getValue<int>(legacyKey), isNull);
  });

  testWidgets('הדבקת קישור איתור מריצה אותו בדיאלוג בלי לסגור', (tester) async {
    final host = _FakeHost();
    final pops = _PopCounter();
    await _pumpDialog(
      tester,
      results: [_ref('בראשית פרק א')],
      host: host,
      observer: pops,
    );

    await tester.enterText(
      find.byType(TextField),
      'otzaria://open/detection?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(FocusRepository().findRefSearchController.text, 'בראשית');
    expect(find.byType(FindRefDialog), findsOneWidget);
    expect(find.text('מקור אחד'), findsOneWidget);
    expect(host.deepLinks, isEmpty, reason: 'אין ניתוב דרך המסך הראשי');
    expect(pops.pops, 0);
  });

  testWidgets('קישור שאינו איתור עדיין מנותב דרך המסך הראשי', (tester) async {
    final host = _FakeHost();
    await _pumpDialog(tester, host: host);

    await tester.enterText(find.byType(TextField), 'otzaria://open/sdk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(_pastDebounce);

    expect(host.deepLinks, hasLength(1));
  });

  testWidgets('"פתח חיפוש טקסט" עובר דרך המסך הראשי ולא סוגר בעצמו', (
    tester,
  ) async {
    final host = _FakeHost();
    final pops = _PopCounter();
    await _pumpDialog(tester, host: host, observer: pops);

    await tester.enterText(find.byType(TextField), 'אין כזה');
    await tester.pump(_pastDebounce);
    await tester.pump();
    final button = find.text('פתח חיפוש טקסט');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(host.textSearches, ['אין כזה']);
    expect(pops.pops, 0, reason: 'המסך הראשי הוא שסוגר את האיתור');
  });

  testWidgets('"לא נמצאה ספרייה" מציע ניסיון חוזר', (tester) async {
    final repository = _FakeRepository(
      const [],
      error: const ReferenceLibraryMissingException(),
    );
    await _pumpDialog(tester, repository: repository);

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    expect(find.text('לא נמצאה ספרייה'), findsOneWidget);
    final callsBefore = repository.calls;

    final retry = find.text('נסה שוב');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(repository.calls, callsBefore + 1);
  });

  testWidgets('פתיחת תוצאה נשמרת כאיתור אחרון', (tester) async {
    await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    await tester.tap(find.text('בראשית פרק א'));
    await tester.pump();

    expect(FindRefRecentStore.load(), contains('בראשית'));
  });

  testWidgets('תוצאות מוצגות עם נתיב הספר ומספר התוצאות', (tester) async {
    await _pumpDialog(
      tester,
      results: [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
    );

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(find.text('בראשית פרק ב'), findsOneWidget);
    expect(find.text('תנ"ך, תורה'), findsNWidgets(2));
    expect(find.text('2 מקורות'), findsOneWidget);
  });

  testWidgets('חץ למטה מעביר את הסימון לתוצאה הבאה', (tester) async {
    await _pumpDialog(
      tester,
      results: [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
    );

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(_titleStyleOf(tester, 'בראשית פרק א')?.fontWeight, FontWeight.w600);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_titleStyleOf(tester, 'בראשית פרק ב')?.fontWeight, FontWeight.w600);
    expect(
      _titleStyleOf(tester, 'בראשית פרק א')?.fontWeight,
      FontWeight.normal,
    );
  });

  testWidgets('חצים והקלדה אינם בונים מחדש את הדיאלוג כולו', (tester) async {
    await _pumpDialog(
      tester,
      results: [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
    );
    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    // מופע ווידג'ט הכותרת מתחלף רק כשה-State של הדיאלוג נבנה מחדש.
    Widget header() => tester.widget(find.text('איתור מקורות'));
    final before = header();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_titleStyleOf(tester, 'בראשית פרק ב')?.fontWeight, FontWeight.w600);
    expect(identical(header(), before), isTrue, reason: 'חץ');

    await tester.enterText(find.byType(TextField), 'בראשית פ');
    await tester.pump();
    expect(identical(header(), before), isTrue, reason: 'הקלדה');
    await tester.pump(_pastDebounce);
  });

  testWidgets('חץ למעלה מחזיר את הסימון לתוצאה הקודמת', (tester) async {
    await _pumpDialog(
      tester,
      results: [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
    );

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(_titleStyleOf(tester, 'בראשית פרק א')?.fontWeight, FontWeight.w600);
  });

  testWidgets('החלפת מתג הספרים האישיים מאפסת את הסימון', (tester) async {
    await _pumpDialog(
      tester,
      results: [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
    );

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_titleStyleOf(tester, 'בראשית פרק ב')?.fontWeight, FontWeight.w600);

    await tester.tap(find.byType(Switch));
    await tester.pump(_pastDebounce);
    await tester.pump();

    // בלי האיפוס, אינדקס שנשאר מסט תוצאות ארוך יותר מפיל את הפתיחה ב-Enter.
    expect(_titleStyleOf(tester, 'בראשית פרק א')?.fontWeight, FontWeight.w600);
  });

  testWidgets('נשמרת השאילתה שהניבה את התוצאות ולא הקלדה חדשה', (tester) async {
    await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    // רווח אינו משנה את הנרמול — התוצאות עדיין של השאילתה שבשדה.
    await tester.enterText(find.byType(TextField), 'בראשית ');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('בראשית פרק א'));
    await tester.pump();

    expect(FindRefRecentStore.load(), ['בראשית']);

    // ניקוז ה-debounce התלוי — טיימר ששורד את פירוק העץ מכשיל את הבדיקה.
    await tester.pump(_pastDebounce);
  });

  group('תוצאות של שאילתה קודמת (U1)', () {
    final repo = _QueryRepository({
      'בראשית': [_ref('בראשית פרק א')],
      'שמות': [_ref('שמות פרק א')],
      'שמות ב': [_ref('שמות פרק ב')],
    });

    Future<void> showFirstResults(WidgetTester tester) async {
      await _pumpDialog(tester, repository: repo);
      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);
      await tester.pump();
      expect(find.text('בראשית פרק א'), findsOneWidget);
    }

    testWidgets('לחיצה בתוך ה-debounce אינה פותחת תוצאה ישנה', (tester) async {
      await showFirstResults(tester);
      await tester.enterText(find.byType(TextField), 'שמות');
      await tester.pump(const Duration(milliseconds: 50));

      final oldTile = find.ancestor(
        of: find.text('בראשית פרק א'),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(oldTile).onTap, isNull);
      await tester.tap(find.text('בראשית פרק א'));
      await tester.pump();
      expect(FindRefRecentStore.load(), isEmpty);
      await tester.pump(_pastDebounce);
    });

    testWidgets('Enter בתוך ה-debounce אינו פותח את התוצאה הישנה', (
      tester,
    ) async {
      await showFirstResults(tester);
      await tester.enterText(find.byType(TextField), 'שמות');
      await tester.pump(const Duration(milliseconds: 50));

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(FindRefRecentStore.load(), isNot(contains('בראשית')));
      await tester.pump(_pastDebounce);
    });

    testWidgets('Enter ממתין ופותח את התוצאה הראשונה של השאילתה החדשה', (
      tester,
    ) async {
      await showFirstResults(tester);
      await tester.enterText(find.byType(TextField), 'שמות');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(FindRefRecentStore.load(), isEmpty);

      await tester.pump(_pastDebounce);
      await tester.pump();

      expect(FindRefRecentStore.load(), ['שמות']);
    });

    testWidgets('הקלדה אחרי Enter מבטלת את הפתיחה הממתינה', (tester) async {
      await showFirstResults(tester);
      await tester.enterText(find.byType(TextField), 'שמות');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'שמות ב');
      await tester.pump(_pastDebounce);
      await tester.pump();

      expect(find.text('שמות פרק ב'), findsOneWidget);
      expect(FindRefRecentStore.load(), isEmpty);
    });
  });

  testWidgets('כפתור הניקוי מרוקן את השדה ומחזיר למצב הפתיחה', (tester) async {
    await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    expect(find.text('בראשית פרק א'), findsOneWidget);

    await tester.tap(find.byTooltip('נקה'));
    await tester.pump();

    expect(FocusRepository().findRefSearchController.text, isEmpty);
    expect(find.text('איתור מקור מדויק'), findsOneWidget);
  });

  testWidgets('שינוי הסתרה בחלון אחר מרוקן תוצאה ישנה ומריץ את השאילתה מחדש', (
    tester,
  ) async {
    final repo = _GatedRepository(
      first: [_ref('בראשית פרק קנ')],
      second: [_ref('בראשית פרק קנא')],
    );
    addTearDown(() {
      if (!repo.gate.isCompleted) repo.gate.complete();
    });
    final sync = SettingsSync.instance;
    final previousApply = sync.applyLocally;
    sync.applyLocally = (key, value) => Settings.setValue<String>(
      key,
      value as String,
    );
    addTearDown(() => sync.applyLocally = previousApply);
    await _pumpDialog(tester, repository: repo);

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    expect(find.text('בראשית פרק קנ'), findsOneWidget);

    expect(
      await sync.applyAuthoritativeValues({
        HiddenLibraryStore.bookKeysSetting: '["o__11__בראשית"]',
      }),
      isTrue,
    );
    await tester.pump();
    expect(find.text('בראשית פרק קנ'), findsNothing);

    await tester.pump(_pastDebounce);
    expect(repo.calls, 2);
    repo.gate.complete();
    await tester.pump();
    expect(find.text('בראשית פרק קנא'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('שמירת הסתרה מקומית מרעננת דיאלוג פתוח פעם אחת', (tester) async {
    final store = HiddenLibraryStore();
    await store.save(const HiddenLibrarySelection());
    addTearDown(() => store.save(const HiddenLibrarySelection()));
    final repo = _GatedRepository(
      first: [_ref('בראשית פרק קנ')],
      second: [_ref('בראשית פרק קנא')],
    );
    addTearDown(() {
      if (!repo.gate.isCompleted) repo.gate.complete();
    });
    await _pumpDialog(tester, repository: repo);

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    expect(find.text('בראשית פרק קנ'), findsOneWidget);

    await store.save(
      const HiddenLibrarySelection(bookKeys: {'o__11__בראשית'}),
    );
    await tester.pump();
    expect(find.text('בראשית פרק קנ'), findsNothing);
    await tester.pump(_pastDebounce);
    expect(repo.calls, 2);
    repo.gate.complete();
    await tester.pump();
    expect(find.text('בראשית פרק קנא'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('בחירה בתפריט מפרשים פתוח אינה פותחת ספר שהוסתר בינתיים', (
    tester,
  ) async {
    final store = HiddenLibraryStore();
    await store.save(const HiddenLibrarySelection());
    addTearDown(() => store.save(const HiddenLibrarySelection()));
    final previousLibrary =
        DataRepository.instance.cachedLibraryFutureForTesting;
    final library = Library(categories: []);
    final category = Category(
      title: 'מפרשים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: library,
    );
    library.subCategories.add(category);
    final commentator = TextBook(
      id: 81,
      title: 'רש"י על בראשית',
      category: category,
      categoryId: 42,
    );
    category.books.add(commentator);
    DataRepository.instance.library = Future.value(library);
    addTearDown(() {
      if (previousLibrary == null) {
        DataRepository.instance.invalidateLibraryCache();
      } else {
        DataRepository.instance.library = previousLibrary;
      }
    });
    final repo = _FakeRepository(
      [_ref('בראשית פרק א')],
      commentators: const [
        DbCommentatorEntry(
          title: 'רש"י על בראשית',
          bookId: 81,
          targetSegment: 0,
        ),
      ],
    );
    await _pumpDialog(tester, repository: repo);
    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    await tester.pump();
    final button = find.byTooltip('הצג מפרשים זמינים');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text(commentator.title), findsOneWidget);
    final popupItem = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem,
    );

    await store.save(
      HiddenLibrarySelection(
        bookKeys: {PerBookSettings.bookKey(commentator)},
      ),
    );
    await tester.tap(popupItem);
    await tester.pump();
    expect(find.text('איתור מקורות'), findsOneWidget);
    await tester.pump(_pastDebounce);
  });

  testWidgets('ללא תוצאות מוצג מצב ריק עם מעבר לחיפוש טקסט', (tester) async {
    await _pumpDialog(tester);

    await tester.enterText(find.byType(TextField), 'ספר שאינו קיים');
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(find.textContaining('לא הצלחנו לאתר'), findsOneWidget);
    expect(find.widgetWithText(ActionButton, 'פתח חיפוש טקסט'), findsOneWidget);
  });

  testWidgets('כשל במאגר מוצג כמצב שגיאה', (tester) async {
    await _pumpDialog(tester, error: Exception('DB down'));

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(find.text('האיתור נכשל'), findsOneWidget);
    expect(find.text('אירעה שגיאה בזמן האיתור'), findsOneWidget);
    expect(find.textContaining('DB down'), findsNothing);
    expect(find.widgetWithText(ActionButton, 'נסה שוב'), findsOneWidget);
  });

  testWidgets('"נסה שוב" במצב שגיאה מריץ את השאילתה מחדש', (tester) async {
    final repo = _FlakyRepository([_ref('בראשית פרק א')]);
    await _pumpDialog(
      tester,
      repository: repo,
      screenSize: const Size(1200, 900),
    );

    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    expect(find.text('האיתור נכשל'), findsOneWidget);

    final retry = find.widgetWithText(ActionButton, 'נסה שוב');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(repo.calls, 2);
    expect(find.text('בראשית פרק א'), findsOneWidget);
  });

  group('התאמה לגדלי מסך', () {
    const sizes = <String, Size>{
      'טלפון לאורך': Size(360, 720),
      'טלפון קטן': Size(320, 568),
      'טלפון לרוחב': Size(740, 360),
      'טאבלט': Size(834, 1112),
      'חלון דסקטופ מינימלי': Size(420, 400),
      'דסקטופ רחב': Size(2560, 1440),
    };

    for (final entry in sizes.entries) {
      for (final textScale in const [1.0, 1.5, 2.0]) {
        testWidgets('${entry.key} @${textScale}x — נכנס במסך בלי חריגה', (
          tester,
        ) async {
          await _pumpDialog(
            tester,
            results: [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
            screenSize: entry.value,
            textScale: textScale,
          );

          await tester.enterText(find.byType(TextField), 'בראשית');
          await tester.pump(_pastDebounce);
          await tester.pump();

          expect(tester.takeException(), isNull);
          // הפאנל עצמו נמדד ולא ה-Dialog, שממלא את המסך ומרכז את הפאנל בתוכו.
          final panel = tester.getRect(find.byKey(tourFindRefDialogTargetKey));
          expect(panel.left, greaterThanOrEqualTo(0));
          expect(panel.top, greaterThanOrEqualTo(0));
          expect(panel.right, lessThanOrEqualTo(entry.value.width));
          expect(panel.bottom, lessThanOrEqualTo(entry.value.height));
          expect(find.byType(TextField), findsOneWidget);
        });
      }
    }

    testWidgets('מקלדת פתוחה במובייל אינה חותכת את הדיאלוג', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);

      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byKey(tourFindRefDialogTargetKey));
      expect(panel.height, lessThanOrEqualTo(720 - 300));
      expect(find.text('סגור'), findsOneWidget);
    });

    testWidgets('תוצאות קודמות נשארות על המסך בזמן שהשאילתה החדשה רצה', (
      tester,
    ) async {
      final repo = _GatedRepository(
        first: [_ref('בראשית פרק א')],
        second: [_ref('בראשית פרק ב')],
      );
      await _pumpDialog(tester, repository: repo);

      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);
      expect(find.text('בראשית פרק א'), findsOneWidget);

      // הקלדה נוספת — השאילתה החדשה תקועה ב-gate.
      await tester.enterText(find.byType(TextField), 'בראשית פרק');
      await tester.pump(_pastDebounce);

      expect(
        find.text('בראשית פרק א'),
        findsOneWidget,
        reason: 'הרשימה הקודמת אינה נעלמת בזמן טעינה',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'חיווי עבודה שקט ליד מספר התוצאות',
      );

      repo.gate.complete();
      await tester.pump(_pastDebounce);
      expect(find.text('בראשית פרק ב'), findsOneWidget);
      expect(find.text('בראשית פרק א'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('תוצאה ישנה נראית אך אינה נפתחת בלחיצה בזמן טעינה', (
      tester,
    ) async {
      final repo = _GatedRepository(
        first: [_ref('בראשית פרק א')],
        second: [_ref('בראשית פרק ב')],
      );
      await _pumpDialog(tester, repository: repo);
      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);
      await tester.enterText(find.byType(TextField), 'בראשית פרק');
      await tester.pump(_pastDebounce);

      final oldTile = find.ancestor(
        of: find.text('בראשית פרק א'),
        matching: find.byType(ListTile),
      );
      expect(oldTile, findsOneWidget);
      expect(tester.widget<ListTile>(oldTile).onTap, isNull);
      await tester.tap(find.text('בראשית פרק א'));
      await tester.pump();
      expect(find.text('בראשית פרק א'), findsOneWidget);

      repo.gate.complete();
      await tester.pump(_pastDebounce);
      final newTile = find.ancestor(
        of: find.text('בראשית פרק ב'),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(newTile).onTap, isNotNull);
    });

    testWidgets('Enter אינו פותח תוצאה ישנה בזמן טעינה', (tester) async {
      final repo = _GatedRepository(
        first: [_ref('בראשית פרק א')],
        second: [_ref('בראשית פרק ב')],
      );
      await _pumpDialog(tester, repository: repo);
      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);
      await tester.enterText(find.byType(TextField), 'בראשית פרק');
      await tester.pump(_pastDebounce);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('בראשית פרק א'), findsOneWidget);
      expect(tester.takeException(), isNull);

      repo.gate.complete();
      await tester.pump(_pastDebounce);
      expect(find.text('בראשית פרק ב'), findsOneWidget);
    });

    testWidgets('בזמן טעינה הרשימה הישנה אינה מבקשת מפרשים', (tester) async {
      final repo = _CommentatorCountingRepository(
        first: [_ref('בראשית פרק א')],
        second: [_ref('בראשית פרק ב')],
      );
      await _pumpDialog(tester, repository: repo);
      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);
      await tester.pump();
      expect(repo.commentatorCalls, 1);

      await tester.enterText(find.byType(TextField), 'בראשית פרק');
      await tester.pump(_pastDebounce);
      await tester.pump();
      await tester.pump();
      expect(repo.commentatorCalls, 1, reason: 'רשימה ישנה בזמן טעינה');

      repo.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('בראשית פרק ב'), findsOneWidget);
      expect(repo.commentatorCalls, 2);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('סט תוצאות של שאילתה אחרת מתחיל מראש הרשימה', (tester) async {
      final repo = _QueryRepository({
        'בראשית': [for (var i = 1; i <= 40; i++) _ref('בראשית $i')],
        'שמות': [for (var i = 1; i <= 40; i++) _ref('שמות $i')],
      });
      await _pumpDialog(tester, repository: repo);
      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);
      await tester.pump();

      final list = find.byType(Scrollable).last;
      await tester.drag(list, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(find.text('בראשית 1'), findsNothing);

      await tester.enterText(find.byType(TextField), 'שמות');
      await tester.pump(_pastDebounce);
      await tester.pump();
      await tester.pump();

      expect(find.text('שמות 1'), findsOneWidget);
    });

    testWidgets('מקום כפתור המפרשים שמור מהפריים הראשון', (tester) async {
      await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);
      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);

      // ה-fake מחזיר רשימת מפרשים ריקה, ולכן הכפתור לא יופיע לעולם — ובכל
      // זאת מקומו שמור, כדי שהופעתו בשורה אמיתית לא תזיז את הטקסט.
      final trailing = find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(Visibility),
      );
      expect(trailing, findsOneWidget);
      final visibility = tester.widget<Visibility>(trailing);
      expect(visibility.visible, isFalse);
      expect(visibility.maintainSize, isTrue);
      expect(
        tester.getSize(trailing).width,
        greaterThan(0),
        reason: 'המקום נשמר גם כשאין מפרשים',
      );
    });

    testWidgets('מקלדת פתוחה בטלפון לרוחב — שדה ההקלדה נשאר, בלי חריגה', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(740, 360);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.reset);

      await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);

      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byKey(tourFindRefDialogTargetKey));
      expect(panel.height, lessThanOrEqualTo(360 - 220));
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
