/// הצגה מורמת של סימוני-עילית במסך עיון — "אות גבוהה".
///
/// הרקע: fwfh מממש `<sup>` ב-WidgetSpan, ומנוע Flutter משבץ placeholders
/// בפסקת RTL בסדר ויזואלי במקום לוגי — שני סימונים באותה פסקה מוצגים הפוך
/// (ראו `_fixFootnoteMarkers` ב-text_renderer_service.dart). לכן sup פשוט
/// לא-מספרי מומר שם ל-span טקסט טהור, שסדרו מובטח.
///
/// אבל ל-fwfh אין תמיכה ב-`position`/`top` — הן היו no-op גם קודם, ולכן
/// מרקרי הערות הוצגו מוקטנים ונטויים אך יושבים על קו הבסיס, בלי הרמה. וטקסט
/// טהור אינו ניתן להרמה בפריסה בכלל.
///
/// הפתרון כאן משלים את התמונה: הגליפים בשורה נצבעים שקוף (תופסים את המקום
/// הנכון בסדר הנכון, וזמינים לבחירה ולהעתקה), ו-[RaisedMarkerOverlay] מאתר
/// את המלבן האמיתי של כל סימון דרך [RenderParagraph.getBoxesForSelection]
/// ומצייר את אותו טקסט מורם מעליו — אותה תבנית כמו
/// PluginHighlightFrameOverlay.
///
/// גם הסימונים ה*לחיצים* עוברים כאן — סימון הערה מוטמעת (`book-note-marker`)
/// ואות מפרש (`link-anchor`): הספאן בשורה שומר את ה-recognizer ואת אירועי
/// הריחוף שלו, והשכבה מפנה hit-test שנוחת על הציור המורם אל העוגן שבשורה,
/// כך שלחיצה וריחוף עובדים על מה שהעין רואה.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/text_book/utils/link_anchor_variants.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

/// מרקר הערה מסומן (`<sup class="footnote-marker">`) — מוקטן ונטוי.
const String kFootnoteMarkerClass = 'footnote-marker-number';

/// sup חשוף — אות הפניה מקובץ משתמש או superscript תוכני. מוקטן בלי נטייה,
/// באותו יחס שבו `<sup>` הוצג קודם בשלושת מסלולי הרינדור.
const String kRaisedSupClass = 'raised-sup';

/// יחס גודל של מרקר הערה לגופן הטקסט.
const double kFootnoteMarkerScale = 0.75;

/// גובה ההרמה כיחס מגודל גופן *הסימון* — תואם לכוונת `top: -0.55em` המקורית.
const double kRaisedMarkerRaiseFactor = 0.55;

/// סימון מורם אחד: הטקסט הגלוי שלו (כולל תווי בידוד הכיווניות), המופע שלו
/// בטקסט הקטע (בספירת indexOf לא-חופפת — אותה ספירה שמבצעת שכבת הציור),
/// והמטריקות שבהן הוא מוצג.
@immutable
class RaisedMarker {
  final String text;
  final int occurrence;

  /// יחס גודל הגופן ביחס לגופן הטקסט.
  final double scale;

  final bool italic;

  /// סימון לחיץ (עוגן) — hit-test על הציור המורם מופנה לעוגן שבשורה.
  final bool clickable;

  /// מצויר בצבע הקישור (אות מפרש) במקום בצבע הטקסט.
  final bool useLinkColor;

  /// אינדקס הווריאנט הטיפוגרפי של אות מפרש (link-anchor-N), אם יש.
  final int? variantIndex;

  /// אות המפרש שחלונית התצוגה שלה פתוחה — מצוירת מודגשת עם רקע.
  final bool active;

  const RaisedMarker({
    required this.text,
    required this.occurrence,
    required this.scale,
    required this.italic,
    this.clickable = false,
    this.useLinkColor = false,
    this.variantIndex,
    this.active = false,
  });

