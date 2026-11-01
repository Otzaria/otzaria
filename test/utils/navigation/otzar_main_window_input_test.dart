import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/navigation/otzar_main_window_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, null);
  });

  test('מזהה לא תקין אינו מגיע לקוד הנייטיב', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, (_) async {
      calls++;
      return null;
    });
    await expectLater(OtzarMainWindowInput.openBook(0), throwsArgumentError);
    expect(calls, 0);
  });

  test('בקשה שנייה ממתינה עד שהראשונה מסתיימת', () async {
    final calls = <int>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, (
      call,
    ) async {
      expect(call.method, 'openBookById');
      final id = (call.arguments as Map)['bookId'] as int;
      calls.add(id);
      if (id == 1234) {
        firstStarted.complete();
        await releaseFirst.future;
      }
      return null;
    });
    final first = OtzarMainWindowInput.openBook(1234);
    final second = OtzarMainWindowInput.openBook(5678);
    await firstStarted.future;
    expect(calls, [1234]);
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(calls, [1234, 5678]);
  });

  test('בקשה שנכשלה אינה חוסמת את הבאה, והשגיאה מגיעה כמות שהיא', () async {
    final calls = <int>[];
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, (
      call,
    ) async {
      final id = (call.arguments as Map)['bookId'] as int;
      calls.add(id);
      if (id == 7) {
        throw PlatformException(code: 'focus_lost', details: true);
      }
      return null;
    });
    await expectLater(
      OtzarMainWindowInput.openBook(7),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'focus_lost')
            .having((e) => e.details, 'details', true),
      ),
    );
    await OtzarMainWindowInput.openBook(8);
    expect(calls, [7, 8]);
  });
}
