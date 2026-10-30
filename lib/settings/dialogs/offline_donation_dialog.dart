import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/messages/messages_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:url_launcher/url_launcher.dart';

/// כתובת דף התרומה של אוצריא בנדרים+.
const String kNedarimDonationUrl = 'https://nedar.im/ezOd';

const String _fundName = 'קרן צרכי הרבים - קרנות';
const String _fundNumber = '7001976';
const String _fundCategory = 'אוצריא - מאגר תורני חינמי (146)';

/// בלי canLaunchUrl — באנדרואיד 11+ הוא מחזיר false ל-https ומשתיק את הפתיחה.
Future<void> _launchDonationPage() async {
  try {
    await launchUrl(
      Uri.parse(kNedarimDonationUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('Could not launch $kNedarimDonationUrl: $e');
  }
}

/// מציג את הוראות התרומה בנדרים+, לשימוש כשאין חיבור לאינטרנט ולא ניתן
/// לפתוח את דף התרומה.
///
/// [context] - ה-context שממנו נלקחות שפת ההגדרות וכיווניותה.
Future<void> showOfflineDonationDialog(BuildContext context) =>
    showSingleActionDialog(
      context: context,
      title: context.settingsText('תרומה בנדרים+'),
      icon: FluentIcons.heart_24_regular,
      headerBand: true,
      confirmText: context.settingsText('סגור'),
      customContent: wrapWithSettingsScope(
        context,
        const _DonationInstructions(),
      ),
    );

class _DonationInstructions extends StatelessWidget {
  const _DonationInstructions();

  Future<void> _copyDetails(BuildContext context) async {
    final details = [
      '${context.settingsText('שם הקופה:')} $_fundName',
      '${context.settingsText('מספר קופה:')} $_fundNumber',
      '${context.settingsText('קטגוריה:')} $_fundCategory',
      kNedarimDonationUrl,
    ].join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: details));
      UiSnack.show(CommonMessages.textCopied);
    } catch (e) {
      debugPrint('Could not copy donation details: $e');
      UiSnack.showError(CommonMessages.clipboardCopyError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 450,
      child: AppSelectionArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.settingsText('ניתן לתרום מכל מכשיר בנדרים+'),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: AppTokens.spaceMD),
              DetailsCard(
                title: context.settingsText('פרטי הקופה'),
                icon: FluentIcons.info_24_regular,
                children: [
                  DetailsInfoSection(
                    icon: FluentIcons.building_bank_24_regular,
                    title: context.settingsText('שם הקופה:'),
                    value: _fundName,
                  ),
                  DetailsInfoSection(
                    icon: FluentIcons.number_symbol_24_regular,
                    title: context.settingsText('מספר קופה:'),
                    value: _fundNumber,
                  ),
                  DetailsInfoSection(
                    icon: FluentIcons.folder_24_regular,
                    title: context.settingsText('קטגוריה:'),
                    value: _fundCategory,
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceMD),
              DetailsCard(
                title: context.settingsText('דף התרומה'),
                icon: FluentIcons.payment_24_regular,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.spaceSM + 1,
                    ),
                    child: InkWell(
                      onTap: _launchDonationPage,
                      child: Text(
                        kNedarimDonationUrl,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: AppTokens.fontMD,
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ActionButton.neutral(
                icon: FluentIcons.copy_24_regular,
                text: context.settingsText('העתק פרטים'),
                onPressed: () => _copyDetails(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
