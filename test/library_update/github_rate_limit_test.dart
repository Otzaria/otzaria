import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';

void main() {
  final now = DateTime.utc(2026, 9, 19, 18, 41);

  group('rateLimitExceptionFor', () {
    test('403 עם מכסה ריקה → חריגה עם מועד החידוש', () {
      final reset = now.add(const Duration(minutes: 10));
      final e = GithubRateLimitAwareClient.rateLimitExceptionFor(403, {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
      });
      expect(e, isNotNull);
      expect(e!.resetAt!.isAtSameMomentAs(reset), isTrue);
      expect(e.minutesUntilReset(now: now), 10);
    });

    test('Retry-After (מכסה משנית) קובע את זמן ההמתנה', () {
      final e = GithubRateLimitAwareClient.rateLimitExceptionFor(429, {
        'retry-after': '90',
      }, now: now);
      expect(e!.minutesUntilReset(now: now), 2);
    });

    test('403 שאינו חסימת מכסה (הרשאה) אינו מזוהה כמכסה', () {
      expect(
        GithubRateLimitAwareClient.rateLimitExceptionFor(403, {
          'x-ratelimit-remaining': '42',
        }),
        isNull,
      );
      expect(GithubRateLimitAwareClient.rateLimitExceptionFor(403, {}), isNull);
    });

    test('200 אינו מזוהה גם כשהמכסה אזלה בדיוק בבקשה זו', () {
      expect(
        GithubRateLimitAwareClient.rateLimitExceptionFor(200, {
          'x-ratelimit-remaining': '0',
        }),
        isNull,
      );
    });

    test('מועד שעבר או לא ידוע', () {
      final past = GithubRateLimitException(
        resetAt: now.subtract(const Duration(seconds: 5)),
      );
      expect(past.minutesUntilReset(now: now), 1);
      expect(const GithubRateLimitException().minutesUntilReset(), isNull);
    });
  });

  test('הלקוח זורק GithubRateLimitException ומעביר תשובות רגילות', () async {
    final client = GithubRateLimitAwareClient(
      MockClient((request) async {
        if (request.url.path == '/limited') {
          return http.Response(
            '{"message":"API rate limit exceeded"}',
            403,
            headers: {'x-ratelimit-remaining': '0'},
          );
        }
        return http.Response('[]', 200);
      }),
    );

    final ok = await client.get(Uri.parse('https://api.github.com/ok'));
    expect(ok.body, '[]');
    await expectLater(
      client.get(Uri.parse('https://api.github.com/limited')),
      throwsA(isA<GithubRateLimitException>()),
    );
  });
}
