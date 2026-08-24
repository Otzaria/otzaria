import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// גבול זמן לקריאה נייטיבית. ה-flush רץ תחת מנעול ה-lifecycle של הדיספצ'ר,
/// וקריאה תקועה הייתה מקפיאה גם השהיה/החייאה של תוספים.
const Duration _focusCallTimeout = Duration(seconds: 3);

/// האם הפלטפורמה זקוקה להעברת פוקוס מפורשת אל ה-WebView של תוסף.
///
/// במגע הפוקוס עובר בנגיעה עצמה, והעברה מפורשת בפתיחת טאב הייתה פותחת
/// מקלדת רכה שהמשתמש לא ביקש. בעיית ה-visual hosting היא של שולחן העבודה.
bool supportsPluginKeyboardFocusHandoff(TargetPlatform platform) =>
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.linux ||
    platform == TargetPlatform.macOS;

/// האם להעביר עכשיו את פוקוס המקלדת אל מופע של תוסף.
///
/// [isBackground] - מופע רקע (WebView בלתי-נראה)
/// [hasController] - ה-WebView נרשם וחי
/// [isVisible] - המופע מוצג בטאב העיון הפעיל
/// [isSuspended] - ה-WebView מוקפא (המשתמש עזב את הטאב)
/// [readerScreenVisible] - מסך העיון עצמו גלוי
/// [platformNeedsHandoff] - ראה [supportsPluginKeyboardFocusHandoff]
/// [appIsActive] - חלון האפליקציה בחזית
/// [flutterOwnsKeyboard] - ראה [flutterOwnsKeyboardNow]
///
/// מופע רקע חי בחלון בלתי-נראה, ומופע שאינו מוצג היה חוטף את המקלדת מהטאב
/// שהמשתמש רואה בפועל. פוקוס נייטיבי אינו מכבד scope של דיאלוג או של חלונית
/// אחרת, ולכן כשה-UI של Flutter מחזיק את המקלדת אין לגעת בה.
bool shouldMoveKeyboardFocusToPlugin({
  required bool isBackground,
  required bool hasController,
  required bool isVisible,
  required bool isSuspended,
  required bool readerScreenVisible,
  required bool platformNeedsHandoff,
  required bool appIsActive,
  required bool flutterOwnsKeyboard,
}) {
  if (isBackground || !hasController || !platformNeedsHandoff) return false;
  if (!appIsActive || flutterOwnsKeyboard) return false;
  return isVisible && readerScreenVisible && !isSuspended;
}

/// האם כדאי לזכור בקשת פוקוס שלא ניתן לבצע כרגע.
///
/// המופע הנכון אך עדיין לא מוכן (ה-WebView נוצר אחרי פתיחת הטאב, ו-resume
/// מתרחש תחת מנעול אסינכרוני) — הבקשה תתבצע ברגע שיהיה מוכן. מופע רקע או
/// מופע שאינו מוצג לא יקבל פוקוס גם בהמשך, ולכן אין מה לזכור.
bool shouldRememberKeyboardFocusRequest({
  required bool isBackground,
  required bool isVisible,
  required bool readerScreenVisible,
  required bool platformNeedsHandoff,
}) {
  if (isBackground || !platformNeedsHandoff) return false;
  return isVisible && readerScreenVisible;
}

/// האם [context] יושב בתוך שדה טקסט. הפוקוס של `TextField` יורד ל-`Focus`
/// פנימי, ולכן `EditableText` נמצא בשרשרת האבות ולא ב-widget עצמו.
@visibleForTesting
bool contextIsInsideTextInput(BuildContext? context) =>
    context?.findAncestorWidgetOfExactType<EditableText>() != null;

/// האם [context] יושב בתוך חלון קופץ — דיאלוג או תפריט. דיאלוג של כפתורים
/// בלבד אינו מחזיק שדה טקסט, אבל Esc/Enter/Tab שלו מתים אם המקלדת תעבור.
@visibleForTesting
bool contextIsInsidePopupRoute(BuildContext? context) =>
    context != null && ModalRoute.of(context) is PopupRoute;

