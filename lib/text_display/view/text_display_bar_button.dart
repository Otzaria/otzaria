import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
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
    'תצוגת הטקסט: ניקוד, טעמים, פיסוק, ציוני מפרשים ושמות הקודש';

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
  final ValueChanged<TextDisplayProfile> onChanged;
  final bool includeTeamimSelector;

  const TextDisplaySection({
    required this.title,
    required this.profile,
    required this.onChanged,
    this.includeTeamimSelector = true,
  });
}

/// תוכן הפאנל: כותרת, מקטע לכל יעד, ושורת הסבר עם איפוס אופציונלי.
class TextDisplayPopupPanel extends StatefulWidget {
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

  static const double width = 300;

  /// הנוסח שהמשתמש בחר לשם הוי"ה — מחריץ השורש של ההגדרות הכלליות.
  /// בלי הגדרות זמינות — יקוק (ברירת המחדל של התוכנה).
  static HolyNameDisplay _preferredHolyName(BuildContext context) {
    try {
      return context
          .read<SettingsBloc>()
          .state
          .textDisplayPolicy
          .resolve(TextDisplaySlot.root)
          .holyName;
    } catch (_) {
      return HolyNameDisplay.kufKuf;
    }
  }

  @override
  State<TextDisplayPopupPanel> createState() => _TextDisplayPopupPanelState();
}

class _TextDisplayPopupPanelState extends State<TextDisplayPopupPanel> {
  /// מקטעים שנפתחו. המקטע הראשון (גוף הטקסט) תמיד פתוח; השאר מקופלים.
  final Set<int> _expanded = {};

  /// הפוקוס נלקח במפורש אחרי הפתיחה — אחרת Esc מגיע לספר שמתחת.
  final FocusNode _focusNode = FocusNode(debugLabel: 'text-display-panel');

  @override
  void initState() {
    super.initState();
    // מטפל גלובלי: Esc סוגר את החלונית גם אם הפוקוס לא הגיע אליה.
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    // רק כשהחלונית היא ה-route העליון (לא כשנפתח מעליה משהו אחר).
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    Navigator.of(context).maybePop();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _focusNode.dispose();
    super.dispose();
  }

  List<TextDisplaySection> get sections => widget.sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferredHolyName = TextDisplayPopupPanel._preferredHolyName(
      context,
    );
    final shared = sections.length > 1;
    // Esc סוגר את החלונית (הפוקוס עובר אליה כשהיא נפתחת).
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _buildPanel(context, theme, preferredHolyName, shared),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    ThemeData theme,
    HolyNameDisplay preferredHolyName,
    bool shared,
  ) {
    return SizedBox(
      width: TextDisplayPopupPanel.width,
      child: Padding(
        // הכותרת צמודה לקצה העליון, כמו בכל דיאלוג.
        padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              // מרווח נדיב סביב הכותרת — שלא ייראה עמוס.
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceSM,
                AppTokens.spaceSMD,
                AppTokens.spaceSM,
                AppTokens.spaceSMD,
              ),
              // הכותרת, ושם התצוגה (צורת הדף / תצוגה רגילה) בשורה מתחתיה.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'תצוגת הטקסט',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize:
                          (theme.textTheme.titleMedium?.fontSize ?? 16) + 2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.viewLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: AppTokens.spaceSM),
            // גוף הספר, ומיד אחריו "שמות הקודש" — מתג משותף לכל המקטעים.
            _SectionTitle(sections.first.title),
            const SizedBox(height: 4),
            ...TextDisplayProfileEditor.popupTiles(
              context,
              profile: sections.first.profile,
              onChanged: sections.first.onChanged,
              includeTeamimSelector: sections.first.includeTeamimSelector,
              preferredHolyName: preferredHolyName,
              includeHolyNames: !shared,
            ),
            if (shared)
              TextDisplayProfileEditor.holyNamesTile(
                context,
                subtitle: context.settingsText('בגוף הספר ובמפרשים'),
                shown: sections.every(
                  (s) => TextDisplayProfileEditor.holyNamesShown(s.profile),
                ),
                onShown: (show) {
                  for (final s in sections) {
                    s.onChanged(
                      TextDisplayProfileEditor.withHolyNames(
                        s.profile,
                        show: show,
                        preferred: preferredHolyName,
                      ),
                    );
                  }
                },
              ),
            // שאר המקטעים (מפרשים) — בתחתית, מקופלים, נפתחים בלחיצה.
            for (final (i, section) in sections.indexed.skip(1)) ...[
              // רווח מהשורה שמעל לפני המפרשים.
              const SizedBox(height: 8),
              const Divider(height: 1),
              _CollapsibleSectionTitle(
                section.title,
                expanded: _expanded.contains(i),
                onTap: () => setState(() {
                  if (!_expanded.remove(i)) _expanded.add(i);
                }),
              ),
              if (_expanded.contains(i))
                ...TextDisplayProfileEditor.popupTiles(
                  context,
                  profile: section.profile,
                  onChanged: section.onChanged,
                  includeTeamimSelector: section.includeTeamimSelector,
                  preferredHolyName: preferredHolyName,
                  includeHolyNames: false,
                ),
              if (_expanded.contains(i))
                const SizedBox(height: AppTokens.spaceSM),
            ],
            const Divider(height: 1),
            // שורת ההסבר בסגנון מערכת העיצוב: אייקון מידע, טקסט, ואיפוס עם אייקון.
            // ריפוד שווה מעל ומתחת, וכל הפריטים ממורכזים לאותו קו אמצע.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceSM,
                vertical: AppTokens.spaceXS,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.info_24_regular,
                    size: AppTokens.iconSM,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: Text(
                      widget.footer,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (widget.onReset != null)
                    ActionButton.ghost(
                      icon: FluentIcons.arrow_reset_24_regular,
                      text: 'איפוס',
                      onPressed: widget.onReset,
                    ),
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
      AppTokens.spaceSM,
      AppTokens.spaceXS,
      AppTokens.spaceSM,
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

/// כותרת מקטע מקופל: לחיצה פותחת וסוגרת, עם חץ.
class _CollapsibleSectionTitle extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onTap;
  const _CollapsibleSectionTitle(
    this.text, {
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metrics =
        Theme.of(context).extension<AppMenuMetrics>() ??
        AppMenuMetrics.create(compactMenus: false);
    // נראה כמו פריט תפריט עם תת-תפריט: שורה מלאה, אייקון, טקסט וחץ.
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceSM),
      child: Material(
        // הצבע הראשי של התוכנה (חום בערכת ברירת המחדל).
        color: expanded ? cs.primaryContainer : Colors.transparent,
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: metrics.itemHeight,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppTokens.spaceSM,
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.book_open_24_regular,
                    size: metrics.iconSize,
                    color: expanded ? cs.onPrimaryContainer : cs.primary,
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: metrics.fontSize,
                        fontWeight: FontWeight.w600,
                        color: expanded ? cs.onPrimaryContainer : cs.primary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppMotion.duration(context, AppTokens.animFast),
                    child: Icon(
                      FluentIcons.chevron_down_16_regular,
                      size: AppTokens.iconSM,
                      color: expanded ? cs.onPrimaryContainer : cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
