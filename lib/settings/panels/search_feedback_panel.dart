import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';

/// כרטיס ההסכמה לשליחת נתוני שימוש של מצב החיפוש הסמנטי.
/// כיבוי המתג מבטל את ההסכמה ומוחק את התור ואת מפתח ההתקנה.
class SearchFeedbackPanel extends StatelessWidget {
  const SearchFeedbackPanel({super.key, this.store});

  /// ברירת המחדל: [SearchFeedbackService.instance].
  final SearchFeedbackConsentStore? store;

  @override
  Widget build(BuildContext context) {
    final consentStore = store ?? SearchFeedbackService.instance;
    final modeName = context.settingsText(kSemanticSearchModeName);
    return SettingsCard(
      cardId: 'system.searchFeedback',
      title: modeName,
      children: [
        StreamBuilder<SearchFeedbackConsent>(
          stream: consentStore.changes,
          initialData: consentStore.consent,
          builder: (context, snapshot) => SettingsActionTile.switchTile(
            key: const ValueKey('search-feedback-consent-switch'),
            icon: FluentIcons.data_usage_24_regular,
            title: context.settingsText('שיפור המנגנון'),
            subtitle: context.settingsText(
              kSemanticSearchConsentTemplate,
              args: {'name': modeName},
            ),
            value: snapshot.data == SearchFeedbackConsent.granted,
            onChanged: (enabled) =>
                enabled ? consentStore.grant() : consentStore.revoke(),
          ),
        ),
      ],
    );
  }
}
