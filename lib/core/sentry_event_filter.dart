import 'package:sentry_flutter/sentry_flutter.dart';

/// מחזירה האם אירוע Sentry הוא חריגה לא מטופלת מהגרסה המופצת הנוכחית.
bool shouldReportSentryEvent({
  required SentryEvent event,
  required int currentBuild,
  required int latestReleasedBuildNumber,
}) {
  if (currentBuild != latestReleasedBuildNumber) return false;

  final exceptions = event.exceptions;
  if (exceptions == null || exceptions.isEmpty) return false;

  final exceptionText = exceptions
      .map((exception) => exception.value ?? '')
      .join('\n');
  if (_isKnownSentryNoise(exceptionText)) return false;

  return !exceptions.every((exception) => exception.mechanism?.handled == true);
}

bool _isKnownSentryNoise(String exceptionText) {
  return exceptionText.contains('Failed to update ui::AXTree') ||
      exceptionText.contains('accessibility_bridge.cc') ||
      exceptionText.contains('!_pressedKeys.containsKey(event.physicalKey)') ||
      exceptionText.contains(
        'A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed',
      ) ||
      exceptionText.contains(
        'A KeyUpEvent is dispatched, but the state shows that the physical key is not pressed',
      );
}
