import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// אייקון הראש של כרטיסיות שתוכנן מזוהה בו — תוצאות חיפוש ומסמכי Word,
/// HTML ו-Markdown — או `null` לכל כרטיסיה אחרת. מקור יחיד לשורה העליונה,
/// לעמודה האנכית, לחלונית חיפוש הכרטיסיות ולמוק הגרירה.
IconData? tabContentIconData(OpenedTab tab) {
  if (tab is SearchingTab) return OtzariaIcons.search_24_regular;
  if (tab is TextBookTab) return documentFormatIcon(tab.book);
  return null;
}

/// הכותרת שמוצגת לצד אייקון הראש. אייקון החיפוש מחליף את המילה "חיפוש:"
/// בכותרת של כרטיסיית חיפוש, ולא מתווסף אליה: נשארת רק השאילתה.
///
/// ⚠️ כשאין שאילתה הכותרת היא המילה "חיפוש" בלבד, והיא נשארת — כרטיסיה בלי
/// טקסט כלל אינה ניתנת לזיהוי. מי שמציג את האייקון רק ברוחב מסוים קורא לכאן
/// רק כשהאייקון מוצג, אחרת המילה נעלמת בלי תחליף.
String tabTitleBesideContentIcon(OpenedTab tab, String title) {
  if (tab is! SearchingTab) return title;
  final prefix = tab is SemanticSearchTab
      ? '$kSemanticSearchModeName: '
      : 'חיפוש: ';
  if (!title.startsWith(prefix) ||
      title.trim().length <= prefix.trim().length) {
    return title;
  }
  return title.substring(prefix.length);
}

/// אייקון סוג הכרטיסיה — משותף לעמודה האנכית ולחלונית חיפוש הכרטיסיות. כל
/// מקום בגודל שלו (16 כאן, 14 ברצועה העליונה), מאותו סט אייקונים (q10 Q14 C).
///
/// מחזיר `null` לכרטיסיית טקסט רגילה, שאין לה אייקון ייעודי.
Widget? buildTabTypeIcon(
  BuildContext context,
  OpenedTab tab, {
  double size = 16,
  Color? color,
}) {
  final resolved = color ?? Theme.of(context).colorScheme.onSurface;
  final contentIcon = tabContentIconData(tab);
  if (contentIcon != null) {
    return Icon(contentIcon, size: size, color: resolved);
  }
  if (tab is PdfBookTab) {
    return Icon(
      OtzariaIcons.document_pdf_24_regular,
      size: size,
      color: resolved,
    );
  }
  if (tab is CombinedTab) {
    return Icon(
      FluentIcons.split_horizontal_24_regular,
      size: size,
      color: resolved,
    );
  }
  if (tab is ToolTab) {
    return buildToolTabLeadingIcon(
      tab.toolId,
      color: resolved,
      pluginState: context.read<PluginSystemBloc>().state,
    );
  }
  return null;
}

/// אותו אייקון כ-[buildTabTypeIcon], כ-[IconData] ולא כווידג'ט.
///
/// ⚠️ נדרש למי שמצייר על `Canvas` ולא בונה עץ וידג'טים — מוק הגרירה של
/// כרטיסיה שאין מה לצלם בה (`composeTabContentPlaceholder`). שם האייקון
/// מצויר כגליף בגופן, וגליף דורש `codePoint` ו-`fontFamily`.
///
/// ⚠️ **תמיד מחזיר אייקון**, בשונה מ-[buildTabTypeIcon] שמחזיר `null`
/// לכרטיסיית טקסט: מוק בלי אייקון הוא מלבן ריק עם כותרת תלויה באוויר.
///
/// ⚠️ כרטיסיית תוסף מקבלת אייקון כללי ולא את האייקון שהתוסף הצהיר עליו.
/// [buildToolTabLeadingIcon] יכול להחזיר גם **תמונה** מהתוסף, ולא רק
/// גליף, ולתמונה אין `codePoint`. זה מוק גרירה של רגע אחד, והנאמנות הזו
/// אינה שווה מסלול ציור שני.
IconData tabTypeIconData(OpenedTab tab) {
  final contentIcon = tabContentIconData(tab);
  if (contentIcon != null) return contentIcon;
  if (tab is PdfBookTab) return OtzariaIcons.document_pdf_24_regular;
  if (tab is CombinedTab) return FluentIcons.split_horizontal_24_regular;
  if (tab is ToolTab) return FluentIcons.toolbox_24_regular;
  return FluentIcons.document_24_regular;
}

