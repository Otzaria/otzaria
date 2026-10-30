import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/semantic_search/view/semantic_progress_text.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיס נתוני החיפוש הסמנטי: מצב ההורדה, בחירת המודל ומחיקת הנתונים.
/// מוסתר כשהפלטפורמה או המנוע אינם תומכים בחיפוש סמנטי.
class SemanticDataPanel extends StatelessWidget {
  const SemanticDataPanel({super.key, this.repository, this.platformSupported});

  /// ברירת המחדל: [SemanticSearchRepository.instance].
  final SemanticSearchRepository? repository;
  final bool? platformSupported;

  @override
  Widget build(BuildContext context) {
    if (!(platformSupported ?? isSemanticSearchPlatformSupported())) {
      return const SizedBox.shrink();
    }
    return BlocProvider(
      create: (_) => SemanticSearchBloc(
        repository: repository ?? SemanticSearchRepository.instance,
      )..add(const SemanticSearchStarted()),
      child: const _SemanticDataCard(),
    );
  }
}

class _SemanticDataCard extends StatelessWidget {
  const _SemanticDataCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SemanticSearchBloc, SemanticSearchState>(
      builder: (context, state) {
        final availability = state.availability;
        if (availability.phase == SemanticAvailabilityPhase.hidden) {
          return const SizedBox.shrink();
        }
        final bloc = context.read<SemanticSearchBloc>();
        return SettingsCard(
          cardId: 'system.semanticData',
          title: context.settingsText('נתוני {name}', args: _nameArgs(context)),
          subtitle: context.settingsText(
            'הנתונים ש{name} משתמש בהם, כ-1.8GB בכונן. אחרי ההורדה הם מתעדכנים ברקע עם עדכוני הספרייה.',
            args: _nameArgs(context),
          ),
          children: [
            SettingsActionTile.text(
              key: const ValueKey('semantic-data-status'),
              icon: FluentIcons.arrow_download_24_regular,
              title: context.settingsText('מצב הנתונים'),
              subtitle: _statusText(context, availability),
              actions: _statusActions(context, bloc, availability),
            ),
            if (bloc.repository.availableQuantizations.length > 1)
              SettingsActionTile.segmentedTile<SemanticQuantization>(
                key: const ValueKey('semantic-data-quantization'),
                icon: FluentIcons.brain_circuit_24_regular,
                title: context.settingsText('רכיב החיפוש'),
                options: [
                  SegmentOption(
                    value: SemanticQuantization.int8,
                    label: context.settingsText('מהיר'),
                    subtitle: context.settingsText('כ-42MB, ברירת המחדל'),
                  ),
                  SegmentOption(
                    value: SemanticQuantization.fp32,
                    label: context.settingsText('מלא'),
                    subtitle: context.settingsText(
                      'כ-168MB, תוצאות כמעט זהות וזיכרון רב יותר',
                    ),
                  ),
                ],
                currentValue: state.quantization,
                onChanged: (value) =>
                    bloc.add(SemanticQuantizationChanged(value)),
              ),
            if (_modelInstalled(availability))
              SettingsActionTile.text(
                icon: FluentIcons.document_text_24_regular,
                title: context.settingsText(
                  'רישיון רכיב {name}',
                  args: _nameArgs(context),
                ),
                subtitle: context.settingsText(
                  'רכיב החיפוש מופץ ברישיון לשימוש אישי בלבד',
                ),
                actions: [
                  ActionButton.ghost(
                    key: const ValueKey('semantic-data-license'),
                    text: context.settingsText('הצג'),
                    onPressed: () => _showLicense(context, bloc),
                  ),
                ],
              ),
            SettingsActionTile.text(
              icon: FluentIcons.delete_24_regular,
              title: context.settingsText(
                'מחיקת נתוני {name}',
                args: _nameArgs(context),
              ),
              subtitle: context.settingsText(
                'מוחק את נתוני {name} מהכונן ומפסיק את עדכונם',
                args: _nameArgs(context),
              ),
              actions: [
                ActionButton.neutral(
                  key: const ValueKey('semantic-data-remove'),
                  text: context.settingsText('מחק'),
                  isLoading: state.isRemoving,
                  onPressed: () => _confirmRemoval(context, bloc),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _statusText(
    BuildContext context,
    SemanticAvailability availability,
  ) {
    final progress = availability.progress;
    return switch (availability.phase) {
      SemanticAvailabilityPhase.hidden => '',
      SemanticAvailabilityPhase.consentRequired => context.settingsText(
        'כדי להשתמש ב{name} יש להפעיל את "שיפור המנגנון"',
        args: _nameArgs(context),
      ),
      SemanticAvailabilityPhase.needsDownload when availability.pausedByUser =>
        context.settingsText('ההורדה הושהתה. אפשר להמשיך אותה מאותה נקודה.'),
      SemanticAvailabilityPhase.needsDownload
          when availability.stagedDataFound =>
        context.settingsText(
          SemanticSearchMessages.stagedDataFound,
          args: _nameArgs(context),
        ),
      SemanticAvailabilityPhase.needsDownload => context.settingsText(
        'הנתונים עוד לא הורדו',
      ),
      SemanticAvailabilityPhase.vectorsNotPublished => context.settingsText(
        'הנתונים לגרסת הספרייה {version} עוד לא פורסמו. הם יורדו כשיתפרסמו.',
        args: {'version': '${availability.unpublishedLibraryVersion ?? ''}'},
      ),
      SemanticAvailabilityPhase.downloading ||
      SemanticAvailabilityPhase.installing when progress != null =>
        semanticProgressText(context, progress),
      SemanticAvailabilityPhase.downloading => context.settingsText(
        SemanticSearchMessages.downloadingData,
      ),
      SemanticAvailabilityPhase.installing => context.settingsText(
        SemanticSearchMessages.installingData,
      ),
      SemanticAvailabilityPhase.ready => context.settingsText(
        'הנתונים מותקנים ומוכנים',
      ),
      SemanticAvailabilityPhase.failed => context.settingsText(
        SemanticSearchMessages.failure(
          availability.failure?.kind ?? SemanticFailureKind.internal,
        ),
        args: _nameArgs(context),
      ),
    };
  }

  static List<Widget> _statusActions(
    BuildContext context,
    SemanticSearchBloc bloc,
    SemanticAvailability availability,
  ) {
    return switch (availability.phase) {
      SemanticAvailabilityPhase.needsDownload => [
        ActionButton.recommended(
          key: const ValueKey('semantic-data-download'),
          text: context.settingsText(
            availability.stagedDataFound
                ? SemanticSearchMessages.install
                : 'הורד',
          ),
          onPressed: () => bloc.add(const SemanticDownloadRequested()),
        ),
      ],
      SemanticAvailabilityPhase.failed => [
        ActionButton.recommended(
          key: const ValueKey('semantic-data-retry'),
          text: context.settingsText('נסה שוב'),
          onPressed: () => bloc.add(const SemanticDownloadRequested()),
        ),
      ],
      SemanticAvailabilityPhase.downloading => [
        ActionButton.ghost(
          key: const ValueKey('semantic-data-cancel'),
          text: context.settingsText('ביטול'),
          onPressed: () => bloc.add(const SemanticDownloadCancelRequested()),
        ),
      ],
      _ => const [],
    };
  }

  static bool _modelInstalled(SemanticAvailability availability) =>
      switch (availability.phase) {
        SemanticAvailabilityPhase.ready ||
        SemanticAvailabilityPhase.vectorsNotPublished ||
        SemanticAvailabilityPhase.installing => true,
        SemanticAvailabilityPhase.downloading =>
          availability.progress?.item != SemanticDownloadItem.model,
        _ => false,
      };

  static Future<void> _showLicense(
    BuildContext context,
    SemanticSearchBloc bloc,
  ) async {
    final license = await bloc.repository.readModelLicense();
    if (license == null || !context.mounted) return;
    await showSemanticLicenseDialog(
      context,
      title: context.settingsText(
        'רישיון רכיב {name}',
        args: _nameArgs(context),
      ),
      license: license,
    );
  }

  static Future<void> _confirmRemoval(
    BuildContext context,
    SemanticSearchBloc bloc,
  ) async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText(
        'למחוק את נתוני {name}?',
        args: _nameArgs(context),
      ),
      content: context.settingsText(
        'הנתונים יימחקו מהכונן. כדי להשתמש שוב ב{name} יהיה צורך להוריד אותם מחדש.',
        args: _nameArgs(context),
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('מחק'),
    );
    if (confirmed == true) bloc.add(const SemanticDataRemovalRequested());
  }
}

/// שם המצב, מתורגם, למחרוזות עם `{name}`.
Map<String, Object?> _nameArgs(BuildContext context) => {
  'name': context.settingsText(kSemanticSearchModeName),
};

/// נוסח הרישיון של רכיב החיפוש החכם, בדיאלוג עם רצועת כותרת וגלילה.
Future<void> showSemanticLicenseDialog(
  BuildContext context, {
  required String title,
  required String license,
}) {
  return showSingleActionDialog(
    context: context,
    title: title,
    icon: FluentIcons.certificate_24_regular,
    headerBand: true,
    customContent: _LicenseContent(license: license),
    confirmText: context.settingsText('סגור'),
  );
}

/// גוף דיאלוג הרישיון: כותרת (שורה ראשונה של הנוסח) ושורת הסבר, ומתחתן הנוסח
/// המלא בכרטיס נגלל עם פס גלילה קבוע — אחרת הנוסח נחתך בלי סימן שיש המשך.
class _LicenseContent extends StatefulWidget {
  const _LicenseContent({required this.license});

  final String license;

  @override
  State<_LicenseContent> createState() => _LicenseContentState();
}

class _LicenseContentState extends State<_LicenseContent> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstLine = widget.license
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final heading = firstLine.isNotEmpty && firstLine.length <= 60
        ? firstLine
        : context.settingsText('נוסח הרישיון');
    return SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailsHeading(
            title: heading,
            subtitle: context.settingsText('נוסח הרישיון המקורי, באנגלית'),
          ),
          const SizedBox(height: AppTokens.spaceMD),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppSurfaces.card(context),
                  borderRadius: AppTokens.borderRadiusAll,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppTokens.spaceMD),
                    child: AppSelectionArea(
                      child: Text(
                        widget.license,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: AppTokens.fontMD,
                          height: 1.5,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
