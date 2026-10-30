import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/settings/l10n/settings_dialog_scope.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// צ'יפ קטן בכרטיס המסדים המצורפים.
class AttachedInfoChip extends StatelessWidget {
  const AttachedInfoChip({
    super.key,
    required this.label,
    this.background,
    this.foreground,
  });

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground ?? cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The update-source chip: none, signed with its domain, or changed.
class AttachedUpdateSourceChip extends StatelessWidget {
  const AttachedUpdateSourceChip({super.key, required this.library});

  final AttachedLibrary library;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final source = library.updateSource;
    if (source == null) {
      return AttachedInfoChip(label: context.settingsText('אין מקור עדכונים'));
    }
    if (library.updateSourceMismatch) {
      return AttachedInfoChip(
        label: context.settingsText('מקור העדכון השתנה — לא יעודכן'),
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
      );
    }
    return AttachedInfoChip(
      label: context.settingsText(
        'חתום · {domain}',
        args: {'domain': source.host},
      ),
    );
  }
}

/// שורת העדכון של מסד: בדיקה, "עדכון זמין", התקדמות וביטול, ושגיאות.
class AttachedLibraryUpdateRow extends StatelessWidget {
  const AttachedLibraryUpdateRow({
    super.key,
    required this.status,
    required this.onCheck,
    required this.onInstall,
    required this.onCancel,
  });

  final AttachedUpdateStatus status;
  final VoidCallback onCheck;
  final void Function(AttachedUpdateOffer offer) onInstall;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    final errorStyle = style?.copyWith(color: cs.error);
    final checkButton = ActionButton.ghost(
      text: context.settingsText('בדוק עדכונים'),
      icon: FluentIcons.arrow_sync_24_regular,
      onPressed: onCheck,
    );
    final status = this.status;
    final List<Widget> children = switch (status) {
      AttachedUpdateIdle() => [checkButton],
      AttachedUpdateChecking() => [
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        Text(context.settingsText('בודק עדכונים…'), style: style),
      ],
      AttachedUpdateUpToDate() => [
        Text(context.settingsText('המסד מעודכן'), style: style),
        checkButton,
      ],
      AttachedUpdateAvailable(:final offer) => [
        Text(
          context.settingsText(
            'עדכון זמין (גרסה {version})',
            args: {'version': offer.dbVersion},
          ),
          style: style?.copyWith(color: cs.primary),
        ),
        ActionButton.recommended(
          text: context.settingsText('עדכן'),
          icon: FluentIcons.arrow_download_24_regular,
          onPressed: () => onInstall(offer),
        ),
      ],
      AttachedUpdateInProgress() => [
        SizedBox(
          width: 160,
          child: LinearProgressIndicator(value: status.fraction),
        ),
        Text(_progressText(context, status), style: style),
        if (status.phase == AttachedUpdatePhase.download)
          ActionButton.ghost(
            text: context.settingsText('ביטול'),
            onPressed: onCancel,
          ),
      ],
      AttachedUpdateInstalled(:final dbVersion) => [
        Text(
          context.settingsText(
            'עודכן לגרסה {version}',
            args: {'version': dbVersion},
          ),
          style: style,
        ),
      ],
      AttachedUpdateFailed(:final offer) => [
        Text(errorText(context, status), style: errorStyle),
        if (offer != null)
          ActionButton.neutral(
            text: context.settingsText('עדכן'),
            icon: FluentIcons.arrow_download_24_regular,
            onPressed: () => onInstall(offer),
          )
        else
          checkButton,
      ],
    };
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  static String _progressText(
    BuildContext context,
    AttachedUpdateInProgress status,
  ) => switch (status.phase) {
    AttachedUpdatePhase.download => context.settingsText(
      'מוריד {received} מתוך {total}',
      args: {
        'received': formatUpdateBytes(status.received),
        'total': formatUpdateBytes(status.total),
      },
    ),
    AttachedUpdatePhase.assemble => context.settingsText('מאמת את הקובץ…'),
    AttachedUpdatePhase.install => context.settingsText('מתקין…'),
  };

