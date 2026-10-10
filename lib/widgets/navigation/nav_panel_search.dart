import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// הגדרת שדה החיפוש של לשונית אחת בחלונית הניווט.
class NavPanelSearchDelegate {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final List<Widget> trailingActions;

  /// דפדוף בתוצאות בחיצים בלי לעזוב את שדה הטקסט (כמו ב"איתור"): הלשונית
  /// מזיזה סימון משלה, והפוקוס — והיכולת להמשיך להקליד — נשארים בשדה.
  /// כשהם null, חץ למטה/למעלה מעביר את הפוקוס אל שורות החלונית.
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowUp;

  const NavPanelSearchDelegate({
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.trailingActions = const [],
    this.onArrowDown,
    this.onArrowUp,
  });

  /// מטפל בחיצי מעלה/מטה עבור שדה חיפוש שמחובר לפעולה זו. מוחזר
  /// [KeyEventResult.ignored] כשאין callback מתאים — ואז חל המנגנון הרגיל.
  KeyEventResult handleArrowKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown && onArrowDown != null) {
      onArrowDown!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && onArrowUp != null) {
      onArrowUp!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// מצב משותף לחלונית הניווט: הלשונית הפעילה וה-scope של שורות התוכן.
class NavPanelSearchHost {
  /// הלשונית הנבחרת — רק שדה החיפוש שלה רשאי למקד את עצמו בבנייה.
  int activeTab = 0;

  /// ה-scope של תוכן החלונית. חץ למטה/למעלה בשדה החיפוש מעביר אליו את
  /// הפוקוס, ומשם החצים מנווטים בין שורות הרשימה (traversal רגיל של Flutter).
  final FocusScopeNode paneFocusScope = FocusScopeNode(
    debugLabel: 'navPanelContent',
  );

  /// מעביר את הפוקוס אל תוכן החלונית: אל השורה שהפוקוס היה עליה, ואם אין —
  /// אל הראשונה לפי מדיניות המעבר (השורה המסומנת, ראה [NavTreeTile]).
  bool focusPaneContent() {
    // השדה עצמו יושב בתוך ה-scope, ולכן הוא לעולם אינו יעד.
    final current = FocusManager.instance.primaryFocus;
    final focusedChild = paneFocusScope.focusedChild;
    if (focusedChild != null && focusedChild != current) {
      focusedChild.requestFocus();
      return true;
    }
    final context = paneFocusScope.context;
    if (context == null) return false;
    final policy =
        FocusTraversalGroup.maybeOf(context) ?? ReadingOrderTraversalPolicy();
    final first = policy.findFirstFocus(
      paneFocusScope,
      ignoreCurrentFocus: true,
    );
    if (first == null || first == current) return false;
    first.requestFocus();
    return true;
  }

  void dispose() => paneFocusScope.dispose();
}

/// עוטף את תוכן החלונית ב-scope הפוקוס שלה ובמדיניות מעבר ממוינת, כדי
/// שכניסת הפוקוס משדה החיפוש תגיע לשורות הרשימה ולא ללשוניות.
class _NavPanelContentFocus extends StatelessWidget {
  final NavPanelSearchHost host;
  final Widget child;

  const _NavPanelContentFocus({required this.host, required this.child});

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: host.paneFocusScope,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: child,
      ),
    );
  }
}

/// מספק את [NavPanelSearchHost] לצאצאי החלונית.
class NavPanelSearchScope extends InheritedWidget {
  final NavPanelSearchHost host;

  NavPanelSearchScope({super.key, required this.host, required Widget child})
    : super(
        child: _NavPanelContentFocus(host: host, child: child),
      );

  static NavPanelSearchHost? hostOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavPanelSearchScope>()?.host;

  /// כמו [hostOf] בלי תלות — לשימוש מחוץ ל-build (מקשים, לחיצות).
  static NavPanelSearchHost? readHost(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NavPanelSearchScope>()?.host;

  @override
  bool updateShouldNotify(NavPanelSearchScope oldWidget) =>
      oldWidget.host != host;
}

/// רוחב החלונית המזערי שבו מותר למקד שדה חיפוש ביוזמת התוכנה. מתחתיו
/// (טלפון) מיקוד כזה פותח את מקלדת המערכת על ספר שהמשתמש רק רצה לקרוא.
const double kNavPanelWideMinWidth = 600.0;

abstract final class NavPanelSearch {
  /// האם החלונית רחבה. בתצוגה מפוצלת החלון רחב אך החלונית צרה — ולכן
  /// נמדדת החלונית ([NavPanelPaneWidthScope]), לא החלון (issue #1268).
  static bool isWide(BuildContext context) =>
      (NavPanelPaneWidthScope.maybeOf(context) ??
          MediaQuery.sizeOf(context).width) >=
      kNavPanelWideMinWidth;

