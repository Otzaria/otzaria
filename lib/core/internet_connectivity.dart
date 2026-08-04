import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// יעדים ניטרליים בכוונה ולא שרתי העדכון — אחרת תקלה ב-GitHub הייתה נראית
/// כמו היעדר אינטרנט ואיש לא היה מדווח עליה. היעד הראשון הוא שם מתחם ולא
/// כתובת IP גולמית: ברשתות מסוננות חיבור ישיר ל-IP ולפורט 53 חסום, ומשתמש
/// מחובר לגמרי היה מסווג כמנותק.
const _kProbeTargets = <(String, int)>[
  ('www.google.com', 443),
  ('1.1.1.1', 443),
  ('8.8.8.8', 53),
];

const _kProbeTimeout = Duration(seconds: 3);

/// דריסת החיבור בטסטים — מונעת גישת רשת אמיתית.
@visibleForTesting
Future<bool> Function(String host, int port, Duration timeout)?
debugSocketConnect;

/// האם קיים חיבור אינטרנט בפועל.
///
/// חיבור TCP ליעד קבוע ולא DNS lookup: מטמון ה-DNS של מערכת ההפעלה מחזיר
/// תשובה מוצלחת גם בלי רשת, ואז "מנותק" נראה כמו "מחובר".
/// הפונקציה נקראת ממסלולי כשל, ולכן לעולם אינה זורקת בעצמה.
Future<bool> hasInternetConnection({
  Duration timeout = _kProbeTimeout,
}) async {
  final connect = debugSocketConnect ?? _connect;
  final results = await Future.wait([
    for (final (host, port) in _kProbeTargets)
      _isReachable(connect, host, port, timeout),
  ]);
  return results.any((reachable) => reachable);
}

Future<bool> _isReachable(
  Future<bool> Function(String, int, Duration) connect,
  String host,
  int port,
  Duration timeout,
) async {
  try {
    // ה-timeout נאכף גם כאן: הקוראים ממתינים לתשובה בתוך מסלול כשל, ותקיעה
    // כאן משאירה אותם תקועים במצב "בודק".
    return await connect(host, port, timeout).timeout(timeout);
  } catch (_) {
    return false;
  }
}

Future<bool> _connect(String host, int port, Duration timeout) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  socket.destroy();
  return true;
}
