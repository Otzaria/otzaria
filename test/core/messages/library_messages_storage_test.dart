import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';

void main() {
  test('הדיאלוג של ייעול האחסון ממליץ על Wi-Fi רק כשמבקשים', () {
    final desktop = LibraryMessages.storageRebaseDialogContent('1.9GB');
    expect(desktop, contains('1.9GB'));
    expect(desktop, isNot(contains(LibraryMessages.storageRebaseWifiHint)));

    final android = LibraryMessages.storageRebaseDialogContent(
      '1.9GB',
      recommendWifi: true,
    );
    expect(android, startsWith(desktop));
    expect(android, endsWith(LibraryMessages.storageRebaseWifiHint));
  });

  test('הודעות ייעול האחסון אינן מניחות מחשב', () {
    for (final text in [
      LibraryMessages.storageRebaseDialogContent('1GB', recommendWifi: true),
      LibraryMessages.storageOptimizedLocally,
    ]) {
      expect(text, isNot(contains('מחשב')));
    }
  });
}
