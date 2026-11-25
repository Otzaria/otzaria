import 'package:path/path.dart' as p;

String saveTargetFileName(String? requested, String? extension) {
  final cleaned = (requested ?? '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .trim();
  final base = cleaned.isEmpty ? 'מסמך' : cleaned;
  final normalizedExtension = extension
      ?.trim()
      .replaceFirst(RegExp(r'^\.+'), '')
      .toLowerCase();
  if (normalizedExtension == null || normalizedExtension.isEmpty) return base;
  if (!RegExp(r'^[a-z0-9]+$').hasMatch(normalizedExtension)) {
    throw ArgumentError.value(extension, 'extension', 'Invalid file extension');
  }
  return base.toLowerCase().endsWith('.$normalizedExtension')
      ? base
      : '$base.$normalizedExtension';
}

String? saveTargetPath({required String folder, required String fileName}) {
  final root = p.normalize(folder);
  final target = p.normalize(p.join(root, fileName));
  if (p.dirname(target) != root || p.basename(target) != fileName) return null;
  return target;
}

String saveTargetFolderDialogTitle(String? dialogTitle) {
  final trimmed = dialogTitle?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'בחירת תיקייה לשמירת הקובץ';
  return 'בחירת תיקייה — $trimmed';
}
