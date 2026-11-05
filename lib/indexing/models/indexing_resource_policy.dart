import 'dart:io';

/// ההעדפה נשמרת בנפרד מהמצב שנבחר אוטומטית לריצת האינדוקס.
enum IndexingResourceMode {
  automatic,
  economy,
  normal;

  static IndexingResourceMode fromStorage(String? value) => switch (value) {
    'economy' => economy,
    'normal' => normal,
    _ => automatic,
  };
}

class IndexingResourcePolicy {
  const IndexingResourcePolicy({
    required this.cpuCount,
    required this.mobile,
    this.totalRamMb,
    this.availableRamMb,
  });

  final int cpuCount;
  final bool mobile;
  final int? totalRamMb;
  final int? availableRamMb;

  bool useEconomy(IndexingResourceMode mode) => switch (mode) {
    IndexingResourceMode.economy => true,
    IndexingResourceMode.normal => false,
    IndexingResourceMode.automatic =>
      mobile ||
          cpuCount <= 4 ||
          totalRamMb == null ||
          totalRamMb! <= 4096 ||
          (availableRamMb != null && availableRamMb! < 1024),
  };

  static IndexingResourcePolicy conservative() => IndexingResourcePolicy(
    cpuCount: Platform.numberOfProcessors,
    mobile: Platform.isAndroid || Platform.isIOS,
  );
}