/// אייקון ברירת מחדל לכרטיסיה שאין לה אייקון סוג משלה.
Widget buildTabFallbackIcon(
  BuildContext context, {
  double size = 16,
  Color? color,
}) => Icon(
  FluentIcons.document_24_regular,
  size: size,
  color: color ?? Theme.of(context).colorScheme.onSurface,
);

/// כותרת מוצמדת ל-start ונדהית בסוף רק כשהיא נחתכת.
/// TextOverflow.fade מציג בעברית את הסוף, לכן משתמשים ב-OverflowBox וב-ClipRect.
Widget buildFadedTabTitle(BuildContext context, String title) => LayoutBuilder(
  builder: (context, constraints) {
    final direction = Directionality.of(context);
    final titleBox = OverflowBox(
      alignment: AlignmentDirectional.centerStart,
      minWidth: 0,
      maxWidth: double.infinity,
      child: Text(title, maxLines: 1, softWrap: false),
    );
    final width = _measuredTitleWidth(
      title,
      _effectiveTitleStyle(context, DefaultTextStyle.of(context).style),
      MediaQuery.textScalerOf(context),
      direction,
    );
    if (width <= constraints.maxWidth + 0.5) return ClipRect(child: titleBox);
    final isLtr = direction == TextDirection.ltr;
    return ClipRect(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: isLtr ? Alignment.centerLeft : Alignment.centerRight,
          end: isLtr ? Alignment.centerRight : Alignment.centerLeft,
          stops: const [0.0, 0.82, 1.0],
          // ui-lint: allow UIL-015 — מסכת השקיפות של ShaderMask (dstIn); הצבע עצמו לא מצויר
          colors: const [Colors.white, Colors.white, Colors.transparent],
        ).createShader(rect),
        child: titleBox,
      ),
    );
  },
);

// Text מחיל boldText גם על משקל מפורש; המדידה והמטמון צריכים אותו סגנון.
TextStyle _effectiveTitleStyle(BuildContext context, TextStyle style) =>
    MediaQuery.boldTextOf(context)
    ? style.merge(const TextStyle(fontWeight: FontWeight.bold))
    : style;

/// רוחבי כותרות שנמדדו. המדידה חוזרת בכל שינוי אילוצים — הנפשת רוחב כרטיסיות
/// או שינוי גודל חלון מייצרים אחרת פריסת טקסט מלאה לכל כרטיסיה בכל פריים.
final Map<(String, TextStyle, TextScaler, TextDirection), double>
_titleWidthCache = {};

/// מעל הסף כל המפה מנוקה: המפתחות מגיעים מכותרות כרטיסיות פתוחות, ולכן
/// המדידות נבנות מחדש מיד ובלי עלות מורגשת.
const int _kTitleWidthCacheLimit = 256;

