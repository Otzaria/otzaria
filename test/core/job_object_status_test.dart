import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/window_listener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('otzaria/process_control');

  void mockStatus(Object? response) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'jobObjectStatus');
          return response;
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('קונטיינמנט פעיל — ready אמת ובלי failure', () async {
    mockStatus({'ready': true, 'failure': null});
    final status = await AppWindowListener.jobObjectStatus();
    expect(status.ready, isTrue);
    expect(status.failure, isNull);
  });

  test('כשל הקמה — ready שקר ו-failure עם שלב הכשל', () async {
    mockStatus({
      'ready': false,
      'failure': 'AssignProcessToJobObject failed (error 5)',
    });
    final status = await AppWindowListener.jobObjectStatus();
    expect(status.ready, isFalse);
    expect(status.failure, contains('AssignProcessToJobObject'));
  });

  test('תשובה חסרה מה-runner אינה מפילה — נחשבת לא-מוכן', () async {
    mockStatus(null);
    final status = await AppWindowListener.jobObjectStatus();
    expect(status.ready, isFalse);
    expect(status.failure, isNull);
  });
}
