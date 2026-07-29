import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// גרירת קובץ מה-OS לאזור בלי מאזין drop מנווטת את הדף לקובץ עצמו (ברירת
// המחדל של Chromium) ועוקפת את מדיניות ה-file:// של התוסף. preventDefault
// ברמת window מבטל את הניווט בלי לשבור אזורי גרירה שהתוסף מגדיר בעצמו —
// המאזינים שלו עדיין מקבלים את האירוע.
const String _dropGuardJs = r'''
(function () {
  // capture=true כדי ש-stopPropagation באלמנט פנימי לא יעקוף את החסימה.
  function isFileDrag(e) {
    var types = e.dataTransfer && e.dataTransfer.types;
    return !!types && Array.prototype.indexOf.call(types, 'Files') !== -1;
  }
  window.addEventListener('dragover', function (e) {
    if (isFileDrag(e)) e.preventDefault();
  }, true);
  window.addEventListener('drop', function (e) {
    if (isFileDrag(e)) e.preventDefault();
  }, true);
})();
''';

/// סקריפט שחוסם את פתיחת קובץ שנגרר לתוך WebView של תוסף.
///
/// מוזרק לכל frame (גם iframes) — הגרירה נוחתת על ה-frame שמתחת לסמן.
UserScript buildPluginDropGuardScript() {
  return UserScript(
    source: _dropGuardJs,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
  );
}
