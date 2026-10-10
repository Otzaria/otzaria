import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_profile_editor.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// אייקון הניקוד של הכפתור לפי המצב הנוכחי.
IconData textDisplayBarIcon(bool removeNikud) => removeNikud
    ? OtzariaIcons.alef_niqqud_24_filled
    : OtzariaIcons.alef_delete_24_filled;

String textDisplayBarTooltip(bool removeNikud) =>
    removeNikud ? 'הצג ניקוד' : 'הסתר ניקוד';

const String textDisplayMenuTooltip =
    'תצוגת הטקסט: ניקוד, טעמים, פיסוק, שם הוי"ה וציונים';

/// כפתור "תצוגת הטקסט" בסרגל: לחיצה ראשית מחליפה ניקוד, והחץ פותח פאנל
/// שמספק [panelBuilder]. אינו תלוי ב-BLoC — ראה [TextBookDisplayBarButton].
class TextDisplayBarButton extends StatelessWidget {
  final bool removeNikud;
  final bool compact;
  final VoidCallback onToggleNikud;
  final WidgetBuilder panelBuilder;

  const TextDisplayBarButton({
    super.key,
    required this.removeNikud,
    required this.onToggleNikud,
    required this.panelBuilder,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return BarSplitButton<void>(
      icon: textDisplayBarIcon(removeNikud),
      tooltip: textDisplayBarTooltip(removeNikud),
      menuTooltip: textDisplayMenuTooltip,
      compact: compact,
      onPressed: onToggleNikud,
      entries: const [],
      onSelected: null,
      onArrowPressed: (anchorContext) => showTextDisplayPopup(
        context,
        anchorContext: anchorContext,
        panelBuilder: panelBuilder,
      ),
    );
  }
}

/// פותח את פאנל תצוגת הטקסט מעל [anchorContext].
Future<void> showTextDisplayPopup(
  BuildContext context, {
  required BuildContext anchorContext,
  required WidgetBuilder panelBuilder,
}) {
  return showAnchoredAppMenu<void>(
    context: context,
    anchorContext: anchorContext,
    offset: const Offset(0, 8),
    itemsBuilder: (_) => [
      _PanelMenuEntry(child: Builder(builder: panelBuilder)),
    ],
  );
}

/// מקטע אחד בפאנל — פרופיל של יעד אחד והפעולה שמחילה שינוי בו.
class TextDisplaySection {
  final String title;
  final TextDisplayProfile profile;
  final bool showAnchorMarkers;
  final ValueChanged<TextDisplayProfile> onChanged;

  const TextDisplaySection({
    required this.title,
    required this.profile,
    required this.onChanged,
    this.showAnchorMarkers = true,
  });
}

/// תוכן הפאנל: כותרת, מקטע לכל יעד, ושורת הסבר עם איפוס אופציונלי.
class TextDisplayPopupPanel extends StatelessWidget {
  final String viewLabel;
  final List<TextDisplaySection> sections;
  final String footer;
  final VoidCallback? onReset;

  const TextDisplayPopupPanel({
    super.key,
    required this.viewLabel,
    required this.sections,
    required this.footer,
    this.onReset,
  });

