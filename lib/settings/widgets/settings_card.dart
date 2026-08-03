import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

// ── SettingsCard ──────────────────────────────────────────────────────────────

/// כרטיס הגדרות מעוצב בסגנון Material 3 / Google Account.
///
/// [cardId] — כשנתון, הכרטיס משמש גם כאנכור חיפוש: נרשם ב-registry, נגלל
/// אליו ומבהב בעת ניווט מתוצאת חיפוש (ראה [SettingsAnchor]).
class SettingsCard extends StatelessWidget {
  final dynamic title; // String או Widget
  final String? subtitle;
  final List<Widget> children;
  final String? cardId;

  const SettingsCard({
    super.key,
    this.title,
    this.subtitle,
    required this.children,
    this.cardId,
  });

  // כשאין title (null או מחרוזת ריקה) הכותרת מוגדרת בתוך children — בלי כותרת חיצונית.
  bool get _hasTitle =>
      title != null && !(title is String && (title as String).isEmpty);

  /// סגנון כותרת הכרטיס — מקור אמת יחיד, גם לשורות שרוצות להיראות ככותרת.
  static TextStyle? titleStyleOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);
    if (cardId != null) return SettingsAnchor(cardId: cardId!, child: card);
    return card;
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);

    if (!_hasTitle) return AppCard.section(children: children);

    final titleStyle = titleStyleOf(context);

    final header = Container(
      width: double.infinity,
      padding: const EdgeInsets.only(right: 16, left: 16, top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title is String
              ? Text(title as String, style: titleStyle)
              : DefaultTextStyle(
                  style: titleStyle ?? const TextStyle(),
                  child: title as Widget,
                ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        AppCard.section(children: children),
      ],
    );
  }
}

// ── Helpers לטיפוגרפיה אחידה ──────────────────────────────────────────────────

Widget _settingTitle(String text) => Text(
  text,
  style: AppTextStyles.settingTitle,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
);

Widget _settingSubtitle(String text, {Color? color, bool ltr = false}) => Text(
  text,
  style: color != null
      ? AppTextStyles.settingSubtitle.copyWith(color: color)
      : AppTextStyles.settingSubtitle,
  textDirection: ltr ? TextDirection.ltr : null,
  textAlign: ltr ? TextAlign.end : null,
);

Widget? _buildSettingIcon(IconData? icon, IconData? rtlIcon, Color? iconColor) {
  if (rtlIcon != null) return RtlIcon(rtlIcon, color: iconColor);
  if (icon != null) return Icon(icon, color: iconColor);
  return null;
}

/// תת-כותרת האפשרות הנבחרת מתוך [options] — משמש ע"י dropdownTile/segmentedTile
/// כדי לא לחייב כל call site לבנות מיפוי value→subtitle בנפרד.
/// [explicitSubtitle], אם סופק, גובר על תת-הכותרת של האפשרות.
String? _selectedOptionSubtitle<TOption, TValue>({
  required String? explicitSubtitle,
  required TValue value,
  required List<TOption> options,
  required TValue Function(TOption option) valueOf,
  required String? Function(TOption option) subtitleOf,
}) {
  if (explicitSubtitle != null) return explicitSubtitle;
  for (final option in options) {
    if (valueOf(option) == value) return subtitleOf(option);
  }
  return null;
}

// ── Segmented width calculation ────────────────────────────────────────────────
// חישוב רוחב מדויק לפקד ה-Segmented לפי מספר האפשרויות ואורך הטקסט.
// מחושב בנפרד ולא בתוך הwidget כדי שאפשר לקרוא לו גם מ-build() ב-LayoutBuilder.

const _kSegBaseNoIcon = 60.0;
const _kSegBaseWithIcon = 80.0;
const _kSegCharWidth = 8.0;
const _kSegGroupPadding = 24.0;
const _kSegMinWidth = 180.0;
const _kSegMaxWidth = 400.0;

