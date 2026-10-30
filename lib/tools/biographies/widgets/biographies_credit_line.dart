import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/details_info_section.dart';
import 'package:url_launcher/url_launcher.dart';

/// The author credit the license of the biographies requires, always visible
/// under the list, with a link to the sources and their licenses.
class BiographiesCreditLine extends StatelessWidget {
  final BiographiesBundle bundle;

  const BiographiesCreditLine({super.key, required this.bundle});

  void _showCredits(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AppDialog.singleAction(
        title: 'מקורות וזכויות',
        icon: FluentIcons.certificate_24_regular,
        headerBand: true,
        confirmText: 'סגור',
        customContent: _CreditsContent(bundle: bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkColor = cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceXS,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppTokens.spaceSM,
        children: [
          Text(
            BiographiesBundle.fullCredit,
            style: TextStyle(
              fontSize: AppTokens.fontSM,
              color: cs.onSurfaceVariant,
            ),
          ),
          Tooltip(
            message: 'הצגת המקורות והרישיונות',
            child: InkWell(
              onTap: () => _showCredits(context),
              borderRadius: AppTokens.borderRadiusAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceXS,
                  vertical: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.info_16_regular,
                      size: 14,
                      color: linkColor,
                    ),
                    const SizedBox(width: AppTokens.spaceXS),
                    Text(
                      'מקורות וזכויות',
                      style: TextStyle(
                        fontSize: AppTokens.fontSM,
                        color: linkColor,
                        decoration: TextDecoration.underline,
                        decorationColor: linkColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditsContent extends StatelessWidget {
  final BiographiesBundle bundle;

  const _CreditsContent({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final version = [
      if (bundle.built != null) 'עודכן: ${bundle.built}',
      if (bundle.release != null) 'גרסה ${bundle.release}',
    ];

    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DetailsHeading(
              title: BiographiesBundle.projectName,
              subtitle: BiographiesBundle.fullCredit,
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              'הערכים נכתבו מחדש בתמצית על פי המקורות הבאים, בתנאי הרישיונות '
              'שלהם:',
              style: TextStyle(
                fontSize: AppTokens.fontMD,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.spaceMD),
            DetailsCard(
              title: 'מקורות',
              icon: FluentIcons.book_open_24_regular,
              children: [
                for (final credit in bundle.credits.values)
                  _CreditTile(credit: credit),
              ],
            ),
            if (version.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceMD),
              Wrap(
                spacing: AppTokens.spaceSM,
                runSpacing: AppTokens.spaceSM,
                children: [
                  for (final label in version)
                    MetaChip(
                      label: label,
                      icon: FluentIcons.arrow_sync_24_regular,
                      outlined: true,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A source: its name, who wrote and published it, the attribution it asks for
/// and its license, as a link when the license has a page.
class _CreditTile extends StatelessWidget {
  final BiographyCredit credit;

  const _CreditTile({required this.credit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byline = [?credit.author, ?credit.publisher].join(', ');
    final muted = TextStyle(
      fontSize: AppTokens.fontMD,
      height: 1.4,
      color: cs.onSurfaceVariant,
    );
    final licenseUrl = credit.licenseUrl;
    final license = credit.license;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM + 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            credit.name,
            style: TextStyle(
              fontSize: AppTokens.fontMD,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          if (byline.isNotEmpty) Text(byline, style: muted),
          if (credit.attribution != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceXS),
              child: Text(credit.attribution!, style: muted),
            ),
          if (license != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSM),
              child: licenseUrl == null
                  ? MetaChip(
                      label: license,
                      icon: FluentIcons.certificate_24_regular,
                    )
                  : InkWell(
                      onTap: () => launchUrl(
                        Uri.parse(licenseUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      borderRadius: AppTokens.borderRadiusAll,
                      child: MetaChip(
                        label: license,
                        icon: FluentIcons.open_24_regular,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