double _measuredTitleWidth(
  String title,
  TextStyle style,
  TextScaler scaler,
  TextDirection direction,
) {
  final key = (title, style, scaler, direction);
  final cached = _titleWidthCache[key];
  if (cached != null) return cached;

  final painter = TextPainter(
    text: TextSpan(text: title, style: style),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();

  if (_titleWidthCache.length >= _kTitleWidthCacheLimit) {
    _titleWidthCache.clear();
  }
  _titleWidthCache[key] = width;
  return width;
}

/// הכותרת שמתעדכנת תוך כדי קריאה (המיקום בספר, שאילתת החיפוש), או `null`
/// לכרטיסיה שכותרתה סטטית.
ValueListenable<String>? liveTabTitleOf(OpenedTab tab) {
  if (tab is SearchingTab) return tab.titleNotifier;
  if (tab is PdfBookTab) return tab.currentTitle;
  if (tab is PdfCommentatorsTab) return tab.sourceTab.currentTitle;
  if (tab is TextBookTab) return tab.currentTitle;
  return null;
}

/// בונה את הזוג (כותרת מוצגת, הודעת tooltip) של כרטיסיה ומתעדכן עם הכותרת
/// החיה; לכרטיסיה סטטית שניהם שם הכרטיסיה. משותף לפס העליון ולפס הצדדי.
class LiveTabTitleBuilder extends StatelessWidget {
  final OpenedTab tab;
  final Widget Function(
    BuildContext context,
    String displayTitle,
    String tooltipMessage,
  )
  builder;

  const LiveTabTitleBuilder({
    super.key,
    required this.tab,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final tab = this.tab;
    final liveTitle = liveTabTitleOf(tab);
    if (liveTitle == null) return builder(context, tab.title, tab.title);
    return ValueListenableBuilder<String>(
      valueListenable: liveTitle,
      builder: (context, value, child) {
        // בכרטיסיית חיפוש הערך הוא הכותרת עצמה; בשאר הוא המיקום שמתווסף לה.
        if (tab is SearchingTab) return builder(context, value, value);
        // טאב שטרם נבנה (שוחזר בעלייה) עוד לא קיבל מיקום מה-BLoC.
        if (value.isEmpty && tab is TextBookTab) tab.ensureLocationTitle();
        return builder(
          context,
          tab.title,
          value.isEmpty ? tab.title : '${tab.title}, $value',
        );
      },
    );
  }
}

/// עוטף כותרת כרטיסיה ב-[Tooltip] רק כשיש בו ערך: הכותרת נחתכה ברוחב הזמין,
/// או שההודעה מוסיפה מידע שאינו מוצג (למשל המיקום הנוכחי בספר).
class TabTitleTooltip extends StatelessWidget {
  /// הטקסט שיוצג ב-tooltip.
  final String message;

  /// הכותרת כפי שהיא מרונדרת בכרטיסיה — נמדדת מול הרוחב הזמין.
  final String title;

  /// כשדולק, ה-tooltip מוצג תמיד (מצב מכווץ: מוצג אייקון בלבד).
  final bool alwaysShow;

  /// הרוחב שבו הכותרת מרונדרת. כשהוא ידוע, ה-[child] יכול להיות שטח רחב יותר
  /// מהכותרת — למשל הכרטיסיה כולה — והחיתוך עדיין נמדד נכון.
  final double? titleWidth;

  /// הסגנון שבו נמדדת הכותרת; חובה יחד עם [titleWidth], כי ה-[child] החיצוני
  /// אינו בהכרח תחת ה-[DefaultTextStyle] של הכותרת.
  final TextStyle? titleStyle;

  final Widget child;

  const TabTitleTooltip({
    super.key,
    required this.message,
    required this.title,
    required this.child,
    this.alwaysShow = false,
    this.titleWidth,
    this.titleStyle,
  });

  Widget _wrapIfNeeded(
    BuildContext context,
    double available,
    TextStyle style,
  ) {
    final width = _measuredTitleWidth(
      title,
      _effectiveTitleStyle(context, style),
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    final truncated = width > available + 0.5;
    if (!truncated && message == title) return child;
    return _tooltip;
  }

  // במגע לחיצה ארוכה פותחת את תפריט הכרטיסיה, כמו לחיצה ימנית.
  Widget get _tooltip => Tooltip(
    message: message,
    triggerMode: TooltipTriggerMode.manual,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    if (alwaysShow) return _tooltip;
    final available = titleWidth;
    if (available != null) {
      return _wrapIfNeeded(
        context,
        available,
        titleStyle ?? DefaultTextStyle.of(context).style,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => _wrapIfNeeded(
        context,
        constraints.maxWidth,
        DefaultTextStyle.of(context).style,
      ),
    );
  }
}

/// כפתור ה-X של כרטיסיה — משותף לפס העליון ולעמודה הצדדית.
///
/// ה-tooltip ניתן לכפתור עצמו (`IconButton.tooltip`) ולא עוטף אותו מבחוץ:
/// IconButton בונה את ה-Tooltip *בתוך* מכולת הסמנטיקה שלו, ולכן ההודעה
/// ועוגן ה-OverlayPortal של הבלון שייכים לצומת הסמנטיקה של הכפתור. Tooltip
/// חיצוני אינו יוצר צומת משלו — הוא מתמזג לצומת הסמנטיקה הקרוב, כאן צומת
/// הכרטיסיה, שכבר נושא את ה-tooltip של הכותרת. לצומת יש מקום לעוגן אחד
/// בלבד (`traversalParentIdentifier`), ולכן עוגן ה-X נשמט; כשהבלון שלו נפתח
/// הוא נשלח למערכת ההפעלה בלי אב, Windows דוחה את עדכון עץ הנגישות והעץ
/// קופא — עד קריסה של התוכנה במעבר הפוקוס הבא (issue #1399).
class TabCloseButton extends StatelessWidget {
  final String tooltip;
  final Size size;
  final double iconSize;

  /// null — לפי ה-[TooltipTheme] שמעליו.
  final bool? preferBelow;

  final VoidCallback onPressed;

  const TabCloseButton({
    super.key,
    required this.tooltip,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    this.preferBelow,
  });

  @override
  Widget build(BuildContext context) {
    return TooltipTheme(
      // במגע לחיצה ארוכה פותחת את תפריט הכרטיסיה, כמו לחיצה ימנית על ה-X.
      data: TooltipTheme.of(context).copyWith(
        preferBelow: preferBelow,
        triggerMode: TooltipTriggerMode.manual,
      ),
      child: IconButton(
        tooltip: tooltip,
        // shrinkWrap + padding אפס: בלעדיהם שטח-המגע ברירת-המחדל (48px)
        // גולש בטאב צר.
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        constraints: BoxConstraints.tight(size),
        onPressed: onPressed,
        icon: Icon(FluentIcons.dismiss_24_regular, size: iconSize),
      ),
    );
  }
}

/// הנעץ של כרטיסיה מוצמדת: בתחילת הכרטיסיה, ולחיצה עליו מבטלת את ההצמדה. משותף
/// לרצועה העליונה ולעמודה האנכית (q10 Q14 C).
///
/// IconButton ולא Tooltip סביב אייקון, מאותה סיבה כמו [TabCloseButton]: Tooltip
/// חיצוני מתמזג לצומת הסמנטיקה של הכרטיסיה (issue #1399).
class TabPinButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;

  /// גודל האייקון, שהוא גם גודל הכפתור: הנעץ לא תופס יותר מקום מהאייקון.
  static const double extent = 14;

  const TabPinButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
      constraints: BoxConstraints.tight(const Size.square(extent)),
      onPressed: onPressed,
      icon: const Icon(FluentIcons.pin_24_filled, size: extent),
    );
  }
}

/// כרטיסיה כפקד נגיש: מקבלת פוקוס מקלדת (טבעת פוקוס רק בניווט מקלדת),
/// Enter/רווח בוחרים בה, ולקורא מסך היא כפתור עם מצב "נבחר" ופעולת הקשה.
/// הלחיצה בעכבר נשארת אצל הרצועה ([child]).
class TabActivationRegion extends StatefulWidget {
  final bool selected;
  final VoidCallback onActivate;

  /// השם הנגיש; null = הטקסט שבתוך [child].
  final String? label;
  final Widget child;

  const TabActivationRegion({
    super.key,
    required this.selected,
    required this.onActivate,
    required this.child,
    this.label,
  });

  @override
  State<TabActivationRegion> createState() => _TabActivationRegionState();
}

class _TabActivationRegionState extends State<TabActivationRegion> {
  bool _focusHighlight = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _focusHighlight = value),
      child: Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: widget.label,
        onTap: widget.onActivate,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: _focusHighlight
              ? AppSurfaces.focusRingDecoration(cs)
              : const BoxDecoration(),
          child: widget.child,
        ),
      ),
    );
  }
}

/// צבעי המצב של כרטיסיה, אחד לרצועה האופקית ולאנכית (DD-06).
abstract final class TabStateColors {
  /// הרקע: בחירה מרובה, ואחריה הכרטיסיה הפעילה (בצבע הסרגל). null = שקוף.
  static Color? background(
    BuildContext context, {
    required bool selected,
    required bool inSelection,
  }) {
    if (inSelection) {
      return AppSurfaces.multiSelected(Theme.of(context).colorScheme);
    }
    if (selected) return AppSurfaces.topBarBackground(context);
    return null;
  }

  /// מסגרת הבחירה המרובה.
  static Color? border(BuildContext context, {required bool inSelection}) =>
      inSelection
      ? AppSurfaces.multiSelectedBorder(Theme.of(context).colorScheme)
      : null;

  /// הצללת הריחוף; לא על הכרטיסיה הפעילה.
  static Color? hover(
    BuildContext context, {
    required bool hovered,
    required bool selected,
  }) => hovered && !selected
      ? AppSurfaces.hoverRow(Theme.of(context).colorScheme)
      : null;
}
