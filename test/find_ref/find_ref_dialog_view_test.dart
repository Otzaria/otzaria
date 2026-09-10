import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/find_ref_recent_store.dart';
import 'package:otzaria/find_ref/repository/db_commentator_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

/// מחזיר תוצאות קבועות לכל שאילתה — הדיאלוג נבדק על הפריסה, לא על המנוע.
class _FakeRepository implements FindRefRepository {
  _FakeRepository(this.results, {this.error});

  final List<DbReferenceResult> results;
  final Object? error;

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    if (error != null) throw error!;
    return results;
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
}) async {
  if (screenSize != null) {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  FocusRepository().findRefSearchController.clear();
  final bloc = FindRefBloc(
    findRefRepository: _FakeRepository(results, error: error),
  );
  addTearDown(bloc.close);

  // עץ ריק ביניים מכריח יצירה מחדש של ה-State — פתיחה חדשה של הדיאלוג,
  // ולא עדכון של הקיים.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
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
              child: const FindRefDialog(),
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

List<String> _chipLabels(WidgetTester tester) => tester
    .widgetList<ActionChip>(find.byType(ActionChip))
    .map((chip) => (chip.label as Text).data!)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    FindRefRecentStore.clear();
    // איפוס היסט הדוגמאות כדי שהחלון המוצג יהיה צפוי בכל בדיקה.
    Settings.setValue<int>('key-find-ref-examples-offset', 0);
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
    // הקלדה נוספת שטרם עברה את ה-debounce — התוצאות הקודמות עדיין מוצגות.
    await tester.enterText(find.byType(TextField), 'בראשיתXYZ');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('בראשית פרק א'));
    await tester.pump();

    expect(FindRefRecentStore.load(), ['בראשית']);

    // ניקוז ה-debounce התלוי — טיימר ששורד את פירוק העץ מכשיל את הבדיקה.
    await tester.pump(_pastDebounce);
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