  @override
  bool operator ==(Object other) =>
      other is RaisedMarker &&
      text == other.text &&
      occurrence == other.occurrence &&
      scale == other.scale &&
      italic == other.italic &&
      clickable == other.clickable &&
      useLinkColor == other.useLinkColor &&
      variantIndex == other.variantIndex &&
      active == other.active;

  @override
  int get hashCode => Object.hash(
    text,
    occurrence,
    scale,
    italic,
    clickable,
    useLinkColor,
    variantIndex,
    active,
  );

  @override
  String toString() =>
      'RaisedMarker("$text"#$occurrence scale:$scale italic:$italic'
      '${clickable ? ' clickable' : ''}'
      '${variantIndex != null ? ' variant:$variantIndex' : ''}'
      '${active ? ' active' : ''})';
}

class RaisedMarkers {
  RaisedMarkers._();

  // אם הדגשת-חיפוש מזריקה span בתוך הסימון, ההתאמה העצלה נעצרת ב-close
  // הפנימי; הטקסט שיחולץ עדיין מכיל את אות הסימון, ולכן האיתור בציור מצליח.
  //
  // שלוש משפחות, כולן בסריקה אחת בסדר המסמך (ספירת המופעים תלויה בסדר):
  //  1+2. שני תגי הסימון של processText.
  //  3.   סימון הערה מוטמעת לחיץ — addInlineNotePreviewLinks פולט בדיוק
  //       `<a class="book-note-marker" href=...>`.
  //  4-6. אות מפרש — injectLinkAnchorMarkers פולט
  //       `class="link-anchor link-anchor-N..."`; הצורה החשופה
  //       `class="link-anchor"` נתפסת גם היא, כי customStylesBuilder צובע
  //       אותה שקוף — אחרת הטקסט היה נעלם. טווח-ציטוט
  //       (`class="link-anchor-range"`) לעולם אינו נתפס ("-" ולא רווח/גרש),
  //       וסמן-מספר מודפס (`numbered-note-marker`) נשאר במקומו בכוונה —
  //       הוא חלק מהטקסט המודפס.
  static final RegExp _markerSpanRegex = RegExp(
    '<span class="($kFootnoteMarkerClass|$kRaisedSupClass)">(.*?)</span>'
    '|<a class="book-note-marker"[^>]*>(.*?)</a>'
    '|<(a|span) class="link-anchor( [^"]*)?"[^>]*>(.*?)</\\4>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _variantIndexRegex = RegExp(r'\blink-anchor-(\d+)\b');
  // עיצוב הסוגריים של processText עוטף תוכן כמו "(א)" ב-<small>; הגליף
  // בשורה מוקטן בהתאם, והציור המורם חייב להתלבש עליו באותו גודל בדיוק.
  static final RegExp _smallTagRegex = RegExp(
    r'<small\b',
    caseSensitive: false,
  );
  static final RegExp _bigTagRegex = RegExp(r'<big\b', caseSensitive: false);
  static final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  /// מחלץ את רשימת הסימונים המורמים מ-HTML מעובד של קטע.
  ///
  /// ה-HTML עצמו אינו משתנה — הסימונים נשארים בשורה (שקופים) כדי לשמור מקום,
  /// סדר, בחירה והעתקה; הרשימה משמשת את שכבת הציור לאיתור ולציור.
  ///
  /// התוצאה נשמרת ב-LRU: הפונקציה נקראת לכל קטע נראה בכל build (גלילה =
  /// עשרות קריאות לפריים), בדיוק כמו המטמון של processText.
  static List<RaisedMarker> extract(String html) {
    if (!html.contains(kFootnoteMarkerClass) &&
        !html.contains(kRaisedSupClass) &&
        !html.contains('book-note-marker') &&
        !html.contains('class="link-anchor')) {
      return const [];
    }

    final cached = _cache.remove(html);
    if (cached != null) {
      _cache[html] = cached;
      return cached;
    }

    final result = _extractUncached(html);

    _cache[html] = result;
    _cacheChars += html.length;
    while (_cacheChars > _cacheMaxChars && _cache.length > 1) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      _cacheChars -= oldestKey.length;
    }

    return result;
  }

