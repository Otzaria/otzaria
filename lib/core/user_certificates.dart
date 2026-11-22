import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// הערוץ שדרכו MainActivity מחזיר את תעודות ה-CA שהמשתמש התקין במכשיר.
const MethodChannel userCertificatesChannel = MethodChannel(
  'otzaria/user_certificates',
);

/// מחזיר את תעודות ה-CA שהמשתמש התקין באנדרואיד (מאגר "user"), כ-PEM.
///
/// dart:io סומך רק על תעודות המערכת, ולכן תעודת סינון שהותקנה במכשיר (נטפרי
/// וכדומה) גרמה ל-CERTIFICATE_VERIFY_FAILED בכל הורדה (issue #1305). הערוץ
/// זמין רק ב-isolate הראשי, ולכן התוצאה עוברת כבתים ל-isolates האחרים
/// (ראו `trustCertificates`). תעודה פגומה מדולגת ואינה עוצרת את השאר.
Future<List<Uint8List>> loadUserInstalledCertificateBytes({
  MethodChannel channel = userCertificatesChannel,
  bool? isAndroid,
}) async {
  if (!(isAndroid ?? (!kIsWeb && Platform.isAndroid))) return const [];
  final List<Object?>? pems;
  try {
    pems = await channel.invokeListMethod<Object?>(
      'getUserInstalledCertificates',
    );
  } on PlatformException catch (e) {
    debugPrint('⚠️ קריאת תעודות המשתמש נכשלה: $e');
    return const [];
  } on MissingPluginException {
    return const [];
  }
  final valid = <Uint8List>[];
  for (final pem in pems ?? const <Object?>[]) {
    if (pem is! String || pem.isEmpty) continue;
    final bytes = Uint8List.fromList(utf8.encode(pem));
    try {
      SecurityContext().setTrustedCertificatesBytes(bytes);
      valid.add(bytes);
    } on TlsException catch (e) {
      debugPrint('⚠️ תעודת משתמש לא תקינה דולגה: ${e.message}');
    }
  }
  if (valid.isNotEmpty) {
    debugPrint('🔐 נמצאו ${valid.length} תעודות CA שהותקנו במכשיר');
  }
  return valid;
}
