import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// אפיק הודעות בין חלונות אוצריא.
///
/// כל חלון הוא isolate נפרד עם מנוע Flutter משלו, **באותו תהליך** (מודל A).
/// ל-isolates נפרדים אין זיכרון משותף ואין ביניהם `SendPort` מובנה, אבל
/// [IsolateNameServer] של המנוע הוא רישום **גלובלי לתהליך** — משותף לכל
/// המנועים. זהו המנגנון היחיד שמאפשר לחלונות לדבר בלי לצאת לנייטיב.
///
/// ⚠️ למה משבצות ולא רישום דינמי: אין "ספרייה" מרכזית שאפשר לשאול מי קיים,
/// וגם אין חלון שמובטח שיהיה חי (המשתמש יכול לסגור את הראשון). לכן כל חלון
/// **תופס משבצת** משמות ידועים מראש, והחיפוש הוא סריקה של כולן. התקרה של
/// ארבעה חלונות היא מה שהופך את זה למעשי.
class WindowBus {
  WindowBus._();

  static final WindowBus instance = WindowBus._();

  /// מספר המשבצות. חייב להתאים ל-`kMaxWindows` ב-`windows/runner`.
  static const int slotCount = 4;

  /// קידומת שמות המשבצות. ניתנת להחלפה **בבדיקות בלבד**.
  ///
  /// ⚠️ [IsolateNameServer] הוא רישום גלובלי לתהליך — בדיוק הסיבה שהאפיק
  /// עובד — ולכן שתי סוויטות בדיקה שרצות באותו תהליך תופסות את אותן
  /// המשבצות ומפילות זו את זו. עם קידומת ייחודית לסוויטה הן מבודדות.
  @visibleForTesting
  static String namespace = 'otzaria.window';

  static String _slotName(int slot) => '$namespace.$slot';

  /// שם המשבצת של הבעלים — החלון שמחזיק את המאגרים המשותפים.
  ///
  /// ⚠️ כינוי ולא סריקה. איתור הבעלים בשאילתת `describe` לכל משבצת עלה
  /// timeout, והבעלים דווקא **עסוק** בזמן שנפתח חלון שני (נמדד 2,092ms
  /// בטעינת קטלוג הספרייה) — כלומר הסריקה פקעה בדיוק כשהיא נחוצה, והקורא
  /// קיבל "אין בעלים". `lookupPortByName` סינכרוני ואינו יכול לפקוע.
  static String get _ownerName => '$namespace.owner';

  ReceivePort? _port;
  int? _slot;

  /// המשבצת שהחלון הזה תפס, או null אם טרם נרשם.
  int? get slot => _slot;

  /// ה-port של הבעלים, או null אם אינו רשום.
  SendPort? get ownerPort => IsolateNameServer.lookupPortByName(_ownerName);

  /// האם משבצת אחרת תפוסה, כלומר קיים isolate של חלון נוסף.
  ///
  /// בדיקה סינכרונית וזולה, בלי סבב אפיק. אינה מבחינה בין חלון גלוי לחלון
  /// מוסתר — שניהם isolates חיים עם קובצי Hive פתוחים, וזו בדיוק השאלה של
  /// מי שצריך לדעת אם מותר לגעת בהם.
  bool get hasOtherWindows {
    for (var candidate = 1; candidate <= slotCount; candidate++) {
      if (candidate == _slot) continue;
      if (IsolateNameServer.lookupPortByName(_slotName(candidate)) != null) {
        return true;
      }
    }
    return false;
  }

  /// מטפל בבקשות נכנסות. נקבע פעם אחת על ידי החלון.
  ///
  /// מקבל את גוף הבקשה ומחזיר תשובה שתישלח חזרה לשולח. חריגה בתוכו
  /// מוחזרת כשגיאה ולא מפילה את החלון.
  Future<Object?> Function(Map<String, dynamic> request)? onRequest;

