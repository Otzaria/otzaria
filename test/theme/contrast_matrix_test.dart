// מטריצת ניגודיות: כל זוגות הצבעים שהממשק מציב אחד מול השני,
// על כל 14 זרעי הצבע × בהיר/כהה, מול סף WCAG: 4.5 לטקסט רגיל, 3 לאייקונים,
// לטקסט גדול ולגבול רכיב.
//
// הבדיקה נועלת את המצב של היום ולא מתקנת אותו:
//  - צירוף שחורג ואינו ב-[_knownExceptions] מכשיל, כלומר החמרה נתפסת;
//  - צירוף שנמצא ב-[_knownExceptions] ועובר היום מכשיל, כלומר חריג שנפתר חייב
//    להימחק מהרשימה, וכך הרשימה לא מצטברת בלי שמישהו מבחין.
// אין להחליש סף ואין להרחיב את הרשימה כדי להעביר בדיקה: חריג חדש הוא באג בצבע
// או החלטה, ומתועד בממצא.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// הצבעים של זרע אחד בבהירות אחת, כפי שהאפליקציה בונה אותם.
class _Palette {
  _Palette(this.seed, this.brightness)
    : cs = AppThemeData.createColorScheme(seed, brightness),
      variant = AppThemeVariant.ofSeed(seed) {
    s = AppSurfaceColors.fromScheme(cs, variant: variant);
  }

  final Color seed;
  final Brightness brightness;
  final ColorScheme cs;
  final AppThemeVariant variant;
  late final AppSurfaceColors s;

  bool get dark => brightness == Brightness.dark;

  String get key => '${AppSeedColors.nameOf(seed)} ${dark ? 'כהה' : 'בהיר'}';

  /// צבע שקוף על רקע: התוצאה האטומה שהמשתמש רואה.
  Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

  /// בחירת טקסט כפי שהערכה קובעת אותה (`textSelectionTheme`).
  Color get selection => AppThemeData.light(
    cs,
    compactMenuMode: false,
    variant: variant,
  ).textSelectionTheme.selectionColor!;
}

typedef _Pick = Color Function(_Palette p);

class _Pair {
  const _Pair(this.id, this.what, this.fg, this.bg, this.min);

  /// מזהה יציב לרשימת החריגים.
  final String id;
  final String what;

  /// הצבע הקדמי. אם הוא שקוף הוא מוטבע על [bg] לפני החישוב.
  final _Pick fg;
  final _Pick bg;
  final double min;
}

const double _text = 4.5;
const double _large = 3.0;

// ── הרקעים שטקסט וכפתורים יושבים עליהם ──
Color _reader(_Palette p) => p.s.readerBackground;
Color _panel(_Palette p) => p.s.panelBackground;
Color _card(_Palette p) => p.s.card;
Color _topBar(_Palette p) => p.s.topBarBackground;
Color _navPanel(_Palette p) => p.s.navPanelBackground;
// דיאלוג, תפריט ו-tooltip.
Color _dialog(_Palette p) => p.cs.surfaceContainerHigh;

