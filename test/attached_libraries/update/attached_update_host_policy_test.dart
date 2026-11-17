import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';

void main() {
  AttachedUpdateHostPolicy resolvingTo(List<String> addresses) =>
      AttachedUpdateHostPolicy(
        lookup: (_) async => [for (final a in addresses) InternetAddress(a)],
      );

  final rejected = throwsA(isA<AttachedUpdateHostRejected>());

  test('syntactic rejection list', () {
    const policy = AttachedUpdateHostPolicy();
    for (final url in [
      'http://example.org/m.json',
      'ftp://example.org/m.json',
      'https://localhost/m.json',
      'https://foo.localhost/m.json',
      'https://printer.local/m.json',
      'https://db.internal/m.json',
      'https://127.0.0.1/m.json',
      'https://10.0.0.1/m.json',
      'https://192.168.1.10/m.json',
      'https://[::1]/m.json',
      'https://[fe80::1]/m.json',
      'https://93.184.216.34/m.json',
      'https://2130706433/m.json',
      'https://0x7f.1/m.json',
      'https://intranet/m.json',
      'https://user:pw@example.org/m.json',
    ]) {
      expect(() => policy.checkUri(Uri.parse(url)), rejected, reason: url);
    }
    policy.checkUri(Uri.parse('https://github.com/o/r/releases/download/v1/a'));
    policy.checkUri(Uri.parse('https://xn--4dbrk0ce.xn--4dbrk0ce/m.json'));
  });

  test('host names resolving to non-public addresses are rejected', () async {
    final uri = Uri.parse('https://updates.example.org/m.json');
    for (final address in [
      '127.0.0.1',
      '10.1.2.3',
      '172.16.0.1',
      '192.168.0.1',
      '169.254.169.254',
      '100.64.0.1',
      '0.0.0.0',
      '224.0.0.1',
      '255.255.255.255',
      '::1',
      '::',
      'fe80::1',
      'fc00::1',
      'fd12:3456::1',
      '::ffff:10.0.0.1',
      '::ffff:127.0.0.1',
      '64:ff9b::a00:1',
      '2002:c0a8:0101::1',
      '2001:db8::1',
      'ff02::1',
    ]) {
      await expectLater(
        resolvingTo(['93.184.216.34', address]).resolve(uri),
        rejected,
        reason: address,
      );
    }
  });

  test('public addresses pass and are returned for the connection', () async {
    final uri = Uri.parse('https://updates.example.org/m.json');
    final addresses = await resolvingTo([
      '93.184.216.34',
      '2606:2800:220:1::1',
      '::ffff:8.8.8.8',
    ]).resolve(uri);
    expect(addresses, hasLength(3));
  });

  // #4935: an unresolvable name is a network failure (the fetcher maps these
  // exceptions to AttachedUpdateError.network), not a policy rejection.
  test('DNS failure is a network error, not a rejection', () async {
    final policy = AttachedUpdateHostPolicy(
      lookup: (_) async => throw const SocketException('nxdomain'),
    );
    await expectLater(
      policy.resolve(Uri.parse('https://nope.example.org/')),
      throwsA(isA<SocketException>()),
    );
    await expectLater(
      resolvingTo([]).resolve(Uri.parse('https://nope.example.org/')),
      throwsA(isA<SocketException>()),
    );
    final slow = AttachedUpdateHostPolicy(
      lookup: (_) => Completer<List<InternetAddress>>().future,
      lookupTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      slow.resolve(Uri.parse('https://nope.example.org/')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('test override allows only http to the listed loopback port', () {
    const policy = AttachedUpdateHostPolicy.allowLoopbackForTesting({8080});
    policy.checkUri(Uri.parse('http://127.0.0.1:8080/m.json'));
    expect(
      () => policy.checkUri(Uri.parse('http://127.0.0.1:8081/m.json')),
      rejected,
    );
    expect(
      () => policy.checkUri(Uri.parse('http://example.org:8080/m.json')),
      rejected,
    );
  });

  group('through a proxy (proxy resolves the host)', () {
    final uri = Uri.parse('https://updates.example.org/m.json');

    test('a host that resolves locally to a private address is rejected', () {
      final policy = AttachedUpdateHostPolicy(
        lookup: (_) async => [InternetAddress('10.1.2.3')],
      );
      expect(
        policy.checkNotPrivate(uri),
        throwsA(isA<AttachedUpdateHostRejected>()),
      );
    });

    test('a failed local lookup is left to the proxy', () async {
      final policy = AttachedUpdateHostPolicy(
        lookup: (_) async => throw const SocketException('no dns'),
      );
      await policy.checkNotPrivate(uri);
    });

    test('the URL rules still apply', () {
      expect(
        const AttachedUpdateHostPolicy().checkNotPrivate(
          Uri.parse('http://updates.example.org/m.json'),
        ),
        throwsA(isA<AttachedUpdateHostRejected>()),
      );
    });
  });
}
