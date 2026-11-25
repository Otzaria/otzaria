import 'dart:io';

import 'package:flutter/services.dart';
import 'package:otzaria/core/error_log_file.dart';

/// NetFree CA bundles trusted by every HTTPS client in the app. Both roots
/// (1 and X2) are listed: a user may meet either chain.
const kNetfreeCaAssets = [
  'assets/ca/netfree_cas.pem',
  'assets/ca/netfree_root_ca_unified_v1.pem',
  'assets/ca/netfree_root_ca_x2.pem',
];

/// Reads the bundles on the UI isolate (rootBundle is unavailable elsewhere),
/// so a worker isolate can trust them via [trustCertificates].
Future<List<Uint8List>> loadNetfreeCaBytes() async {
  final bundles = <Uint8List>[];
  for (final asset in kNetfreeCaAssets) {
    try {
      bundles.add((await rootBundle.load(asset)).buffer.asUint8List());
    } catch (error, stackTrace) {
      // A bundle missing from the install (e.g. removed by antivirus) must not
      // block startup: the rest are still trusted.
      ErrorLogFile.appendInBackground(
        title: 'NetFree CA asset',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  return bundles;
}

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