  static String errorText(
    BuildContext context,
    AttachedUpdateFailed failed,
  ) => switch (failed.error) {
    AttachedUpdateError.offline => context.settingsText(
      'מצב לא מקוון — העדכונים כבויים',
    ),
    AttachedUpdateError.updatesDisabled => context.settingsText(
      'עדכוני התוכנה והספרים כבויים בהגדרות',
    ),
    AttachedUpdateError.noSource => context.settingsText('אין מקור עדכונים'),
    AttachedUpdateError.sourceMismatch => context.settingsText(
      'מקור העדכון השתנה — לא יעודכן',
    ),
    AttachedUpdateError.network => context.settingsText(
      'לא ניתן להתחבר למקור העדכונים',
    ),
    AttachedUpdateError.hostRejected => context.settingsText(
      'כתובת מקור העדכונים אינה מותרת',
    ),
    AttachedUpdateError.badSignature => context.settingsText(
      'חתימת העדכון אינה תקינה — העדכון נדחה',
    ),
    AttachedUpdateError.badManifest => context.settingsText(
      'קובץ העדכון שפורסם אינו תקין',
    ),
    AttachedUpdateError.notApplicable => context.settingsText(
      'העדכון שפורסם אינו מתאים למסד זה',
    ),
    AttachedUpdateError.fileMissing => context.settingsText(
      'קובץ המסד אינו זמין (הכונן מנותק?)',
    ),
    AttachedUpdateError.readOnly => context.settingsText(
      'אין הרשאת כתיבה לתיקיית המסד',
    ),
    AttachedUpdateError.noSpace => context.settingsText(
      'אין מספיק מקום פנוי (נדרשים {size})',
      args: {'size': formatUpdateBytes(failed.requiredBytes ?? 0)},
    ),
    AttachedUpdateError.fileLocked => context.settingsText(
      'קובץ המסד תפוס על ידי תוכנה אחרת',
    ),
    AttachedUpdateError.downloadCorrupt => context.settingsText(
      'הקובץ שהורד פגום — נסו שוב',
    ),
    AttachedUpdateError.verifyFailed => context.settingsText(
      'המסד החדש לא עבר את הבדיקה — המסד הקודם נשמר',
    ),
    AttachedUpdateError.unknown => context.settingsText('העדכון נכשל'),
  };
}

String formatUpdateBytes(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}

/// אישור התקנה: דומיין, גרסה, גודל והערות השחרור (טקסט פשוט).
Future<bool> confirmAttachedUpdate(
  BuildContext context,
  AttachedLibrary library,
  AttachedUpdateOffer offer,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (dialogContext) => AppDialog.twoActions(
        title: dialogContext.settingsText(
          'עדכון המסד "{name}"',
          args: {'name': library.displayName},
        ),
        icon: FluentIcons.arrow_sync_24_regular,
        headerBand: true,
        content: '',
        customContent: _ConfirmContent(offer: offer),
        cancelText: dialogContext.settingsText('ביטול'),
        confirmText: dialogContext.settingsText('עדכן'),
      ),
    ),
  );
  return confirmed == true;
}

class _ConfirmContent extends StatelessWidget {
  const _ConfirmContent({required this.offer});

  final AttachedUpdateOffer offer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notes = offer.releaseNotes?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.settingsText(
            'גרסה: {version}',
            args: {'version': offer.dbVersion},
          ),
        ),
        Text(
          context.settingsText(
            'מקור: {domain} (חתום)',
            args: {'domain': offer.domain},
          ),
        ),
        Text(
          context.settingsText(
            'הקבצים יורדו מ: {hosts}',
            args: {'hosts': offer.manifest.downloadHosts.join(', ')},
          ),
        ),
        Text(
          context.settingsText(
            'גודל ההורדה: {size}',
            args: {'size': formatUpdateBytes(offer.downloadSize)},
          ),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            context.settingsText('מה חדש:'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(child: Text(notes)),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          context.settingsText(
            'המסד יוחלף במקומו; הגרסה הקודמת נשמרת עד שהעדכון יאומת.',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// סיכום אחרי צירוף מסד שיש לו מקור עדכונים — הסכמה מדעת לפנייה לדומיין.
Future<void> showAttachedSummaryDialog(
  BuildContext context,
  AttachedLibrary library,
) async {
  final source = library.updateSource;
  if (source == null) return;
  await showDialog<void>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (dialogContext) {
        final attached = dialogContext.settingsText(
          'המסד "{name}" צורף לספרייה.',
          args: {'name': library.displayName},
        );
        final consent = dialogContext.settingsText(
          'העדכונים שלו חתומים ויגיעו מ-{domain}. אוצריא תבדוק שם עדכונים כשבדיקת עדכוני הספרייה פעילה, ולא תתקין דבר בלי אישורך.',
          args: {'domain': source.host},
        );
        return AppDialog.singleAction(
          title: dialogContext.settingsText('המסד צורף'),
          content: '$attached\n\n$consent',
          confirmText: dialogContext.settingsText('הבנתי'),
        );
      },
    ),
  );
}
