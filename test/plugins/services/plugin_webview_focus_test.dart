import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_webview_focus.dart';

/// בדיקות להעברת פוקוס המקלדת אל ה-WebView של תוסף (issue #958).
///
/// הרקע: ה-WebView של תוסף אינו חלק מעץ הפוקוס של Flutter. בווינדוס הוא מוצג
/// ב-visual hosting, והקשות מגיעות אליו רק אחרי `MoveFocus` נייטיבי — שקורה
/// מעצמו רק בלחיצת עכבר. לכן בפתיחת תוסף לא היה אפשר להקליד עד קליק.
///
/// שם המסלול בווינדוס הוא ערוץ ה-platform view, ולא
/// `InAppWebViewController.requestFocus` — שם המתודה **אינה ממומשת** וזורקת
/// `UnimplementedError`.

class _FocusFake extends Fake implements InAppWebViewController {
  _FocusFake({
    this.viewId = 7,
    this.focusResult = true,
    this.error,
    this.pageHasFocus = false,
    this.evalError,
    this.hangEvaluate = false,
  });

  final Object? viewId;
  final bool? focusResult;
  final Object? error;

  /// תשובת `document.hasFocus()` — הדף כבר במיקוד (המשתמש הקדים ולחץ).
  final Object? pageHasFocus;
  final Object? evalError;

  /// הדף אינו מגיב — הבדיקה חייבת להיחתך ולא לחסום את ההעברה.
  final bool hangEvaluate;

  int requestFocusCalls = 0;
  int getViewIdCalls = 0;
  final List<String> evaluated = [];

  @override
  dynamic getViewId() {
    getViewIdCalls++;
    return viewId;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    evaluated.add(source);
    if (hangEvaluate) return Completer<dynamic>().future;
    if (evalError != null) throw evalError!;
    return pageHasFocus;
  }

  @override
  Future<bool?> requestFocus({
    FocusDirection? direction,
    InAppWebViewRect? previouslyFocusedRect,
  }) async {
    requestFocusCalls++;
    if (error != null) throw error!;
    return focusResult;
  }
}