  /// תופס משבצת פנויה ומתחיל להאזין.
  ///
  /// [asOwner] רושם בנוסף את כינוי הבעלים, כך שכל חלון יוכל למצוא את
  /// מחזיק המאגרים המשותפים בקריאה סינכרונית אחת.
  ///
  /// מחזיר את מספר המשבצת, או null אם כולן תפוסות — מצב שאמור להיות בלתי
  /// אפשרי כי ה-runner אוכף את אותה תקרה, אבל עדיף להיכשל בשקט מאשר לדרוס
  /// רישום של חלון אחר.
  int? register({bool asOwner = false}) {
    if (_slot != null) return _slot;
    final port = ReceivePort();
    for (var candidate = 1; candidate <= slotCount; candidate++) {
      final name = _slotName(candidate);
      // ⚠️ `registerPortWithName` נכשל אם השם תפוס — זו בדיוק בדיקת
      // התפיסה האטומית, ואין צורך ב-lookup מקדים שהיה יוצר מרוץ.
      if (IsolateNameServer.registerPortWithName(port.sendPort, name)) {
        _slot = candidate;
        _port = port;
        port.listen(_handleMessage);
        if (asOwner) {
          _ownsOwnerName = IsolateNameServer.registerPortWithName(
            port.sendPort,
            _ownerName,
          );
        }
        return candidate;
      }
    }
    port.close();
    return null;
  }

  bool _ownsOwnerName = false;

  /// משחרר את המשבצת.
  ///
  /// ⚠️ **אינו** נקרא בסגירת חלון, במכוון. חלון סגור מוסתר ולא נהרס,
  /// ה-isolate שלו חי, וקובצי ה-Hive שלו נשארים פתוחים — כלומר הבעלים
  /// ממשיך לשרת את המאגרים המשותפים גם אחרי שהמשתמש סגר אותו, וזו התנהגות
  /// נדרשת. מה שכן צריך להיפסק בסגירה הוא היכולת **לקבל כרטיסיה**, וזה
  /// נקבע לפי נראות החלון ([WindowPeer.isVisible]) ולא לפי הרישום באפיק.
  void unregister() {
    final slot = _slot;
    if (slot != null) {
      IsolateNameServer.removePortNameMapping(_slotName(slot));
    }
    if (_ownsOwnerName) {
      IsolateNameServer.removePortNameMapping(_ownerName);
      _ownsOwnerName = false;
    }
    _port?.close();
    _port = null;
    _slot = null;
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) return;
    final reply = message['reply'];
    final body = message['body'];
    if (reply is! SendPort || body is! Map) return;
    final request = Map<String, dynamic>.from(body);

