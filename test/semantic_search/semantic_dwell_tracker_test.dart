import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/semantic_search/services/semantic_dwell_binding.dart';
import 'package:otzaria/semantic_search/services/semantic_dwell_tracker.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';

class _Harness {
  _Harness() {
    tracker = SemanticDwellTracker(
      clock: () => now,
      replacementOf: (tab) => replacements[tab],
      resultsKeyOf: (tab) => identical(tab, resultsClone) ? results : tab,
      timer: (duration, callback) {
        timers.add((due: now.add(duration), callback: callback));
        return Timer(const Duration(days: 365), () {});
      },
    );
  }

  DateTime now = DateTime(2026, 10, 3, 12);
  late final SemanticDwellTracker tracker;
  final timers = <({DateTime due, void Function() callback})>[];
  final ended = <({Duration dwell, SearchFeedbackDwellEnd reason})>[];

  final replacements = <Object, Object>{};
  final results = Object();
  final resultsClone = Object();
  final book = Object();
  final other = Object();

  void begin({Object? tab}) => tracker.begin(
    tab: tab,
    resultsTab: results,
    onEnd: (dwell, reason) => ended.add((dwell: dwell, reason: reason)),
  );

  void observe(Object? active, {List<Object>? open, bool showsTabs = true}) =>
      tracker.observe(
        SemanticDwellObservation(
          activePane: active,
          openPanes: open ?? [results, book, other],
          showsTabs: showsTabs,
        ),
      );

  void advance(Duration duration) => now = now.add(duration);
}

