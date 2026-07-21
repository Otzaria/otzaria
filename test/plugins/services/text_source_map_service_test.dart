import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  const service = TextSourceMapService();

  test('ממפה טקסט זהה כ-identity ומחשב offsets בכל יחידות Unicode', () {
    final map = service.build(
      bookId: 'book',
      sectionIndex: 3,
      rawText: 'א😀ב',
      settings: const RenderSettings(formatParentheses: false),
    );

    expect(map.sourceText, 'א😀ב');
    expect(map.renderedText, 'א😀ב');
    expect(map.sourceTextHash, map.renderedTextHash);
    expect(map.mappings, hasLength(1));
    expect(map.mappings.single.kind, PluginTextSourceMapKind.identity);
    expect(map.mappings.single.sourceEnd.grapheme, 3);
    expect(map.mappings.single.sourceEnd.codePoint, 3);
    expect(map.mappings.single.sourceEnd.utf16, 4);
  });

  test('תגי HTML אינם חלק משכבת המקור הטקסטואלית', () {
    final map = service.build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: '<b>שלום</b> עולם',
      settings: const RenderSettings(formatParentheses: false),
    );

    expect(map.sourceText, 'שלום עולם');
    expect(map.renderedText, 'שלום עולם');
    expect(map.mappings.single.kind, PluginTextSourceMapKind.identity);
  });

  test('ניקוד שמוסר מהתצוגה ממופה כהחלפת grapheme', () {
    final map = service.build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: 'אָב',
      settings: const RenderSettings(
        removeNikud: true,
        removeTeamim: false,
        formatParentheses: false,
      ),
    );

    expect(map.sourceText, 'אָב');
    expect(map.renderedText, 'אב');
    expect(
      map.mappings.map((segment) => segment.kind),
      contains(PluginTextSourceMapKind.substitution),
    );
  });

  test('החלפת שם בתצוגה אינה משנה את hash המקור', () {
    final plain = service.build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: 'יהוה מלך',
      settings: const RenderSettings(
        replaceHolyNames: false,
        formatParentheses: false,
      ),
    );
    final replaced = service.build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: 'יהוה מלך',
      settings: const RenderSettings(
        replaceHolyNames: true,
        formatParentheses: false,
      ),
    );

    expect(replaced.sourceTextHash, plain.sourceTextHash);
    expect(replaced.renderedTextHash, isNot(plain.renderedTextHash));
    expect(
      replaced.mappings.map((segment) => segment.kind),
      contains(PluginTextSourceMapKind.substitution),
    );
  });

  test('שינוי גופן אינו משנה אף hash טקסטואלי', () {
    final first = service.build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: 'טקסט',
      settings: const RenderSettings(fontSize: 18),
    );
    final second = service.build(
      bookId: 'book',
      sectionIndex: 0,
      rawText: 'טקסט',
      settings: const RenderSettings(fontSize: 30),
    );

    expect(second.sourceTextHash, first.sourceTextHash);
    expect(second.renderedTextHash, first.renderedTextHash);
  });
}