  static List<RaisedMarker> _extractUncached(String html) {
    final markers = <RaisedMarker>[];
    // הטקסט הגלוי שנצבר עד כה — לספירת מופעים של כל סימון.
    final visibleSoFar = StringBuffer();
    var index = 0;

    for (final match in _markerSpanRegex.allMatches(html)) {
      visibleSoFar.write(_visibleText(html.substring(index, match.start)));
      index = match.end;

      final String rawContent;
      double scale;
      var italic = false;
      var clickable = false;
      var useLinkColor = false;
      int? variantIndex;
      var active = false;

      if (match[1] != null) {
        // תג סימון של processText — sup שהומר ל-span.
        final isFootnote = match[1]!.toLowerCase() == kFootnoteMarkerClass;
        rawContent = match[2] ?? '';
        scale = isFootnote ? kFootnoteMarkerScale : kHtmlSmallerFontScale;
        italic = isFootnote;
      } else if (match[3] != null) {
        // סימון הערה מוטמעת לחיץ — אותן מטריקות של מרקר הערה, עם הפניית
        // לחיצה/ריחוף לציור המורם.
        rawContent = match[3]!;
        scale = kFootnoteMarkerScale;
        italic = true;
        clickable = true;
      } else {
        // אות מפרש — צבע קישור, וריאנט טיפוגרפי קבוע למפרש, רקע כשפעילה.
        rawContent = match[6] ?? '';
        scale = kLinkAnchorMarkerScale;
        clickable = true;
        useLinkColor = true;
        final extraClasses = match[5] ?? '';
        final variantMatch = _variantIndexRegex.firstMatch(extraClasses);
        final parsedVariant = variantMatch == null
            ? null
            : int.tryParse(variantMatch[1]!);
        if (parsedVariant != null &&
            parsedVariant < kLinkAnchorVariants.length) {
          variantIndex = parsedVariant;
        }
        active = extraClasses.contains('link-anchor-active');
      }

      // תגי small/big שהוזרקו לתוך הסימון (עיצוב סוגריים) מקטינים את הגליף
      // בשורה — הציור מקבל את אותו יחס כדי להתלבש עליו בדיוק.
      final smalls = _smallTagRegex.allMatches(rawContent).length;
      final bigs = _bigTagRegex.allMatches(rawContent).length;
      if (smalls > 0 || bigs > 0) {
        scale *=
            math.pow(kHtmlSmallerFontScale, smalls) *
            math.pow(kHtmlLargerFontScale, bigs);
      }

      // תווי הבידוד (LRI/RLI/PDI) הם חלק מהטקסט הגלוי — נשארים בתבנית, וגם
      // הופכים אותה לייחודית יותר מול טקסט הגוף.
      final markerText = _visibleText(rawContent);
      final visibleBefore = visibleSoFar.toString();
      visibleSoFar.write(markerText);

      if (markerText.trim().isEmpty) continue;

      markers.add(
        RaisedMarker(
          text: markerText,
          occurrence: _countOccurrences(visibleBefore, markerText) + 1,
          scale: scale,
          italic: italic,
          clickable: clickable,
          useLinkColor: useLinkColor,
          variantIndex: variantIndex,
          active: active,
        ),
      );
    }

    if (markers.isEmpty) return const [];
    return List.unmodifiable(markers);
  }

  /// טקסט גלוי: בלי תגים ועם רצפי רווחים מכווצים — אותם כללי נרמול שחלים על
  /// הטקסט בפריסה, כך שספירת המופעים תואמת את מה שמוצג.
  static String _visibleText(String html) {
    final withoutTags = html.replaceAll(_htmlTagRegex, '');
    final decoded = withoutTags.contains('&')
        ? html_parser.parseFragment(withoutTags).text ?? withoutTags
        : withoutTags;
    return decoded.replaceAll(_whitespaceRegex, ' ');
  }

