import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// פעולת החיפוש של לשונית אחת בחלונית הניווט.
///
/// הלשונית אינה מציירת שדה חיפוש בעצמה — היא מפרסמת את הפעולה שלה
/// ([NavPanelSearchPublisher]), ו-[NavPanelSearchBar] שבסרגל העליון מצייר אותה.
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
    this.actionsKey,
    this.onArrowDown,
    this.onArrowUp,
  });

  /// מזהה המצב החזותי של [trailingActions]. פעולה שמחליפה אייקון או צבע
  /// שומרת על אורך הרשימה, ולכן בלעדיו הסרגל המורם נשאר על התצוגה הישנה.
  final Object? actionsKey;

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

  /// האם שתי הפעולות מכוונות לאותו שדה (אותו controller/focus/תווית). ה-callbacks
  /// נבנים מחדש בכל build אך קוראים את ה-state העדכני בזמן ההפעלה, ולכן שינוי
  /// שלהם אינו מחייב בנייה מחדש של הסרגל.
  bool sameTargetAs(NavPanelSearchDelegate other) =>
      controller == other.controller &&
      focusNode == other.focusNode &&
      hintText == other.hintText &&
      actionsKey == other.actionsKey &&
      trailingActions.length == other.trailingActions.length;
}

/// מרכז את פעולות החיפוש של לשוניות החלונית ומזין את הסרגל שבסרגל העליון.
///
/// המסך מחזיק מופע אחד, מעדכן [activeTab] לפי הלשונית הנבחרת, ומעביר אותו
/// גם ל-[NavPanelSearchBar] וגם ל-[NavPanelSearchScope] שעוטף את החלונית.
class NavPanelSearchHost extends ChangeNotifier {
  final Map<int, NavPanelSearchDelegate> _delegates = {};
  int _activeTab = 0;
  bool _disposed = false;
  bool _notifyScheduled = false;

  /// ה-scope של תוכן החלונית. חץ למטה/למעלה בסרגל החיפוש מעביר אליו את
  /// הפוקוס, ומשם החצים מנווטים בין שורות הרשימה (traversal רגיל של Flutter).
  final FocusScopeNode paneFocusScope = FocusScopeNode(
    debugLabel: 'navPanelContent',
  );

  /// מעביר את הפוקוס אל תוכן החלונית: אל השורה שהפוקוס היה עליה, ואם אין —
  /// אל הראשונה לפי מדיניות המעבר (השורה המסומנת, ראה [NavTreeTile]).
  bool focusPaneContent() {
    if (_disposed) return false;
    final focusedChild = paneFocusScope.focusedChild;
    if (focusedChild != null) {
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
    if (first == null) return false;
    first.requestFocus();
    return true;
  }

  int get activeTab => _activeTab;

  set activeTab(int value) {
    if (_activeTab == value) return;
    _activeTab = value;
    _scheduleNotify();
  }

  /// פעולת החיפוש של הלשונית הפעילה, או null כשאין לה חיפוש.
  NavPanelSearchDelegate? get active => _delegates[_activeTab];

  void publish(int tab, NavPanelSearchDelegate delegate) {
    if (_disposed) return;
    final previous = _delegates[tab];
    _delegates[tab] = delegate;
    if (tab != _activeTab) return;
    if (previous != null && previous.sameTargetAs(delegate)) return;
    _scheduleNotify();
  }

  void withdraw(int tab) {
    if (_disposed) return;
    if (_delegates.remove(tab) != null && tab == _activeTab) {
      _scheduleNotify();
    }
  }

  /// הפרסום מתרחש בתוך build של הלשונית, ולכן ההודעה נדחית לסוף ה-frame —
  /// אחרת ה-setState של הסרגל נופל על "markNeedsBuild during build".
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    paneFocusScope.dispose();
    super.dispose();
  }
}

/// עוטף את תוכן החלונית ב-scope הפוקוס שלה ובמדיניות מעבר ממוינת, כדי
/// שכניסת הפוקוס מסרגל החיפוש תגיע לשורות הרשימה ולא ללשוניות.
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

  @override
  bool updateShouldNotify(NavPanelSearchScope oldWidget) =>
      oldWidget.host != host;
}

