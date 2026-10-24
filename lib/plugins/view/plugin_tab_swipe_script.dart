import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// שם ה-handler ש-Flutter מאזין לו. הארגומנט: הצטברות ה-dx של המחווה
/// כפי ש-Flutter מדווח עליה (כיוון האצבעות, לא כיוון הגלילה של ה-DOM).
const String pluginTabSwipeHandlerName = 'otzaria_tab_swipe';

// ה-WebView הנייטיבי של macOS מקבל את אירועי הגלילה של לוח המגע ישירות, ו-Flutter
// אינו רואה אותם — ולכן ההחלקה בשתי אצבעות בין טאבים לא עובדת מעליו. כאן
// המחווה נתפסת בצד הדף ומועברת ל-Flutter.
//
// מחווה = רצף אירועי wheel בלי הפסקה של IDLE_MS (כולל תנופת ההמשך — momentum —
// של macOS, ולכן מחווה אחת מדווחת פעם אחת בלבד).
const String _tabSwipeJs = r'''
(function () {
  if (window.__otzariaTabSwipeInstalled) return;
  window.__otzariaTabSwipeInstalled = true;

  var THRESHOLD_PX = 80;
  var IDLE_MS = 150;
  // היחס שמבדיל החלקה אופקית מגלילה אנכית עם סטייה קלה.
  var AXIS_RATIO = 3;

  var accX = 0;
  var accY = 0;
  var lastAt = 0;
  var reported = false;
  // המחווה התחילה בתוך אלמנט שעוד יכול לגלול לכיוונה — היא שלו עד סופה.
  var ownerChecked = false;
  var ownedByPage = false;

  // dx > 0 = גלילה ימינה. ב-RTL scrollLeft הוא בטווח [-max, 0].
  function canScrollX(el, dx) {
    var st = getComputedStyle(el);
    var isRoot = el === document.documentElement || el === document.body;
    var overflowX = st.overflowX;
    if (!isRoot && overflowX !== 'auto' && overflowX !== 'scroll') return false;
    var max = el.scrollWidth - el.clientWidth;
    if (max <= 1) return false;
    var rtl = st.direction === 'rtl';
    var minPos = rtl ? -max : 0;
    var maxPos = rtl ? 0 : max;
    return dx > 0 ? el.scrollLeft < maxPos - 1 : el.scrollLeft > minPos + 1;
  }

  function pageCanScrollX(e, dx) {
    var path = e.composedPath ? e.composedPath() : [];
    for (var i = 0; i < path.length; i++) {
      var node = path[i];
      if (node && node.nodeType === 1 && canScrollX(node, dx)) return true;
    }
    return false;
  }

  window.addEventListener('wheel', function (e) {
    // ctrlKey = צביטת זום; deltaMode != 0 = גלגלת עכבר בשורות, לא לוח מגע.
    if (e.ctrlKey || e.deltaMode !== 0) return;
    if (!window.flutter_inappwebview) return;
    var now = Date.now();
    if (now - lastAt > IDLE_MS) {
      accX = 0;
      accY = 0;
      reported = false;
      ownerChecked = false;
      ownedByPage = false;
    }
    lastAt = now;
    if (reported || ownedByPage) return;
    // הבעלות נקבעת באירוע האופקי הראשון של המחווה, לא בכל אירוע: גלילה
    // שהגיעה לקצה האלמנט באמצע המחווה אינה הופכת למעבר טאב.
    if (!ownerChecked && e.deltaX !== 0) {
      ownerChecked = true;
      if (pageCanScrollX(e, e.deltaX)) {
        ownedByPage = true;
        return;
      }
    }
    accX += e.deltaX;
    accY += e.deltaY;
    if (Math.abs(accX) < THRESHOLD_PX) return;
    if (Math.abs(accX) < AXIS_RATIO * Math.abs(accY)) return;
    reported = true;
    // deltaX חיובי = התוכן זז שמאלה = האצבעות זזו שמאלה; Flutter מדווח את
    // כיוון האצבעות, ולכן הסימן מתהפך.
    window.flutter_inappwebview.callHandler('otzaria_tab_swipe', -accX);
  }, { capture: true, passive: true });
})();
''';

/// סקריפט שמעביר ל-Flutter החלקה אופקית בשתי אצבעות על לוח המגע.
///
/// מוזרק לכל frame: אירוע wheel בתוך iframe אינו מגיע ל-window של ההורה.
UserScript buildPluginTabSwipeScript() {
  return UserScript(
    source: _tabSwipeJs,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
  );
}
