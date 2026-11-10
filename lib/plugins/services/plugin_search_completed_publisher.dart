import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/search/models/search_completion.dart';
import 'package:otzaria/search/search_dialog_query.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

/// מוסר לתוספים את האירוע `search.completed`: חיפוש טקסט מלא באוצריא הסתיים
/// בהצלחה, עם המונה הסופי. האירוע לקריאה בלבד ואינו משנה את החיפוש.
class PluginSearchCompletedPublisher {
  PluginSearchCompletedPublisher({
    required this.viewId,
    required this.windowId,
    this._sink,
  });

  static const topic = 'search.completed';

  final int viewId;
  final String windowId;
  final Future<void> Function(String topic, Map<String, dynamic> payload)?
  _sink;
  final _subscriptions = <SearchingTab, StreamSubscription<SearchCompletion>>{};
  bool _disposed = false;

  /// הרשימה מגיעה מבעל הטאבים בחלון, גם כשהתוצאות טרם הורכבו למסך.
  void updateTabs(Iterable<SearchingTab> tabs) {
    if (_disposed) return;
    final current = tabs.toSet();
    for (final tab in _subscriptions.keys.toList()) {
      if (!current.contains(tab)) {
        unawaited(_subscriptions.remove(tab)!.cancel());
      }
    }
    for (final tab in current) {
      if (_subscriptions.containsKey(tab)) continue;
      late final StreamSubscription<SearchCompletion> subscription;
      void publish(SearchCompletion completion) => unawaited(
        _publish(
          tab,
          completion,
          isCurrent: _completionGuard(
            _subscriptions,
            tab,
            subscription,
            completion,
          ),
        ),
      );
      subscription = tab.searchBloc.completions.listen(publish);
      _subscriptions[tab] = subscription;
      final completed = tab.searchBloc.lastCompletion;
      if (completed != null) publish(completed);
    }
  }

  /// תור של תוסף מושהה אינו משאיר טאב שנסגר ואת תוצאותיו בזיכרון.
  static bool Function() _completionGuard(
    Map<SearchingTab, StreamSubscription<SearchCompletion>> subscriptions,
    SearchingTab tab,
    StreamSubscription<SearchCompletion> subscription,
    SearchCompletion completion,
  ) {
    final tabRef = WeakReference(tab);
    final subscriptionRef = WeakReference(subscription);
    return () {
      final currentTab = tabRef.target;
      final currentSubscription = subscriptionRef.target;
      return currentTab != null &&
          currentSubscription != null &&
          identical(subscriptions[currentTab], currentSubscription) &&
          identical(currentTab.searchBloc.lastCompletion, completion);
    };
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  /// ה-payload של האירוע. [request] הוא אותו אובייקט ש-`search.requested`
  /// נושא, כך שתוסף יכול להעביר אותו כמות שהוא לחיפוש משלו.
  @visibleForTesting
  static Map<String, dynamic> payloadFor({
    required String tabId,
    required String windowId,
    required SearchCompletion completion,
    required Map<String, dynamic> request,
  }) => {
    'tabId': tabId,
    'windowId': windowId,
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
  Future<void> _publish(
    SearchingTab tab,
    SearchCompletion completion, {
    required bool Function() isCurrent,
  }) async {
    try {
      if (!isCurrent()) return;
      final configuration = completion.configuration;
      final searched = completion.request;
      final request = pluginSearchRequest(
        query: completion.query,
        negativeQuery: completion.negativeQuery,
        mode: configuration.searchMode,
        distance: searched.distance,
        proximityScope: searched.scope,
        facets: completion.facets,
        configuration: configuration,
        normalizedParameters: SearchQueryBuilder.normalizeParametersForMode(
          configuration.searchMode,
          customSpacing: searched.customSpacing,
          alternativeWords: searched.alternativeWords,
          searchOptions: searched.searchOptions,
        ),
        normalizedNegativeParameters:
            SearchQueryBuilder.normalizeParametersForMode(
              configuration.searchMode,
              customSpacing: searched.negativeCustomSpacing,
              alternativeWords: searched.negativeAlternativeWords,
              searchOptions: searched.negativeSearchOptions,
            ),
      );
      final payload = payloadFor(
        tabId: tab.pluginTabId,
        windowId: windowId,
        completion: completion,
        request: request,
      );
      if (!tab.claimSearchCompletion(completion.requestId)) return;
      final sink = _sink;
      await (sink != null
          ? sink(topic, payload)
          : PluginRuntimeDispatcher.instance.dispatchEvent(
              topic,
              payload,
              viewId: viewId,
              isCurrent: isCurrent,
            ));
    } catch (error) {
      debugPrint('PluginSearchCompletedPublisher: $error');
    }
  }
}