/// עזר לזיהוי המצב: בתוך חלונית ניווט שדה החיפוש עולה לסרגל שמעליה, ולכן
/// הלשונית אינה מציירת שדה מקומי. מחוץ לחלונית (דיאלוג, מסך אחר) היא כן.
abstract final class NavPanelSearch {
  static bool isHoisted(BuildContext context) =>
      NavPanelSearchScope.hostOf(context) != null &&
      NavPanelSearchSlot.indexOf(context) != null;
}

/// מסמן את אינדקס הלשונית שבתוכה יושב התוכן — כדי שהפרסום יגיע לסרגל רק
/// כשהלשונית הזו נבחרת. עוטף כל child של ה-TabBarView בחלונית.
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

/// מפרסם את פעולת החיפוש של הלשונית שבתוכה הוא יושב, כל עוד הוא בעץ.
/// מחוץ ל-[NavPanelSearchScope] (למשל בדיאלוג) הוא שקוף לחלוטין.
class NavPanelSearchPublisher extends StatefulWidget {
  final NavPanelSearchDelegate delegate;
  final Widget child;

  const NavPanelSearchPublisher({
    super.key,
    required this.delegate,
    required this.child,
  });

  @override
  State<NavPanelSearchPublisher> createState() =>
      _NavPanelSearchPublisherState();
}

class _NavPanelSearchPublisherState extends State<NavPanelSearchPublisher> {
  NavPanelSearchHost? _host;
  int? _slot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = NavPanelSearchScope.hostOf(context);
    final slot = NavPanelSearchSlot.indexOf(context);
    if (host != _host || slot != _slot) {
      if (_host != null && _slot != null) _host!.withdraw(_slot!);
      _host = host;
      _slot = slot;
    }
    _republish();
  }

  @override
  void didUpdateWidget(NavPanelSearchPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _republish();
  }

  void _republish() {
    final host = _host;
    final slot = _slot;
    if (host == null || slot == null) return;
    host.publish(slot, widget.delegate);
  }

  @override
  void dispose() {
    if (_host != null && _slot != null) _host!.withdraw(_slot!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// שדה החיפוש המקומי של לשונית — לשימוש כשהיא אינה בתוך חלונית ניווט
/// (ואז אין סרגל שמעליה שיצייר אותו).
class NavPanelLocalSearchField extends StatelessWidget {
  final NavPanelSearchDelegate delegate;

  const NavPanelLocalSearchField({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) => delegate.handleArrowKey(event),
        child: OtzariaSearchField(
          controller: delegate.controller,
          focusNode: delegate.focusNode,
          hintText: delegate.hintText,
          onChanged: delegate.onChanged,
          onSubmitted: delegate.onSubmitted,
          onClear: delegate.onClear,
          trailingActions: delegate.trailingActions.isEmpty
              ? null
              : delegate.trailingActions,
        ),
      ),
    );
  }
}

/// סרגל החלונית שבתוך הסרגל העליון: שדה החיפוש של הלשונית הפעילה וכפתור
/// הנעיצה. הוא תופס בדיוק את רוחב החלונית שמתחתיו, עם אותם שוליים אופקיים של
/// תוכן החלונית ([kNavTreeSideInset]) — כדי שלא ייראה כמרחף מעל תוכן הקריאה.
/// אייקון הפתיחה/סגירה נשאר מחוץ לרוחב הזה, כפריט הבא בסרגל.
///
/// נפתח באנימציה מרוחב 0 (מקום אייקון הפתיחה) לרוחב החלונית, ולכן הוא דוחק
/// את האייקון פנימה ו"נמשך" ממנו. הפעולה שבתוכו מתחלפת לפי הלשונית הנבחרת,
/// והסרגל נשאר מוצג ומורכב כל עוד החלונית פתוחה.
class NavPanelSearchBar extends StatefulWidget {
  final NavPanelSearchHost host;

  /// האם החלונית פתוחה — הסרגל נפתח ונסגר יחד איתה.
  final bool isOpen;

  /// רוחב החלונית שמעליה הסרגל יושב.
  final double paneWidth;

  /// מצב נעיצת החלונית. [onTogglePin] null = הכפתור מוסתר (למשל במסך צר, או
  /// בחלונית שאין בה נעיצה).
  final bool isPinned;
  final VoidCallback? onTogglePin;

  const NavPanelSearchBar({
    super.key,
    required this.host,
    required this.isOpen,
    required this.paneWidth,
    this.isPinned = false,
    this.onTogglePin,
  });

  @override
  State<NavPanelSearchBar> createState() => _NavPanelSearchBarState();
}