final List<_Pair> _pairs = [
  // טקסט ראשי ומשני מול כל משטח.
  for (final (name, bg) in <(String, _Pick)>[
    ('קריאה', _reader),
    ('לוח', _panel),
    ('כרטיס', _card),
    ('סרגל עליון', _topBar),
    ('חלונית ניווט', _navPanel),
    ('דיאלוג/תפריט', _dialog),
  ]) ...[
    _Pair(
      'onSurface/$name',
      'טקסט ראשי על $name',
      (p) => p.cs.onSurface,
      bg,
      _text,
    ),
    _Pair(
      'onSurfaceVariant/$name',
      'טקסט משני על $name',
      (p) => p.cs.onSurfaceVariant,
      bg,
      _text,
    ),
    // כפתור טקסט, קישור ואייקון בצבע הערכה.
    _Pair(
      'primary/$name',
      'primary (כפתור טקסט, אייקון) על $name',
      (p) => p.cs.primary,
      bg,
      _text,
    ),
    // טבעת הפוקוס היא רכיב ממשק: 3:1.
    _Pair(
      'focusRing/$name',
      'טבעת פוקוס (primary) על $name',
      (p) => p.cs.primary,
      bg,
      _large,
    ),
    // גבול שדה וכרטיס שמזהה את הרכיב.
    _Pair(
      'outline/$name',
      'גבול (outline) על $name',
      (p) => p.cs.outline,
      bg,
      _large,
    ),
  ],

  // onX מול X.
  _Pair(
    'onPrimary/primary',
    'כפתור מלא',
    (p) => p.cs.onPrimary,
    (p) => p.cs.primary,
    _text,
  ),
  _Pair(
    'onPrimaryContainer/primaryContainer',
    'בחירה מרובה, צ\'יפ מודגש',
    (p) => p.cs.onPrimaryContainer,
    (p) => p.cs.primaryContainer,
    _text,
  ),
  _Pair(
    'onSecondaryContainer/secondaryContainer',
    'שורה נבחרת',
    (p) => p.cs.onSecondaryContainer,
    (p) => p.cs.secondaryContainer,
    _text,
  ),
  _Pair(
    'onTertiaryContainer/tertiaryContainer',
    'משטח משני מודגש',
    (p) => p.cs.onTertiaryContainer,
    (p) => p.cs.tertiaryContainer,
    _text,
  ),
  _Pair(
    'onError/error',
    'כפתור הרסני מלא',
    (p) => p.cs.onError,
    (p) => p.cs.error,
    _text,
  ),
  _Pair(
    'onErrorContainer/errorContainer',
    'באנר שגיאה',
    (p) => p.cs.onErrorContainer,
    (p) => p.cs.errorContainer,
    _text,
  ),
  _Pair(
    'onWarning/warning',
    'כפתור אזהרה',
    (p) => p.s.onWarning,
    (p) => p.s.warning,
    _text,
  ),
  _Pair(
    'onWarningContainer/warningContainer',
    'באנר אזהרה',
    (p) => p.s.onWarningContainer,
    (p) => p.s.warningContainer,
    _text,
  ),

  // צבעי שגיאה כטקסט על משטחים.
  _Pair(
    'error/קריאה',
    'טקסט שגיאה על קריאה',
    (p) => p.cs.error,
    _reader,
    _text,
  ),
  _Pair('error/כרטיס', 'טקסט שגיאה על כרטיס', (p) => p.cs.error, _card, _text),
  _Pair(
    'error/errorContainer',
    'פעולה בהודעת שגיאה (UiSnack)',
    (p) => p.cs.error,
    (p) => p.cs.errorContainer,
    _text,
  ),
  _Pair(
    'warning/warningContainer',
    'אייקון אזהרה על באנר',
    (p) => p.s.warning,
    (p) => p.s.warningContainer,
    _large,
  ),

  // באנרים והודעות.
  _Pair(
    'banner-info',
    'AppInfoBanner (info)',
    (p) => p.cs.onSurface,
    (p) => p.cs.surfaceContainerHighest,
    _text,
  ),
  _Pair(
    'snack-action',
    'פעולה בהודעה (primary)',
    (p) => p.cs.primary,
    (p) => p.cs.surfaceContainerHighest,
    _text,
  ),

  // מצבים: טקסט מעל שכבת ריחוף ופוקוס.
  _Pair(
    'hover/card',
    'טקסט על שורה בריחוף (כרטיס)',
    (p) => p.cs.onSurface,
    (p) => p.over(AppSurfaces.hoverRow(p.cs), _card(p)),
    _text,
  ),
  _Pair(
    'hover/panel',
    'טקסט על שורה בריחוף (לוח)',
    (p) => p.cs.onSurface,
    (p) => p.over(AppSurfaces.hoverRow(p.cs), _panel(p)),
    _text,
  ),
  _Pair(
    'focusedRow/card',
    'טקסט על שורה בפוקוס מקלדת',
    (p) => p.cs.onSurface,
    (p) => p.over(AppSurfaces.focusedRow(p.cs), _card(p)),
    _text,
  ),
  _Pair(
    'primary/selectedRow',
    'primary על שורה נבחרת (טבעת פוקוס)',
    (p) => p.cs.primary,
    (p) => AppSurfaces.selectedRow(p.cs),
    _large,
  ),
  _Pair(
    'primary/hover',
    'כפתור טקסט בריחוף',
    (p) => p.cs.primary,
    (p) => p.over(p.cs.primary.withValues(alpha: 0.08), _panel(p)),
    _text,
  ),
  _Pair(
    'barButtonSelected',
    'כפתור סרגל נבחר',
    (p) => p.cs.onSurface,
    (p) => p.over(AppSurfaces.barButtonSelected(p.cs), _topBar(p)),
    _text,
  ),
  _Pair(
    'multiSelected',
    'כרטיסייה בבחירה מרובה',
    (p) => p.cs.onPrimaryContainer,
    (p) => AppSurfaces.multiSelected(p.cs),
    _text,
  ),
  _Pair(
    'multiSelectedBorder',
    'מסגרת בחירה מרובה',
    (p) => AppSurfaces.multiSelectedBorder(p.cs),
    _card,
    _large,
  ),

  // שדות: טקסט, רמז ומילוי.
  _Pair(
    'field/text',
    'טקסט בשדה (מילוי כרטיס)',
    (p) => p.cs.onSurface,
    _card,
    _text,
  ),
  _Pair(
    'field/hint',
    'רמז בשדה (onSurfaceVariant)',
    (p) => p.cs.onSurfaceVariant,
    _card,
    _text,
  ),
  _Pair(
    'field/fill-text',
    'טקסט בשדה (מילוי surfaceContainerHighest)',
    (p) => p.cs.onSurface,
    (p) => p.cs.surfaceContainerHighest,
    _text,
  ),
  _Pair(
    'field/fill-hint',
    'רמז בשדה (מילוי surfaceContainerHighest)',
    (p) => p.cs.onSurfaceVariant,
    (p) => p.cs.surfaceContainerHighest,
    _text,
  ),

  // בחירת טקסט: הטקסט מעל מילוי הבחירה, מעל רקע הקריאה והכרטיס.
  _Pair(
    'selection/קריאה',
    'בחירת טקסט בקריאה',
    (p) => p.cs.onSurface,
    (p) => p.over(p.selection, _reader(p)),
    _text,
  ),
  _Pair(
    'selection/כרטיס',
    'בחירת טקסט בכרטיס',
    (p) => p.cs.onSurface,
    (p) => p.over(p.selection, _card(p)),
    _text,
  ),

  // פס הגלילה במנוחה וסימן השורה הקשורה: רכיבי ממשק, 3:1 (WCAG 1.4.11).
  for (final (name, bg) in <(String, _Pick)>[
    ('קריאה', _reader),
    ('לוח', _panel),
    ('כרטיס', _card),
  ])
    _Pair(
      'scrollbarThumb/$name',
      'פס גלילה במנוחה על $name',
      (p) => AppSurfaces.scrollbarThumb(p.cs, isDragging: false),
      bg,
      _large,
    ),
  for (final (name, bg) in <(String, _Pick)>[
    ('קריאה', _reader),
    ('כרטיס', _card),
  ])
    _Pair(
      'relatedLineMarker/$name',
      'סימן שורה קשורה על $name',
      (p) => AppSurfaces.relatedLineMarker(p.cs),
      bg,
      _large,
    ),

  // סימון חיפוש והדגשות בטקסט הספר.
  _Pair(
    'searchHit/קריאה',
    'מילת חיפוש בטקסט',
    (p) => AppSurfaces.searchHit(p.cs),
    _reader,
    _text,
  ),
  _Pair(
    'searchHitCurrent',
    'התוצאה הנוכחית',
    (p) => AppSurfaces.searchHitCurrent(p.cs),
    (p) => p.over(AppSurfaces.searchHitCurrentBackground(p.cs), _reader(p)),
    _text,
  ),
  _Pair(
    'permanentMark',
    'סימון קבוע בטקסט',
    (p) => AppSurfaces.onPermanentMark(p.cs),
    (p) => p.over(AppSurfaces.permanentMark(p.cs), _reader(p)),
    _text,
  ),
  _Pair(
    'highlightedLine',
    'שורה שהודגשה במעבר',
    (p) => p.cs.onSurface,
    (p) => p.over(AppSurfaces.highlightedLineBackground(p.cs), _reader(p)),
    _text,
  ),
  _Pair(
    'semanticPassage',
    'קטע שהחיפוש החכם סימן',
    (p) => p.cs.onSurface,
    (p) => p.over(AppSurfaces.semanticPassageHighlight(p.cs), _reader(p)),
    _text,
  ),

  // קישורי ספר.
  _Pair(
    'readerLink/קריאה',
    'קישור בטקסט הספר',
    (p) => AppSurfaces.readerLink(p.cs),
    _reader,
    _text,
  ),
  _Pair(
    'readerLink/כרטיס',
    'קישור בכרטיס',
    (p) => AppSurfaces.readerLink(p.cs),
    _card,
    _text,
  ),
];

