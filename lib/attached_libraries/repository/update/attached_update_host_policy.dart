import 'dart:async';
import 'dart:io';

/// כתובת שמדיניות הרשת דוחה.
class AttachedUpdateHostRejected implements Exception {
  final String reason;
  const AttachedUpdateHostRejected(this.reason);

  @override
  String toString() => 'AttachedUpdateHostRejected: $reason';
}

/// מי מותר לפנות אליו בעדכון מסד מצורף: https בלבד, שם מארח (לא כתובת IP),
/// ורק כתובות ציבוריות — גם אחרי תרגום DNS, שאחרת הוא דרך לרשת הפנימית.
class AttachedUpdateHostPolicy {
  const AttachedUpdateHostPolicy({
    this.lookup = _systemLookup,
    this.lookupTimeout = const Duration(seconds: 10),
  }) : _testLoopbackPorts = const {};

  /// לבדיקות בלבד: מתיר http ל-127.0.0.1 בפורטים [ports] (שרת מקומי).
  const AttachedUpdateHostPolicy.allowLoopbackForTesting(Set<int> ports)
    : lookup = _systemLookup,
      lookupTimeout = const Duration(seconds: 10),
      _testLoopbackPorts = ports;

  final Future<List<InternetAddress>> Function(String host) lookup;
  final Duration lookupTimeout;
  final Set<int> _testLoopbackPorts;

  static Future<List<InternetAddress>> _systemLookup(String host) =>
      InternetAddress.lookup(host);

  static const _blockedSuffixes = [
    '.localhost',
    '.local',
    '.internal',
    '.lan',
    '.home.arpa',
    '.intranet',
  ];

  bool _isTestTarget(Uri uri) =>
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      _testLoopbackPorts.contains(uri.port);

  /// בדיקה תחבירית, בלי רשת. זורק [AttachedUpdateHostRejected].
  void checkUri(Uri uri) {
    if (_isTestTarget(uri)) return;
    if (uri.scheme != 'https') {
      throw const AttachedUpdateHostRejected('only https is allowed');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const AttachedUpdateHostRejected('credentials in URL');
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) throw const AttachedUpdateHostRejected('no host');
    if (InternetAddress.tryParse(host) != null) {
      throw const AttachedUpdateHostRejected('IP address instead of host name');
    }
    // סיומת אלפביתית חובה: דוחה גם צורות IP מספריות (2130706433, 0x7f.1).
    final labels = host.split('.');
    if (labels.length < 2 ||
        !RegExp(r'^(xn--[a-z0-9-]+|[a-z]{2,63})$').hasMatch(labels.last)) {
      throw const AttachedUpdateHostRejected('not a public host name');
    }
    if (host == 'localhost' || _blockedSuffixes.any(host.endsWith)) {
      throw const AttachedUpdateHostRejected('local host name');
    }
  }

  /// For a proxied request: [checkUri], then rejects a host that resolves
  /// locally to a non-public address. A failed local lookup is not an error.
  Future<void> checkNotPrivate(Uri uri) async {
    checkUri(uri);
    if (_isTestTarget(uri)) return;
    final List<InternetAddress> addresses;
    try {
      addresses = await lookup(uri.host).timeout(lookupTimeout);
    } on SocketException {
      return;
    } on TimeoutException {
      return;
    }
    if (!addresses.every(isPublicAddress)) {
      throw const AttachedUpdateHostRejected(
        'host name resolves to a non-public address',
      );
    }
  }

  /// בדיקה מלאה: תחביר + כל כתובות ה-DNS ציבוריות. מחזיר את הכתובות
  /// שנבדקו, כדי שהחיבור ייעשה אליהן בדיוק (בלי תרגום DNS שני).
  Future<List<InternetAddress>> resolve(Uri uri) async {
    checkUri(uri);
    if (_isTestTarget(uri)) return [InternetAddress.loopbackIPv4];
    final List<InternetAddress> addresses;
    try {
      addresses = await lookup(uri.host).timeout(lookupTimeout);
    } on SocketException {
      throw const AttachedUpdateHostRejected('host name does not resolve');
    } on TimeoutException {
      throw const AttachedUpdateHostRejected('DNS lookup timed out');
    }
    if (addresses.isEmpty) {
      throw const AttachedUpdateHostRejected('host name does not resolve');
    }
    for (final address in addresses) {
      if (!isPublicAddress(address)) {
        throw const AttachedUpdateHostRejected(
          'host name resolves to a non-public address',
        );
      }
    }
    return addresses;
  }

  /// false לכתובות loopback, פרטיות, link-local, CGNAT, multicast ושמורות —
  /// כולל IPv4 שעטוף ב-IPv6 (mapped, NAT64, 6to4).
  static bool isPublicAddress(InternetAddress address) {
    final b = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && b.length == 4) {
      return _isPublicIPv4(b);
    }
    if (address.type != InternetAddressType.IPv6 || b.length != 16) {
      return false;
    }
    final prefix10 = b.sublist(0, 10).every((x) => x == 0);
    // ::ffff:a.b.c.d; ::/96 (כולל :: ו-::1) אינו ציבורי.
    if (prefix10 && b[10] == 0xff && b[11] == 0xff) {
      return _isPublicIPv4(b.sublist(12));
    }
    if (prefix10 && b[10] == 0 && b[11] == 0) return false;
    // 64:ff9b::/96 (NAT64)
    if (b[0] == 0 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
      return _isPublicIPv4(b.sublist(12));
    }
    // 2002::/16 (6to4) — כתובת IPv4 בבתים 2-5.
    if (b[0] == 0x20 && b[1] == 0x02) return _isPublicIPv4(b.sublist(2, 6));
    // רק 2000::/3 הוא unicast גלובלי.
    if ((b[0] & 0xe0) != 0x20) return false;
    // 2001:db8::/32 תיעוד, 2001::/23 שמורים של IETF (כולל Teredo).
    if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8) {
      return false;
    }
    if (b[0] == 0x20 && b[1] == 0x01 && b[2] < 0x02) return false;
    return true;
  }

  static bool _isPublicIPv4(List<int> b) {
    final a = b[0], c = b[1];
    if (a == 0 || a == 10 || a == 127) return false;
    if (a == 100 && c >= 64 && c <= 127) return false; // CGNAT
    if (a == 169 && c == 254) return false;
    if (a == 172 && c >= 16 && c <= 31) return false;
    if (a == 192 && c == 168) return false;
    if (a == 192 && c == 0 && b[2] == 0) return false;
    if (a == 192 && c == 0 && b[2] == 2) return false;
    if (a == 198 && (c == 18 || c == 19)) return false;
    if (a == 198 && c == 51 && b[2] == 100) return false;
    if (a == 203 && c == 0 && b[2] == 113) return false;
    if (a >= 224) return false; // multicast, שמורים, broadcast
    return true;
  }
}
