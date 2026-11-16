import 'dart:convert';

/// זהות מקום קריאה משותפת להיסטוריה ולגיבויים; שם משמש רק לפני שמירת ID.
String readingHistoryKey({
  required String bookKey,
  required String targetKind,
  String? historySlot,
  String? workspaceId,
  String? workspaceName,
}) {
  final key =
      '$targetKind:$bookKey${historySlot == null ? '' : '#$historySlot'}';
  final workspace = workspaceId != null
      ? ['id', workspaceId]
      : workspaceName != null
      ? ['name', workspaceName]
      : null;
  return workspace == null ? key : '$key@${jsonEncode(workspace)}';
}
