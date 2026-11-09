import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/error_boundary.dart';

void main() {
  testWidgets('משחזר את FlutterError.onError אחרי dispose', (tester) async {
    final originalHandler = FlutterError.onError;
    void sentinelHandler(FlutterErrorDetails details) {}
    FlutterError.onError = sentinelHandler;
    addTearDown(() => FlutterError.onError = originalHandler);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorBoundary(
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(identical(FlutterError.onError, sentinelHandler), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(identical(FlutterError.onError, sentinelHandler), isTrue);
  });

  testWidgets('לא הופך לשגיאה עבור FlutterError חיצוני', (tester) async {
    final originalHandler = FlutterError.onError;
    var forwardedCalls = 0;
    FlutterError.onError = (details) {
      forwardedCalls++;
    };
    addTearDown(() => FlutterError.onError = originalHandler);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorBoundary(
            child: Text('תוכן רגיל'),
          ),
        ),
      ),
    );

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: const FormatException(
          'Unable to parse JSON message:\nThe document is empty.',
        ),
      ),
    );
    await tester.pump();

    expect(forwardedCalls, 1);
    expect(find.text('תוכן רגיל'), findsOneWidget);
    expect(find.text('אירעה שגיאה לא צפויה. אנא נסה שוב.'), findsNothing);
  });

  testWidgets('מציג fallback עבור שגיאה של שמור וזכור', (tester) async {
    final originalHandler = FlutterError.onError;
    var forwardedCalls = 0;
    FlutterError.onError = (details) {
      forwardedCalls++;
    };
    addTearDown(() => FlutterError.onError = originalHandler);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorBoundary(
            child: Text('תוכן רגיל'),
          ),
        ),
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

    expect(forwardedCalls, 1);
    expect(find.text('תוכן רגיל'), findsNothing);
    expect(find.text('אירעה שגיאה לא צפויה. אנא נסה שוב.'), findsOneWidget);
  });

  // לכלי אין Navigator משלו (DD-29): "איפוס" לא נוגע בניווט של החלון.
  testWidgets('איפוס מחזיר את התוכן ולא סוגר route של החלון', (tester) async {
    final originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {};
    addTearDown(() => FlutterError.onError = originalHandler);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('מסך קודם')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: ErrorBoundary(child: Text('תוכן רגיל')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.fromString(
          '#0      package:otzaria/tools/shamor_zachor/screens/fake_screen.dart',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('אירעה שגיאה לא צפויה. אנא נסה שוב.'), findsOneWidget);

    await tester.tap(find.text('איפוס'));
    await tester.pumpAndSettle();

    expect(find.text('תוכן רגיל'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isTrue);
    expect(find.text('מסך קודם'), findsNothing);
  });
}
