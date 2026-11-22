import 'dart:io';

import 'package:flutter/services.dart';
import 'package:otzaria/core/user_certificates.dart';

/// NetFree CA bundles trusted by every HTTPS client in the app. Both roots
/// (1 and X2) are listed: a user may meet either chain.
const kNetfreeCaAssets = [
  'assets/ca/netfree_cas.pem',
  'assets/ca/netfree_root_ca_unified_v1.pem',
  'assets/ca/netfree_root_ca_x2.pem',
];

/// Reads the bundles on the UI isolate (rootBundle is unavailable elsewhere),
/// so a worker isolate can trust them via [trustCertificates]. On Android it
/// also returns the CA certificates the user installed on the device.
Future<List<Uint8List>> loadNetfreeCaBytes() async => [
  for (final asset in kNetfreeCaAssets)
    (await rootBundle.load(asset)).buffer.asUint8List(),
  ...await loadUserInstalledCertificateBytes(),
];

/// Adds [certificates] to this isolate's default context. `defaultContext` is
/// per isolate, so a download isolate must call this itself.
void trustCertificates(List<Uint8List> certificates) {
  for (final bytes in certificates) {
    try {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(bytes);
    } on TlsException {
      // Already trusted in this context.
    }
  }
}
