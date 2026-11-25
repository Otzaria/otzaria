const perfResourceObservationVersion = 1;
const perfPdfPostCloseIdle = Duration(seconds: 3);

const pdfImageBudgetObservationIdentity = {
  'schemaVersion': perfResourceObservationVersion,
  'source': 'pdfSharedImageBudget',
  'scope': 'current-window-ui-isolate',
  'unit': 'estimated-bytes',
  'peakScope': 'since-budget-construction',
};

const pdfImageBudgetByteKeys = [
  'maximumBytes',
  'retainedBytes',
  'pendingBytes',
  'speculativePendingBytes',
  'estimatedBytes',
  'processPeakEstimatedBytes',
];

Map<String, dynamic>? parsePdfImageBudgetSnapshot(
  Object? value, {
  required String context,
}) {
  if (value == null) return null;
  if (value is! Map<String, dynamic>) {
    throw FormatException('$context: תמונת תקציב תמונות PDF אינה מפה');
  }
  for (final entry in pdfImageBudgetObservationIdentity.entries) {
    if (value[entry.key] != entry.value ||
        (entry.key == 'schemaVersion' && value[entry.key] is! int)) {
      throw FormatException('$context: זהות מדידה לא נתמכת: ${entry.key}');
    }
  }
  for (final key in pdfImageBudgetByteKeys) {
    final bytes = value[key];
    if (bytes is! int || bytes < 0) {
      throw FormatException('$context: $key חייב להיות מספר שלם ולא שלילי');
    }
  }
  if (value['estimatedBytes'] !=
          (value['retainedBytes'] as int) + (value['pendingBytes'] as int) ||
      (value['speculativePendingBytes'] as int) >
          (value['pendingBytes'] as int) ||
      (value['processPeakEstimatedBytes'] as int) <
          (value['estimatedBytes'] as int)) {
    throw FormatException('$context: מוני תקציב תמונות PDF אינם עקביים');
  }
  return value;
}
