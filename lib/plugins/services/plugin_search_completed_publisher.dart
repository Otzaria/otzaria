import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/search/models/search_completion.dart';

/// מוסר לתוספים את האירוע `search.completed`: חיפוש טקסט מלא באוצריא הסתיים
/// בהצלחה, עם המונה הסופי. האירוע לקריאה בלבד ואינו משנה את החיפוש.
class PluginSearchCompletedPublisher {
  PluginSearchCompletedPublisher({
    Future<void> Function(String topic, Map<String, dynamic> payload)? sink,
  }) : _sink = sink ?? PluginRuntimeDispatcher.instance.dispatchEvent;

  static const topic = 'search.completed';

  final Future<void> Function(String topic, Map<String, dynamic> payload) _sink;

  /// ה-payload של האירוע. [request] הוא אותו אובייקט ש-`search.requested`
  /// נושא, כך שתוסף יכול להעביר אותו כמות שהוא לחיפוש משלו.
  @visibleForTesting
  static Map<String, dynamic> payloadFor({
    required String tabId,
    required SearchCompletion completion,
    required Map<String, dynamic> request,
  }) => {
    'tabId': tabId,
    'requestId': completion.requestId,
    'query': completion.query,
    'mode': completion.configuration.searchMode.name,
    'request': request,
    'total': completion.total,
    'totalKind': completion.countsGroups ? 'groups' : 'matches',
    'truncated': completion.truncated,
    'returned': completion.returned,
  };

  /// שולח את האירוע לכל תוסף שנרשם אליו. כשל במסירה לא מגיע לחיפוש.
  void publish({
    required String tabId,
    required SearchCompletion completion,
    required Map<String, dynamic> Function() buildRequest,
  }) {
    unawaited(
      Future<void>(() {
        return _sink(
          topic,
          payloadFor(
            tabId: tabId,
            completion: completion,
            request: buildRequest(),
          ),
        );
      }).catchError((Object error) {
        debugPrint('PluginSearchCompletedPublisher: $error');
      }),
    );
  }
}
