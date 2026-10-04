import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/services/semantic_dwell_tracker.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';

/// מזין את [SemanticDwellTracker] ממצב הכרטיסיות, המסך ופוקוס החלון.
///
/// נוצר בפתיחת התוצאה הראשונה, ולא בעליית התוכנה.
class SemanticDwellBinding {
  SemanticDwellBinding._(this._tabs, this._navigation) {
    _subscriptions = [
      _tabs.stream.listen((_) => _observe()),
      _navigation.stream.listen((_) => _observe()),
    ];
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _appActive = state == AppLifecycleState.resumed;
        _observe();
      },
    );
    PreCloseRegistry.register(_onAppExit);
    _observe();
  }

  static SemanticDwellBinding? _instance;

  /// ההמתנה המרבית ביציאה לכתיבת דיווחי העיון לתור.
  static const Duration exitWait = Duration(milliseconds: 500);

  /// המופע של החלון; נבנה מחדש אם ה-blocs הוחלפו.
  static SemanticDwellBinding of(TabsBloc tabs, NavigationBloc navigation) {
    final current = _instance;
    if (current != null &&
        identical(current._tabs, tabs) &&
        identical(current._navigation, navigation)) {
      return current;
    }
    current?._dispose();
    return _instance = SemanticDwellBinding._(tabs, navigation);
  }

  /// סוגר את המופע (טיימרים ומנויים) — לבדיקות.
  @visibleForTesting
  static void resetForTesting() {
    _instance?._dispose();
    _instance = null;
  }

  final TabsBloc _tabs;
  final NavigationBloc _navigation;
  final SemanticDwellTracker tracker = SemanticDwellTracker(
    replacementOf: (tab) => tab is ResolvingTab ? tab.resolvedTab : null,
    resultsKeyOf: semanticResultsKeyOf,
  );
  late final List<StreamSubscription<Object?>> _subscriptions;
  late final AppLifecycleListener _lifecycle;
  bool _appActive = true;

  void _observe() {
    tracker.observe(
      dwellObservationOf(
        _tabs.state,
        _navigation.state.currentScreen,
        appActive: _appActive,
      ),
    );
  }

  Future<void> _onAppExit() async {
    if (!tracker.hasSessions) return;
    try {
      await tracker.endAll(SearchFeedbackDwellEnd.appExit).timeout(exitWait);
    } on TimeoutException {
      // best effort: היציאה אינה ממתינה יותר מזה לטלמטריה.
    }
  }

  void _dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _lifecycle.dispose();
    PreCloseRegistry.unregister(_onAppExit);
    tracker.dispose();
  }
}

/// מפתח כרטיסיית תוצאות: זהות יציבה ששורדת שכפול.
Object semanticResultsKeyOf(Object tab) =>
    tab is SemanticSearchTab ? tab.resultsId : tab;

/// תצפית מעקב מתוך מצב הכרטיסיות, המסך הנוכחי ופוקוס החלון.
SemanticDwellObservation dwellObservationOf(
  TabsState tabs,
  Screen screen, {
  bool appActive = true,
}) => SemanticDwellObservation(
  activePane: tabs.activePane,
  openPanes: tabs.tabs.expand(leafPanes),
  showsTabs: appActive && (screen == Screen.reading || screen == Screen.search),
);
