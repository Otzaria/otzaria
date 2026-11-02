import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/find_ref/find_ref_personal_books_setting.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
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
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

/// מחזיר תוצאות קבועות לכל שאילתה — הדיאלוג נבדק על הפריסה, לא על המנוע.
class _FakeRepository implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;

  @override
  Stream<void> get userBooksChanges => const Stream.empty();

  _FakeRepository(this.results, {this.error, this.commentators = const []});

  final List<DbReferenceResult> results;
  final Object? error;
  final List<DbCommentatorEntry> commentators;
  int calls = 0;
  final List<bool> personalBooksFlags = [];

  @override
  void cancelPendingSearch() {}

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    calls++;
    personalBooksFlags.add(includePersonalBooks);
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

  @override
  Stream<void> get userBooksChanges => const Stream.empty();

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
  String query = '',
}) async {
  if (screenSize != null) {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  FocusRepository().findRefSearchController.text = query;
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

/// כותרות השורות שה-ListTile שלהן מסומן selected.
List<String> _selectedTiles(WidgetTester tester) => [
  for (final element in find.byType(ListTile).evaluate())
    if ((element.widget as ListTile).selected)
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byWidget(element.widget),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!,
];

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

  testWidgets('שדה ריק מתעדכן ברישום ובהסרת כפתור תוסף', (tester) async {
    final registry = PluginSearchFieldActionsRegistry.instance;
    addTearDown(() => registry.removeAll('voice'));
    await _pumpDialog(tester);
    final field = find.byType(TextField);
    final initialSize = tester.getSize(field);
    expect(tester.widget<TextField>(field).decoration!.suffixIcon, isNull);

    registry.registerPayload('voice', {
      'id': 'dictate',
      'title': 'חיפוש בדיבור',
      'icon': 'mic_24_regular',
      'fields': ['findRef'],
    });
    await tester.pump();
    expect(find.byTooltip('חיפוש בדיבור'), findsOneWidget);
    expect(FocusRepository().findRefSearchController.text, isEmpty);

    registry.removeAll('voice');
    await tester.pump();
    expect(find.byTooltip('חיפוש בדיבור'), findsNothing);
    expect(tester.widget<TextField>(field).decoration!.suffixIcon, isNull);
    expect(tester.getSize(field), initialSize);
  });

  testWidgets(
    'הכתבה מכפתור תוסף מחליפה את האיתור הקודם המסומן, כמו הקלדה (issue #3878)',
    (tester) async {
      final registry = PluginSearchFieldActionsRegistry.instance;
      addTearDown(() => registry.removeAll('voice'));
      registry.registerPayload('voice', {
        'id': 'dictate',
        'title': 'חיפוש בדיבור',
        'icon': 'mic_24_regular',
        'fields': ['findRef'],
      });
      await _pumpDialog(tester, query: 'בראשית פרק א');
      final controller = FocusRepository().findRefSearchController;
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 12),
      );

      // לחיצת עכבר אמיתית ארוכה מ-kPressTimeout, ואז השדה כבר מגיב ל-tap down.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('חיפוש בדיבור')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kPressTimeout * 2);
      await gesture.up();
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 12),
      );

      final sessions = PluginSearchFieldSessionService.instance;
      final binding =
          tester.state(find.byType(PluginSearchFieldActions))
              as PluginSearchFieldBinding;
      final session = sessions.sessionFor(binding, 'voice', 'dictate')!;
      sessions.setFieldText('voice', session.id, 'שמות פרק ב');
      await tester.pump(_pastDebounce);
      expect(controller.text, 'שמות פרק ב');
    },
    variant: TargetPlatformVariant.all(),
  );

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
    final firstDelete = deleteOf('רמב"ם תשובה ב');
    await tester.drag(
      find.ancestor(of: firstDelete, matching: find.byType(Scrollable)),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(firstDelete.hitTestable(), findsOneWidget);
    await tester.tap(firstDelete);
    await tester.pumpAndSettle();

    expect(FindRefRecentStore.load(), ['בראשית פרק א']);
    expect(_chipLabels(tester), ['בראשית פרק א']);
    expect(find.text('האיתורים האחרונים'), findsOneWidget);

    final lastDelete = deleteOf('בראשית פרק א');
    await tester.ensureVisible(lastDelete);
    await tester.pumpAndSettle();
    expect(lastDelete.hitTestable(), findsOneWidget);
    await tester.tap(lastDelete);
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

  testWidgets('אייקון השורה לפי סוג הספר, כמו ברשימות הספרייה', (tester) async {
    var nextBookId = 1;
    DbReferenceResult result(
      String reference, {
      String fileType = 'txt',
      bool isPdf = false,
      BookSource source = BookSource.official,
    }) => DbReferenceResult(
      title: 'ספר $nextBookId',
      reference: reference,
      segment: 1,
      bookId: nextBookId++,
      bookPath: 'נתיב',
      fileType: fileType,
      isPdf: isPdf,
      source: source,
    );
    await _pumpDialog(
      tester,
      screenSize: const Size(900, 1400),
      results: [
        result('רשמי'),
        result('פי די אף', fileType: 'pdf', isPdf: true),
        result('וורד', fileType: 'docx', source: BookSource.user),
        result('טקסט אישי', source: BookSource.user),
        result('html אישי', fileType: 'html', source: BookSource.user),
        result('htm אישי', fileType: 'htm', source: BookSource.user),
        result('md אישי', fileType: 'md', source: BookSource.user),
        result('markdown אישי', fileType: 'markdown', source: BookSource.user),
        result('epub אישי', fileType: 'epub', source: BookSource.user),
        result('odt אישי', fileType: 'odt', source: BookSource.user),
        result('rtf אישי', fileType: 'rtf', source: BookSource.user),
        result('doc אישי', fileType: 'doc', source: BookSource.user),
        result(
          'html מצורף',
          fileType: 'html',
          source: BookSource.attached('l'),
        ),
        result('md מצורף', fileType: 'md', source: BookSource.attached('l')),
        result('md רשמי', fileType: 'md'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'ספר');
    await tester.pump(_pastDebounce);
    await tester.pump();

    // הרשימה עצלה: שורה נבנית רק כשגוללים אליה, לכן בודקים לפי סדר התוצאות.
    Future<IconData?> leadingIcon(String reference) async {
      await tester.scrollUntilVisible(
        find.text(reference),
        100,
        scrollable: find
            .descendant(
              of: find.byType(FindRefDialog),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      return tester
          .widget<Icon>(
            find
                .descendant(
                  of: find.ancestor(
                    of: find.text(reference),
                    matching: find.byType(ListTile),
                  ),
                  matching: find.byType(Icon),
                )
                .first,
          )
          .icon;
    }

    final expected = <(String, IconData)>[
      ('רשמי', FluentIcons.document_text_24_regular),
      ('פי די אף', OtzariaIcons.book_pdf_24_regular),
      ('וורד', OtzariaIcons.document_word_24_regular),
      ('טקסט אישי', OtzariaIcons.document_alef_24_regular),
      ('html אישי', OtzariaIcons.document_html_24_regular),
      ('htm אישי', OtzariaIcons.document_html_24_regular),
      ('md אישי', OtzariaIcons.document_md_24_regular),
      ('markdown אישי', OtzariaIcons.document_md_24_regular),
      // אין לאלה אייקון משלהם בספרייה.
      ('epub אישי', OtzariaIcons.book_pdf_24_regular),
      ('odt אישי', OtzariaIcons.document_word_24_regular),
      ('rtf אישי', OtzariaIcons.document_word_24_regular),
      ('doc אישי', OtzariaIcons.document_word_24_regular),
      ('html מצורף', OtzariaIcons.document_html_24_regular),
      ('md מצורף', OtzariaIcons.document_md_24_regular),
      ('md רשמי', FluentIcons.document_text_24_regular),
    ];
    for (final (reference, icon) in expected) {
      expect(await leadingIcon(reference), icon, reason: reference);
    }
  });

  testWidgets('הכותרת ברצועת הדיאלוגים, והתחתית בצבע הגוף', (tester) async {
    await _pumpDialog(tester, results: [_ref('בראשית פרק א')]);

    final context = tester.element(find.byType(FindRefDialog));
    expect(
      find.ancestor(
        of: find.text('איתור מקורות'),
        matching: find.byType(AppDialogHeader),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      AppSurfaces.panelBackground(context),
    );
    expect(
      find.ancestor(
        of: find.widgetWithText(ActionButton, 'סגור'),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == AppSurfaces.card(context),
        ),
      ),
      findsNothing,
      reason: 'התחתית אינה צובעת רקע משלה',
    );
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

  testWidgets('השורה המסומנת מדווחת כנבחרת לנגישות', (tester) async {
    await _pumpDialog(
      tester,
      results: [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
    );
    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_selectedTiles(tester), ['בראשית פרק ב']);
  });

  testWidgets('הסימון אינו צובע את כפתור המפרשים', (tester) async {
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
    category.books.add(TextBook(id: 81, title: 'מפרש', category: category));
    DataRepository.instance.library = Future.value(library);
    addTearDown(() {
      if (previousLibrary == null) {
        DataRepository.instance.invalidateLibraryCache();
      } else {
        DataRepository.instance.library = previousLibrary;
      }
    });
    final repo = _FakeRepository(
      [_ref('בראשית פרק א'), _ref('בראשית פרק ב')],
      commentators: const [
        DbCommentatorEntry(title: 'מפרש', bookId: 81, targetSegment: 0),
      ],
    );
    await _pumpDialog(tester, repository: repo);
    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    await tester.pump();

    await tester.pumpAndSettle();
    final buttons = find.byTooltip('הצג מפרשים זמינים');
    expect(buttons, findsNWidgets(2));
    final colors = [
      for (final element
          in find.byIcon(FluentIcons.library_24_regular).evaluate())
        IconTheme.of(element).color,
    ];
    final context = tester.element(find.byType(FindRefDialog));

    expect(_selectedTiles(tester), ['בראשית פרק א']);
    expect(colors, [
      for (var i = 0; i < 2; i++)
        Theme.of(context).colorScheme.onSurfaceVariant,
    ]);
  });

  group('מקשי דפדוף ברשימת התוצאות', () {
    final many = [for (var i = 1; i <= 40; i++) _ref('בראשית פרק $i')];

    Future<void> pumpMany(WidgetTester tester) async {
      await _pumpDialog(
        tester,
        results: many,
        screenSize: const Size(1000, 1400),
      );
      await tester.enterText(find.byType(TextField), 'בראשית');
      await tester.pump(_pastDebounce);
      await tester.pump();
    }

    testWidgets('Ctrl+End ו-Ctrl+Home קופצים לסוף ולתחילת הרשימה', (
      tester,
    ) async {
      await pumpMany(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_selectedTiles(tester), ['בראשית פרק 40']);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_selectedTiles(tester), ['בראשית פרק 1']);
    });

    testWidgets('End בלי Ctrl נשאר לשדה ההקלדה', (tester) async {
      await pumpMany(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();

      expect(_selectedTiles(tester), ['בראשית פרק 1']);
    });

    testWidgets('Ctrl+Shift+End בוחר בשדה ואינו מזיז את הסימון', (
      tester,
    ) async {
      await pumpMany(tester);
      final controller = FocusRepository().findRefSearchController;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(_selectedTiles(tester), ['בראשית פרק 1']);
      expect(
        controller.selection,
        TextSelection(baseOffset: 0, extentOffset: controller.text.length),
      );
    });

    testWidgets('PageDown ו-PageUp מזיזים עמוד שלם של שורות', (tester) async {
      await pumpMany(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      final afterDown = _selectedTiles(tester).single;
      final step = int.parse(afterDown.split(' ').last) - 1;
      expect(step, greaterThan(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(_selectedTiles(tester), ['בראשית פרק 1']);
    });
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
    // גרש אינו משנה את הנרמול, ו-trim אינו מסיר אותו: הנשמר מבדיל ביניהם.
    const variant = "בראשית'";
    expect(
      FindRefBloc.normalizeQuery(variant),
      FindRefBloc.normalizeQuery('בראשית'),
    );
    expect(variant.trim(), isNot('בראשית'));
    await tester.enterText(find.byType(TextField), variant);
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

    testWidgets('קישור איתור חיצוני אחרי Enter מבטל את הפתיחה הממתינה', (
      tester,
    ) async {
      await showFirstResults(tester);
      await tester.enterText(find.byType(TextField), 'שמות');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // כמו otzaria://detection מהמסך הראשי: הטקסט מוחלף בלי onChanged.
      FocusRepository().findRefSearchController.text = 'שמות ב';
      final context = tester.element(find.byType(FindRefDialog));
      context.read<FindRefBloc>().add(const SearchRefRequested('שמות ב'));
      await tester.pump(_pastDebounce);
      await tester.pump();

      expect(find.text('שמות פרק ב'), findsOneWidget);
      expect(FindRefRecentStore.load(), isEmpty);
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

  testWidgets('Enter במצב שגיאה אינו פותח תוצאה אחרי "נסה שוב"', (
    tester,
  ) async {
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

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final retry = find.widgetWithText(ActionButton, 'נסה שוב');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(find.text('בראשית פרק א'), findsOneWidget);
    expect(FindRefRecentStore.load(), isEmpty);
  });

  testWidgets('מתג שהשתנה מחוץ לדיאלוג אינו משאיר תוצאות נעולות', (
    tester,
  ) async {
    final repo = _FakeRepository([_ref('בראשית פרק א')]);
    await _pumpDialog(tester, repository: repo);
    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();

    // חלון אחר הפך את המתג, וקישור חיצוני הריץ איתור בלי ערך מפורש.
    await Settings.setValue<bool>('key-find-ref-include-personal-books', true);
    FocusRepository().findRefSearchController.text = 'בראשית פרק';
    final context = tester.element(find.byType(FindRefDialog));
    context.read<FindRefBloc>().add(const SearchRefRequested('בראשית פרק'));
    await tester.pump(_pastDebounce);
    await tester.pump();

    final tile = find.ancestor(
      of: find.text('בראשית פרק א'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(tile).onTap, isNotNull);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(repo.personalBooksFlags, [false, true]);
  });

  testWidgets('מתג שסונכרן מחלון אחר מריץ מחדש, והתוצאות נפתחות', (
    tester,
  ) async {
    final repo = _FakeRepository([_ref('בראשית פרק א')]);
    await _pumpDialog(tester, repository: repo);
    await tester.enterText(find.byType(TextField), 'בראשית');
    await tester.pump(_pastDebounce);
    await tester.pump();
    expect(repo.personalBooksFlags, [false]);

    await FindRefPersonalBooksSetting.save(true);
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    // Enter לפני שהחיפוש החוזר הסתיים ממתין לו ופותח את תוצאתו.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(_pastDebounce);
    await tester.pump();

    expect(repo.personalBooksFlags, [false, true]);
    final tile = find.ancestor(
      of: find.text('בראשית פרק א'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(tile).onTap, isNotNull);
    expect(FindRefRecentStore.load(), ['בראשית']);
  });

  for (final initialValue in [false, true]) {
    for (final submitDuringDebounce in [false, true]) {
      testWidgets(
        'סנכרון המתג הלוך וחזור בתוך debounce ($initialValue, Enter: $submitDuringDebounce)',
        (tester) async {
          final repo = _FakeRepository([_ref('בראשית פרק א')]);
          await Settings.setValue<bool>(
            'key-find-ref-include-personal-books',
            initialValue,
          );
          await _pumpDialog(tester, repository: repo);
          await tester.enterText(find.byType(TextField), 'בראשית');
          await tester.pump(_pastDebounce);
          await tester.pump();

          await FindRefPersonalBooksSetting.save(!initialValue);
          await tester.pump(const Duration(milliseconds: 180));
          if (submitDuringDebounce) {
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await tester.pump();
            expect(FindRefRecentStore.load(), isEmpty);
          }
          await FindRefPersonalBooksSetting.save(initialValue);
          await tester.pump(_pastDebounce);
          await tester.pump();

          expect(repo.personalBooksFlags, [initialValue]);
          expect(
            tester.widget<Switch>(find.byType(Switch)).value,
            initialValue,
          );
          final tile = find.ancestor(
            of: find.text('בראשית פרק א'),
            matching: find.byType(ListTile),
          );
          expect(tester.widget<ListTile>(tile).onTap, isNotNull);
          expect(
            FindRefRecentStore.load(),
            submitDuringDebounce ? ['בראשית'] : isEmpty,
          );
        },
      );
    }
  }

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
    testWidgets('חלונית קומפקטית נשארת יציבה לאורך החיפוש והגלילה', (
      tester,
    ) async {
      final repo = _GatedRepository(
        first: [_ref('מקור 1')],
        second: [for (var i = 1; i <= 40; i++) _ref('מקור $i')],
      );
      await _pumpDialog(
        tester,
        repository: repo,
        screenSize: const Size(1200, 900),
      );
      final panel = find.byKey(AppWindowKeys.current.tour.findRefDialog);
      final initialRect = tester.getRect(panel);
      final initialFieldRect = tester.getRect(find.byType(TextField));
      expect(initialRect.height, lessThan(600));

      await tester.enterText(find.byType(TextField), 'מקור');
      await tester.pump(_pastDebounce);
      await tester.pump();
      expect(find.text('מקור 1'), findsOneWidget);
      expect(tester.getRect(panel), initialRect);
      expect(tester.getRect(find.byType(TextField)), initialFieldRect);

      await tester.enterText(find.byType(TextField), 'מקור נוסף');
      await tester.pump(_pastDebounce);
      await tester.pump();
      expect(repo.calls, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getRect(panel), initialRect);

      repo.gate.complete();
      await tester.pumpAndSettle();
      expect(tester.getRect(panel), initialRect);
      expect(tester.getRect(find.byType(TextField)), initialFieldRect);
      await tester.scrollUntilVisible(
        find.text('מקור 40'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('מקור 40').hitTestable(), findsOneWidget);
      expect(tester.getRect(panel), initialRect);

      await tester.tap(find.byTooltip('נקה'));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsNothing);
      expect(tester.getRect(panel), initialRect);
      expect(tester.getRect(find.byType(TextField)), initialFieldRect);
      expect(tester.takeException(), isNull);
    });

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
          final panel = tester.getRect(
            find.byKey(AppWindowKeys.current.tour.findRefDialog),
          );
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
      final panel = tester.getRect(
        find.byKey(AppWindowKeys.current.tour.findRefDialog),
      );
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
      final panel = tester.getRect(
        find.byKey(AppWindowKeys.current.tour.findRefDialog),
      );
      expect(panel.height, lessThanOrEqualTo(360 - 220));
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
