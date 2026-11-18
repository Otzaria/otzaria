import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/pending_attached_catalog.dart';

void main() {
  test('tracks completion of a pending catalog read', () async {
    final completer = Completer<String>();
    final pending = PendingAttachedCatalog(completer.future);

    expect(pending.future, same(completer.future));
    expect(pending.done, isFalse);
    expect(pending.timedOut, isFalse);

    completer.complete('catalog');
    expect(await pending.future, 'catalog');

    expect(pending.done, isTrue);
  });

  test('marks the read done when the future fails', () async {
    final completer = Completer<String>();
    final pending = PendingAttachedCatalog(completer.future);

    final error = StateError('catalog failed');
    final expectation = expectLater(pending.future, throwsA(same(error)));
    completer.completeError(error);
    await expectation;

    expect(pending.done, isTrue);
  });

  test('timeout state is independent of future completion', () async {
    final completer = Completer<String>();
    final pending = PendingAttachedCatalog(completer.future);

    pending.timedOut = true;
    expect(pending.timedOut, isTrue);
    expect(pending.done, isFalse);

    completer.complete('catalog');
    await pending.future;

    expect(pending.done, isTrue);
    expect(pending.timedOut, isTrue);
  });
}
