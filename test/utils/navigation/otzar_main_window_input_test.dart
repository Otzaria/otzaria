import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/navigation/otzar_main_window_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, null);
  });

  test('invalid ID never reaches native code', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, (_) async {
      calls++;
      return {'sent': true};
    });
    await expectLater(OtzarMainWindowInput.openBook(0), throwsArgumentError);
    expect(calls, 0);
  });

  test('requests are serialized until the native operation finishes', () async {
    final calls = <int>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, (call) async {
      expect(call.method, 'openBookById');
      final id = (call.arguments as Map)['bookId'] as int;
      calls.add(id);
      if (id == 1234) {
        firstStarted.complete();
        await releaseFirst.future;
      }
      return {'sent': true, 'bookId': id, 'openedVerified': false};
    });
    final first = OtzarMainWindowInput.openBook(1234);
    final second = OtzarMainWindowInput.openBook(5678);
    await firstStarted.future;
    expect(calls, [1234]);
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(calls, [1234, 5678]);
  });

  test('failed focus does not trigger duplicate input or poison the queue', () async {
    final calls = <int>[];
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, (call) async {
      final id = (call.arguments as Map)['bookId'] as int;
      calls.add(id);
      if (id == 7) {
        throw PlatformException(code: 'focus_lost');
      }
      return {'sent': true};
    });
    await expectLater(
      OtzarMainWindowInput.openBook(7),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'focus_lost')),
    );
    await OtzarMainWindowInput.openBook(8);
    expect(calls, [7, 8]);
  });

  test('missing native confirmation is treated as failure', () async {
    messenger.setMockMethodCallHandler(OtzarMainWindowInput.channel, (_) async => {});
    await expectLater(
      OtzarMainWindowInput.openBook(9),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'input_not_confirmed')),
    );
  });
}
