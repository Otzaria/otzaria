import 'dart:async';

/// אותו גבול polling של ה-probe הראשי; timeout הוא כשל ולא דגימה מוצלחת.
Future<void> waitForPdfProbeCondition(
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 45),
  Future<void> Function()? advance,
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    final remaining = timeout - clock.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Waiting for $description', timeout);
    }
    await (advance?.call() ??
            Future<void>.delayed(const Duration(milliseconds: 16)))
        .timeout(
          remaining,
          onTimeout: () =>
              throw TimeoutException('Waiting for $description', timeout),
        );
  }
}