/// קריאה למדיניות עם ברירות מחדל של המצב הזכאי, כדי שכל טסט ישנה שער אחד.
bool _policy({
  bool isBackground = false,
  bool hasController = true,
  bool isVisible = true,
  bool isSuspended = false,
  bool readerScreenVisible = true,
  bool platformNeedsHandoff = true,
  bool appIsActive = true,
  bool flutterOwnsKeyboard = false,
}) => shouldMoveKeyboardFocusToPlugin(
  isBackground: isBackground,
  hasController: hasController,
  isVisible: isVisible,
  isSuspended: isSuspended,
  readerScreenVisible: readerScreenVisible,
  platformNeedsHandoff: platformNeedsHandoff,
  appIsActive: appIsActive,
  flutterOwnsKeyboard: flutterOwnsKeyboard,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('shouldMoveKeyboardFocusToPlugin', () {
    test('מופע קדמי מוצג וחי בשולחן עבודה — מעבירים', () {
      expect(_policy(), isTrue);
    });

    test('מופע רקע — לעולם לא (WebView בלתי-נראה)', () {
      expect(_policy(isBackground: true), isFalse);
    });

    test('אין WebView — אין למי להעביר', () {
      expect(_policy(hasController: false), isFalse);
    });

    test('המופע אינו מוצג — היה חוטף מקלדת מהטאב הנראה', () {
      expect(_policy(isVisible: false), isFalse);
    });

    test('מסך העיון מוסתר — לא מעבירים', () {
      expect(_policy(readerScreenVisible: false), isFalse);
    });

    test('ה-WebView מוקפא — לא מעבירים (ההחייאה תשלים)', () {
      expect(_policy(isSuspended: true), isFalse);
    });

    test('פלטפורמת מגע — לא מעבירים (מקלדת רכה לא מבוקשת)', () {
      expect(_policy(platformNeedsHandoff: false), isFalse);
    });

    test('חלון האפליקציה אינו בחזית — לא מעבירים', () {
      expect(_policy(appIsActive: false), isFalse);
    });

    test('ה-UI של Flutter מחזיק את המקלדת — לא גוזלים', () {
      expect(_policy(flutterOwnsKeyboard: true), isFalse);
    });
  });

  group('shouldRememberKeyboardFocusRequest', () {
    test('מוצג ומסך העיון גלוי — זוכרים עד שיהיה מוכן', () {
      expect(
        shouldRememberKeyboardFocusRequest(
          isBackground: false,
          isVisible: true,
          readerScreenVisible: true,
          platformNeedsHandoff: true,
        ),
        isTrue,
      );
    });

    test('מופע רקע — אין מה לזכור', () {
      expect(
        shouldRememberKeyboardFocusRequest(
          isBackground: true,
          isVisible: true,
          readerScreenVisible: true,
          platformNeedsHandoff: true,
        ),
        isFalse,
      );
    });

    test('אינו מוצג — לא ייקבל פוקוס גם בהמשך', () {
      expect(
        shouldRememberKeyboardFocusRequest(
          isBackground: false,
          isVisible: false,
          readerScreenVisible: true,
          platformNeedsHandoff: true,
        ),
        isFalse,
      );
    });

    test('מסך העיון מוסתר — לא זוכרים', () {
      expect(
        shouldRememberKeyboardFocusRequest(
          isBackground: false,
          isVisible: true,
          readerScreenVisible: false,
          platformNeedsHandoff: true,
        ),
        isFalse,
      );
    });

    test('פלטפורמת מגע — לא זוכרים', () {
      expect(
        shouldRememberKeyboardFocusRequest(
          isBackground: false,
          isVisible: true,
          readerScreenVisible: true,
          platformNeedsHandoff: false,
        ),
        isFalse,
      );
    });
  });

  group('supportsPluginKeyboardFocusHandoff', () {
    test('שולחן עבודה — כן', () {
      for (final platform in const [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        expect(supportsPluginKeyboardFocusHandoff(platform), isTrue);
      }
    });

    test('מגע — לא (שם הפוקוס עובר בנגיעה)', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(supportsPluginKeyboardFocusHandoff(platform), isFalse);
      }
    });
  });

  group('זיהוי שדה טקסט ממוקד', () {
    test('אין context — אין שדה טקסט', () {
      expect(contextIsInsideTextInput(null), isFalse);
    });

    testWidgets('TextField ממוקד מזוהה דרך primaryFocus', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: TextField(focusNode: node)),
        ),
      );
      expect(flutterOwnsKeyboardNow(), isFalse);

      node.requestFocus();
      await tester.pump();

      expect(
        flutterOwnsKeyboardNow(),
        isTrue,
        reason: 'המשתמש מקליד — אין לגזול את המקלדת לתוסף',
      );
    });

    testWidgets('פוקוס על צומת שאינו שדה טקסט אינו נחשב', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: node, child: const SizedBox(width: 10)),
        ),
      );
      node.requestFocus();
      await tester.pump();

      expect(flutterOwnsKeyboardNow(), isFalse);
    });

    testWidgets('דיאלוג של כפתורים בלבד מחזיק את המקלדת', (tester) async {
      // בלי השער הזה MoveFocus היה עובר אל ה-WebView שמאחורי הדיאלוג,
      // ו-Esc/Enter/Tab בדיאלוג היו מתים.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('א')),
                  ],
                ),
              ),
              child: const Text('פתח'),
            ),
          ),
        ),
      );
      expect(flutterOwnsKeyboardNow(), isFalse);

      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      expect(flutterOwnsKeyboardNow(), isTrue);
    });

    testWidgets('אין פוקוס בכלל — לא נחשב', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(contextIsInsidePopupRoute(null), isFalse);
    });
  });

  group('בחירת המסלול לפי פלטפורמה', () {
    test('ווינדוס — ערוץ ה-platform view', () {
      expect(usesPlatformViewFocusChannel(TargetPlatform.windows), isTrue);
    });

    test('שאר הפלטפורמות — ה-API של ה-controller', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          usesPlatformViewFocusChannel(platform),
          isFalse,
          reason: 'ערוץ ה-platform view הוא מסלול ווינדוס בלבד',
        );
      }
    });
  });

  group('appIsActiveNow', () {
    tearDown(() {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    });

    test('resumed — פעיל', () {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      expect(appIsActiveNow(), isTrue);
    });

    test('inactive / paused / hidden — לא פעיל', () {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
      ]) {
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          state,
        );
        expect(appIsActiveNow(), isFalse, reason: '$state');
      }
    });
  });

  group('customPlatformViewChannelName', () {
    test('תואם לשם שהחבילה פותחת בצד ה-Dart', () {
      expect(
        customPlatformViewChannelName(12),
        'com.pichillilorenzo/custom_platform_view_12',
      );
    });

    // בונה שם לכל קלט; חסימת מזהה שאינו מספר היא באחריות request.
    test('גם מזהה שאינו מספר מקבל שם', () {
      expect(
        customPlatformViewChannelName('abc-1'),
        'com.pichillilorenzo/custom_platform_view_abc-1',
      );
    });

    test('כל viewId מקבל ערוץ נפרד', () {
      expect(
        customPlatformViewChannelName(1),
        isNot(customPlatformViewChannelName(2)),
      );
    });
  });

  group('PluginWebViewFocus.request — מסלול ווינדוס', () {
    late List<MethodCall> calls;

    void mockChannel(Object viewId, {Object? throws}) {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(customPlatformViewChannelName(viewId)),
            (call) async {
              calls.add(call);
              if (throws != null) throw throws;
              return null;
            },
          );
    }

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    });

    test('קורא requestFocus על ערוץ ה-platform view של אותו viewId', () async {
      mockChannel(7);
      final controller = _FocusFake(viewId: 7);

      expect(await PluginWebViewFocus.request(controller), isTrue);
      expect(calls.map((c) => c.method), [kPlatformViewRequestFocusMethod]);
    });

    test('אינו נוגע ב-controller.requestFocus (זורק בווינדוס)', () async {
      mockChannel(7);
      final controller = _FocusFake(viewId: 7);

      await PluginWebViewFocus.request(controller);

      expect(
        controller.requestFocusCalls,
        0,
        reason: 'בווינדוס ה-API של ה-controller אינו ממומש',
      );
    });

    test('viewId שאינו null נלקח מה-controller', () async {
      mockChannel(42);
      final controller = _FocusFake(viewId: 42);

      expect(await PluginWebViewFocus.request(controller), isTrue);
      expect(controller.getViewIdCalls, 1);
    });

    test('אין viewId — נכשל בשקט בלי קריאה לערוץ', () async {
      mockChannel(7);
      final controller = _FocusFake(viewId: null);

      expect(await PluginWebViewFocus.request(controller), isFalse);
      expect(calls, isEmpty);
    });

    test('viewId שאינו מספר (keepAlive) — לא פונים לערוץ שאינו קיים', () async {
      // ערוץ ה-platform view נקרא תמיד על ה-textureId. עם keepAlive ה-viewId
      // הוא String, ובניית שם ערוץ ממנו הייתה נכשלת בשקט.
      mockChannel('abc-1');
      final controller = _FocusFake(viewId: 'abc-1');

      expect(await PluginWebViewFocus.request(controller), isFalse);
      expect(calls, isEmpty);
    });

    test('הדף כבר במיקוד — לא שולחים MoveFocus נוסף', () async {
      // MoveFocus שמגיע אחרי קליק של המשתמש מבטל את הפוקוס שהקליק נתן.
      mockChannel(7);
      final controller = _FocusFake(viewId: 7, pageHasFocus: true);

      expect(await PluginWebViewFocus.request(controller), isTrue);
      expect(calls, isEmpty);
      expect(controller.evaluated.single, contains('document.hasFocus()'));
    });

    test('בדיקת המיקוד נכשלה — ממשיכים להעברה', () async {
      mockChannel(7);
      final controller = _FocusFake(
        viewId: 7,
        evalError: PlatformException(code: 'dead-bridge'),
      );

      expect(await PluginWebViewFocus.request(controller), isTrue);
      expect(calls.map((c) => c.method), [kPlatformViewRequestFocusMethod]);
    });

    test('תשובה שאינה true אינה נחשבת "כבר במיקוד"', () async {
      mockChannel(7);
      final controller = _FocusFake(viewId: 7, pageHasFocus: 'true');

      await PluginWebViewFocus.request(controller);

      expect(calls, hasLength(1));
    });

    test('הערוץ אינו רשום (פלטפורמה בלי המימוש) — false בשקט', () async {
      final controller = _FocusFake(viewId: 99);

      expect(await PluginWebViewFocus.request(controller), isFalse);
    });

    test('שגיאה נייטיבית — false, בלי לזרוק', () async {
      mockChannel(7, throws: PlatformException(code: 'error'));
      final controller = _FocusFake(viewId: 7);

      expect(await PluginWebViewFocus.request(controller), isFalse);
    });

    test(
      'קריאה נייטיבית תקועה נחתכת ואינה מקפיאה את הקורא',
      () async {
        // ה-flush רץ תחת מנעול ה-lifecycle של הדיספצ'ר; בלי גבול זמן קריאה
        // תקועה הייתה מקפיאה כל השהיה/החייאה של תוספים.
        calls = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              MethodChannel(customPlatformViewChannelName(7)),
              (call) => Completer<void>().future,
            );

        expect(
          await PluginWebViewFocus.request(_FocusFake(viewId: 7)),
          isFalse,
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'בדיקת מיקוד תקועה אינה חוסמת את ההעברה',
      () async {
        mockChannel(7);
        final controller = _FocusFake(viewId: 7, hangEvaluate: true);

        expect(await PluginWebViewFocus.request(controller), isTrue);
        expect(calls.map((c) => c.method), [kPlatformViewRequestFocusMethod]);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('PluginWebViewFocus.request — מסלול ה-controller', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('קורא ל-API הרשמי ולא לערוץ', () async {
      final controller = _FocusFake();

      expect(await PluginWebViewFocus.request(controller), isTrue);
      expect(controller.requestFocusCalls, 1);
      expect(controller.getViewIdCalls, 0);
    });

    test('ה-WebView לא לקח פוקוס (false) — מדווח false', () async {
      expect(
        await PluginWebViewFocus.request(_FocusFake(focusResult: false)),
        isFalse,
      );
    });

    test('null — מדווח false', () async {
      expect(
        await PluginWebViewFocus.request(_FocusFake(focusResult: null)),
        isFalse,
      );
    });

    test('פלטפורמה בלי מימוש — UnimplementedError נבלע', () async {
      final controller = _FocusFake(error: UnimplementedError('nope'));

      expect(await PluginWebViewFocus.request(controller), isFalse);
    });

    test('חריגה כלשהי אינה מבעבעת — פוקוס הוא נוחות', () async {
      final controller = _FocusFake(error: StateError('boom'));

      expect(await PluginWebViewFocus.request(controller), isFalse);
    });

    test('macOS גם היא במסלול ה-controller', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final controller = _FocusFake();

      expect(await PluginWebViewFocus.request(controller), isTrue);
      expect(controller.requestFocusCalls, 1);
    });

    test('הדף כבר במיקוד — לא קוראים ל-requestFocus', () async {
      final controller = _FocusFake(pageHasFocus: true);

      expect(await PluginWebViewFocus.request(controller), isTrue);
      expect(controller.requestFocusCalls, 0);
    });

    test('בדיקת המיקוד קודמת לבקשה', () async {
      final controller = _FocusFake();

      await PluginWebViewFocus.request(controller);

      expect(controller.evaluated, hasLength(1));
      expect(controller.requestFocusCalls, 1);
    });
  });
}