    Future<void>(() async {
      try {
        final handler = onRequest;
        final result = handler == null ? null : await handler(request);
        reply.send({'ok': true, 'result': result});
      } catch (e) {
        reply.send({'ok': false, 'error': '$e'});
      }
    });
  }

  /// שולח בקשה לחלון במשבצת [slot] וממתין לתשובה.
  ///
  /// מחזיר null אם אין חלון במשבצת, אם הוא לא ענה בתוך [timeout], או אם
  /// הוא החזיר שגיאה. **timeout הוא חובה ולא נוחות**: חלון עסוק או חלון
  /// שנסגר באמצע היו משאירים את הקורא תלוי לנצח.
  Future<Object?> request(
    int slot,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    final target = IsolateNameServer.lookupPortByName(_slotName(slot));
    if (target == null) return Future.value();
    return requestPort(target, body, timeout: timeout, label: 'slot $slot');
  }

  /// כמו [request], אבל אל port שכבר בידינו.
  ///
  /// קיים כי הבעלים מאותר דרך כינוי ולא דרך מספר משבצת — ואין טעם לתרגם
  /// port חזרה למשבצת רק כדי לחפש אותו שוב.
  Future<Object?> requestPort(
    SendPort target,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 3),
    String label = 'port',
  }) async {
    final reply = ReceivePort();
    try {
      target.send({'reply': reply.sendPort, 'body': body});
      final response = await reply.first.timeout(timeout);
      if (response is Map && response['ok'] == true) {
        return response['result'];
      }
      if (response is Map) {
        debugPrint('WindowBus $label returned error: ${response['error']}');
      }
      return null;
    } on TimeoutException {
      debugPrint(
        'WindowBus $label timed out after ${timeout.inMilliseconds}ms',
      );
      return null;
    } catch (e) {
      debugPrint('WindowBus $label request failed: $e');
      return null;
    } finally {
      reply.close();
    }
  }

  /// שולח הודעה לכל המשבצות התפוסות חוץ מזו שלנו, בלי להמתין לתשובה.
  ///
  /// ⚠️ אין ערך החזרה ואין timeout — הקורא אינו יכול לעשות דבר בכשל.
  /// המשתמשת היחידה היא הודעת "מפתח משותף השתנה", שכל תפקידה למנוע
  /// התיישנות; חלון שלא קיבל אותה יקבל את הערך הנכון בקריאה הבאה שלו.
  void broadcast(Map<String, dynamic> body) {
    for (var candidate = 1; candidate <= slotCount; candidate++) {
      if (candidate == _slot) continue;
      final target = IsolateNameServer.lookupPortByName(_slotName(candidate));
      if (target == null) continue;
      final reply = ReceivePort();
      target.send({'reply': reply.sendPort, 'body': body});
      // התשובה נזרקת, אבל ה-port חייב להיסגר אחרי שהיא תגיע — סגירה
      // מיידית הייתה מפילה את השולח כשהיעד מנסה לענות. הטיימר סוגר גם
      // כשהיעד אינו עונה כלל, אחרת כל שידור לחלון שקרס היה משאיר port פתוח.
      final closer = Timer(const Duration(seconds: 1), reply.close);
      reply.listen((_) {
        closer.cancel();
        reply.close();
      });
    }
  }

  /// סורק את כל המשבצות ומחזיר את החלונות האחרים שעונים.
  ///
  /// ⚠️ נשאלים בפועל ולא רק נבדק אם השם רשום: משבצת יכולה להישאר רשומה
  /// אחרי שחלון נסגר בלי לשחרר אותה (קריסה, סגירה כפויה), ואז הרישום
  /// קיים אבל אין מאזין. השאלה עצמה היא הבדיקה.
  /// ⚠️ ה-timeout רחב מ-800ms שהיה כאן: תפיסת ה-thread המשותף בטעינת קטלוג
  /// נמדדה ב-~2,100ms, ולכן חלון עסוק נעלם מ"העבר לחלון קיים". נשאר מתחת
  /// לפעימת הרענון (3 שניות) כדי ששתי סריקות לא יחפפו.
  Future<List<WindowPeer>> peers({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final futures = <Future<WindowPeer?>>[];
    for (var candidate = 1; candidate <= slotCount; candidate++) {
      if (candidate == _slot) continue;
      futures.add(
        request(candidate, const {'type': 'describe'}, timeout: timeout).then(
          (result) {
            if (result is! Map) return null;
            return WindowPeer(
              slot: candidate,
              title: (result['title'] as String?) ?? 'חלון $candidate',
              tabCount: (result['tabCount'] as int?) ?? 0,
              isOwner: result['isOwner'] == true,
            );
          },
        ),
      );
    }
    final results = await Future.wait(futures);
    return results.whereType<WindowPeer>().toList();
  }
}

/// חלון אחר שעונה על האפיק.
@immutable
class WindowPeer {
  const WindowPeer({
    required this.slot,
    required this.title,
    required this.tabCount,
    this.isOwner = false,
    this.isVisible = true,
  });

  WindowPeer copyWith({bool? isVisible}) => WindowPeer(
    slot: slot,
    title: title,
    tabCount: tabCount,
    isOwner: isOwner,
    isVisible: isVisible ?? this.isVisible,
  );

  final int slot;

  /// כותרת לתצוגה בתפריט — בדרך כלל שם הכרטיסיה הפעילה באותו חלון.
  final String title;

  final int tabCount;

  /// האם זה החלון הראשון, שמחזיק את המאגרים המשותפים.
  ///
  /// ⚠️ נקבע לפי תשובת החלון עצמו ולא לפי מספר המשבצת: סדר תפיסת המשבצות
  /// תלוי בסדר הפתיחה, ואין קשר מובטח בין "משבצת 1" ל"החלון הראשון".
  final bool isOwner;

  /// האם החלון מוצג על המסך כרגע.
  ///
  /// ⚠️ חלון שהמשתמש סגר **מוסתר ולא נהרס**, וה-isolate שלו ממשיך לענות
  /// על האפיק. לכן "עונה" אינו "פתוח": חלון סגור המשיך להופיע ב"העבר
  /// לחלון קיים", אישר קבלת כרטיסיה, והמקור מחק אותה. הנראות נמדדת בנייטיב
  /// (`IsWindowVisible`) ולא בתשובת החלון — חלון מוסתר אינו יודע שהוסתר.
  final bool isVisible;

  @override
  bool operator ==(Object other) =>
      other is WindowPeer &&
      other.slot == slot &&
      other.title == title &&
      other.tabCount == tabCount &&
      other.isOwner == isOwner &&
      other.isVisible == isVisible;

  @override
  int get hashCode => Object.hash(slot, title, tabCount, isOwner, isVisible);
}
