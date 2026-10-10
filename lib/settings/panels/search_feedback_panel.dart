import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיס ההסכמה לשליחת נתוני שימוש של מצב החיפוש הסמנטי.
/// כיבוי המתג מבטל את ההסכמה ומוחק אירועים שטרם נשלחו.
class SearchFeedbackPanel extends StatelessWidget {
  const SearchFeedbackPanel({
    super.key,
    this.store,
    this.platformSupported,
    this.networkBlock,
  });

  /// ברירת המחדל: [SearchFeedbackService.instance].
  final SearchFeedbackConsentStore? store;
  final bool? platformSupported;

  /// ברירת המחדל: [SearchFeedbackService.networkBlock] של [store].
  final ValueListenable<SearchFeedbackNetworkBlock?>? networkBlock;

  @override
  Widget build(BuildContext context) {
    if (!(platformSupported ?? isSemanticSearchPlatformSupported())) {
      return const SizedBox.shrink();
    }
    final consentStore = store ?? SearchFeedbackService.instance;
    final modeName = context.settingsText(kSemanticSearchModeLabel);
    final blockStatus =
        networkBlock ??
        (consentStore is SearchFeedbackService
            ? consentStore.networkBlock
            : null);
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
            ),
            value: snapshot.data == SearchFeedbackConsent.granted,
            onChanged: (enabled) =>
                enabled ? consentStore.grant() : consentStore.revoke(),
          ),
        ),
        if (blockStatus != null)
          ValueListenableBuilder<SearchFeedbackNetworkBlock?>(
            valueListenable: blockStatus,
            builder: (context, block, _) => block == null
                ? const SizedBox.shrink()
                : Padding(
                    key: const ValueKey('search-feedback-network-block'),
                    padding: const EdgeInsets.only(
                      right: 16,
                      left: 16,
                      bottom: 16,
                    ),
                    child: Text(
                      context.settingsText(
                        'השליחה לשרת חסומה כעת ברשת שלך (ייתכן שעל ידי סינון). הנתונים נשמרים במחשב ויישלחו כשהגישה תיפתח.',
                      ),
                      style: kSettingsSubtitleStyle,
                    ),
                  ),
          ),
      ],
    );
  }
}
