import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// Structured author details within the book dialog. The full biography,
/// including its source material, belongs in the biographies tool.
class BookAuthorBiographies extends StatelessWidget {
  const BookAuthorBiographies({
    super.key,
    required this.biographies,
    required this.openBiography,
  });

  final List<Biography> biographies;
  final ValueChanged<String> openBiography;

  @override
  Widget build(BuildContext context) {
    return DetailsCard(
      title: 'על המחבר',
      icon: OtzariaIcons.person_24_regular,
      children: [
        for (final bio in biographies)
          ExpansionTile(
            key: ValueKey(bio.id),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsetsDirectional.only(
              bottom: AppTokens.spaceSM,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(bio.fullName),
            subtitle: _years(bio),
            children: [
              if (bio.knownAs.isNotEmpty)
                DetailsInfoSection(
                  title: 'כינויים',
                  value: bio.knownAs.join(', '),
                  block: true,
                ),
              if (bio.eraLabel case final String era)
                DetailsInfoSection(title: 'תקופה', value: era),
              if (bio.region.isNotEmpty)
                DetailsInfoSection(title: 'אזור', value: bio.region.join(', ')),
              if (bio.works.isNotEmpty)
                DetailsInfoSection(
                  title: 'מחיבוריו',
                  value: bio.works.take(3).map((work) => work.title).join(', '),
                  block: true,
                ),
              ActionButton.ghost(
                text: 'לביוגרפיה המלאה',
                onPressed: () => openBiography(bio.id),
              ),
            ],
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
          child: DetailsText(BiographiesBundle.authorCredit),
        ),
      ],
    );
  }

  Widget? _years(Biography bio) {
    final born = bio.born?.hebrew;
    final died = bio.died?.hebrew;
    return switch ((born, died)) {
      (final String start, final String end) => Text('$start – $end'),
      (final String start, null) => Text('נולד: $start'),
      (null, final String end) => Text('נפטר: $end'),
      (null, null) => null,
    };
  }
}
