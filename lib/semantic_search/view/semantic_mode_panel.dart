import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';
import 'package:otzaria/semantic_search/view/semantic_progress_text.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// גוף דיאלוג החיפוש כשנבחר המצב הסמנטי: הסכמה, מצב הנתונים או טופס החיפוש.
class SemanticModePanel extends StatelessWidget {
  const SemanticModePanel({
    super.key,
    required this.availability,
    required this.queryController,
    required this.queryFocusNode,
    this.queryTrailingAction,
    required this.scopeSelection,
    required this.onScopeChanged,
    required this.includeLexical,
    required this.onIncludeLexicalChanged,
    required this.groupIdenticalText,
    required this.onGroupIdenticalTextChanged,
    required this.onSubmit,
    required this.onGrantConsent,
    required this.onDeclineConsent,
    required this.onDownload,
    required this.onCancelDownload,
    this.debug = false,
  });

  final SemanticAvailability availability;
  final TextEditingController queryController;
  final FocusNode queryFocusNode;

  /// פעולה בסוף שדה השאילתה (היסטוריית החיפושים).
  final Widget? queryTrailingAction;
  final Set<String> scopeSelection;
  final ValueChanged<Set<String>> onScopeChanged;
  final bool includeLexical;
  final ValueChanged<bool> onIncludeLexicalChanged;
  final bool groupIdenticalText;
  final ValueChanged<bool> onGroupIdenticalTextChanged;
  final VoidCallback onSubmit;
  final VoidCallback onGrantConsent;
  final VoidCallback onDeclineConsent;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;

  /// מצב פיתוח (kDebugMode), שבו מותרת תצוגה מקדימה בלי מנוע.
  final bool debug;

  static const Set<SemanticAvailabilityPhase> _statusPhases = {
    SemanticAvailabilityPhase.needsDownload,
    SemanticAvailabilityPhase.vectorsNotPublished,
    SemanticAvailabilityPhase.downloading,
    SemanticAvailabilityPhase.installing,
    SemanticAvailabilityPhase.failed,
  };

