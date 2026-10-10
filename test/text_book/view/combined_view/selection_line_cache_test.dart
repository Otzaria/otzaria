import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// חלון הבחירה נבנה מחדש בכל תזוזת עכבר בגרירה; המטמון חוסך את רינדור
/// השורות החוזר בלי לשנות את התוצאה.
void main() {
  final data = List.generate(
    2100,
    (i) => '<b>וַיֹּאמֶר</b> אֱלֹהִים, יְהִי אוֹר; וַיְהִי־אוֹר. שורה $i',
  );
  const settings = RenderSettings(removeNikud: true);
  final visible = List.generate(30, (i) => 200 + i);

  String Function(int) textOf(SelectionLine Function(int) lines) =>
      (i) => lines(i).text;

  SelectionWindow window(String Function(int) renderLine) =>
      buildSelectionWindow(
        visibleIndices: visible,
        totalLines: data.length,
        selectionLength: 300,
        renderLine: renderLine,
      );

  test('עדכוני בחירה חוזרים מקבלים את אותן שורות בלי לרנדר מחדש', () {
    final cache = SelectionLineCache();

    final first = window(textOf(cache.lines(data, settings)));
    final again = window(textOf(cache.lines(data, settings)));

    for (var i = 0; i < first.lines.length; i++) {
      expect(identical(again.lines[i], first.lines[i]), isTrue);
    }
  });

  test('טעינת ציונים ושינוי פרופיל מבטלים את המטמון', () {
    final data = ['שלום'];
    final links = <int, Object>{};
    final cache = SelectionLineCache();
    expect(
      cache.lines(data, settings, markerKey: (links, true, null))(0).text,
      'שלום',
    );
    final loadedLinks = {1: Object()};
    String inject(String raw, int index) =>
        '<a class="link-anchor link-anchor-0">(א)</a>$raw';
    expect(
      cache
          .lines(
            data,
            settings,
            injectMarkers: inject,
            markerKey: (loadedLinks, true, null),
          )(0)
          .text,
      '(א)שלום',
    );
    expect(
      cache
          .lines(data, settings, markerKey: (loadedLinks, false, null))(0)
          .text,
      'שלום',
    );
    expect(
      cache
          .lines(
            data,
            settings,
            injectMarkers: inject,
            markerKey: (loadedLinks, true, null),
          )(0)
          .markers,
      [(0, 3)],
    );
    expect(
      cache
          .lines(
            data,
            settings,
            markerKey: (loadedLinks, true, 'מהדורה חלופית'),
          )(0)
          .text,
      'שלום',
    );
  });

  test('closure חדש ומפתח ציונים זהה שומרים את המטמון חם', () {
    final data = ['שלום'];
    final links = {1: Object()};
    final cache = SelectionLineCache();
    var renders = 0;
    SelectionLine Function(int) render() => cache.lines(
      data,
      settings,
      markerKey: (links, true, null),
      injectMarkers: (raw, index) {
        renders++;
        return '<a class="link-anchor link-anchor-0">(א)</a>$raw';
      },
    );
    final first = render()(0);
    final again = render()(0);
    expect(renders, 1);
    expect(identical(first, again), isTrue);
    cache.clear();
    final afterClear = render()(0);
    expect(afterClear.text, first.text);
    expect(afterClear.markers, first.markers);
    expect(renders, 2);
  });

  test('התוצאה זהה לרינדור ללא מטמון', () {
    final cache = SelectionLineCache();
    String direct(int i) =>
        renderSelectionLine(rawText: data[i], settings: settings);

    final expected = window(direct);
    final cachedFirst = window(textOf(cache.lines(data, settings)));
    final cachedAgain = window(textOf(cache.lines(data, settings)));

    expect(cachedFirst.baseIndex, expected.baseIndex);
    expect(cachedFirst.lines, expected.lines);
    expect(cachedAgain.lines, expected.lines);
  });

  test('שינוי הגדרות או נתונים מרנדר מחדש', () {
    final cache = SelectionLineCache();
    final withoutNikud = textOf(cache.lines(data, settings))(200);

    const keepNikud = RenderSettings();
    expect(
      textOf(cache.lines(data, keepNikud))(200),
      renderSelectionLine(rawText: data[200], settings: keepNikud),
    );
    expect(textOf(cache.lines(data, keepNikud))(200), isNot(withoutNikud));

    final newData = [...data]..[200] = 'טקסט שנטען מחדש';
    expect(textOf(cache.lines(newData, keepNikud))(200), 'טקסט שנטען מחדש');
  });

  test('ניקוי בסוף גרירה מרנדר מחדש', () {
    final cache = SelectionLineCache();
    final before = textOf(cache.lines(data, settings))(200);

    cache.clear();

    final after = textOf(cache.lines(data, settings))(200);
    expect(after, before);
    expect(identical(after, before), isFalse);
  });

  test('מעבר למכסת השורות אינו נשמר', () {
    final cache = SelectionLineCache();
    final render = textOf(cache.lines(data, settings));
    final firstLines = [for (var i = 0; i < data.length; i++) render(i)];

    final again = textOf(cache.lines(data, settings));
    expect(identical(again(0), firstLines[0]), isTrue);
    expect(identical(again(1999), firstLines[1999]), isTrue);
    expect(identical(again(2050), firstLines[2050]), isFalse);
  });

  test('שורות ארוכות אינן חורגות ממכסת התווים', () {
    final cache = SelectionLineCache();
    final longData = List.generate(4, (i) => '<b>${'אב' * 40000}</b>$i');
    final render = textOf(cache.lines(longData, settings));
    final first = render(0);
    final second = render(1);

    expect(identical(render(0), first), isTrue);
    expect(render(1), second);
    expect(identical(render(1), second), isFalse);
    cache.clear();
    final afterClear = render(1);
    expect(identical(render(1), afterClear), isTrue);
  });

  test('שורה מעל המכסה אינה נשמרת ושינוי נתונים מאפס את התקציב', () {
    final cache = SelectionLineCache();
    final oversized = [
      '<b>${'אב' * 70000}</b>',
      '<b>שורה קצרה</b>',
      '<b>${'אב' * 40000}</b>',
    ];
    final render = textOf(cache.lines(oversized, settings));
    final first = render(0);
    expect(render(0), first);
    expect(identical(render(0), first), isFalse);
    final short = render(1);
    expect(identical(render(1), short), isTrue);

    render(2);
    final newData = ['<b>${'אב' * 40000}</b>'];
    final newRender = textOf(cache.lines(newData, settings));
    final afterDataChange = newRender(0);
    expect(identical(newRender(0), afterDataChange), isTrue);
    final newSettingsRender = textOf(
      cache.lines(newData, const RenderSettings()),
    );
    final afterSettingsChange = newSettingsRender(0);
    expect(identical(newSettingsRender(0), afterSettingsChange), isTrue);
  });
}
