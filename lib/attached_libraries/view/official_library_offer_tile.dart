import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/official_attached_library.dart';
import 'package:otzaria/attached_libraries/view/attached_library_update_view.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// הצעה להוריד מסד רשמי שאינו מותקן: שם, גודל מהמניפסט החתום, הורדה וביטול.
class OfficialLibraryOfferTile extends StatelessWidget {
  const OfficialLibraryOfferTile({
    super.key,
    required this.entry,
    required this.status,
    required this.onDownload,
    required this.onCancel,
    required this.onRetry,
    required this.onDecline,
    required this.onImportPackage,
  });

  final OfficialAttachedLibrary entry;
  final AttachedUpdateStatus status;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onDecline;

  /// התקנה מחבילה לא-מקוונת (`<name>-offline.tar.zst`).
  final VoidCallback onImportPackage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final offer = status.offer;
    return SettingsActionTile(
      columnBelowWidth: 620,
      icon: OtzariaIcons.library_database_24_regular,
      iconColor: cs.primary,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(entry.displayName, style: AppTextStyles.settingTitle),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              const OfficialLibraryChip(),
              if (offer != null)
                MetaChip(
                  size: MetaChipSize.small,
                  label: formatUpdateBytes(offer.manifest.full.compressedSize),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _statusRow(context),
        ],
      ),
      subtitle: Text(
        context.settingsText(
          'מסד ספרים רשמי של אוצריא. מתעדכן אוטומטית יחד עם הספרייה.',
        ),
        style: AppTextStyles.settingSubtitle.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _statusRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    final decline = ActionButton.ghost(
      text: context.settingsText('לא תודה'),
      onPressed: onDecline,
    );
    final importPackage = ActionButton.ghost(
      text: context.settingsText('ייבוא מקובץ'),
      icon: FluentIcons.folder_open_24_regular,
      onPressed: onImportPackage,
    );
    final status = this.status;
    final List<Widget> children = switch (status) {
      AttachedUpdateIdle() || AttachedUpdateUpToDate() => [
        ActionButton.ghost(
          text: context.settingsText('בדוק זמינות'),
          icon: FluentIcons.arrow_sync_24_regular,
          onPressed: onRetry,
        ),
        importPackage,
        decline,
      ],
      AttachedUpdateChecking() => [
        const LoadingIndicator.inline(),
        Text(context.settingsText('בודק זמינות…'), style: style),
      ],
      AttachedUpdateAvailable() => [
        ActionButton.recommended(
          text: context.settingsText('הורד'),
          icon: FluentIcons.arrow_download_24_regular,
          onPressed: onDownload,
        ),
        importPackage,
        decline,
      ],
      AttachedUpdateInProgress() => [
        SizedBox(
          width: 160,
          child: LinearProgressIndicator(value: status.fraction),
        ),
        Text(
          AttachedLibraryUpdateRow.progressText(context, status),
          style: style,
        ),
        if (status.phase == AttachedUpdatePhase.download ||
            status.phase == AttachedUpdatePhase.waitingForWifi)
          ActionButton.neutral(
            text: context.settingsText('ביטול'),
            onPressed: onCancel,
          ),
      ],
      AttachedUpdateInstalled() => [
        Text(context.settingsText('הותקן'), style: style),
      ],
      AttachedUpdateFailed(:final offer) => [
        Text(
          AttachedLibraryUpdateRow.errorText(context, status),
          style: style?.copyWith(color: cs.error),
        ),
        ActionButton.neutral(
          text: context.settingsText('נסה שוב'),
          icon: FluentIcons.arrow_sync_24_regular,
          onPressed: offer != null ? onDownload : onRetry,
        ),
        importPackage,
        decline,
      ],
    };
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// שורה מצומצמת למסדים רשמיים שהמשתמש סירב להם: ההצעה זמינה רק כאן.
class DeclinedOfficialLibrariesTile extends StatelessWidget {
  const DeclinedOfficialLibrariesTile({
    super.key,
    required this.entries,
    required this.onShow,
  });

  final List<OfficialAttachedLibrary> entries;
  final void Function(OfficialAttachedLibrary entry) onShow;

  @override
  Widget build(BuildContext context) {
    return SettingsActionTile.text(
      icon: OtzariaIcons.library_database_24_regular,
      title: context.settingsText('מסדים רשמיים'),
      subtitle: context.settingsText(
        'זמינים להורדה: {names}',
        args: {'names': entries.map((e) => e.displayName).join(', ')},
      ),
      actions: [
        for (final entry in entries)
          ActionButton.ghost(
            text: context.settingsText(
              'הצג את {name}',
              args: {'name': entry.displayName},
            ),
            onPressed: () => onShow(entry),
          ),
      ],
    );
  }
}