/// האם ה-UI של Flutter מחזיק כרגע את המקלדת — שדה טקסט פעיל או חלון קופץ.
bool flutterOwnsKeyboardNow() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return contextIsInsideTextInput(context) ||
      contextIsInsidePopupRoute(context);
}

/// האם חלון האפליקציה בחזית. Alt-Tab בזמן טעינת תוסף לא יגרור העברת פוקוס.
bool appIsActiveNow() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

/// שם ערוץ ה-platform view של `flutter_inappwebview_windows` עבור [viewId].
@visibleForTesting
String customPlatformViewChannelName(Object viewId) =>
    'com.pichillilorenzo/custom_platform_view_$viewId';

/// בווינדוס `InAppWebViewController.requestFocus` אינו ממומש (זורק
/// `UnimplementedError`, וגם אין לו מטפל נייטיבי בערוץ ה-controller) —
/// המימוש שם חי על ערוץ ה-platform view.
@visibleForTesting
bool usesPlatformViewFocusChannel(TargetPlatform platform) =>
    platform == TargetPlatform.windows;

/// שם המתודה הנייטיבית שמעבירה את הפוקוס אל ה-WebView.
@visibleForTesting
const String kPlatformViewRequestFocusMethod = 'requestFocus';

/// מעביר את פוקוס המקלדת של המערכת אל ה-WebView של תוסף.
///
/// ה-WebView של תוסף אינו חלק מעץ הפוקוס של Flutter: בווינדוס הוא מוצג
/// ב-visual hosting, והקשות מגיעות אליו רק אחרי העברת פוקוס נייטיבית
/// (`MoveFocus`) — שקורית מעצמה רק בלחיצת עכבר. בלי הקריאה כאן, פתיחת תוסף
/// משאירה את המקלדת מחוץ לדף ואי אפשר להקליד בו עד קליק.
class PluginWebViewFocus {
  const PluginWebViewFocus._();

  /// מבקש פוקוס מקלדת ל-[controller]. מחזיר האם הבקשה הועברה בהצלחה —
  /// לא האם הפוקוס אכן עבר (הצד הנייטיבי בולע HRESULT כושל).
  /// כשל אינו נזרק: פוקוס הוא נוחות, לא תקינות.
  static Future<bool> request(InAppWebViewController controller) async {
    // הדף כבר במיקוד (המשתמש הקדים ולחץ) — MoveFocus שמגיע אחרי קליק מבטל
    // את הפוקוס שהקליק נתן, וההקלדה נשברת (upstream #2736).
    if (await _pageAlreadyHasFocus(controller)) return true;
    try {
      if (usesPlatformViewFocusChannel(defaultTargetPlatform)) {
        final viewId = controller.getViewId();
        // ערוץ ה-platform view נקרא תמיד על ה-textureId, שהוא מספר. עם
        // keepAlive/headless ה-viewId הוא מזהה אחר — ואז אין ערוץ כזה.
        if (viewId is! int) return false;
        await MethodChannel(customPlatformViewChannelName(viewId))
            .invokeMethod<void>(kPlatformViewRequestFocusMethod)
            .timeout(_focusCallTimeout);
        return true;
      }
      final took = await controller.requestFocus().timeout(_focusCallTimeout);
      return took ?? false;
    } catch (e) {
      debugPrint('PluginWebViewFocus: request failed: $e');
      return false;
    }
  }

  static Future<bool> _pageAlreadyHasFocus(
    InAppWebViewController controller,
  ) async {
    try {
      final result = await controller
          .evaluateJavascript(source: 'document.hasFocus()')
          .timeout(_focusCallTimeout);
      return result == true;
    } catch (e) {
      // לא ידוע — ממשיכים להעברה; ההנחה השמרנית היא שהדף אינו במיקוד.
      return false;
    }
  }
}