  /// ספירת מופעים לא-חופפת — חייבת להישאר זהה ללולאת האיתור שבשכבת הציור.
  static int _countOccurrences(String text, String pattern) {
    if (pattern.isEmpty) return 0;
    var count = 0;
    var from = 0;
    while (true) {
      final idx = text.indexOf(pattern, from);
      if (idx < 0) return count;
      count++;
      from = idx + pattern.length;
    }
  }

  static final LinkedHashMap<String, List<RaisedMarker>> _cache =
      LinkedHashMap<String, List<RaisedMarker>>();
  static int _cacheChars = 0;
  static const int _cacheMaxChars = 1024 * 1024;

  @visibleForTesting
  static void clearCacheForTesting() {
    _cache.clear();
    _cacheChars = 0;
  }
}

/// שכבת הציור: עוטפת את ווידג'ט הטקסט ומציירת כל סימון מורם מעל המלבן
/// שהגליפים השקופים שלו תופסים בשורה.
class RaisedMarkerOverlay extends SingleChildRenderObjectWidget {
  final List<RaisedMarker> markers;

  /// סגנון הטקסט של הקטע. הסגנון של כל סימון נגזר ממנו לפי
  /// [RaisedMarker.scale] ו-[RaisedMarker.italic], כך שהציור מתלבש בדיוק על
  /// הגליפים השקופים שבשורה.
  final TextStyle baseStyle;

  /// צבע הציור של סימון עם [RaisedMarker.useLinkColor] (אות מפרש).
  /// null — נופל לצבע הטקסט.
  final Color? linkColor;

  /// רקע הציור של אות מפרש פעילה ([RaisedMarker.active]).
  final Color? activeBackground;

  /// צבע האות הפעילה; ברירת המחדל היא onPrimaryContainer.
  final Color? activeForeground;

  const RaisedMarkerOverlay({
    super.key,
    required this.markers,
    required this.baseStyle,
    this.linkColor,
    this.activeBackground,
    this.activeForeground,
    required super.child,
  });

  /// נקודת הכניסה האחידה לכל תצוגת טקסט: עוטף את [child] בשכבת הסימונים אם
  /// יש כאלה, ומשלים צבע טקסט מהסביבה כש-[baseStyle] בא בלעדיו. כל מסלול
  /// רינדור חדש שמציג טקסט ספר צריך לקרוא לזה — לא לבנות עטיפה משלו.
  ///
  /// [linkColor] ו-[activeBackground] — צבעי אותיות המפרשים; כשאינם מסופקים
  /// נגזרים מערכת הנושא (primary / primaryContainer), כמו ב-SmartTextWidget.
  static Widget wrap({
    required BuildContext context,
    required List<RaisedMarker> markers,
    required TextStyle baseStyle,
    required Widget child,
    Color? linkColor,
    Color? activeBackground,
    Color? activeForeground,
  }) {
    if (markers.isEmpty) return child;
    final colorScheme = Theme.of(context).colorScheme;
    final style = baseStyle.color != null
        ? baseStyle
        : baseStyle.copyWith(
            color:
                DefaultTextStyle.of(context).style.color ??
                colorScheme.onSurface,
          );
    return RaisedMarkerOverlay(
      markers: markers,
      baseStyle: style,
      linkColor: linkColor ?? colorScheme.primary,
      activeBackground: activeBackground ?? colorScheme.primaryContainer,
      activeForeground: activeForeground ?? colorScheme.onPrimaryContainer,
      child: child,
    );
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderRaisedMarkerOverlay(
        markers,
        baseStyle,
        linkColor,
        activeBackground,
        activeForeground,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderRaisedMarkerOverlay renderObject,
  ) {
    renderObject
      ..markers = markers
      ..baseStyle = baseStyle
      ..linkColor = linkColor
      ..activeBackground = activeBackground
      ..activeForeground = activeForeground;
  }
}

/// מיקום מחושב של סימון אחד — חשוף לצורכי בדיקות.
@immutable
class RaisedMarkerPlacement {
  /// המלבן שהגליפים השקופים תופסים בשורה (בקואורדינטות של השכבה).
  final Rect anchorRect;