  /// האם לסמן ב-host לשונית שנבחרה כפעילה. לשונית שנבחרה אוטומטית (ספר שנפתח
  /// מחיפוש) מסומנת רק במסך רחב — אחרת השדה שלה ממקד את עצמו ופותח מקלדת.
  static bool shouldMarkActiveTab(
    BuildContext context, {
    required bool autoSelected,
  }) => !autoSelected || isWide(context);

  /// מקשי שדה חיפוש בחלונית: דפדוף של הלשונית אם יש, ואחרת חץ למטה/למעלה
  /// מעביר את הפוקוס אל שורות החלונית. ימין ושמאל נשארים לעריכת הטקסט.
  static KeyEventResult handleFieldKey(
    BuildContext context,
    NavPanelSearchDelegate delegate,
    KeyEvent event,
  ) {
    if (delegate.handleArrowKey(event) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final host = NavPanelSearchScope.readHost(context);
    return host != null && host.focusPaneContent()
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}

/// רוחב החלונית (הטאב) שבה מוצג הספר — מסופק ע"י מארח החלוניות, כדי שהחלטות
/// רוחב יתייחסו לחלונית ולא לחלון כולו.
class NavPanelPaneWidthScope extends InheritedWidget {
  final double width;

  const NavPanelPaneWidthScope({
    super.key,
    required this.width,
    required super.child,
  });

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NavPanelPaneWidthScope>()
      ?.width;

  @override
  bool updateShouldNotify(NavPanelPaneWidthScope oldWidget) =>
      (oldWidget.width >= kNavPanelWideMinWidth) !=
      (width >= kNavPanelWideMinWidth);
}

/// מסמן את אינדקס הלשונית שבתוכה יושב התוכן. עוטף כל child של ה-TabBarView
/// בחלונית.
class NavPanelSearchSlot extends InheritedWidget {
  final int index;

  const NavPanelSearchSlot({
    super.key,
    required this.index,
    required super.child,
  });

  static int? indexOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavPanelSearchSlot>()?.index;

  @override
  bool updateShouldNotify(NavPanelSearchSlot oldWidget) =>
      oldWidget.index != index;
}

/// חיפוש משני של לשונית: השדה מוסתר עד שלוחצים על [NavPanelSearchToggle]
/// (שיושב בכותרת הרשימה), ונפתח מעל התוכן עם כפתור סגירה שגם מנקה אותו.
/// כשהכותרת נגללה מחוץ לתחום, אייקון זהה צף בפינה העליונה (issue #1725).
class NavPanelCollapsibleSearch extends StatefulWidget {
  final NavPanelSearchDelegate delegate;
  final Widget child;

  const NavPanelCollapsibleSearch({
    super.key,
    required this.delegate,
    required this.child,
  });

  @override
  State<NavPanelCollapsibleSearch> createState() =>
      _NavPanelCollapsibleSearchState();
}

class _NavPanelCollapsibleSearchState extends State<NavPanelCollapsibleSearch> {
  late bool _isOpen = widget.delegate.controller.text.isNotEmpty;
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.delegate.focusNode ?? (_ownFocusNode ??= FocusNode());

  final _contentKey = GlobalKey();
  final _toggles = <BuildContext>{};
  bool _hadToggle = false;
  bool _toggleOffscreen = false;
  bool _checkScheduled = false;

  void _registerToggle(BuildContext toggle) {
    _toggles.add(toggle);
    _hadToggle = true;
    _scheduleToggleCheck();
  }

  void _unregisterToggle(BuildContext toggle) {
    _toggles.remove(toggle);
    _scheduleToggleCheck();
  }

  void _scheduleToggleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final offscreen = _hadToggle && !_isAnyToggleVisible();
      if (offscreen != _toggleOffscreen) {
        setState(() => _toggleOffscreen = offscreen);
      }
    });
  }

  // רשימה עצלה פורקת כותרת רחוקה, ורשימה רגילה מציירת אותה מחוץ לתחום.
  bool _isAnyToggleVisible() {
    final area = _contentKey.currentContext?.findRenderObject();
    if (area is! RenderBox || !area.hasSize) return true;
    for (final toggle in _toggles) {
      final box = toggle.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final center = box.localToGlobal(
        box.size.center(Offset.zero),
        ancestor: area,
      );
      if (center.dy >= 0 && center.dy <= area.size.height) return true;
    }
    return false;
  }

