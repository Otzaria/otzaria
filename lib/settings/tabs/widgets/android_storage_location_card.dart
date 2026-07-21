import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/empty_library/services/android_storage_service.dart';
import 'package:otzaria/settings/dialogs/change_location_dialog.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיס הגדרות (Android בלבד) לבחירת מיקום אחסון הספרייה — אחסון פנימי
/// או כרטיס SD. מוצג רק כשקיים כרטיס SD (אחרת אין ברירה אמיתית).
class AndroidStorageLocationCard extends StatefulWidget {
  const AndroidStorageLocationCard({super.key});

  @override
  State<AndroidStorageLocationCard> createState() =>
      _AndroidStorageLocationCardState();
}

class _AndroidStorageLocationCardState
    extends State<AndroidStorageLocationCard> {
  late Future<_StorageView> _view = _load();

  Future<_StorageView> _load() async {
    final options = await AndroidStorageService.listStorageOptions();
    final internalRoot = await AppPaths.getDataRootPath();
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '';
    // שורש הספרייה הנוכחי הוא ההורה של תיקיית "books"; אם עדיין לא הותקנה
    // ספרייה, ברירת המחדל היא האחסון הפנימי.
    final currentRoot = libraryPath.isEmpty
        ? internalRoot
        : (p.basename(libraryPath).toLowerCase() == 'books'
              ? p.dirname(libraryPath)
              : libraryPath);
    return _StorageView(
      options: options,
      internalRoot: internalRoot,
      currentRoot: currentRoot,
    );
  }

  /// היעד הקונקרטי להעברה עבור אפשרות (אחסון פנימי => שורש הנתונים הפנימי).
  String _targetRoot(AndroidStorageOption option, String internalRoot) =>
      option.libraryRoot ?? internalRoot;

  bool _isCurrent(AndroidStorageOption option, _StorageView view) =>
      p.equals(_targetRoot(option, view.internalRoot), view.currentRoot);

  Future<void> _changeLocation(
    AndroidStorageOption option,
    _StorageView view,
  ) async {
    final booksPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '';
    if (booksPath.isEmpty) return;
    final target = _targetRoot(option, view.internalRoot);
    final removalWarning = option.isRemovable
        ? ' אם הכרטיס יוסר, האפליקציה לא תוכל לגשת לספרים עד שיוחזר.'
        : '';

    final confirmed = await showWarningDialog(
      context: context,
      title: 'העברת הספרייה אל ${option.label}',
      content:
          'הספרייה, האינדקס ומסדי הנתונים יועברו אל ${option.label}. '
          'בזמן ההעברה התוכנה תיטען מחדש ולא תהיה זמינה עד לסיום הפעולה.'
          '$removalWarning',
      subtitle: 'העברה של ספרייה גדולה עשויה לקחת מספר דקות.',
      cancelText: 'ביטול',
      confirmText: 'העבר',
    );
    if (confirmed != true || !mounted) return;

    await performLibraryMove(context: context, from: booksPath, to: target);
    if (mounted) setState(() => _view = _load());
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return FutureBuilder<_StorageView>(
      future: _view,
      builder: (context, snapshot) {
        final view = snapshot.data;
        if (view == null || view.options.isEmpty) {
          return const SizedBox.shrink();
        }
        return SettingsCard(
          cardId: 'library.android_storage',
          title: 'מיקום אחסון הספרייה',
          subtitle: 'בחר אם לשמור את הספרייה באחסון הפנימי או על כרטיס SD',
          children: [
            for (final option in view.options)
              _buildOptionTile(context, option, view),
          ],
        );
      },
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    AndroidStorageOption option,
    _StorageView view,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isCurrent = _isCurrent(option, view);
    final freeText = option.freeBytes >= 0
        ? '${(option.freeBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB פנוי'
        : null;
    final subtitle = option.supportsLargeFiles
        ? freeText
        : 'לא נתמך — הכרטיס מפורמט ב-FAT32 (מגבלת 4GB לקובץ)';

    Widget? trailing;
    if (isCurrent) {
      trailing = Text(
        'בשימוש',
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
      );
    } else if (option.supportsLargeFiles) {
      trailing = ActionButton.recommended(
        text: 'העבר לכאן',
        onPressed: () => _changeLocation(option, view),
      );
    }

    return ListTile(
      enabled: option.supportsLargeFiles,
      hoverColor: Colors.transparent,
      leading: Icon(
        option.isRemovable
            ? FluentIcons.storage_24_regular
            : FluentIcons.phone_24_regular,
        color: isCurrent ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(
        option.label,
        style: TextStyle(
          color: isCurrent ? cs.primary : cs.onSurface,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing,
    );
  }
}

class _StorageView {
  final List<AndroidStorageOption> options;
  final String internalRoot;
  final String currentRoot;

  const _StorageView({
    required this.options,
    required this.internalRoot,
    required this.currentRoot,
  });
}
