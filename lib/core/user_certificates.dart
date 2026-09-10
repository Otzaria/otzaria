import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// הערוץ שדרכו MainActivity מחזיר את תעודות ה-CA שהמשתמש התקין במכשיר.
const MethodChannel userCertificatesChannel = MethodChannel(
  'otzaria/user_certificates',
);

/// מוסיף ל-[context] את תעודות ה-CA שהמשתמש התקין באנדרואיד (מאגר "user").
///
/// dart:io סומך רק על תעודות המערכת, ולכן תעודת סינון שהותקנה במכשיר (נטפרי
/// וכדומה) גרמה ל-CERTIFICATE_VERIFY_FAILED בכל הורדה (issue #1305). מחזיר
/// את מספר התעודות שנוספו; תעודה פגומה מדולגת ואינה עוצרת את השאר.
Future<int> trustUserInstalledCertificates(
  SecurityContext context, {
  MethodChannel channel = userCertificatesChannel,
  bool? isAndroid,
}) async {
  if (!(isAndroid ?? (!kIsWeb && Platform.isAndroid))) return 0;
  final List<Object?>? pems;
  try {
    pems = await channel.invokeListMethod<Object?>(
      'getUserInstalledCertificates',
    );
  } on PlatformException catch (e) {
    debugPrint('⚠️ קריאת תעודות המשתמש נכשלה: $e');
    return 0;
  } on MissingPluginException {
    return 0;
  }
  var added = 0;
  for (final pem in pems ?? const <Object?>[]) {
    if (pem is! String || pem.isEmpty) continue;
    try {
      context.setTrustedCertificatesBytes(utf8.encode(pem));
      added++;
    } on TlsException catch (e) {
      debugPrint('⚠️ תעודת משתמש לא תקינה דולגה: ${e.message}');
    }
  }
  if (added > 0) debugPrint('🔐 נוספו $added תעודות CA שהותקנו במכשיר');
  return added;
}
