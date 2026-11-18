import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_http_client.dart';
import 'package:otzaria/empty_library/services/library_space_estimate.dart';
import 'package:otzaria/utils/http_redirect_download.dart';

/// Reads only the first zstd frame header, including split archives whose
/// first part is a byte range of the same compressed stream.
/// A missing/invalid FCS is not a failure of the download: callers fall back
/// to a conservative compressed-size estimate.
Future<int?> probeZstdFrameContentSize(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final response = await sendGetFollowingRedirects(
      createDownloadClient(httpClient),
      Uri.parse(url),
      headers: const {'Range': 'bytes=0-17'},
      stallTimeout: timeout,
    );
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.listen((_) {}).cancel();
      return null;
    }

    final header = <int>[];
    await for (final chunk in response.stream) {
      header.addAll(chunk.take(18 - header.length));
      if (header.length == 18) break;
    }
    return zstdFrameContentSize(header);
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) httpClient.close();
  }
}
