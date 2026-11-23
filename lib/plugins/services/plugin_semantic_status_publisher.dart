import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/bridge/plugin_semantic_api.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';

/// מוסר לתוספים את `semantic.status_changed` כשהשלב של החיפוש החכם, כפי
/// שתוסף רואה אותו, משתנה. מאזין לזרם הסטטי בלבד ואינו יוצר את המאגר.
class PluginSemanticStatusPublisher {
  PluginSemanticStatusPublisher._();

  static const topic = 'semantic.status_changed';

  static StreamSubscription<SemanticAvailability>? _subscription;
  static String? _lastPhase;

  /// פעם אחת לתהליך; קריאה חוזרת אינה עושה דבר.
  static void start({
    Stream<SemanticAvailability>? changes,
    Future<void> Function(String topic, Map<String, dynamic> payload)? sink,
  }) {
    _subscription ??=
        (changes ?? SemanticSearchRepository.sharedAvailabilityChanges).listen((
          availability,
        ) {
          final phase = PluginSemanticApi.phaseOf(availability);
          if (phase == _lastPhase) return;
          _lastPhase = phase;
          final payload = {'phase': phase};
          unawaited(
            (sink != null
                    ? sink(topic, payload)
                    : PluginRuntimeDispatcher.instance.dispatchEvent(
                        topic,
                        payload,
                      ))
                .catchError((Object error) {
                  debugPrint('PluginSemanticStatusPublisher: $error');
                }),
          );
        });
  }

  @visibleForTesting
  static Future<void> stopForTesting() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastPhase = null;
  }
}
