import 'package:http/http.dart' as http;
import 'package:otzaria/core/download_http_client.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    as updater;

export 'package:seforim_library_updater/seforim_library_updater.dart'
    show FileExtractor, FileExtractionResult, extractedPatchFileName;

typedef StreamingZstdExtractor = updater.FileExtractor;

/// מחבר את מנגנון ההורדה המשותף למחלץ zstd ולמדיניות ההורדות של האפליקציה.
class StreamingPatchDownloader extends updater.StreamingPatchDownloader {
  factory StreamingPatchDownloader({
    StreamingZstdExtractor? extractor,
    http.Client? httpClient,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration stallTimeout = const Duration(seconds: 30),
  }) => StreamingPatchDownloader._(
    createDownloadClient(httpClient),
    httpClient == null,
    extractor ?? ZstdStreamExtractor.extractVerifiedToFile,
    connectTimeout,
    stallTimeout,
  );

  StreamingPatchDownloader._(
    this._client,
    this._ownsClient,
    StreamingZstdExtractor extractor,
    Duration connectTimeout,
    Duration stallTimeout,
  ) : super(
        httpClient: _client,
        extractor: extractor,
        connectTimeout: connectTimeout,
        stallTimeout: stallTimeout,
      );

  final http.Client _client;
  final bool _ownsClient;

  @override
  void dispose() {
    super.dispose();
    if (_ownsClient) _client.close();
  }
}
