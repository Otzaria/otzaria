import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';

/// Issue #4935: a transient DNS failure while checking an attached database
/// for updates was shown as "the update source address is not allowed"
/// (a policy verdict) instead of "cannot reach the update source".
///
/// These tests drive the real [AttachedUpdateFetcher] (connectionFactory and
/// all) with an injected DNS lookup, so no network is needed, and assert on
/// the user-visible classification via [AttachedLibraryUpdateService.errorOf].
void main() {
  final uri = Uri.parse('https://github.com/o/r/releases/download/v1/m.json');

  AttachedUpdateFetcher fetcherWith(
    Future<List<InternetAddress>> Function(String host) lookup, {
    Duration lookupTimeout = const Duration(seconds: 10),
  }) => AttachedUpdateFetcher(
    policy: AttachedUpdateHostPolicy(
      lookup: lookup,
      lookupTimeout: lookupTimeout,
    ),
    // No proxy: take the direct path that resolves the name itself.
    findProxy: (_) => 'DIRECT',
  );

  Future<Object> failureOf(AttachedUpdateFetcher fetcher, Uri target) async {
    try {
      await fetcher.fetchBytes(target, maxBytes: 10);
    } catch (e) {
      return e;
    }
    fail('expected the fetch to fail');
  }

  group('a DNS failure is a network failure, not a policy rejection', () {
    test('lookup throws SocketException (offline / DNS not ready)', () async {
      final e = await failureOf(
        fetcherWith(
          (_) async => throw const SocketException('Failed host lookup'),
        ),
        uri,
      );
      expect(e, isNot(isA<AttachedUpdateHostRejected>()), reason: '$e');
      expect(
        AttachedLibraryUpdateService.errorOf(e),
        AttachedUpdateError.network,
      );
    });

    test('lookup exceeds lookupTimeout', () async {
      final e = await failureOf(
        fetcherWith(
          (_) => Completer<List<InternetAddress>>().future,
          lookupTimeout: const Duration(milliseconds: 50),
        ),
        uri,
      );
      expect(e, isNot(isA<AttachedUpdateHostRejected>()), reason: '$e');
      expect(
        AttachedLibraryUpdateService.errorOf(e),
        AttachedUpdateError.network,
      );
    });

    test('lookup returns no addresses', () async {
      final e = await failureOf(fetcherWith((_) async => []), uri);
      expect(e, isNot(isA<AttachedUpdateHostRejected>()), reason: '$e');
      expect(
        AttachedLibraryUpdateService.errorOf(e),
        AttachedUpdateError.network,
      );
    });
  });

  group('real policy verdicts stay hostRejected (guard)', () {
    test('a name that resolves to a private address', () async {
      final e = await failureOf(
        fetcherWith((_) async => [InternetAddress('10.1.2.3')]),
        uri,
      );
      expect(e, isA<AttachedUpdateHostRejected>(), reason: '$e');
      expect(
        AttachedLibraryUpdateService.errorOf(e),
        AttachedUpdateError.hostRejected,
      );
    });

    test('a non-https scheme', () async {
      final e = await failureOf(
        fetcherWith((_) async => [InternetAddress('93.184.216.34')]),
        Uri.parse('http://github.com/o/r/m.json'),
      );
      expect(e, isA<AttachedUpdateHostRejected>(), reason: '$e');
    });

    test('an IP address instead of a host name', () async {
      final e = await failureOf(
        fetcherWith((_) async => [InternetAddress('93.184.216.34')]),
        Uri.parse('https://93.184.216.34/m.json'),
      );
      expect(e, isA<AttachedUpdateHostRejected>(), reason: '$e');
    });
  });
}