  /// המלבן שבו הסימון מצויר בפועל — מורם מעל [anchorRect].
  final Rect paintRect;

  final RaisedMarker marker;

  const RaisedMarkerPlacement({
    required this.anchorRect,
    required this.paintRect,
    required this.marker,
  });

  String get text => marker.text;
}

class RenderRaisedMarkerOverlay extends RenderProxyBox {
  RenderRaisedMarkerOverlay(
    this._markers,
    this._baseStyle,
    this._linkColor,
    this._activeBackground,
    this._activeForeground,
  ) : _hasClickableMarkers = _markers.any((marker) => marker.clickable);

  List<RaisedMarker> _markers;
  TextStyle _baseStyle;
  Color? _linkColor;
  Color? _activeBackground;
  Color? _activeForeground;

  // מחושב פעם אחת: קטע בלי סימונים לחיצים לא משלם דבר על hit-test.
  bool _hasClickableMarkers;

  // TextPainter לכל (טקסט, מטריקות), ממוזג בין פריימים; מתאפס עם שינוי סגנון.
  final Map<String, TextPainter> _painters = <String, TextPainter>{};

  // המיקומים המחושבים, ממוזגים בין פריימים. האיתור עצמו יקר (toPlainText לכל
  // פסקה + חיפוש לכל סימון), והוא תלוי אך ורק בפריסה — לכן הוא לא רץ שוב בכל
  // פריים ציור. גלילה מזיזה את ה-RenderObject בלי פריסה מחדש, ומיקומי הסימונים
  // מוחזקים ביחס לשכבה עצמה, ולכן הם נשארים תקפים.
  List<RaisedMarkerPlacement>? _placements;
  List<Object?>? _placementsSignature;

  set markers(List<RaisedMarker> value) {
    if (listEquals(value, _markers)) return;
    _markers = value;
    _hasClickableMarkers = value.any((marker) => marker.clickable);
    _invalidatePlacements();
    markNeedsPaint();
  }

  set baseStyle(TextStyle value) {
    if (value == _baseStyle) return;
    _baseStyle = value;
    _disposePainters();
    _invalidatePlacements();
    markNeedsPaint();
  }

  // צבע משנה רק את הציור, לא את המטריקות — המיקומים נשארים תקפים.
  set linkColor(Color? value) {
    if (value == _linkColor) return;
    _linkColor = value;
    _disposePainters();
    markNeedsPaint();
  }

  set activeBackground(Color? value) {
    if (value == _activeBackground) return;
    _activeBackground = value;
    _disposePainters();
    markNeedsPaint();
  }

  set activeForeground(Color? value) {
    if (value == _activeForeground) return;
    _activeForeground = value;
    _disposePainters();
    markNeedsPaint();
  }

  void _invalidatePlacements() {
    _placements = null;
    _placementsSignature = null;
  }

  @override
  void performLayout() {
    super.performLayout();
    _invalidatePlacements();
  }

  void _disposePainters() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }

  @override
  void dispose() {
    _disposePainters();
    super.dispose();
  }

  double _fontSizeOf(RaisedMarker marker) =>
      (_baseStyle.fontSize ?? 18.0) * marker.scale;

  TextPainter _painterFor(RaisedMarker marker) {
    final key =
        '${marker.scale}|${marker.italic}|${marker.useLinkColor}'
        '|${marker.variantIndex}|${marker.active}|${marker.text}';
    return _painters.putIfAbsent(key, () {
      var style = _baseStyle.copyWith(
        fontSize: _fontSizeOf(marker),
        fontStyle: marker.italic ? FontStyle.italic : FontStyle.normal,
        height: 1.0,
      );
      // אות מפרש: הווריאנט הטיפוגרפי של המפרש, צבע הקישור, והדגשה עם רקע
      // כשחלונית התצוגה שלה פתוחה — אותו מראה שהיה לגליף לפני שהוסתר.
      final variantIndex = marker.variantIndex;
      if (variantIndex != null) {
        style = applyLinkAnchorVariant(
          kLinkAnchorVariants[variantIndex],
          style,
        );
      }
      if (marker.useLinkColor && _linkColor != null) {
        style = style.copyWith(color: _linkColor);
      }
      if (marker.active && _activeBackground != null) {
        style = style.copyWith(
          fontWeight: FontWeight.bold,
          fontVariations: AppFonts.boldFontVariations(style.fontFamily),
          backgroundColor: _activeBackground,
          color: _activeForeground ?? style.color,
        );
      } else if (marker.active) {
        style = style.copyWith(
          fontWeight: FontWeight.bold,
          fontVariations: AppFonts.boldFontVariations(style.fontFamily),
        );
      }
      final painter = TextPainter(
        text: TextSpan(text: marker.text, style: style),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      );
      painter.layout();
      return painter;
    });
  }

