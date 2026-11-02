import 'package:http/http.dart' as http;

/// התג של ה-release היציב האחרון, מההפניה של `github.com/<repo>/releases/latest`.
/// בקשה זו אינה נספרת במכסת ה-API האנונימית; null כשאין הפניה תקינה לתג.
Future<String?> fetchLatestStableTagViaRedirect({
  required String owner,
  required String repository,
  required http.Client client,
  required Duration timeout,
}) async {
  final request = http.Request(
    'HEAD',
    Uri.https('github.com', '/$owner/$repository/releases/latest'),
  )..followRedirects = false;
  final response = await http.Response.fromStream(
    await client.send(request).timeout(timeout),
  );
  if (response.statusCode != 301 && response.statusCode != 302) return null;
  final location = response.headers['location'];
  if (location == null) return null;
  final target = request.url.resolve(location);
  if (target.host != 'github.com') return null;
  const marker = '/releases/tag/';
  final index = target.path.lastIndexOf(marker);
  if (index == -1) return null;
  final tag = Uri.decodeComponent(
    target.path.substring(index + marker.length),
  );
  return tag.isEmpty ? null : tag;
}
