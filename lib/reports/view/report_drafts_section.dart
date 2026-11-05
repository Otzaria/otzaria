import 'package:flutter/material.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// Only summaries are read here; attachment bytes load when a draft is opened.
class ReportDraftsSection extends StatefulWidget {
  const ReportDraftsSection({super.key, this.store, this.openDraft});

  final ReportDraftStore? store;
  final Future<void> Function(BuildContext, ReportDraftRecord)? openDraft;

  @override
  State<ReportDraftsSection> createState() => _ReportDraftsSectionState();
}

class _ReportDraftsSectionState extends State<ReportDraftsSection> {
  late final ReportDraftStore _store;
  List<ReportDraftRecord> _drafts = const [];
  final Set<String> _busy = {};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? ReportDraftStore.instance;
    _store.changes.addListener(_reload);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (widget.store == null) await AppReportService().migrateLegacyDraft();
      await _reload();
    } catch (error) {
      debugPrint('Loading report drafts failed: $error');
    }
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final drafts = await _store.list();
      if (mounted && generation == _generation) {
        setState(() => _drafts = drafts);
      }
    } catch (error) {
      debugPrint('Loading report drafts failed: $error');
    }
  }

  @override
  void dispose() {
    _store.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _run(ReportDraftRecord draft, {bool discard = false}) async {
    if (!_busy.add(draft.id)) return;
    setState(() {});
    try {
      if (discard) {
        await _store.delete(draft.id);
      } else if (widget.openDraft case final open?) {
        await open(context, draft);
      } else if (draft.kind == ReportDraftStore.appKind) {
        await showAppReportDialog(
          context,
          createBloc: () => AppReportBloc(
            trigger: AppReportTrigger.manual,
            draftId: draft.id,
          ),
        );
      } else if (draft.kind == ReportDraftStore.bookKind) {
        await ErrorReportHelper.resumeDraft(context, draft);
      }
      await _reload();
    } catch (error) {
      debugPrint('Report draft action failed: $error');
      if (mounted) {
        UiSnack.showError(
          context.settingsText('לא ניתן לעדכן את הטיוטה. נסו שוב.'),
        );
      }
    } finally {
      _busy.remove(draft.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_drafts.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('report-drafts-section'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.settingsText('טיוטות דיווחים'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.settingsText(
              'הטיוטות נשמרות במחשב הזה בלבד ואינן נשלחות או מיוצאות.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final draft in _drafts) _row(context, draft),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ReportDraftRecord draft) {
    final isBook = draft.kind == ReportDraftStore.bookKind;
    final target = draft.payload['target'] as Map?;
    final form = draft.payload['form'] as Map?;
    final title = draft.title.trim().isNotEmpty
        ? draft.title
        : context.settingsText('דיווח על תקלה בתוכנה');
    final kind = context.settingsText(isBook ? 'טעות בספר' : 'תקלה בתוכנה');
    final details =
        (isBook
                ? (form == null ? null : form['details'])
                : draft.payload['description'])
            as String? ??
        '';
    final location = isBook
        ? '${target?['currentRef'] ?? ''} · ${context.settingsText('שורה {number}', args: {'number': target?['lineNumber'] ?? ''})}'
        : '';
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatCompactDate(draft.updatedAt.toLocal());
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(draft.updatedAt.toLocal()),
    );
    return Padding(
      key: ValueKey('report-draft-${draft.id}'),
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: AppTokens.borderRadiusAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '$kind · $date $time',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (location.isNotEmpty)
                Text(location, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (details.isNotEmpty)
                Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionButton.recommended(
                    key: ValueKey('open-draft-${draft.id}'),
                    text: context.settingsText('המשך עריכה'),
                    onPressed: _busy.contains(draft.id)
                        ? null
                        : () => _run(draft),
                  ),
                  ActionButton.neutral(
                    key: ValueKey('discard-draft-${draft.id}'),
                    text: context.settingsText('השלך טיוטה'),
                    onPressed: _busy.contains(draft.id)
                        ? null
                        : () => _run(draft, discard: true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