  static const double width = 640;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD,
              ),
              child: Row(
                children: [
                  Text(
                    'תצוגת הטקסט',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(viewLabel, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            for (final (i, section) in sections.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _SectionTitle(section.title),
              ...TextDisplayProfileEditor.tiles(
                context,
                profile: section.profile,
                showAnchorMarkers: section.showAnchorMarkers,
                onChanged: section.onChanged,
              ),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMD,
                AppTokens.spaceSM,
                AppTokens.spaceMD,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(footer, style: theme.textTheme.bodySmall),
                  ),
                  if (onReset != null)
                    ActionButton.ghost(text: 'איפוס', onPressed: onReset),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// מחליף את ניקוד [target] בכרטיסייה (הפעולה הראשית של הכפתור).
void toggleTextBookNikud(
  BuildContext context,
  TextBookLoaded state,
  TextTarget target,
) {
  final removeNikud = state.displayProfile(target: target).removeNikud;
  context.read<TextBookBloc>().add(
    ApplyDisplayPatch(
      target: target,
      patch: TextDisplayPatch(
        nikud: removeNikud ? MarkVisibility.show : MarkVisibility.hide,
      ),
      persistToBook: context.read<SettingsBloc>().state.enablePerBookSettings,
    ),
  );
}

/// [TextDisplayBarButton] מעל [TextBookBloc]: הפאנל מציג מקטע לכל יעד
/// ב-[targets], והלחיצה הראשית מחליפה את ניקוד היעד הראשון.
class TextBookDisplayBarButton extends StatelessWidget {
  final TextBookLoaded state;
  final bool compact;
  final List<TextTarget> targets;

  const TextBookDisplayBarButton({
    super.key,
    required this.state,
    this.compact = false,
    this.targets = const [TextTarget.body, TextTarget.commentary],
  });

  @override
  Widget build(BuildContext context) {
    final textBookBloc = context.read<TextBookBloc>();
    final settingsBloc = context.read<SettingsBloc>();
    return TextDisplayBarButton(
      removeNikud: state.displayProfile(target: targets.first).removeNikud,
      compact: compact,
      onToggleNikud: () => toggleTextBookNikud(context, state, targets.first),
      panelBuilder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: textBookBloc),
          BlocProvider.value(value: settingsBloc),
        ],
        child: TextBookDisplayPanel(targets: targets),
      ),
    );
  }
}

/// פאנל תצוגת הטקסט של כרטיסיית ספר — נבנה מעל BlocBuilder כדי שהמתגים
/// ישקפו את המצב מיד.
class TextBookDisplayPanel extends StatelessWidget {
  final List<TextTarget> targets;

  const TextBookDisplayPanel({super.key, required this.targets});

  static String _titleOf(TextTarget target) => switch (target) {
    TextTarget.body => 'גוף הספר',
    TextTarget.commentary => 'מפרשים',
  };

  void _apply(
    BuildContext context,
    TextTarget target,
    TextDisplayProfile current,
    TextDisplayProfile next,
  ) {
    // רק השדה שהשתנה נכתב כעקיפה — שאר השדות ממשיכים לרשת.
    final patch = next.toPatch().pruneAgainst(current);
    if (patch.isEmpty) return;
    context.read<TextBookBloc>().add(
      ApplyDisplayPatch(
        target: target,
        patch: patch,
        persistToBook: context.read<SettingsBloc>().state.enablePerBookSettings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(
      builder: (context, state) {
        if (state is! TextBookLoaded) return const SizedBox.shrink();
        final settings = context.watch<SettingsBloc>().state;
        return TextDisplayPopupPanel(
          viewLabel: state.showPageShapeView ? 'צורת הדף' : 'תצוגה רגילה',
          sections: [
            for (final target in targets)
              TextDisplaySection(
                title: _titleOf(target),
                profile: state.displayProfile(target: target),
                showAnchorMarkers: target == TextTarget.body,
                onChanged: (next) => _apply(
                  context,
                  target,
                  state.displayProfile(target: target),
                  next,
                ),
              ),
          ],
          footer: settings.enablePerBookSettings
              ? 'השינויים נשמרים לספר זה'
              : 'השינויים חלים על כרטיסייה זו בלבד',
          onReset: state.displayOverrides.isNotEmpty
              ? () => context.read<TextBookBloc>().add(
                  const ClearDisplayOverrides(),
                )
              : null,
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppTokens.spaceMD,
      AppTokens.spaceSM,
      AppTokens.spaceMD,
      0,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// פריט תפריט שמארח ווידג'ט חופשי (הפאנל) בתוך תפריט מוצמד.
class _PanelMenuEntry extends PopupMenuEntry<void> {
  final Widget child;
  const _PanelMenuEntry({required this.child});

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(void value) => false;

  @override
  State<_PanelMenuEntry> createState() => _PanelMenuEntryState();
}

class _PanelMenuEntryState extends State<_PanelMenuEntry> {
  @override
  Widget build(BuildContext context) => widget.child;
}
