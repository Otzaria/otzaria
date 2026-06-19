import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import '../helpers/memory_settings_cache.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
      : super(const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        )) {
    on<PersonalNotesEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) => MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
          BlocProvider<PersonalNotesBloc>.value(
            value: _FakePersonalNotesBloc(),
          ),
        ],
        child: Scaffold(body: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('כרטסיית מפרשי PDF מסתנכרנת עם currentTitle של sourceTab',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 1,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'פרק א': 1,
        'פרק ב': 10,
      },
    );
    sourceTab.currentTitle.value = 'פרק א';
    sourceTab.currentTextLineNumber = 1;
    sourceTab.currentTextLineNumberEnd = 9;

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    // הסנכרון משתקף בטווח השורות שמועבר ל-PdfCommentaryPanel:
    // 'פרק א' מתחיל בשורה 1.
    PdfCommentaryPanel panel() =>
        tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));
    expect(panel().lineStartOverride, 1);

    sourceTab.currentTitle.value = 'פרק ב';
    sourceTab.currentTextLineNumber = 10;
    sourceTab.currentTextLineNumberEnd = 19;
    await tester.pump();

    // הבחירה התעדכנה ל'פרק ב' (מתחיל בשורה 10)
    expect(panel().lineStartOverride, 10);
  });

  testWidgets(
      'תצוגת ספר: כותרת משולבת נפתחת על העמוד הראשון ומציגה גם את העמוד השני',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 2,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'פרק א': 1,
        'פרק ב': 10,
        'פרק ג': 20,
      },
    );
    // כותרת ספירייד משולבת (כפי שנוצרת בתצוגת ספר)
    sourceTab.currentTitle.value = 'פרק ב — פרק ג';

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    PdfCommentaryPanel panel() =>
        tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));

    // לא נופל ל'פרק א' (שורה 1) — נבחר העמוד הראשון בספירייד, 'פרק ב' (שורה 10)
    expect(panel().lineStartOverride, 10);
    // העמוד השני בספירייד ('פרק ג', שורה 20) נכלל דרך extraLineIndices
    expect(panel().extraLineIndices, contains(20));
  });

  testWidgets('כותרת חוקית עם מקף ארוך אינה מפוצלת בטעות לספירייד',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 3,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'שער': 1,
        'שער — מבוא': 30,
        'פרק א': 40,
      },
    );
    // כותרת בודדת חוקית שמכילה מקף ארוך — אינה ספירייד
    sourceTab.currentTitle.value = 'שער — מבוא';

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    PdfCommentaryPanel panel() =>
        tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));

    // נבחרה הכותרת המלאה (שורה 30), לא 'שער' (שורה 1)
    expect(panel().lineStartOverride, 30);
    // אין הוספת עמוד שני — זו כותרת בודדת
    expect(panel().extraLineIndices, isNull);
  });

  testWidgets('ספירייד שכותרתו הראשונה מכילה מקף — מתפצל במקום הנכון',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 2,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'שער — מבוא': 10,
        'פרק א': 20,
        'פרק ב': 30,
      },
    );
    // העמוד הראשון בספירייד הוא הכותרת 'שער — מבוא' (מכילה מקף בעצמה)
    sourceTab.currentTitle.value = 'שער — מבוא — פרק א';

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    PdfCommentaryPanel panel() =>
        tester.widget<PdfCommentaryPanel>(find.byType(PdfCommentaryPanel));

    // העמוד הראשון נבחר נכון ('שער — מבוא', שורה 10) ולא פוצל ל'שער'
    expect(panel().lineStartOverride, 10);
    // העמוד השני ('פרק א', שורה 20) נכלל
    expect(panel().extraLineIndices, contains(20));
  });

  testWidgets(
      'כרטסיית מפרשי PDF מציגה "טוען מפרשים..." בזמן טעינת links של sourceTab',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceTab = PdfBookTab(
      book: PdfBook(title: 'PDF בדיקה', path: '/tmp/book.pdf'),
      pageNumber: 1,
    );
    addTearDown(sourceTab.dispose);

    sourceTab.pdfHeadings = PdfHeadings(
      bookTitle: 'PDF בדיקה',
      headingsMap: {
        'פרק א': 1,
      },
    );
    sourceTab.currentTitle.value = 'פרק א';
    sourceTab.currentTextLineNumber = 1;
    sourceTab.currentTextLineNumberEnd = 9;
    sourceTab.linksLoadingNotifier.value = true;

    final tab = PdfCommentatorsTab(sourceTab: sourceTab);

    await tester.pumpWidget(
      _wrap(PdfCommentatorsTabScreen(tab: tab)),
    );
    await tester.pump();

    expect(find.text('טוען מפרשים...'), findsOneWidget);
    expect(find.text('לא נמצאו מפרשים לקטע הנבחר'), findsNothing);

    sourceTab.linksLoadingNotifier.value = false;
    await tester.pump();

    expect(find.text('לא נמצאו מפרשים לקטע הנבחר'), findsOneWidget);
  });
}