double _segGroupWidth(List<SegmentOption<dynamic>> options) {
  final hasIcons = options.any((o) => o.icon != null || o.rtlIcon != null);
  final maxLen = options
      .map((o) => o.label.length)
      .reduce((a, b) => a > b ? a : b);
  final btnW =
      (hasIcons ? _kSegBaseWithIcon : _kSegBaseNoIcon) +
      maxLen * _kSegCharWidth;
  return (btnW * options.length + _kSegGroupPadding).clamp(
    _kSegMinWidth,
    _kSegMaxWidth,
  );
}

// ── SettingsActionTile ────────────────────────────────────────────────────────

/// עיגול בחירה (radio) לא-אינטראקטיבי — הבחירה מתבצעת בהקשה על השורה כולה.
class _RadioIndicator extends StatelessWidget {
  final bool selected;

  const _RadioIndicator({required this.selected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    // תופס בדיוק את שטח אייקון רגיל (24) — כדי שהיישור והמרווח יהיו זהים
    // לשורות עם אייקון, בלי מרווח כפול.
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: selected
              ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// שורת הגדרה רספונסיבית — מקור האמת לפריסה, מרווחים וסגנון כל שורות ההגדרות.
///
/// ### בנאים בסיסיים
/// • `SettingsActionTile(title: widget, ...)` — title גולמי כ-Widget.
/// • `SettingsActionTile.text(title: 'כותרת', ...)` — title ו-subtitle כ-String.
/// • `SettingsActionTile.path(title: '...', path: '...', ...)` — path עם BiDi.
///
/// ### factory methods (נראים כבנאים ב-call site)
/// • `SettingsActionTile.switchTile(...)` — שורה עם [CustomSwitch], focus וניהול keyboard.
/// • `SettingsActionTile.dropdownTile(...)` — שורה עם [AppDropdownField].
/// • `SettingsActionTile.segmentedTile(...)` — שורה עם [AppSegmentedControl].
///
/// ### אייקונים
/// • [icon] — אייקון סטטי ([Icon]), לא מתהפך ב-RTL.
/// • [rtlIcon] — אייקון כיווני ([RtlIcon]), מתהפך ב-RTL.
/// • [iconColor] — צבע אופציונלי לאייקון (לאייקונים דינמיים כמו shield_lock).
///
/// ### פריסה
/// - מסך רחב (>=[LayoutBreakpoints.compact]): [ListTile] עם trailing.
/// - מסך צר: כותרת+תת-כותרת למעלה, actions למטה.
class SettingsActionTile extends StatelessWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final Color? iconColor;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;
  // ווידג'ט שנשאר צמוד לטקסט תמיד (לדוגמה: צ'בֺרן של ExpandableSection) —
  // בניגוד ל-actions, לא גולש מתחת לטקסט ב-layout האנכי.
  final Widget? pinnedTrailing;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool enabled;
  // כשהtitle גולש לשורה נוספת, actions יגלשו אוטומטית מתחת לטקסט ולא ידחסו אותו
  final bool responsiveActions;
  // ווידג'ט leading מותאם (למשל רדיו) שגובר על האייקון.
  final Widget? leading;
  // טקסט גולמי לבדיקת גלישה עם TextPainter — מאוכלס רק ב-.text() ו-.path()
  final String? _rawTitle;

  const SettingsActionTile({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.pinnedTrailing,
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.responsiveActions = true,
    this.leading,
  }) : _rawTitle = null,
       assert(
         icon == null || rtlIcon == null,
         'העבר icon או rtlIcon — לא שניהם יחד',
       );

  SettingsActionTile.text({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required String title,
    String? subtitle,
    bool subtitleLtr = false,
    Color? subtitleColor,
    this.actions = const [],
    this.pinnedTrailing,
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.responsiveActions = true,
    this.leading,
  }) : assert(
         icon == null || rtlIcon == null,
         'העבר icon או rtlIcon — לא שניהם יחד',
       ),
       _rawTitle = title,
       title = _settingTitle(title),
       subtitle = subtitle != null
           ? _settingSubtitle(subtitle, color: subtitleColor, ltr: subtitleLtr)
           : null;

  /// שורת בחירה (radio) — עיגול רדיו כ-leading במקום אייקון, כותרת/תת-כותרת,
  /// וכפתורי פעולה אופציונליים ב-[actions] שגולשים מתחת לטקסט במסך צר.
  /// הבחירה מתבצעת בהקשה על כל השורה ([onTap]).
  static Widget radioOption({
    Key? key,
    required String title,
    String? subtitle,
    required bool selected,
    VoidCallback? onTap,
    List<Widget> actions = const [],
  }) => SettingsActionTile.text(
    key: key,
    title: title,
    subtitle: subtitle,
    leading: _RadioIndicator(selected: selected),
    actions: actions,
    onTap: onTap,
  );

  /// קונסטרקטור ייעודי לנתיבי קבצים — מאכוף LTR ומוסיף סימני U+200E אחרי מפרידים.
  /// [responsiveActions] מופעל כברירת מחדל כדי שהכפתורים לא ידחסו את הנתיב.
  SettingsActionTile.path({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required String title,
    required String? path,
    required String placeholder,
    this.actions = const [],
    this.pinnedTrailing,
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.responsiveActions = true,
    this.leading,
  }) : assert(
         icon == null || rtlIcon == null,
         'העבר icon או rtlIcon — לא שניהם יחד',
       ),
       _rawTitle = title,
       title = _settingTitle(title),
       subtitle = _settingSubtitle(
         (path != null && path.isNotEmpty) ? _formatPath(path) : placeholder,
         ltr: path != null && path.isNotEmpty,
       );

  // ── Static factory methods ─────────────────────────────────────────────────
  // נראים כבנאים ב-call site (SettingsActionTile.switchTile(...)) אך מחזירים
  // widget פרטי עצמאי — מאפשר state management ללא שכפול בקוד קורא.

  /// שורת ניהול נתיב תיקייה — כפתור "אפשרויות מיקום" עם תפריט פעולות.
  /// [clearPathEnabled] — כשfalse, "הסרת מיקום שמור" מוצג בתפריט כפריט לא פעיל.
  /// [simpleButtonWhenEmpty] — כאשר true (ברירת מחדל) ואין נתיב, מוצג כפתור "הגדר מיקום".
  static Widget pathTile({
    Key? key,
    required IconData icon,
    required String title,
    required String currentPath,
    String placeholder = 'לא נבחר מיקום',
    required Future<void> Function(String newPath) onFolderChanged,
    required VoidCallback onOpenFolder,
    VoidCallback? onClearPath,
    Future<void> Function(BuildContext)? requestChangeLocation,
    bool simpleButtonWhenEmpty = true,
    bool clearPathEnabled = true,
    List<PathTarget>? pathTargets,
    void Function(String path)? onOpenPath,
    String changeLocationLabel = 'שינוי מיקום...',
  }) => _PathTile(
    key: key,
    icon: icon,
    title: title,
    currentPath: currentPath,
    placeholder: placeholder,
    onFolderChanged: onFolderChanged,
    onOpenFolder: onOpenFolder,
    onClearPath: onClearPath,
    requestChangeLocation: requestChangeLocation,
    simpleButtonWhenEmpty: simpleButtonWhenEmpty,
    clearPathEnabled: clearPathEnabled,
    pathTargets: pathTargets,
    onOpenPath: onOpenPath,
    changeLocationLabel: changeLocationLabel,
  );

  /// שורת on/off עם [CustomSwitch].
  /// tap על כל השורה, Enter ו-Space מחליפים מצב.
  static Widget switchTile({
    Key? key,
    IconData? icon,
    IconData? rtlIcon,
    Color? iconColor,
    required String title,
    String? subtitle,
    bool subtitleLtr = false,
    Color? subtitleColor,
    required bool value,
    ValueChanged<bool>? onChanged,
    bool enabled = true,
  }) => _SwitchTile(
    key: key,
    icon: icon,
    rtlIcon: rtlIcon,
    iconColor: iconColor,
    title: title,
    subtitle: subtitle,
    subtitleLtr: subtitleLtr,
    subtitleColor: subtitleColor,
    value: value,
    onChanged: onChanged,
    enabled: enabled,
  );

  /// שורה עם [AppDropdownField].
  /// [subtitle] — כשלא סופק, נלקח אוטומטית מ-[AppMenuEntry.subtitle] של האפשרות הנבחרת.
  static Widget dropdownTile<T>({
    Key? key,
    IconData? icon,
    IconData? rtlIcon,
    required String title,
    String? subtitle,
    required T? value,
    required List<AppMenuEntry<T>> entries,
    required ValueChanged<T?> onSelected,
    bool enableSearch = false,
  }) => _DropdownTile<T>(
    key: key,
    icon: icon,
    rtlIcon: rtlIcon,
    title: title,
    subtitle: subtitle,
    value: value,
    entries: entries,
    onSelected: onSelected,
    enableSearch: enableSearch,
  );

  /// שורה עם [AppSegmentedControl].
  /// במסך רחב: מוגבל ל-400px. במסך צר: מתרחב לכל הרוחב.
  /// כשלאפשרויות ([SegmentOption.icon]) יש אייקונים, אייקון השורה עוקב
  /// אוטומטית אחרי הבחירה הנוכחית ([icon] משמש רק כברירת מחדל).
  static Widget segmentedTile<T>({
    Key? key,
    IconData? icon,
    IconData? rtlIcon,
    Color? iconColor,
    required String title,
    String? subtitle,
    required List<SegmentOption<T>> options,
    required T currentValue,
    required ValueChanged<T> onChanged,
  }) => _SegmentedTile<T>(
    key: key,
    icon: icon,
    rtlIcon: rtlIcon,
    iconColor: iconColor,
    title: title,
    subtitle: subtitle,
    options: options,
    currentValue: currentValue,
    onChanged: onChanged,
  );

  // ── Internals ──────────────────────────────────────────────────────────────

  static final RegExp _pathSeparatorRegExp = RegExp(r'[/\\]');

  static String _formatPath(String path) =>
      path.replaceAllMapped(_pathSeparatorRegExp, (m) => '${m[0]!}‎');

  Widget? _buildIcon() =>
      leading ?? _buildSettingIcon(icon, rtlIcon, iconColor);

  Widget? _buildTrailing() {
    if (actions.isEmpty) return pinnedTrailing;
    final actionsWrap = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    if (pinnedTrailing == null) return actionsWrap;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [actionsWrap, const SizedBox(width: 8), pinnedTrailing!],
    );
  }

  Widget _buildListTile() => ListTile(
    focusNode: focusNode,
    enabled: enabled,
    onTap: onTap,
    leading: _buildIcon(),
    title: title,
    subtitle: subtitle,
    trailing: _buildTrailing(),
  );

  // בודק עם TextPainter אם הטקסט יגלוש כשה-actions יהיו ב-trailing.
  // אומדן שמרני לרוחב הactions כדי להטות לצד של Column (לא ידחוס את הטקסט).
  bool _wouldTextOverflow(double containerWidth, TextDirection textDirection) {
    if (_rawTitle == null) return false;
    const iconAreaWidth = 56.0;
    const hPadding = 32.0;
    final actionsEst = actions.length * 170.0;
    final pinnedEst = pinnedTrailing != null ? 48.0 : 0.0;
    final textWidth =
        containerWidth -
        iconAreaWidth -
        hPadding -
        actionsEst -
        pinnedEst -
        8.0;
    if (textWidth <= 80) return true;

    final titlePainter = TextPainter(
      text: TextSpan(text: _rawTitle, style: AppTextStyles.settingTitle),
      textDirection: textDirection,
      maxLines: 1,
    )..layout(maxWidth: textWidth);
    if (titlePainter.didExceedMaxLines) return true;

    return false;
  }

  Widget _buildColumnLayout() {
    final iconWidget = _buildIcon();
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (iconWidget != null) ...[
                iconWidget,
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              if (pinnedTrailing != null) ...[
                const SizedBox(width: 8),
                pinnedTrailing!,
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    // _buildListTile מעביר onTap ל-ListTile; ב-layout האנכי אין ListTile,
    // אז ה-InkWell הוא מה שמאפשר ללחוץ על השורה (למשל לפתוח ExpandableSection).
    return InkWell(
      onTap: enabled ? onTap : null,
      focusNode: focusNode,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!responsiveActions) return _buildListTile();
    return LayoutBuilder(
      builder: (context, constraints) =>
          _wouldTextOverflow(constraints.maxWidth, Directionality.of(context))
          ? _buildColumnLayout()
          : _buildListTile(),
    );
  }
}

// ── _SwitchTile ───────────────────────────────────────────────────────────────

class _SwitchTile extends StatefulWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool subtitleLtr;
  final Color? subtitleColor;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const _SwitchTile({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleLtr = false,
    this.subtitleColor,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<_SwitchTile> createState() => __SwitchTileState();
}

class __SwitchTileState extends State<_SwitchTile> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'switch_tile');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.enabled || widget.onChanged == null) return;
    widget.onChanged!(!widget.value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusNode.canRequestFocus) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          _toggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SettingsActionTile.text(
        icon: widget.icon,
        rtlIcon: widget.rtlIcon,
        iconColor: widget.iconColor,
        title: widget.title,
        subtitle: widget.subtitle,
        subtitleLtr: widget.subtitleLtr,
        subtitleColor: widget.subtitleColor,
        enabled: widget.enabled,
        focusNode: _focusNode,
        responsiveActions: false,
        onTap: widget.enabled && widget.onChanged != null
            ? () => _toggle()
            : null,
        actions: [
          ExcludeFocus(
            child: CustomSwitch(
              value: widget.value,
              onChanged: widget.enabled && widget.onChanged != null
                  ? (_) => _toggle()
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _DropdownTile ─────────────────────────────────────────────────────────────

class _DropdownTile<T> extends StatelessWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final String title;
  final String? subtitle;
  final T? value;
  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T?> onSelected;
  final bool enableSearch;

  const _DropdownTile({
    super.key,
    this.icon,
    this.rtlIcon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.enableSearch = false,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsActionTile.text(
      icon: icon,
      rtlIcon: rtlIcon,
      title: title,
      subtitle: _selectedOptionSubtitle<AppMenuEntry<T>, T?>(
        explicitSubtitle: subtitle,
        value: value,
        options: entries,
        valueOf: (e) => e.value,
        subtitleOf: (e) => e.subtitle,
      ),
      actions: [
        AppDropdownField<T>(
          value: value,
          entries: entries,
          onSelected: onSelected,
          enableSearch: enableSearch,
          isExpanded: false,
        ),
      ],
    );
  }
}

// ── _SegmentedTile ────────────────────────────────────────────────────────────

class _SegmentedTile<T> extends StatefulWidget {
  final IconData? icon;
  final IconData? rtlIcon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;

  const _SegmentedTile({
    super.key,
    this.icon,
    this.rtlIcon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  State<_SegmentedTile<T>> createState() => __SegmentedTileState<T>();
}

class __SegmentedTileState<T> extends State<_SegmentedTile<T>> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'segmented_tile');
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncFocusedIndex();
  }

  @override
  void didUpdateWidget(covariant _SegmentedTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentValue != widget.currentValue ||
        oldWidget.options != widget.options) {
      _syncFocusedIndex();
    }
  }

  void _syncFocusedIndex() {
    final idx = widget.options.indexWhere(
      (o) => o.value == widget.currentValue,
    );
    _focusedIndex = idx < 0 ? 0 : idx;
  }

  // כשלאפשרויות יש אייקונים משלהן, אייקון הכרטיס עוקב אחרי הבחירה הנוכחית
  // (כמו בהתראות לוח שנה) — במקום להישאר קבוע לפי [SettingsActionTile.icon]/[rtlIcon].
  bool get _iconTracksSelection =>
      widget.options.any((o) => o.icon != null || o.rtlIcon != null);

  ({IconData? icon, IconData? rtlIcon}) get _leadingIcons {
    if (!_iconTracksSelection) {
      return (icon: widget.icon, rtlIcon: widget.rtlIcon);
    }
    final selected = widget.options.firstWhere(
      (o) => o.value == widget.currentValue,
      orElse: () => widget.options.first,
    );
    if (selected.rtlIcon != null) {
      return (icon: null, rtlIcon: selected.rtlIcon);
    }
    if (selected.icon != null) return (icon: selected.icon, rtlIcon: null);
    return (icon: widget.icon, rtlIcon: widget.rtlIcon);
  }

  /// [widget.subtitle], אם סופק, גובר על תת-הכותרת של האפשרות הנבחרת.
  String? get _resolvedSubtitle => _selectedOptionSubtitle<SegmentOption<T>, T>(
    explicitSubtitle: widget.subtitle,
    value: widget.currentValue,
    options: widget.options,
    valueOf: (o) => o.value,
    subtitleOf: (o) => o.subtitle,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(
        () => _focusedIndex = (_focusedIndex + 1) % widget.options.length,
      );
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(
        () => _focusedIndex =
            (_focusedIndex - 1 + widget.options.length) % widget.options.length,
      );
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.enter ||
        ev.logicalKey == LogicalKeyboardKey.space) {
      widget.onChanged(widget.options[_focusedIndex].value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < LayoutBreakpoints.compact;

        final control = Focus(
          focusNode: _focusNode,
          child: AppSegmentedControl<T>(
            options: widget.options,
            currentValue: widget.currentValue,
            onChanged: widget.onChanged,
            expandToFillWidth: isNarrow,
            height: 40,
          ),
        );

        if (!isNarrow) {
          // מסך רחב: פקד ה-Segmented ב-trailing, ברוחב המחושב לפי תוכן
          return Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _handleKeyEvent,
            child: SettingsActionTile.text(
              icon: _leadingIcons.icon,
              rtlIcon: _leadingIcons.rtlIcon,
              title: widget.title,
              subtitle: _resolvedSubtitle,
              actions: [
                SizedBox(
                  width: _segGroupWidth(widget.options),
                  child: control,
                ),
              ],
            ),
          );
        }

        // מסך צר: כותרת + תת-כותרת ב-ListTile, פקד ה-Segmented מתחת (רוחב מלא)
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _handleKeyEvent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: _buildSettingIcon(
                  _leadingIcons.icon,
                  _leadingIcons.rtlIcon,
                  widget.iconColor,
                ),
                title: _settingTitle(widget.title),
                subtitle: _resolvedSubtitle != null
                    ? _settingSubtitle(_resolvedSubtitle!)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                child: control,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── PathTarget ───────────────────────────────────────────────────────────────

/// יעד נתיב בתפריט "אפשרויות מיקום" — תווית + נתיב (למשל שורש/ספרייה/אינדקס).
/// כשמסופקת רשימה כזו, "פתח תיקייה" ו"העתק נתיב" נפתחים כתת-תפריט של היעדים.
class PathTarget {
  final String label;
  final String path;
  const PathTarget({required this.label, required this.path});
}

// ── _PathTile ─────────────────────────────────────────────────────────────────

class _PathTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String currentPath;
  final String placeholder;
  final Future<void> Function(String newPath) onFolderChanged;
  final VoidCallback onOpenFolder;
  final VoidCallback? onClearPath;
  final Future<void> Function(BuildContext)? requestChangeLocation;
  final bool simpleButtonWhenEmpty;
  final bool clearPathEnabled;
  final List<PathTarget>? pathTargets;
  final void Function(String path)? onOpenPath;
  final String changeLocationLabel;

  const _PathTile({
    super.key,
    required this.icon,
    required this.title,
    required this.currentPath,
    required this.placeholder,
    required this.onFolderChanged,
    required this.onOpenFolder,
    this.onClearPath,
    this.requestChangeLocation,
    this.simpleButtonWhenEmpty = true,
    this.clearPathEnabled = true,
    this.pathTargets,
    this.onOpenPath,
    this.changeLocationLabel = 'שינוי מיקום...',
  });

  @override
  Widget build(BuildContext context) {
    return SettingsActionTile.path(
      icon: icon,
      title: title,
      path: currentPath.isNotEmpty ? currentPath : null,
      placeholder: placeholder,
      actions: [
        _PathMenuButton(
          currentPath: currentPath,
          onFolderChanged: onFolderChanged,
          onOpenFolder: onOpenFolder,
          onClearPath: onClearPath,
          requestChangeLocation: requestChangeLocation,
          simpleButtonWhenEmpty: simpleButtonWhenEmpty,
          clearPathEnabled: clearPathEnabled,
          pathTargets: pathTargets,
          onOpenPath: onOpenPath,
          changeLocationLabel: changeLocationLabel,
        ),
      ],
    );
  }
}

// ── _PathMenuButton ───────────────────────────────────────────────────────────

class _PathMenuButton extends StatefulWidget {
  final String currentPath;
  final Future<void> Function(String newPath) onFolderChanged;
  final VoidCallback onOpenFolder;
  final VoidCallback? onClearPath;
  final Future<void> Function(BuildContext)? requestChangeLocation;
  final bool simpleButtonWhenEmpty;
  final bool clearPathEnabled;
  final List<PathTarget>? pathTargets;
  final void Function(String path)? onOpenPath;
  final String changeLocationLabel;

  const _PathMenuButton({
    required this.currentPath,
    required this.onFolderChanged,
    required this.onOpenFolder,
    this.onClearPath,
    this.requestChangeLocation,
    this.simpleButtonWhenEmpty = true,
    this.clearPathEnabled = true,
    this.pathTargets,
    this.onOpenPath,
    this.changeLocationLabel = 'שינוי מיקום...',
  });

  @override
  State<_PathMenuButton> createState() => _PathMenuButtonState();
}

class _PathMenuButtonState extends State<_PathMenuButton> {
  bool _isLoading = false;

  Future<void> _pickAndChange() async {
    final path = await FilePicker.getDirectoryPath(lockParentWindow: true);
    if (path == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await widget.onFolderChanged(path);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showMenu(BuildContext anchorContext) async {
    final hasPath = widget.currentPath.isNotEmpty;
    final targets = widget.pathTargets;
    final hasTargets = targets != null && targets.isNotEmpty;
    final entries = <AppMenuEntry<_PathMenuAction>>[
      AppMenuEntry(
        value: _PathMenuAction.openFolder,
        label: context.settingsText(
          hasTargets ? 'פתח תיקייה...' : 'פתח תיקייה',
        ),
        icon: FluentIcons.folder_open_24_regular,
        enabled: hasPath || hasTargets,
      ),
      AppMenuEntry(
        value: _PathMenuAction.changeLocation,
        label: context.settingsText(widget.changeLocationLabel),
        icon: FluentIcons.folder_arrow_right_24_regular,
      ),
      AppMenuEntry(
        value: _PathMenuAction.copyPath,
        label: context.settingsText(
          hasTargets ? 'העתק נתיב...' : 'העתק נתיב',
        ),
        icon: FluentIcons.copy_24_regular,
        enabled: hasPath || hasTargets,
      ),
      // מוצג תמיד כשיש onClearPath; מושבת אם clearPathEnabled=false
      if (widget.onClearPath != null)
        AppMenuEntry(
          value: _PathMenuAction.clearPath,
          label: context.settingsText('הסרת מיקום שמור'),
          icon: FluentIcons.dismiss_24_regular,
          enabled: widget.clearPathEnabled,
        ),
    ];

    final selected = await showAnchoredAppMenu<_PathMenuAction>(
      context: context,
      anchorContext: anchorContext,
      itemsBuilder: (m) => entries
          .map(
            (e) => buildAppPopupMenuItem<_PathMenuAction>(context, e, m, null),
          )
          .toList(),
    );

    if (selected == null || !mounted || !anchorContext.mounted) return;

    switch (selected) {
      case _PathMenuAction.openFolder:
        if (hasTargets) {
          await _showTargetSubMenu(anchorContext, open: true);
        } else {
          widget.onOpenFolder();
        }
      case _PathMenuAction.changeLocation:
        await _handleChangeLocation();
      case _PathMenuAction.copyPath:
        if (hasTargets) {
          await _showTargetSubMenu(anchorContext, open: false);
        } else {
          await Clipboard.setData(ClipboardData(text: widget.currentPath));
          UiSnack.showSuccess(CommonMessages.pathCopied);
        }
      case _PathMenuAction.clearPath:
        widget.onClearPath?.call();
    }
  }

  /// תת-תפריט לבחירת יעד (שורש/ספרייה/אינדקס) עבור פתיחה או העתקה.
  Future<void> _showTargetSubMenu(
    BuildContext anchorContext, {
    required bool open,
  }) async {
    final targets = widget.pathTargets!;
    if (!mounted) return;
    final selected = await showAnchoredAppMenu<int>(
      context: context,
      anchorContext: anchorContext,
      itemsBuilder: (m) => [
        for (var i = 0; i < targets.length; i++)
          buildAppPopupMenuItem<int>(
            context,
            AppMenuEntry(
              value: i,
              label: targets[i].label,
              icon: open
                  ? FluentIcons.folder_open_24_regular
                  : FluentIcons.copy_24_regular,
              enabled: targets[i].path.isNotEmpty,
            ),
            m,
            null,
          ),
      ],
    );
    if (selected == null) return;
    final path = targets[selected].path;
    if (path.isEmpty) return;
    if (open) {
      widget.onOpenPath?.call(path);
    } else {
      await Clipboard.setData(ClipboardData(text: path));
      UiSnack.showSuccess(CommonMessages.pathCopied);
    }
  }

  Future<void> _handleChangeLocation() async {
    if (widget.requestChangeLocation != null) {
      await widget.requestChangeLocation!(context);
    } else {
      await _pickAndChange();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentPath.isEmpty && widget.simpleButtonWhenEmpty) {
      return ActionButton.recommended(
        text: context.settingsText('הגדר מיקום'),
        isLoading: _isLoading,
        // דיאלוג שינוי המיקום ברור יותר מבורר תיקייה ישיר; כשאין
        // requestChangeLocation נופלים לבורר. בלי מיקום נוכחי הדיאלוג
        // ממילא מסתיר את אפשרות העברת התוכן.
        onPressed: _isLoading ? null : _handleChangeLocation,
        icon: FluentIcons.folder_arrow_right_24_regular,
      );
    }
    return Builder(
      builder: (buttonContext) => ActionButton.neutral(
        text: context.settingsText('אפשרויות מיקום'),
        icon: FluentIcons.folder_arrow_right_24_regular,
        isLoading: _isLoading,
        onPressed: _isLoading ? null : () => _showMenu(buttonContext),
      ),
    );
  }
}

enum _PathMenuAction { openFolder, changeLocation, copyPath, clearPath }