class _NavPanelSearchBarState extends State<NavPanelSearchBar> {
  /// controller קבוע ללשונית שאין בה חיפוש — כדי שהשדה עצמו יישאר אותו
  /// ווידג'ט ולא ייבנה מחדש במעבר בין לשוניות.
  final TextEditingController _idleController = TextEditingController();

  @override
  void dispose() {
    _idleController.dispose();
    super.dispose();
  }

  KeyEventResult _handleFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final delegate = widget.host.active;
    if (delegate != null &&
        delegate.handleArrowKey(event) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    return widget.host.focusPaneContent()
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // כמו ב-OtzariaSearchField: קריאה סובלנית, כדי שהסרגל יעבוד גם בהקשר
    // שאין בו SettingsBloc.
    final isCompact =
        context.read<SettingsBloc?>()?.state.compactMenuMode ?? false;
    // הסרגל העליון מרווח את פריטיו מהדופן, והחלונית צמודה אליה — לכן הרוחב
    // והשוליים מפצים על אותו ריווח, ושפת הסרגל מתיישרת לשפת החלונית.
    final barInset = AppTopBar.horizontalPadding(isCompact);
    final width = (widget.paneWidth - barInset).clamp(0.0, double.infinity);
    final hasPin = widget.onTogglePin != null;
    // בלי נעיצה השדה מתיישר לשוליים של תוכן החלונית משני הצדדים. עם נעיצה
    // השוליים נשמרים לשדה בלבד: הוא מוותר על השוליים החיצוניים (שם הסרגל
    // העליון עמוס בכל מקרה), וכפתור הנעיצה גולש אל השוליים הפנימיים — כך
    // הוא לא נצמד לשדה ולא מתרחק מאייקון הסגירה.
    final fieldStartInset = hasPin
        ? 0.0
        : (kNavTreeSideInset - barInset).clamp(0.0, double.infinity);
    final fieldEndInset = hasPin ? AppTokens.spaceXS : kNavTreeSideInset;

    // בסרגל צפוף (פריט flexible) השדה מקבל פחות מרוחב החלונית — מתכווצים
    // אליו, אחרת ה-ClipRect חותך את כפתורי הקצה (נעיצה, ניקוי) מהשדה.
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth = constraints.hasBoundedWidth
            ? width.clamp(0.0, constraints.maxWidth)
            : width;
        // IntrinsicHeight: ה-OverflowBox דורש גובה חסום, וסרגל עליון עשוי לתת
        // גובה חופשי (Row בתוך Column).
        return IntrinsicHeight(
          child: AnimatedContainer(
            duration: AppTokens.animPanelSlide,
            curve: Curves.easeInOut,
            width: widget.isOpen ? effectiveWidth : 0,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: effectiveWidth,
                minWidth: 0,
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: effectiveWidth,
                  child: Row(
                    children: [
                      // רק תוכן השדה מתחלף לפי הלשונית — הסרגל עצמו נשאר מוצג
                      // ומורכב כל עוד החלונית פתוחה, ואינו נבנה מחדש.
                      Expanded(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: fieldStartInset,
                            end: fieldEndInset,
                          ),
                          // חץ למטה/למעלה מעביר את הפוקוס אל שורות החלונית; ימין
                          // ושמאל נשארים לעריכת הטקסט. ה-handler יושב מעל השדה
                          // ולכן הוא מקבל את המקש לפני קיצורי עריכת הטקסט.
                          child: Focus(
                            canRequestFocus: false,
                            onKeyEvent: _handleFieldKey,
                            child: ListenableBuilder(
                              listenable: widget.host,
                              builder: (context, _) {
                                final delegate = widget.host.active;
                                return OtzariaSearchField(
                                  controller:
                                      delegate?.controller ?? _idleController,
                                  focusNode: delegate?.focusNode,
                                  enabled: delegate != null,
                                  hintText:
                                      delegate?.hintText ??
                                      'אין חיפוש בלשונית זו',
                                  onChanged: delegate?.onChanged,
                                  onSubmitted: delegate?.onSubmitted,
                                  onClear: delegate?.onClear,
                                  trailingActions:
                                      delegate == null ||
                                          delegate.trailingActions.isEmpty
                                      ? null
                                      : delegate.trailingActions,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      if (hasPin)
                        NavPanelPinButton(
                          isPinned: widget.isPinned,
                          onToggle: widget.onTogglePin,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