/// חריגים ידועים: `'<זוג>|<זרע ובהירות>'` ← תווית החריג.
///
/// הערך הוא הסיבה, לא פטור: כל שורה היא חוב צבע שמחכה להכרעה. תיקון שמחסל
/// חריג מכשיל את הבדיקה עד שהשורה נמחקת.
const Map<String, String> _knownExceptions = {
  // שולי: primary של "פרגמנט" בבהיר על surfaceContainerHighest,
  // כמו פעולה בהודעה (UiSnack): 4.48 מול 4.5. נמדד כאן, לא היה בדוח כחריג.
  "snack-action|פרגמנט / בז' בהיר": 'snack-action-contrast',
};

String _fmt(double v) => v.toStringAsFixed(2);

double _ratio(Color fg, Color bg) {
  final f = fg.computeLuminance() + 0.05;
  final b = bg.computeLuminance() + 0.05;
  return f > b ? f / b : b / f;
}

void main() {
  final palettes = [
    for (final option in AppSeedColors.options)
      for (final brightness in Brightness.values)
        _Palette(option.color, brightness),
  ];

  test('הרשימה מכסה את כל הזרעים בשתי הבהירויות', () {
    expect(palettes.length, AppSeedColors.options.length * 2);
    expect(_pairs.length, greaterThan(50));
    final ids = _pairs.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'מזהה זוג כפול');
  });

  test('כל זוגות הצבעים עוברים את סף WCAG, חוץ מהחריגים הידועים', () {
    final newFailures = <String>[];
    final resolvedExceptions = <String>[];
    final seenExceptions = <String>{};
    for (final pair in _pairs) {
      for (final p in palettes) {
        final bg = pair.bg(p);
        final fg = pair.fg(p);
        final effective = fg.a < 1 ? p.over(fg, bg) : fg;
        final ratio = _ratio(effective, bg);
        final key = '${pair.id}|${p.key}';
        final known = _knownExceptions[key];
        if (ratio < pair.min) {
          if (known == null) {
            newFailures.add(
              '$key: ${pair.what} ${_fmt(ratio)}:1 < ${_fmt(pair.min)}:1',
            );
          } else {
            seenExceptions.add(key);
          }
        } else if (known != null) {
          resolvedExceptions.add(
            '$key ($known) עובר עכשיו עם ${_fmt(ratio)}:1: למחוק מהרשימה',
          );
        }
      }
    }
    final stale = _knownExceptions.keys
        .where((k) => !seenExceptions.contains(k))
        .where((k) => !resolvedExceptions.any((r) => r.startsWith(k)))
        .toList();
    expect(
      newFailures,
      isEmpty,
      reason: 'צירופים שחורגים מהסף ואינם ברשימת החריגים הידועים',
    );
    expect(resolvedExceptions, isEmpty, reason: 'חריגים שנפתרו');
    expect(stale, isEmpty, reason: 'מפתח בחריגים שלא קיים במטריצה');
  });
}
