/// zstd-compressed page VFS for SQLite (`zvfs`) with an append-only write
/// overlay, a streaming converter from plain SQLite to `.zdb`, and compaction.
library;

export 'src/zvfs.dart'
    show
        ZVfs,
        ZVfsStats,
        ZdbCancellationToken,
        ZdbCancelledException,
        ZdbCompactResult,
        ZdbConvertProgress,
        ZdbConvertResult,
        ZdbDictionary,
        ZdbException,
        ZdbInfo,
        ZdbOverlayInfo,
        ZdbSource,
        compactZdb,
        convertToZdb,
        isZdb,
        readZdbBytes,
        readZdbInfo,
        readZdbOverlayInfo,
        verifyZdb,
        zdbMagic;