  bool _onContentNotification(Notification notification) {
    if (notification is ScrollNotification ||
        notification is ScrollMetricsNotification) {
      _scheduleToggleCheck();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    widget.delegate.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(NavPanelCollapsibleSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate.controller != widget.delegate.controller) {
      oldWidget.delegate.controller.removeListener(_onTextChanged);
      widget.delegate.controller.addListener(_onTextChanged);
      _onTextChanged();
    }
  }

  @override
  void dispose() {
    widget.delegate.controller.removeListener(_onTextChanged);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  // סינון שהוחל מבחוץ (שחזור טאב) חייב שדה גלוי — אחרת הרשימה מסוננת בלי הסבר.
  void _onTextChanged() {
    if (!_isOpen && widget.delegate.controller.text.isNotEmpty) {
      setState(() => _isOpen = true);
    }
  }

  // autofocus מוותר כשיש פוקוס אחר (טקסט הספר) — לכן מבקשים במפורש.
  void _open() {
    setState(() => _isOpen = true);
    _focusNode.requestFocus();
  }

  void _close() {
    final delegate = widget.delegate;
    final hadFocus = _focusNode.hasFocus;
    if (delegate.controller.text.isNotEmpty) {
      delegate.controller.clear();
      delegate.onClear?.call();
    }
    setState(() => _isOpen = false);
    if (hadFocus) NavPanelSearchScope.readHost(context)?.focusPaneContent();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return NavPanelSearch.handleFieldKey(context, widget.delegate, event);
  }

  Widget _buildFieldRow(BuildContext context) {
    final delegate = widget.delegate;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        kNavTreeSideInset,
        AppTokens.spaceSM,
        AppTokens.spaceXS,
        AppTokens.spaceXS,
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: _handleKey,
              child: OtzariaSearchField(
                controller: delegate.controller,
                focusNode: _focusNode,
                hintText: delegate.hintText,
                onChanged: delegate.onChanged,
                onSubmitted: delegate.onSubmitted,
                trailingActions: delegate.trailingActions.isEmpty
                    ? null
                    : delegate.trailingActions,
              ),
            ),
          ),
          IconButton(
            tooltip: 'סגור חיפוש',
            onPressed: _close,
            visualDensity: VisualDensity.compact,
            icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _NavPanelSearchToggleScope(
      owner: this,
      isOpen: _isOpen,
      onOpen: _open,
      hintText: widget.delegate.hintText,
      child: Column(
        children: [
          ClipRect(
            child: AnimatedSize(
              duration: AppTokens.animFast,
              curve: Curves.easeOut,
              alignment: AlignmentDirectional.topCenter,
              child: _isOpen
                  ? _buildFieldRow(context)
                  : const SizedBox(width: double.infinity),
            ),
          ),
          Expanded(
            child: Stack(
              key: _contentKey,
              children: [
                NotificationListener<Notification>(
                  onNotification: _onContentNotification,
                  child: widget.child,
                ),
                PositionedDirectional(
                  top: kNavTreeListPadding.top + AppTokens.spaceXS,
                  end: kNavTreeSideInset + 12,
                  child: AnimatedSwitcher(
                    duration: AppTokens.animFast,
                    child: _toggleOffscreen && !_isOpen
                        ? Material(
                            color: AppSurfaces.navPanelBackground(context),
                            shape: AppTokens.roundedShape,
                            elevation: 1,
                            child: _SearchToggleButton(
                              hintText: widget.delegate.hintText,
                              onPressed: _open,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavPanelSearchToggleScope extends InheritedWidget {
  final _NavPanelCollapsibleSearchState owner;
  final bool isOpen;
  final VoidCallback onOpen;
  final String hintText;

  const _NavPanelSearchToggleScope({
    required this.owner,
    required this.isOpen,
    required this.onOpen,
    required this.hintText,
    required super.child,
  });

  @override
  bool updateShouldNotify(_NavPanelSearchToggleScope oldWidget) =>
      oldWidget.owner != owner ||
      oldWidget.isOpen != isOpen ||
      oldWidget.hintText != hintText;
}

/// אייקון שפותח את השדה של [NavPanelCollapsibleSearch] שמעליו. מיועד ל-trailing
/// של הכותרת הראשית ברשימה; נעלם כשהשדה פתוח או כשאין חיפוש מעליו.
class NavPanelSearchToggle extends StatefulWidget {
  const NavPanelSearchToggle({super.key});

  @override
  State<NavPanelSearchToggle> createState() => _NavPanelSearchToggleState();
}

class _NavPanelSearchToggleState extends State<NavPanelSearchToggle> {
  _NavPanelCollapsibleSearchState? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context
        .dependOnInheritedWidgetOfExactType<_NavPanelSearchToggleScope>()
        ?.owner;
    if (owner == _owner) return;
    _owner?._unregisterToggle(context);
    _owner = owner?.._registerToggle(context);
  }

  @override
  void dispose() {
    _owner?._unregisterToggle(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_NavPanelSearchToggleScope>();
    if (scope == null || scope.isOpen) return const SizedBox.shrink();
    return _SearchToggleButton(
      hintText: scope.hintText,
      onPressed: scope.onOpen,
    );
  }
}

class _SearchToggleButton extends StatelessWidget {
  final String hintText;
  final VoidCallback onPressed;

  const _SearchToggleButton({required this.hintText, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        tooltip: hintText,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: const Icon(FluentIcons.search_24_regular, size: 18),
      ),
    );
  }
}
