import 'package:pdfrx/pdfrx.dart';

import '../../tool/perf_probe/src/pdf_image_budget.dart';

/// דגימה נקודתית שאינה משנה את התקציב או מאפסת את השיא המצטבר.
Map<String, Object?> capturePdfImageBudget(PdfImageCacheBudget budget) => {
  ...pdfImageBudgetObservationIdentity,
  'maximumBytes': budget.maximumBytes,
  'retainedBytes': budget.retainedBytes,
  'pendingBytes': budget.pendingBytes,
  'speculativePendingBytes': budget.speculativePendingBytes,
  'estimatedBytes': budget.estimatedBytes,
  'processPeakEstimatedBytes': budget.peakEstimatedBytes,
};
