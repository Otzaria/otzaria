import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/attached_libraries/external_link_work_status.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// המסדים התקינים שיש להם אינדקס קישורים חיצוניים.
List<AttachedLibrary> externalLinkLibraries(List<AttachedLibrary> libraries) =>
    [
      for (final library in libraries)
        if (library.isOk &&
            library.capabilities.contains(
              AttachedLibraryCapability.externalLinks,
            ))
          library,
    ];

/// אישור עצירה, באותו נוסח של עצירת אינדקס החיפוש.
Future<bool> confirmLinkIndexStop(BuildContext context) async =>
    await showWarningDialog(
      context: context,
      title: context.settingsText('עצירת עדכון'),
      content: context.settingsText('האם לעצור את תהליך עדכון האינדקס?'),
      confirmText: context.settingsText('עצור'),
    ) ??
    false;

/// אישור לפני בנייה מחדש, שמוחקת את ההתקדמות השמורה.
Future<bool> confirmLinkIndexRebuild(BuildContext context) async =>
    await showWarningDialog(
      context: context,
      title: context.settingsText('בנייה מחדש של האינדקס'),
      content: context.settingsText(
        'בנייה מחדש מוחקת את ההתקדמות ומתחילה מההתחלה (כמה דקות במסד גדול). להמשיך?',
      ),
      confirmText: context.settingsText('בנה מחדש'),
      cancelText: context.settingsText('ביטול'),
    ) ??
    false;

/// שורת "אינדקס קישורים" בהגדרות הספרייה: התקדמות הבנייה, עצירה, ובנייה
/// מחדש אחרי בנייה שנקטעה.
class ExternalLinkIndexTile extends StatefulWidget {
  const ExternalLinkIndexTile({super.key, required this.slugs, this.links});

  /// המסדים שהאיפוס בונה מחדש.
  final List<String> slugs;

  /// ברירת המחדל: [ExternalLinkRepository.instance].
  final ExternalLinkRepository? links;

  @override
  State<ExternalLinkIndexTile> createState() => _ExternalLinkIndexTileState();
}

class _ExternalLinkIndexTileState extends State<ExternalLinkIndexTile> {
  late final ExternalLinkRepository _repository =
      widget.links ?? ExternalLinkRepository.instance;
  late final Listenable _state = Listenable.merge([
    _repository.buildProgress,
    _repository.buildingSlugs,
    _repository.incompleteSlugs,
    _repository.tooLargeSlugs,
  ]);

  // אחרי אישור הכפתורים כבויים עד שהמצב משתנה, נגד בקשה כפולה.
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() => _requested = false);
  }

  Future<void> _request(
    Future<bool> Function(BuildContext) confirm,
    void Function(String slug) action,
    Iterable<String> targets,
  ) async {
    if (!await confirm(context)) return;
    setState(() => _requested = true);
    targets.toList().forEach(action);
  }

  @override
  Widget build(BuildContext context) {
    if (WindowRole.isSecondary) return const SizedBox.shrink();
    final progress = _repository.buildProgress.value;
    final isBuilding =
        progress.isNotEmpty || _repository.buildingSlugs.value.isNotEmpty;
    final incomplete = _repository.incompleteSlugs.value;
    final tooLarge = _repository.tooLargeSlugs.value.isNotEmpty;
    final (:done, :total) = sumLinkBuildProgress(progress);
    final subtitle = isBuilding
        ? context.settingsText(
            'התקדמות האינדקס: {processed}/{total}',
            args: {
              'processed': formatLinkCount(done),
              'total': formatLinkCount(total),
            },
          )
        : incomplete.isNotEmpty
        ? context.settingsText('אינדקס הקישורים לא הושלם')
        : tooLarge
        ? context.settingsText('הקישורים החיצוניים לא נטענו — יותר מדי שורות')
        : context.settingsText('האינדקס מעודכן');
    return SettingsActionTile.text(
      icon: FluentIcons.table_24_regular,
      title: context.settingsText('אינדקס קישורים'),
      subtitle: subtitle,
      actions: [
        if (isBuilding)
          ActionButton.neutral(
            text: context.settingsText('עצור'),
            onPressed: () async {
              if (await confirmLinkIndexStop(context)) {
                _repository.cancelBuild();
              }
            },
          )
        else if (incomplete.isNotEmpty) ...[
          ActionButton.recommended(
            text: context.settingsText('המשך בנייה'),
            onPressed: _requested
                ? null
                : () {
                    setState(() => _requested = true);
                    incomplete.toList().forEach(_repository.requestResume);
                  },
          ),
          ActionButton.neutral(
            text: context.settingsText('בנה מחדש'),
            onPressed: _requested
                ? null
                : () => _request(
                    confirmLinkIndexRebuild,
                    _repository.requestRebuild,
                    incomplete,
                  ),
          ),
        ] else if (!tooLarge)
          ActionButton.ghost(
            text: context.settingsText('איפוס'),
            onPressed: _requested
                ? null
                : () => _request(
                    confirmLinkIndexRebuild,
                    _repository.requestRebuild,
                    widget.slugs,
                  ),
          ),
      ],
    );
  }
}
