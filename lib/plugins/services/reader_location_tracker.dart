import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

typedef ReaderLocationResolver =
    Future<ReaderLocationSnapshot?> Function(
      OpenedTab? currentTab,
    );

typedef ReaderLocationEventDispatcher =
    Future<void> Function(
      String topic,
      Map<String, dynamic> payload,
    );

/// עוקב אחרי שינויי מיקום בקורא ומפיץ אירועים לתוספים
///
/// אחראי על:
/// - מעקב אחרי הטאב הפעיל
/// - זיהוי שינויי מיקום (index, ref, page)
/// - dedupe של אירועים זהים
/// - שליחת reader.current_ref_changed
class ReaderLocationTracker {
  final TabsBloc _tabsBloc;
  final ReaderLocationResolver _resolveLocation;
  final ReaderLocationEventDispatcher _dispatchEvent;
  final Duration _debounceDuration;

  StreamSubscription<TabsState>? _tabsSubscription;
  StreamSubscription? _currentTabStreamListener;
  VoidCallback? _currentTabValueListener;
  Timer? _debounceTimer;

  String? _lastSignature;
  OpenedTab? _lastTab;
  int _generation = 0; // למניעת race conditions

  ReaderLocationTracker({
    required this._tabsBloc,
    this._resolveLocation = resolveReaderLocation,
    this._dispatchEvent = _dispatchReaderLocationEvent,
    this._debounceDuration = const Duration(milliseconds: 150),
  }) {
    _init();
  }

  void _init() {
    // האזנה לשינויים ב-TabsBloc
    _tabsSubscription = _tabsBloc.stream.listen(_handleTabsStateChange);

    // טיפול במצב הראשוני
    _handleTabsStateChange(_tabsBloc.state);
  }

  void _handleTabsStateChange(TabsState state) {
    // החלונית הפעילה ולא הטאב: על טאב מפוצל אין למה להאזין, ולכן אירועי
    // שינוי מיקום לא נשלחו כלל בזמן קריאה בפיצול.
    final currentTab = state.activePane;

    // אם הטאב השתנה, צריך לנתק listeners ישנים ולהתחבר לחדש
    if (currentTab != _lastTab) {
      _disconnectFromTab();
      _lastTab = currentTab;
      _generation++; // הגדלת generation למניעת race
      _connectToTab(currentTab);

      // שינוי טאב = שינוי מיקום, לכן נבדוק מיד
      _scheduleLocationCheck();
    }
  }

  void _connectToTab(OpenedTab? tab) {
    if (tab == null) return;

    if (tab is TextBookTab) {
      // האזנה ל-currentTitle של הטאב
      _currentTabValueListener = () {
        _scheduleLocationCheck();
      };
      tab.currentTitle.addListener(_currentTabValueListener!);

      // האזנה גם ל-stream של ה-bloc
      _currentTabStreamListener = tab.bloc.stream.listen((_) {
        _scheduleLocationCheck();
      });
    } else if (tab is PdfBookTab) {
      // האזנה ל-currentTitle של ה-PDF
      _currentTabValueListener = () {
        _scheduleLocationCheck();
      };
      tab.currentTitle.addListener(_currentTabValueListener!);

      // האזנה גם לשינויי עמוד דרך ה-controller
      // (זה יקרה אוטומטית כי PdfBookTab מעדכן את pageNumber שלו)
    }
  }

  void _disconnectFromTab() {
    _currentTabStreamListener?.cancel();
    _currentTabStreamListener = null;

    if (_currentTabValueListener != null && _lastTab != null) {
      if (_lastTab is TextBookTab) {
        (_lastTab as TextBookTab).currentTitle.removeListener(
          _currentTabValueListener!,
        );
      } else if (_lastTab is PdfBookTab) {
        (_lastTab as PdfBookTab).currentTitle.removeListener(
          _currentTabValueListener!,
        );
      }
      _currentTabValueListener = null;
    }
  }

  /// מתזמן בדיקת מיקום עם debounce קטן
  void _scheduleLocationCheck() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _checkAndDispatchLocationChange();
    });
  }

  Future<void> _checkAndDispatchLocationChange() async {
    final currentTab = _tabsBloc.state.activePane;
    final generationAtStart = _generation; // שמירת generation לפני async

    // אם אין טאב פעיל, מאפסים את ה-signature כדי שפתיחה מחדש תשלח event
    if (currentTab == null) {
      _lastSignature = null;
      return;
    }

    final snapshot = await _resolveLocation(currentTab);

    // בדיקה שהטאב לא השתנה בזמן ה-async
    if (generationAtStart != _generation) {
      return; // הטאב השתנה, מתעלמים מ-snapshot הישן
    }

    if (snapshot == null) {
      // לא הצלחנו לפתור את המיקום
      return;
    }

    final signature = snapshot.signature();

    // dedupe: אם ה-signature זהה, לא נשלח אירוע
    if (signature == _lastSignature) {
      return;
    }

    _lastSignature = signature;

    // שליחת האירוע
    await _dispatchEvent(
      'reader.current_ref_changed',
      snapshot.toJson(),
    );
  }

  void dispose() {
    _tabsSubscription?.cancel();
    _disconnectFromTab();
    _debounceTimer?.cancel();
    _lastTab = null;
  }
}

Future<void> _dispatchReaderLocationEvent(
  String topic,
  Map<String, dynamic> payload,
) {
  return PluginRuntimeDispatcher.instance.dispatchEvent(topic, payload);
}
