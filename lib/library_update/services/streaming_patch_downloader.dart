import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    as updater;

export 'package:seforim_library_updater/seforim_library_updater.dart'
    show FileExtractor, FileExtractionResult, extractedPatchFileName;

typedef StreamingZstdExtractor = updater.FileExtractor;

/// מחבר את מנגנון ההורדה המשותף למחלץ zstd הנייטיבי של האפליקציה.
class StreamingPatchDownloader extends updater.StreamingPatchDownloader {
  StreamingPatchDownloader({
    StreamingZstdExtractor? extractor,
    super.httpClient,
    super.connectTimeout,
    super.stallTimeout,
  }) : super(
         extractor: extractor ?? ZstdStreamExtractor.extractVerifiedToFile,
       );
}
