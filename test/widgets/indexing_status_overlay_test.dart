import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/widgets/indexing_status_overlay.dart';

class MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

void main() {
  testWidgets('מציג חיווי מיד כשיש יצירת אינדקס בפועל',
      (WidgetTester tester) async {
    final bloc = MockIndexingBloc();
    const indexingState = IndexingInProgress(
      booksProcessed: 25,
      totalBooks: 100,
      isCreatingIndex: true,
    );

    whenListen(
      bloc,
      const Stream<IndexingState>.empty(),
      initialState: indexingState,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<IndexingBloc>.value(
          value: bloc,
          child: const Scaffold(
            body: IndexingStatusOverlay(),
          ),
        ),
      ),
    );

    expect(find.text('התוכנה בתהליך אינדוקס'), findsOneWidget);
    expect(find.text('ייתכן איטיות בפעילות התוכנה'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('התקדמות: 25/100'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Align && widget.alignment == Alignment.bottomLeft,
      ),
      findsOneWidget,
    );
  });

  testWidgets('לא מציג חיווי כשיש רק מעבר על ספרים בלי יצירת אינדקס',
      (WidgetTester tester) async {
    final bloc = MockIndexingBloc();
    const indexingState = IndexingInProgress(
      booksProcessed: 25,
      totalBooks: 100,
      isCreatingIndex: false,
    );

    whenListen(
      bloc,
      const Stream<IndexingState>.empty(),
      initialState: indexingState,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<IndexingBloc>.value(
          value: bloc,
          child: const Scaffold(
            body: IndexingStatusOverlay(),
          ),
        ),
      ),
    );

    expect(find.text('התוכנה בתהליך אינדוקס'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('לא מציג כלום כשאין אינדוקס פעיל', (WidgetTester tester) async {
    final bloc = MockIndexingBloc();

    whenListen(
      bloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<IndexingBloc>.value(
          value: bloc,
          child: const Scaffold(
            body: IndexingStatusOverlay(),
          ),
        ),
      ),
    );

    expect(find.text('התוכנה בתהליך אינדוקס'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('לחיצה על החיווי מפעילה את פעולת הניווט שסופקה',
      (WidgetTester tester) async {
    final bloc = MockIndexingBloc();
    const indexingState = IndexingInProgress(
      booksProcessed: 25,
      totalBooks: 100,
      isCreatingIndex: true,
    );
    var tapped = false;

    whenListen(
      bloc,
      const Stream<IndexingState>.empty(),
      initialState: indexingState,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<IndexingBloc>.value(
          value: bloc,
          child: Scaffold(
            body: IndexingStatusOverlay(
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('התוכנה בתהליך אינדוקס'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}
