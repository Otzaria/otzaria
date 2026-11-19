import 'dart:async';

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
  final httpClient = createDownloadClient(client);
  final abort = Completer<void>();
  StreamIterator<List<int>>? body;

  Future<int?> readHeader() async {
    final response = await sendGetFollowingRedirects(
      httpClient,
      Uri.parse(url),
      headers: const {'Range': 'bytes=0-17'},
      stallTimeout: timeout,
      abortTrigger: abort.future,
    );
    if (abort.isCompleted ||
        (response.statusCode != 200 && response.statusCode != 206)) {
      await response.stream.listen((_) {}).cancel();
      return null;
    }

    final header = <int>[];
    final chunks = body = StreamIterator(response.stream);
    while (await chunks.moveNext()) {
      header.addAll(chunks.current.take(18 - header.length));
      if (header.length == 18) break;
    }
    return zstdFrameContentSize(header);
  }

  try {
    return await readHeader().timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    abort.complete();
    unawaited(body?.cancel().catchError((Object _) {}));
    if (ownsClient) httpClient.close();
  }
}
