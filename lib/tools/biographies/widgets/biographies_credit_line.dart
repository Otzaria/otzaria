import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
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
        confirmText: 'סגור',
        customContent: _CreditsContent(bundle: bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkColor = cs.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD,
          vertical: AppTokens.spaceSM,
        ),
        child: SizedBox(
          width: double.infinity,
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
        ),
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
    final textStyle = TextStyle(
      fontSize: AppTokens.fontMD,
      color: cs.onSurface,
    );
    final linkStyle = textStyle.copyWith(
      color: cs.primary,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
    );
    final version = [
      if (bundle.built != null) 'עודכן: ${bundle.built}',
      if (bundle.release != null) 'גרסה ${bundle.release}',
    ].join(', ');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${BiographiesBundle.fullCredit}. הערכים נכתבו מחדש בתמצית '
              'על פי המקורות הבאים, בתנאי הרישיונות שלהם:',
              style: textStyle,
            ),
            for (final credit in bundle.credits.values)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceSM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        credit.name,
                        ?credit.author,
                        ?credit.publisher,
                      ].join(', '),
                      style: textStyle.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (credit.attribution != null)
                      Text(credit.attribution!, style: textStyle),
                    if (credit.license != null)
                      credit.licenseUrl == null
                          ? Text(credit.license!, style: textStyle)
                          : InkWell(
                              onTap: () => launchUrl(
                                Uri.parse(credit.licenseUrl!),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: Text(
                                credit.license!,
                                style: linkStyle,
                                textDirection: TextDirection.ltr,
                              ),
                            ),
                  ],
                ),
              ),
            if (version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceSM),
                child: Text(
                  version,
                  style: textStyle.copyWith(
                    fontSize: AppTokens.fontSM,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
