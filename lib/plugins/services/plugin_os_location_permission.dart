import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// אישור המיקום של מערכת ההפעלה, לבקשות מיקום של דפי תוספים.
///
/// רק באנדרואיד האפליקציה עצמה צריכה אישור מערכת: שם ה-WebView מחזיר לדף
/// שגיאה אם `ACCESS_COARSE_LOCATION` לא ניתנה לאפליקציה. בשאר הפלטפורמות
/// המערכת מטפלת בזה בעצמה — בווינדוס דרך הגדרות הפרטיות של המיקום, ובלינוקס
/// דרך שירות המיקום — ולכן אין כאן מה לבקש.
///
/// מבקשים מיקום משוער בלבד: זה מה שחישוב כיוון או זמני היום צריך, והוא אינו
/// חושף את הכתובת המדויקת.
abstract final class PluginOsLocationPermission {
  static const MethodChannel _channel = MethodChannel(
    'otzaria/location_permission',
  );

  /// חלון המערכת יכול להישאר פתוח, ובקשה שהאפליקציה ברקע לא נענית כלל. בלי
  /// הגבלה הדף של התוסף היה ממתין לנצח.
  static const Duration _userDecisionTimeout = Duration(minutes: 2);

  /// האם יש לאפליקציה הרשאת מיקום במערכת; באנדרואיד מציג את חלון המערכת אם
  /// עוד לא נשאל המשתמש. כל כשל נחשב סירוב.
  static Future<bool> ensure() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('requestCoarse')
              .timeout(_userDecisionTimeout) ??
          false;
    } on TimeoutException {
      // בלי זה הבקשה נשארת ממתינה בצד של אנדרואיד וחוסמת כל בקשה אחריה.
      unawaited(_cancelPending());
      debugPrint('PluginOsLocationPermission: אין תשובה מהמערכת — נדחה.');
      return false;
    } catch (e) {
      debugPrint('PluginOsLocationPermission: בקשת המיקום נכשלה — נדחה. $e');
      return false;
    }
  }

  static Future<void> _cancelPending() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {
      // רשת ביטחון בלבד: הפעלה מחדש של הפעילות מנקה גם כך.
    }
  }
}