  @override
  Widget build(BuildContext context) {
    if (!isSemanticModeVisible(availability, debug: debug)) {
      return const SizedBox.shrink();
    }
    if (!availability.consentGranted) return _buildConsentCard(context);
    final preview = isSemanticDebugPreview(availability, debug: debug);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_statusPhases.contains(availability.phase)) ...[
          _buildStatusCard(context),
          const SizedBox(height: 12),
        ],
        if (preview) ...[
          const SemanticDebugPreviewBanner(),
          const SizedBox(height: 12),
        ],
        if (availability.isUsable || preview) _buildSearchForm(context),
      ],
    );
  }

  String _modeName(BuildContext context) =>
      context.settingsText(kSemanticSearchModeName);

  Widget _card(BuildContext context, {required Widget child, Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _buildConsentCard(BuildContext context) {
    final theme = Theme.of(context);
    return _card(
      context,
      key: const ValueKey('semantic-consent-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.shield_checkmark_24_regular,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.settingsText(kSemanticSearchModeLabel),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.settingsText(
              kSemanticSearchConsentTemplate,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionButton.recommended(
                key: const ValueKey('semantic-consent-grant'),
                text: context.settingsText('אני מסכים'),
                onPressed: onGrantConsent,
              ),
              ActionButton.neutral(
                key: const ValueKey('semantic-consent-decline'),
                text: context.settingsText('לא עכשיו'),
                onPressed: onDeclineConsent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final progress = availability.progress;
    final fraction = progress?.fraction;
    final name = {'name': _modeName(context)};
    final staged = availability.stagedDataFound;
    final String text = switch (availability.phase) {
      SemanticAvailabilityPhase.needsDownload when staged =>
        context.settingsText(
          SemanticSearchMessages.stagedDataFound,
          args: name,
        ),
      SemanticAvailabilityPhase.needsDownload => context.settingsText(
        'כדי להשתמש ב{name} יש להוריד תחילה את הנתונים שלו (כ-1.8GB).',
        args: name,
      ),
      SemanticAvailabilityPhase.vectorsNotPublished => context.settingsText(
        'נתוני החיפוש לגרסת הספרייה {version} עוד לא פורסמו. הם יורדו כשיתפרסמו.',
        args: {'version': '${availability.unpublishedLibraryVersion ?? ''}'},
      ),
      SemanticAvailabilityPhase.downloading ||
      SemanticAvailabilityPhase.installing when progress != null =>
        semanticProgressText(context, progress),
      SemanticAvailabilityPhase.downloading => context.settingsText(
        'מוריד את הנתונים',
      ),
      SemanticAvailabilityPhase.installing => context.settingsText(
        'מתקין את הנתונים',
      ),
      _ => context.settingsText(
        SemanticSearchMessages.failure(
          availability.failure?.kind ?? SemanticFailureKind.internal,
        ),
        args: name,
      ),
    };
    final isFailure = availability.phase == SemanticAvailabilityPhase.failed;
    final Widget? action = switch (availability.phase) {
      SemanticAvailabilityPhase.needsDownload => ActionButton.recommended(
        key: const ValueKey('semantic-status-download'),
        text: context.settingsText(
          staged ? SemanticSearchMessages.install : 'הורד',
        ),
        icon: FluentIcons.arrow_download_24_regular,
        onPressed: onDownload,
      ),
      SemanticAvailabilityPhase.vectorsNotPublished => ActionButton.neutral(
        key: const ValueKey('semantic-status-recheck'),
        text: context.settingsText('בדוק שוב'),
        icon: FluentIcons.arrow_clockwise_24_regular,
        onPressed: onDownload,
      ),
      SemanticAvailabilityPhase.downloading => ActionButton.ghost(
        key: const ValueKey('semantic-status-cancel'),
        text: context.settingsText('ביטול'),
        onPressed: onCancelDownload,
      ),
      SemanticAvailabilityPhase.failed => ActionButton.recommended(
        key: const ValueKey('semantic-status-retry'),
        text: context.settingsText('נסה שוב'),
        icon: FluentIcons.arrow_clockwise_24_regular,
        onPressed: onDownload,
      ),
      _ => null,
    };
    final showsProgress =
        availability.phase == SemanticAvailabilityPhase.downloading ||
        availability.phase == SemanticAvailabilityPhase.installing;
    return _card(
      context,
      key: const ValueKey('semantic-status-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isFailure
                    ? FluentIcons.warning_24_regular
                    : FluentIcons.arrow_download_24_regular,
                color: isFailure
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isFailure ? theme.colorScheme.error : null,
                  ),
                ),
              ),
              if (action != null) ...[const SizedBox(width: 8), action],
            ],
          ),
          if (showsProgress) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: availability.phase == SemanticAvailabilityPhase.installing
                  ? null
                  : fraction,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchForm(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('semantic-search-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RtlTextField(
          key: const ValueKey('semantic-query-field'),
          controller: queryController,
          focusNode: queryFocusNode,
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHigh,
            border: const OutlineInputBorder(),
            labelText: context.settingsText(kSemanticSearchModeLabel),
            hintText: context.settingsText(
              'תארו במילים שלכם את העניין שאתם מחפשים',
            ),
            prefixIcon: const Icon(
              OtzariaIcons.search_in_library_24_regular,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: queryController,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            key: const ValueKey('semantic-query-clear'),
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            tooltip: context.settingsText('נקה'),
                            onPressed: queryController.clear,
                          ),
                  ),
                  ?queryTrailingAction,
                ],
              ),
            ),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SearchScopeMenuButton(
                selected: scopeSelection,
                officialBooksOnly: true,
                onChanged: onScopeChanged,
              ),
              FilterChip(
                key: const ValueKey('semantic-include-lexical'),
                label: Text(context.settingsText('שלב גם התאמה מילולית')),
                visualDensity: VisualDensity.compact,
                selected: includeLexical,
                onSelected: onIncludeLexicalChanged,
              ),
              FilterChip(
                key: const ValueKey('semantic-group-identical'),
                label: Text(context.settingsText('איחוד טקסטים זהים')),
                visualDensity: VisualDensity.compact,
                selected: groupIdenticalText,
                onSelected: onGroupIdenticalTextChanged,
              ),
            ],
          ),
        ),
        if (isWholeLibraryScope(scopeSelection)) ...[
          const SizedBox(height: 8),
          SemanticNarrowScopeHint(
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// המלצה לצמצם את ההיקף, כשהחיפוש רץ על כל הספרייה.
class SemanticNarrowScopeHint extends StatelessWidget {
  const SemanticNarrowScopeHint({super.key, this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.settingsText(
        'החיפוש מדויק יותר כשמצמצמים אותו לספרים או לקטגוריות מסוימות.',
      ),
      key: const ValueKey('semantic-narrow-scope-hint'),
      style: style,
    );
  }
}

/// באנר התצוגה המקדימה בפיתוח.
class SemanticDebugPreviewBanner extends StatelessWidget {
  const SemanticDebugPreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('semantic-debug-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.beaker_24_regular,
            size: 18,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.settingsText(kSemanticDebugPreviewBanner),
              style: TextStyle(color: colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
