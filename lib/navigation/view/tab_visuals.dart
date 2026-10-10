import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';

/// אייקון סוג הכרטיסיה — משותף לעמודה האנכית ולחלונית חיפוש הכרטיסיות.
///
/// מחזיר `null` לכרטיסיית טקסט רגילה, שאין לה אייקון ייעודי.
Widget? buildTabTypeIcon(
  BuildContext context,
  OpenedTab tab, {
  double size = 16,
  Color? color,
}) {
  final resolved = color ?? Theme.of(context).colorScheme.onSurface;
  if (tab is PdfBookTab) {
    return Icon(
      FluentIcons.document_pdf_16_regular,
      size: size,
      color: resolved,
    );
  }
  if (tab is SearchingTab) {
    return Icon(FluentIcons.search_24_regular, size: size, color: resolved);
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
  if (tab is PdfBookTab) return FluentIcons.document_pdf_16_regular;
  if (tab is SearchingTab) return FluentIcons.search_24_regular;
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
    return Tooltip(message: message, child: child);
  }

  @override
  Widget build(BuildContext context) {
    if (alwaysShow) return Tooltip(message: message, child: child);
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
