import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/layout/tool_result_card_shell.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class BiographyCard extends StatefulWidget {
  final Biography biography;

  /// Whether a related person's [RelatedPerson.ref] has an entry to open.
  final bool Function(String id) canOpen;

  /// Opens the entry with this id.
  final ValueChanged<String>? onOpen;

  final bool initiallyExpanded;

  const BiographyCard({
    super.key,
    required this.biography,
    this.canOpen = _never,
    this.onOpen,
    this.initiallyExpanded = false,
  });

  static bool _never(String id) => false;

  @override
  State<BiographyCard> createState() => _BiographyCardState();
}

class _BiographyCardState extends State<BiographyCard> {
  /// Summary lines shown before expanding.
  static const int _collapsedLines = 3;

  static const EdgeInsets _padding = EdgeInsets.all(AppTokens.spaceMD);

  /// Width of the label column of the expanded details.
  static const double _labelWidth = 112;

  late bool _expanded = widget.initiallyExpanded;

  Biography get _bio => widget.biography;

  String? get _metaLine {
    final parts = <String>[
      [?_bio.eraLabel, ?_bio.generation].join(', '),
      if (_bio.born != null) 'נולד: ${_bio.born!.display}',
      if (_bio.died != null) 'נפטר: ${_bio.died!.display}',
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join('  •  ');
  }

  String? get _knownAsLine =>
      _bio.knownAs.isEmpty ? null : 'נודע גם: ${_bio.knownAs.join(' · ')}';

  /// Labeled detail rows shown when expanded, in the order of the viewer.
  List<(String, String, IconData)> get _detailRows => [
    if (_bio.region.isNotEmpty)
      ('מקומות', _bio.region.join(', '), FluentIcons.globe_24_regular),
    if (_bio.buried != null)
      ('מקום מנוחתו', _bio.buried!, FluentIcons.location_24_regular),
    if (_bio.mentionedIn != null)
      ('מוזכר ב', _bio.mentionedIn!, OtzariaIcons.book_link_24_regular),
    if (_bio.roles.isNotEmpty)
      ('תפקידים', _bio.roles.join(' · '), FluentIcons.briefcase_24_regular),
  ];

  bool get _hasDetails =>
      _detailRows.isNotEmpty ||
      _bio.teachers.isNotEmpty ||
      _bio.students.isNotEmpty ||
      _bio.family.isNotEmpty ||
      _bio.works.isNotEmpty ||
      _bio.remember != null ||
      _bio.sources.isNotEmpty;

  void _copy() {
    String people(List<RelatedPerson> list) =>
        list.map((p) => p.display).join(' · ');
    final text = [
      _bio.fullName,
      _knownAsLine,
      _metaLine,
      _bio.summary,
      if (_expanded) ...[
        for (final (label, value, _) in _detailRows) '$label: $value',
        if (_bio.teachers.isNotEmpty) 'רבותיו: ${people(_bio.teachers)}',
        if (_bio.students.isNotEmpty) 'תלמידיו: ${people(_bio.students)}',
        if (_bio.family.isNotEmpty) 'משפחה: ${people(_bio.family)}',
        if (_bio.works.isNotEmpty)
          'חיבוריו: ${_bio.works.map((w) => w.display).join(' · ')}',
        _bio.remember,
      ],
      BiographiesBundle.authorCredit,
    ].whereType<String>().join('\n');
    Clipboard.setData(ClipboardData(text: text));
    UiSnack.show(UiSnack.textCopied);
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  /// Whether [text] needs more than [maxLines] at [width].
  bool _overflows(String text, TextStyle style, double width, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bodyStyle = TextStyle(
      fontSize: AppTokens.fontMD,
      height: 1.5,
      color: cs.onSurface,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = constraints.maxWidth - _padding.horizontal;
        final summary = _bio.summary;
        final clamped =
            summary != null &&
            _overflows(summary, bodyStyle, textWidth, _collapsedLines);
        return _buildCard(cs, bodyStyle, _hasDetails || clamped);
      },
    );
  }

  Widget _buildCard(ColorScheme cs, TextStyle bodyStyle, bool hasBody) {
    final mutedStyle = TextStyle(
      fontSize: AppTokens.fontMD,
      color: cs.onSurfaceVariant,
    );
    return ToolResultCardShell(
      onTap: hasBody ? _toggle : null,
      outlined: true,
      padding: _padding,
      bottomGap: AppTokens.spaceSM + AppTokens.spaceXS,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: _bio.name,
                    children: [
                      if (_bio.honorific != null)
                        TextSpan(
                          text: ' ${_bio.honorific}',
                          style: TextStyle(
                            fontSize: AppTokens.fontMD,
                            fontWeight: FontWeight.normal,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: AppTokens.fontXL,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSM),
              SecondaryIconButton(
                icon: FluentIcons.copy_24_regular,
                tooltip: 'העתק',
                onPressed: _copy,
              ),
            ],
          ),
          if (_knownAsLine != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceXS),
              child: Text(_knownAsLine!, style: mutedStyle),
            ),
          if (_bio.eraLabel != null || _bio.generation != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSM),
              child: Wrap(
                spacing: AppTokens.spaceSM,
                runSpacing: AppTokens.spaceXS,
                children: [
                  if (_bio.eraLabel != null)
                    MetaChip(
                      label: _bio.eraLabel!,
                      icon: FluentIcons.history_24_regular,
                    ),
                  if (_bio.generation != null)
                    MetaChip(
                      label: _bio.generation!,
                      icon: FluentIcons.people_24_regular,
                      outlined: true,
                    ),
                ],
              ),
            ),
          if (_bio.born != null || _bio.died != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSM),
              child: Wrap(
                spacing: AppTokens.spaceMD,
                runSpacing: AppTokens.spaceXS,
                children: [
                  if (_bio.born != null)
                    _lifeEvent(
                      'נולד',
                      _bio.born!,
                      cs,
                      bodyStyle,
                    ),
                  if (_bio.died != null)
                    _lifeEvent(
                      'נפטר',
                      _bio.died!,
                      cs,
                      bodyStyle,
                    ),
                ],
              ),
            ),
          if (_bio.summary != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSM),
              child: Text(
                _bio.summary!,
                style: bodyStyle,
                maxLines: _expanded ? null : _collapsedLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ),
          if (_expanded) ..._buildDetails(cs, bodyStyle),
          if (hasBody)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _toggle,
                icon: Icon(
                  _expanded
                      ? FluentIcons.chevron_up_24_regular
                      : FluentIcons.chevron_down_24_regular,
                  size: 18,
                ),
                iconAlignment: IconAlignment.end,
                label: Text(_expanded ? 'הצג פחות' : 'הצג עוד'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSM,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lifeEvent(
    String label,
    LifeEvent event,
    ColorScheme cs,
    TextStyle bodyStyle,
  ) {
    return Text.rich(
      TextSpan(
        text: '$label  ',
        style: bodyStyle.copyWith(
          fontSize: AppTokens.fontSM,
          color: cs.onSurfaceVariant,
        ),
        children: [TextSpan(text: event.display, style: bodyStyle)],
      ),
    );
  }

  List<Widget> _buildDetails(ColorScheme cs, TextStyle bodyStyle) {
    final labelStyle = bodyStyle.copyWith(
      fontSize: AppTokens.fontSM,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
    );
    final linkStyle = bodyStyle.copyWith(
      color: cs.primary,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary,
    );

    Widget row(String label, IconData icon, Widget value) => Padding(
      padding: const EdgeInsets.only(top: AppTokens.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppTokens.spaceXS),
                  Expanded(child: Text(label, style: labelStyle)),
                ],
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );

    Widget values(List<Widget> items) => Wrap(
      spacing: AppTokens.spaceMD,
      runSpacing: AppTokens.spaceXS,
      children: items,
    );

    Widget person(RelatedPerson p) {
      final ref = p.ref;
      if (ref == null || widget.onOpen == null || !widget.canOpen(ref)) {
        return Text(p.display, style: bodyStyle);
      }
      final prefix = p.relation == null ? '' : '${p.relation}: ';
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (prefix.isNotEmpty) Text(prefix, style: bodyStyle),
          InkWell(
            onTap: () => widget.onOpen!(ref),
            child: Text(p.name, style: linkStyle),
          ),
        ],
      );
    }

    return [
      const SizedBox(height: AppTokens.spaceSM),
      Divider(height: 1, color: cs.outlineVariant),
      for (final (label, value, icon) in _detailRows)
        row(label, icon, Text(value, style: bodyStyle)),
      if (_bio.teachers.isNotEmpty)
        row(
          'רבותיו',
          OtzariaIcons.lectern_24_regular,
          values(_bio.teachers.map(person).toList()),
        ),
      if (_bio.students.isNotEmpty)
        row(
          'תלמידיו',
          OtzariaIcons.person_portrait_24_regular,
          values(_bio.students.map(person).toList()),
        ),
      if (_bio.family.isNotEmpty)
        row(
          'משפחה',
          FluentIcons.people_community_24_regular,
          values(_bio.family.map(person).toList()),
        ),
      if (_bio.works.isNotEmpty)
        row(
          'חיבוריו',
          OtzariaIcons.book_person_24_regular,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final work in _bio.works)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
                  child: Text.rich(
                    TextSpan(
                      text: work.title,
                      style: bodyStyle.copyWith(fontWeight: FontWeight.w600),
                      children: [
                        if (work.description != null)
                          TextSpan(
                            text: ' - ${work.description}',
                            style: bodyStyle.copyWith(
                              fontWeight: FontWeight.normal,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (_bio.sources.isNotEmpty)
        row(
          'מקורות',
          OtzariaIcons.link_24_regular,
          values([
            for (final source in _bio.sources)
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse(source.url),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  source.title ?? source.url,
                  style: linkStyle,
                  textDirection: source.title == null
                      ? TextDirection.ltr
                      : null,
                ),
              ),
          ]),
        ),
      if (_bio.remember != null)
        Container(
          margin: const EdgeInsets.only(top: AppTokens.spaceMD),
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                OtzariaIcons.text_citation_24_regular,
                size: 20,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Text(
                  _bio.remember!,
                  style: bodyStyle.copyWith(color: cs.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
