import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/download_network_policy.dart';

void main() {
  test('כל רשת אינה פותחת מאזין לסוג החיבור', () async {
    final policy = DownloadNetworkPolicy(
      isAndroid: true,
      wifiOnlyReader: () => false,
      wifiChanges: () => throw StateError('unexpected transport lookup'),
    );
    addTearDown(policy.dispose);
    await policy.requireAccess();
  });

  test('מדיניות Android אינה משנה פלטפורמות אחרות', () async {
    final policy = DownloadNetworkPolicy(
      isAndroid: false,
      wifiOnlyReader: () => true,
      wifiChanges: () => throw StateError('unexpected transport lookup'),
    );
    addTearDown(policy.dispose);
    await policy.requireAccess();
    expect(
      await policy.runResumable(
        () async => 'unchanged',
        checkCancelled: () => throw StateError('unexpected gate'),
      ),
      'unchanged',
    );
  });

  group('WiFi בלבד', () {
    late StreamController<bool> network;
    late DownloadNetworkPolicy policy;
    var wifiOnly = true;

    setUp(() {
      wifiOnly = true;
      network = StreamController<bool>.broadcast(sync: true);
      policy = DownloadNetworkPolicy(
        isAndroid: true,
        wifiOnlyReader: () => wifiOnly,
        wifiChanges: () => network.stream,
      );
    });
    tearDown(() async {
      await policy.dispose();
      await network.close();
    });

    Future<void> wifi(bool available) async {
      final refresh = policy.refresh();
      network.add(available);
      await refresh;
    }

    test('אין היתר לפני תמונת רשת, ובסלולר הבקשה נחסמת', () async {
      expect(policy.status, DownloadNetworkStatus.waitingForWifi);
      await wifi(false);
      await expectLater(
        policy.requireAccess(),
        throwsA(isA<DownloadNetworkPaused>()),
      );
      await wifi(true);
      await policy.requireAccess();
      await wifi(false);
      expect(policy.status, DownloadNetworkStatus.waitingForWifi);
    });

    test('שגיאת זיהוי חיבור אינה מתירה הורדה', () async {
      final refresh = policy.refresh();
      network.addError(StateError('transport unavailable'));
      await refresh;
      expect(policy.status, DownloadNetworkStatus.waitingForWifi);
    });

    test('המתנה מתחדשת גם בביטול הגבלת WiFi', () async {
      await wifi(false);
      var completed = false;
      final waiting = policy.waitUntilAllowed().then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      wifiOnly = false;
      await policy.refresh();
      await waiting;
      expect(completed, isTrue);
    });

    test('ביטול בזמן המתנה משמר את החריגה המקורית', () async {
      await wifi(false);
      var cancelled = false;
      final waiting = policy.waitUntilAllowed(
        checkCancelled: () {
          if (cancelled) throw const _Cancelled();
        },
      );
      final expectation = expectLater(waiting, throwsA(isA<_Cancelled>()));
      cancelled = true;
      await expectation;
    });

    test('WiFi ללא אינטרנט אינו גורר ניסיונות חוזרים של המדיניות', () async {
      await wifi(true);
      var attempts = 0;
      await expectLater(
        policy.runResumable(() async {
          attempts++;
          throw const SocketException('no internet');
        }),
        throwsA(isA<SocketException>()),
      );
      expect(attempts, 1);
    });
  });
}

class _Cancelled implements Exception {
  const _Cancelled();
}