  /// לחיצה/ריחוף שנוחתים על ציור מורם של סימון לחיץ מופנים לעוגן שבשורה —
  /// כך ה-recognizer, תצוגת הריחוף וסמן העכבר של הספאן עובדים על מה שהעין
  /// רואה. ההפניה נרשמת כטרנספורם כדי שגם localPosition של האירועים יתאים.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (child != null && _hasClickableMarkers) {
      for (final placement in _resolvePlacements()) {
        if (!placement.marker.clickable) continue;
        if (!placement.paintRect.contains(position)) continue;
        // בתחום החפיפה עם העוגן עצמו הפגיעה הטבעית ממילא נכונה.
        if (placement.anchorRect.contains(position)) break;
        final target = placement.anchorRect.center;
        return result.addWithRawTransform(
          transform: Matrix4.translationValues(
            target.dx - position.dx,
            target.dy - position.dy,
            0,
          ),
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) =>
              super.hitTest(result, position: transformed),
        );
      }
    }
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (child == null || _markers.isEmpty) return;
    for (final placement in _resolvePlacements()) {
      _painterFor(
        placement.marker,
      ).paint(context.canvas, offset + placement.paintRect.topLeft);
    }
  }

  /// מחזיר את המיקומים מהמטמון, ומחשב מחדש רק כשהפריסה בפועל השתנתה.
  ///
  /// [performLayout] מנקה את המטמון, אבל פסקה פנימית יכולה להתפרס מחדש בלי
  /// שהפריסה של השכבה תרוץ (relayout boundary). לכן נבנית כאן חתימה זולה —
  /// זהות הפסקאות, ההיסט, הגודל, ואובייקט הטקסט — והחישוב היקר רץ רק כשהיא
  /// משתנה. הליכה על העץ היא O(צמתים) ולא נוגעת בטקסט עצמו.
  List<RaisedMarkerPlacement> _resolvePlacements() {
    final paragraphs = _collectParagraphs();
    final signature = <Object?>[];
    for (final info in paragraphs) {
      signature
        ..add(info.paragraph)
        ..add(info.offset)
        ..add(info.paragraph.size)
        ..add(info.paragraph.text);
    }

    final cached = _placements;
    if (cached != null && listEquals(_placementsSignature, signature)) {
      return cached;
    }

    final computed = _computePlacements(paragraphs);
    _placements = computed;
    _placementsSignature = signature;
    return computed;
  }

  /// אוסף את כל ה-RenderParagraph-ים שמתחת לשכבה, בסדר המסמך. זול בכוונה —
  /// בלי לגעת בטקסט — כדי שיוכל לרוץ בכל פריים ציור לצורך בדיקת החתימה.
  List<_ParagraphInfo> _collectParagraphs() {
    final paragraphs = <_ParagraphInfo>[];
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        if (object.attached && object.hasSize) {
          paragraphs.add(
            _ParagraphInfo(
              paragraph: object,
              offset: object.localToGlobal(Offset.zero, ancestor: this),
            ),
          );
        }
        return;
      }
      object.visitChildren(visit);
    }

    visit(child!);
    return paragraphs;
  }

  /// מיקומי כל הסימונים ביחס לפינת השכבה.
  ///
  /// מאחד את הטקסט הגלוי של הפסקאות עם '\n' כמפריד (מונע התאמה שחוצה
  /// פסקאות), מאתר את המופע ה-n של כל סימון באותה ספירת indexOf שביצע
  /// החילוץ, וממפה למלבני הפריסה. אינדקסים של indexOf הם UTF-16 — בדיוק
  /// היחידות ש-getBoxesForSelection מצפה להן.
  List<RaisedMarkerPlacement> _computePlacements(
    List<_ParagraphInfo> paragraphs,
  ) {
    if (paragraphs.isEmpty) return const [];

    final joined = StringBuffer();
    final paragraphStarts = <int>[];
    for (final info in paragraphs) {
      paragraphStarts.add(joined.length);
      joined.write(_plainTextOf(info.paragraph));
      joined.write('\n');
    }
    final joinedText = joined.toString();

    final placements = <RaisedMarkerPlacement>[];
    for (final marker in _markers) {
      final globalIndex = _nthOccurrence(
        joinedText,
        marker.text,
        marker.occurrence,
      );
      if (globalIndex < 0) continue;

      // הפסקה שההתאמה בתוכה ('\n' מבטיח שההתאמה לא חוצה פסקאות).
      var paragraphIndex = paragraphStarts.length - 1;
      while (paragraphIndex > 0 &&
          paragraphStarts[paragraphIndex] > globalIndex) {
        paragraphIndex--;
      }
      final info = paragraphs[paragraphIndex];
      final localStart = globalIndex - paragraphStarts[paragraphIndex];

      final boxes = info.paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: localStart,
          extentOffset: localStart + marker.text.length,
        ),
      );
      if (boxes.isEmpty) continue;

      // סימון כמעט תמיד בשורה אחת; אם נשבר, נצמדים לחלק שבשורה הראשונה.
      final firstTop = boxes.first.top;
      var anchorRect = boxes.first.toRect();
      for (final box in boxes.skip(1)) {
        if ((box.top - firstTop).abs() > 2) break;
        anchorRect = anchorRect.expandToInclude(box.toRect());
      }
      anchorRect = anchorRect.shift(info.offset);

      final painter = _painterFor(marker);
      final raise = _fontSizeOf(marker) * kRaisedMarkerRaiseFactor;
      // ממורכז אופקית על העוגן; אנכית — מורם, עם הצמדה לגבול העליון של
      // השכבה כדי לא להיחתך בשורה הראשונה.
      final dx = anchorRect.center.dx - painter.width / 2;
      final dy = math.max(0.0, anchorRect.top - raise);

      placements.add(
        RaisedMarkerPlacement(
          anchorRect: anchorRect,
          paintRect: Rect.fromLTWH(dx, dy, painter.width, painter.height),
          marker: marker,
        ),
      );
    }
    return placements;
  }

  static int _nthOccurrence(String text, String pattern, int n) {
    if (pattern.isEmpty || n < 1) return -1;
    var from = 0;
    for (var i = 0; i < n; i++) {
      final idx = text.indexOf(pattern, from);
      if (idx < 0) return -1;
      if (i == n - 1) return idx;
      from = idx + pattern.length;
    }
    return -1;
  }

  @visibleForTesting
  List<RaisedMarkerPlacement> debugPlacements() => _resolvePlacements();
}

class _ParagraphInfo {
  final RenderParagraph paragraph;
  final Offset offset;

  _ParagraphInfo({required this.paragraph, required this.offset});
}

/// `toPlainText` בונה את המחרוזת מחדש בכל קריאה בהליכה על עץ הספאנים. הטקסט
/// נגזר מאובייקט הספאן, ולכן ממוזג לפיו — ה-Expando משתחרר עם ה-GC כשהספאן
/// מוחלף בבנייה מחדש.
final Expando<String> _plainTextCache = Expando<String>('raisedMarkerText');

String _plainTextOf(RenderParagraph paragraph) {
  final span = paragraph.text;
  final cached = _plainTextCache[span];
  if (cached != null) return cached;
  final text = span.toPlainText();
  _plainTextCache[span] = text;
  return text;
}
