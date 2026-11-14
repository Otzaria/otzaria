import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/update/updat_compat.dart';

/// בדיקת עדכוני תוכנה יזומה: אותה בדיקה של חיווי העדכון בשורת הכותרת.
/// מחזיר הודעה למשתמש, או null כשאין מה לומר (כשל מדווח בנפרד).
Future<String?> softwareUpdateCheckMessage(
  Future<UpdatStatus?> Function() check,
) async => switch (await check()) {
  UpdatStatus.upToDate => SettingsMessages.softwareUpToDate,
  UpdatStatus.available ||
  UpdatStatus.availableWithChangelog => SettingsMessages.softwareUpdateFound,
  _ => null,
};

/// בדיקת עדכוני ספרייה יזומה: אותה פעולה של כפתור עדכון הספרייה בסרגל.
/// מחזיר הודעה רק כשהספרייה מעודכנת. עדכון שנמצא מוצג בחיווי העבודה
/// ובדיאלוגי העדכון.
Future<String?> libraryUpdateCheckMessage(LibraryUpdateBloc bloc) async {
  if (bloc.state.isBusy || bloc.isOfflineMode() || !bloc.areUpdatesEnabled()) {
    return null;
  }
  final checked = bloc.stream.firstWhere(
    (s) => s.status != LibraryUpdateStatus.checking,
  );
  bloc.add(const StartLibraryUpdate());
  final result = await checked;
  return result.status == LibraryUpdateStatus.completed && !result.hasUpdate
      ? SettingsMessages.libraryUpToDate
      : null;
}
