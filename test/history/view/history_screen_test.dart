import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';

class MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

Bookmark _searchBookmark(
  String ref, {
  required String query,
  SearchConfiguration? configuration,
}) {
  return Bookmark(
    ref: ref,
    book: TextBook(title: query),
    index: 0,
    isSearch: true,
    searchConfiguration: configuration?.toMap(),
  );
}

Bookmark _bookmark(String ref, {String? workspaceName}) {
  return Bookmark(
    ref: ref,
    book: TextBook(title: ref),
    index: 0,
    workspaceName: workspaceName,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HistoryView - workspace filter chips', () {
    late MockHistoryBloc historyBloc;
    late StreamController<HistoryState> stateController;

    setUp(() {
      historyBloc = MockHistoryBloc();
      stateController = StreamController<HistoryState>.broadcast();
      whenListen(
        historyBloc,
        stateController.stream,
        initialState: HistoryLoaded([]),
      );
    });

    tearDown(() async {
      await stateController.close();
    });

    Widget buildWidget() {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<HistoryBloc>.value(
            value: historyBloc,
            child: const HistoryView(),
          ),
        ),
      );
    }

    testWidgets('לא מציג צ\'יפים כשכל הפריטים שייכים ל-workspace אחד', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('ברכות ב.', workspaceName: 'גמרא'),
        ]),
      );
      await tester.pump();

      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('לא מציג צ\'יפים כשאין workspaceName בפריטים', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:'),
          _bookmark('ברכות ב.'),
        ]),
      );
      await tester.pump();

      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('מציג צ\'יפים עם שמות ה-workspaces כשיש 2+', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      expect(find.byType(FilterChip), findsNWidgets(2));
      expect(find.widgetWithText(FilterChip, 'גמרא'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'הלכה'), findsOneWidget);
    });

    testWidgets('לחיצה על צ\'יפ מסננת את הרשימה לאותו workspace', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('ברכות ב.', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsNothing);
    });

    testWidgets('לחיצה שנייה על צ\'יפ שנבחר מבטלת את הסינון', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      // בחר גמרא
      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();
      expect(find.text('הלכות שבת'), findsNothing);

      // בטל בחירה
      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();
      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsOneWidget);
    });

    testWidgets(
      'workspace שנבחר ונמחק מההיסטוריה - הסינון מתבטל אוטומטית (P1 regression)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildWidget());
        stateController.add(
          HistoryLoaded([
            _bookmark('שבת עד:', workspaceName: 'גמרא'),
            _bookmark('הלכות שבת', workspaceName: 'הלכה'),
          ]),
        );
        await tester.pump();

        // בחר workspace 'גמרא'
        await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
        await tester.pump();
        expect(find.text('שבת עד:'), findsOneWidget);
        expect(find.text('הלכות שבת'), findsNothing);

        // state חדש - workspace 'גמרא' נעלם
        stateController.add(
          HistoryLoaded([
            _bookmark('הלכות שבת', workspaceName: 'הלכה'),
          ]),
        );
        await tester.pump();

        // אין צ'יפים (workspace יחיד)
        expect(find.byType(FilterChip), findsNothing);
        // הפריט הנותר מוצג - סינון לא תקוע
        expect(find.text('הלכות שבת'), findsOneWidget);
      },
    );

    testWidgets('חיפוש טקסט מוצא פריטים לפי שם workspace', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      // חפש לפי שם workspace
      await tester.enterText(find.byType(TextField).first, 'גמרא');
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsNothing);
    });

    testWidgets('צ\'יפ וחיפוש טקסט פועלים ביחד', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _bookmark('שבת עד:', workspaceName: 'גמרא'),
          _bookmark('ברכות ב.', workspaceName: 'גמרא'),
          _bookmark('הלכות שבת', workspaceName: 'הלכה'),
        ]),
      );
      await tester.pump();

      // סנן לגמרא
      await tester.tap(find.widgetWithText(FilterChip, 'גמרא'));
      await tester.pump();

      // חיפוש על גבי הסינון
      await tester.enterText(find.byType(TextField).first, 'שבת');
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsNothing);
      expect(find.text('הלכות שבת'), findsNothing);
    });
  });

  group('HistoryView - חיווי הגדרות חיפוש בפריט', () {
    late MockHistoryBloc historyBloc;
    late StreamController<HistoryState> stateController;

    setUp(() {
      historyBloc = MockHistoryBloc();
      stateController = StreamController<HistoryState>.broadcast();
      whenListen(
        historyBloc,
        stateController.stream,
        initialState: HistoryLoaded([]),
      );
    });

    tearDown(() async {
      await stateController.close();
    });

    Widget buildWidget() {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<HistoryBloc>.value(
            value: historyBloc,
            child: const HistoryView(),
          ),
        ),
      );
    }

    testWidgets('הכותרת מציגה את השאילתה וההגדרות יורדות לכותרת המשנה', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _searchBookmark(
            'כדאי + הוא + בית',
            query: 'כדאי הוא בית',
            configuration: const SearchConfiguration(distance: 5),
          ),
        ]),
      );
      await tester.pump();

      // הכותרת — השאילתה המפורמטת (ה-ref), בלי ההגדרות.
      expect(find.text('כדאי + הוא + בית'), findsOneWidget);
      // כותרת המשנה — ההגדרות עם תווית ברורה.
      expect(find.text('הגדרות: מרחק 5'), findsOneWidget);
    });

    testWidgets('חיפוש ברירת מחדל אינו מציג חיווי הגדרות', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      stateController.add(
        HistoryLoaded([
          _searchBookmark(
            'שבת',
            query: 'שבת',
            configuration: const SearchConfiguration(),
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('שבת'), findsOneWidget);
      expect(find.textContaining('הגדרות:'), findsNothing);
    });
  });
}
