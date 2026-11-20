import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/error_boundary.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';

void main() {
  Future<void> pumpBoundaryWithError(WidgetTester tester) async {
    final originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {};
    addTearDown(() => FlutterError.onError = originalHandler);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ErrorBoundary(child: Text('תוכן רגיל'))),
      ),
    );
    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.fromString(
          '#0      package:otzaria/tools/shamor_zachor/screens/fake_screen.dart',
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('מסך השגיאה הוא הרכיב הסטנדרטי OtzariaErrorState', (
    tester,
  ) async {
    await pumpBoundaryWithError(tester);

    expect(find.byType(OtzariaErrorState), findsOneWidget);
    expect(find.text('אירעה שגיאה לא צפויה. אנא נסה שוב.'), findsOneWidget);
  });

  testWidgets('כפתור אחד, "נסה שוב", גם כשהשגיאה אינה ניתנת לשחזור', (
    tester,
  ) async {
    await pumpBoundaryWithError(tester);

    expect(find.byType(ActionButton), findsOneWidget);
    expect(find.text('נסה שוב'), findsOneWidget);
    expect(find.text('איפוס'), findsNothing);
  });

  testWidgets('"נסה שוב" מחזיר את התוכן', (tester) async {
    await pumpBoundaryWithError(tester);
    expect(find.text('תוכן רגיל'), findsNothing);

    await tester.tap(find.text('נסה שוב'));
    await tester.pumpAndSettle();

    expect(find.text('תוכן רגיל'), findsOneWidget);
    expect(find.byType(OtzariaErrorState), findsNothing);
  });
}