void main() {
  test('חזרה לכרטיסיית התוצאות מסיימת ב-returnedToResults', () {
    final h = _Harness();
    h.observe(h.results);
    h.begin();
    h.observe(h.book);
    h.advance(const Duration(seconds: 42));
    h.observe(h.results);

    expect(h.ended.single.reason, SearchFeedbackDwellEnd.returnedToResults);
    expect(h.ended.single.dwell, const Duration(seconds: 42));
  });

  test('מעבר לכרטיסייה אחרת או למסך אחר — tabSwitched', () {
    final h = _Harness();
    h.observe(h.results);
    h.begin();
    h.observe(h.book);
    h.advance(const Duration(seconds: 5));
    h.observe(h.other);

    final screen = _Harness();
    screen.observe(screen.results);
    screen.begin();
    screen.observe(screen.book);
    screen.advance(const Duration(seconds: 7));
    screen.observe(screen.book, showsTabs: false);

    expect(h.ended.single.reason, SearchFeedbackDwellEnd.tabSwitched);
    expect(screen.ended.single.reason, SearchFeedbackDwellEnd.tabSwitched);
    expect(screen.ended.single.dwell, const Duration(seconds: 7));
  });

  test('סגירת הכרטיסייה — tabClosed', () {
    final h = _Harness();
    h.observe(h.results);
    h.begin();
    h.observe(h.book);
    h.advance(const Duration(seconds: 3));
    h.observe(h.results, open: [h.results]);

    expect(h.ended.single.reason, SearchFeedbackDwellEnd.tabClosed);
  });

  test('יציאה מהתוכנה — appExit; מעקב שלא התחיל נזנח', () {
    final h = _Harness();
    h.observe(h.results);
    h.begin();
    h.begin(tab: h.other);
    h.observe(h.book);
    h.advance(const Duration(seconds: 9));
    h.tracker.endAll(SearchFeedbackDwellEnd.appExit);

    expect(h.ended, hasLength(1));
    expect(h.ended.single.reason, SearchFeedbackDwellEnd.appExit);
    expect(h.ended.single.dwell, const Duration(seconds: 9));
    expect(h.tracker.hasSessions, isFalse);
  });

  test('אחרי 30 דקות המעקב נחתך ב-capped, גם בלי שינוי במסך', () {
    final h = _Harness();
    h.observe(h.results);
    h.begin();
    h.observe(h.book);
    final timer = h.timers.last;
    expect(timer.due, h.now.add(const Duration(minutes: 30)));

    h.advance(const Duration(minutes: 31));
    timer.callback();

    expect(h.ended.single.reason, SearchFeedbackDwellEnd.capped);
    expect(h.ended.single.dwell, const Duration(minutes: 30));
  });

  test('פתיחה ברקע נמדדת רק מרגע שהכרטיסייה הופכת לפעילה', () {
    final h = _Harness();
    h.observe(h.results, open: [h.results]);
    h.begin(tab: h.book);
    // הכרטיסייה עוד לא הגיעה למצב — אסור לזנוח אותה.
    h.observe(h.results, open: [h.results]);
    h.observe(h.results);
    h.advance(const Duration(minutes: 2));
    h.observe(h.book);
    h.advance(const Duration(seconds: 4));
    h.observe(h.results);

    expect(h.ended.single.dwell, const Duration(seconds: 4));
    expect(h.ended.single.reason, SearchFeedbackDwellEnd.returnedToResults);
  });

  test('פתיחה שלא הובילה לכרטיסייה פעילה נזנחת אחרי הזמן הקצוב', () {
    final h = _Harness();
    h.observe(h.results);
    h.begin();
    h.advance(const Duration(seconds: 11));
    h.observe(h.results);

    expect(h.tracker.hasSessions, isFalse);
    expect(h.ended, isEmpty);
  });

  test('כרטיסיית טעינה שהוחלפה בכרטיסייה הסופית — המעקב ממשיך בה', () {
    final h = _Harness();
    final loading = Object();
    h.observe(h.results, open: [h.results, loading]);
    h.begin();
    h.observe(loading, open: [h.results, loading]);
    h.advance(const Duration(seconds: 2));
    h.replacements[loading] = h.book;
    h.observe(h.book, open: [h.results, h.book]);
    h.advance(const Duration(seconds: 8));
    h.observe(h.results, open: [h.results, h.book]);

    expect(h.ended.single.reason, SearchFeedbackDwellEnd.returnedToResults);
    expect(h.ended.single.dwell, const Duration(seconds: 10));
  });

  test('כרטיסייה שנפתחה ברקע ולא הופעלה נזנחת אחרי 30 דקות', () {
    final h = _Harness();
    h.observe(h.results);
    h.begin(tab: h.other);
    h.observe(h.results);
    expect(h.tracker.hasSessions, isTrue);

    h.advance(const Duration(minutes: 31));
    h.timers.last.callback();

    expect(h.tracker.hasSessions, isFalse);
    expect(h.ended, isEmpty);
  });

  test('חזרה לעותק משוכפל של כרטיסיית התוצאות — returnedToResults', () {
    final h = _Harness();
    h.observe(h.results, open: [h.results, h.book, h.resultsClone]);
    h.begin();
    h.observe(h.book, open: [h.results, h.book, h.resultsClone]);
    h.advance(const Duration(seconds: 6));
    h.observe(h.resultsClone, open: [h.results, h.book, h.resultsClone]);

    expect(h.ended.single.reason, SearchFeedbackDwellEnd.returnedToResults);
  });

  test('יציאה ממתינה לכתיבת הדיווחים', () async {
    final h = _Harness();
    var written = false;
    h.observe(h.results);
    h.tracker.begin(
      resultsTab: h.results,
      onEnd: (_, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        written = true;
      },
    );
    h.observe(h.book);
    h.advance(const Duration(seconds: 1));

    await h.tracker.endAll(SearchFeedbackDwellEnd.appExit);

    expect(written, isTrue);
  });

  test('חלון ממוזער או ללא פוקוס — המסך אינו נחשב מוצג', () {
    final observation = dwellObservationOf(
      TabsState.initial(),
      Screen.reading,
      appActive: false,
    );
    expect(observation.showsTabs, isFalse);
    expect(
      dwellObservationOf(TabsState.initial(), Screen.reading).showsTabs,
      isTrue,
    );
  });
}
