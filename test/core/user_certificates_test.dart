import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_certificates.dart';

/// issue #1305 — dart:io סומך רק על תעודות המערכת; תעודת סינון שהמשתמש
/// התקין במכשיר (נטפרי וכדומה) חייבת להגיע ל-SecurityContext כדי שההורדות
/// לא ייפלו ב-CERTIFICATE_VERIFY_FAILED.
const _testCaPem =
    '-----BEGIN CERTIFICATE-----\n'
    'MIIDFTCCAf2gAwIBAgIUFBLl430mY984rJ/Iui/yF4dLb6YwDQYJKoZIhvcNAQEL\n'
    'BQAwGjEYMBYGA1UEAwwPT3R6YXJpYSBUZXN0IENBMB4XDTI2MDkxMDIyMjEzMVoX\n'
    'DTI2MTAxMDIyMjEzMVowGjEYMBYGA1UEAwwPT3R6YXJpYSBUZXN0IENBMIIBIjAN\n'
    'BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxHV35B85HKzHp2guTix/DZHgB5bU\n'
    'z5VVoI1XA0M7GzLBqnw8sSe3LWj8qgAjWqNtZ18lnPpbCrwbp9KQkQYEEFXh6S9s\n'
    'nCV0ebOL3ccRvn00WNNtgXq64fpwn4dRa+/ly5GrI5N0DOE66mL5vUyWLsIuszk+\n'
    'Xw6x/FGBECKaNmTHBEs7adoe49X+V5un2cj3JTvBl2CjdSbsBhzEX00N6eE5aifR\n'
    'PQYqG5/D3T/25vGEL+B15Q4gKbez/bARn2h+Ve4zw5cnktyqHdT1jh94l+5OqMud\n'
    'tW84wg3zY15s6rnE1/IuPNXL/bSnn8z+6Zo9YABKSCcPbCICwYt2MiPibQIDAQAB\n'
    'o1MwUTAdBgNVHQ4EFgQUSOOHRtpttqCw2QDllh6X19StJU0wHwYDVR0jBBgwFoAU\n'
    'SOOHRtpttqCw2QDllh6X19StJU0wDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0B\n'
    'AQsFAAOCAQEAK0cB8iBB26uMSf8APYVjPW7QbBawD1HaPtRNDJoNk7Yn05lGzKy0\n'
    'NMu3IVGu6iIcO/nI/8F/8V632vPF5y6C4CBwn3+vy16bYAtA5+RtN+AlbIGIqtJr\n'
    '4GNffxzwVuD3v6eJ54MqPx+WFdi5G/kGPSPAPyE6XzI9+LYmADTotK5g/lz9k3q1\n'
    '0dNdNdKMcSyua8FQt1uhTU0UXqUBJstGVfAcBxPdv8eoAAwnwO4ALIZa6icPqHfC\n'
    'vGLQEK3DXxsGVb0Ks9iFasy/RNqKfuJkQsyV9JCFAEfzT847UPm4XyJ14PKyYsu4\n'
    'VGOakDJlKGvbPgLraY/EPzvkYo+/v2l8nw==\n'
    '-----END CERTIFICATE-----\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('otzaria/user_certificates_test');

  void mockCertificates(List<Object?>? result) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getUserInstalledCertificates');
          return result;
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('תעודות CA שהותקנו במכשיר (issue #1305)', () {
    test('תעודות המשתמש מוחזרות כבתים; תעודה פגומה מדולגת', () async {
      mockCertificates([_testCaPem, 'not a certificate', _testCaPem]);
      final certs = await loadUserInstalledCertificateBytes(
        channel: channel,
        isAndroid: true,
      );
      expect(certs, hasLength(2));
      final context = SecurityContext();
      for (final bytes in certs) {
        context.setTrustedCertificatesBytes(bytes);
      }
    });

    test('מחוץ לאנדרואיד לא פונים לערוץ', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            called = true;
            return <Object?>[];
          });
      final certs = await loadUserInstalledCertificateBytes(
        channel: channel,
        isAndroid: false,
      );
      expect(certs, isEmpty);
      expect(called, isFalse);
    });

    test('ערוץ שאינו מיושם או ריק → רשימה ריקה בלי חריגה', () async {
      mockCertificates(null);
      expect(
        await loadUserInstalledCertificateBytes(
          channel: channel,
          isAndroid: true,
        ),
        isEmpty,
      );
    });
  });
}
