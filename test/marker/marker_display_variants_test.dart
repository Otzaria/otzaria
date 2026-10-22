import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/services/marker_realign.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

import 'marker_test_helpers.dart';

const _verse =
    'וַיְדַבֵּ֣ר יְהֹוָ֔ה אֶל־מֹשֶׁ֖ה לֵּאמֹֽר׃ דַּבֵּ֞ר אֶל־בְּנֵ֤י '
    'יִשְׂרָאֵל֙ וְאָמַרְתָּ֣ אֲלֵהֶ֔ם, אֲנִ֖י יְהוָ֥ה אֱלֹהֵיכֶֽם׃ (א) וַיֹּ֥אמֶר';

const _displays = {
  'הכול מוצג': RenderSettings(),
  'בלי ניקוד': RenderSettings(removeNikud: true),
  'בלי טעמים': RenderSettings(removeTeamim: true),
  'בלי ניקוד וטעמים': RenderSettings(removeNikud: true, removeTeamim: true),
  'בלי פיסוק': RenderSettings(removePunctuation: true),
  'שם הוי"ה בכינוי': RenderSettings(replaceHolyNames: true),
  'הכול מוסתר': RenderSettings(
    removeNikud: true,
    removeTeamim: true,
    removePunctuation: true,
    replaceHolyNames: true,
  ),
};

/// האותיות בלבד, להשוואה בין תצוגות.
String _letters(String text) => text.replaceAll(RegExp(r'[֑-ׇ\s:.,()"־]'), '');

void main() {
  test('a mark stays on the same words in every display of the text', () {
    final failures = <String>[];
    for (final from in _displays.entries) {
      final shown = TextRendererService.stripHtml(
        TextRendererService.processText(_verse, from.value),
      );
      var column = 0;
      for (final word in shown.split(' ')) {
        final start = column;
        column += word.length + 1;
        if (_letters(word).isEmpty) continue;
        final range = const ReaderSelectionService()
            .buildFromRenderedSelection(
              bookId: 'b',
              bookTitle: 'b',
              sectionIndex: 0,
              rawText: _verse,
              settings: from.value,
              selectedText: word,
              startHint: start,
            )
            ?.sourceRange;
        if (range == null) {
          failures.add('${from.key}: "$word" was not anchored');
          continue;
        }
        final highlight = PluginHighlight(
          highlightId: 'h',
          ownerPluginId: 'o',
          bookId: 'b',
          sectionIndex: 0,
          range: range,
          style: const PluginHighlightStyle(backgroundColor: '#ffff00'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        for (final to in _displays.entries) {
          final html = TextRendererService.processText(_verse, to.value);
          final ranges = const PluginHighlightRenderer().resolveRenderedRanges(
            bookId: 'b',
            sectionIndex: 0,
            rawText: _verse,
            processedHtml: html,
            highlights: [highlight],
          );
          final text = TextRendererService.stripHtml(html).characters;
          final painted = ranges.isEmpty
              ? ''
              : text
                    .skip(ranges.single.start)
                    .take(
                      ranges.single.end - ranges.single.start,
                    )
                    .string;
          // שם הוי"ה מוצג בכינוי באחת התצוגות, ולכן משווים את המקור.
          final holy = range.exactText.contains('יְה');
          final ok = holy
              ? painted.isNotEmpty && !painted.contains(' ')
              : _letters(painted) == _letters(word);
          if (!ok) {
            failures.add('${from.key} → ${to.key}: "$word" → "$painted"');
          }
        }
      }
    }
    expect(failures, isEmpty);
  });

  group('realignMarkerSegment', () {
    const source = 'אמר רבי יוחנן משום רבי שמעון בן יוחאי';

    test('moves a segment to the words that were marked', () {
      final segment = segmentFor(0, source, 'יוחנן משום');
      final realigned = realignMarkerSegment(
        segment: segment,
        markText: 'רבי שמעון',
        rawLine: source,
      );
      expect(realigned!.range.exactText, 'רבי שמעון');
      expect(realigned.status, MarkerAnchorStatus.active);
    });

    test('picks the occurrence nearest the saved place', () {
      final segment = segmentFor(0, source, 'משום');
      final realigned = realignMarkerSegment(
        segment: segment,
        markText: 'רבי',
        rawLine: source,
      );
      expect(realigned!.start, 'אמר רבי יוחנן משום '.length);
    });

    test('ignores nikud, teamim and punctuation in the marked text', () {
      const pointed = 'אָמַר רַבִּי, יוֹחָנָן';
      final segment = segmentFor(0, pointed, 'אָמַר');
      final realigned = realignMarkerSegment(
        segment: segment,
        markText: 'רבי יוחנן',
        rawLine: pointed,
      );
      expect(realigned!.range.exactText, 'רַבִּי, יוֹחָנָן');
    });

    test('keeps a segment whose text agrees', () {
      expect(
        realignMarkerSegment(
          segment: segmentFor(0, source, 'רבי יוחנן'),
          markText: 'רבי  יוחנן',
          rawLine: source,
        ),
        isNull,
      );
    });

    test('keeps a Divine Name that was shown as a substitute', () {
      const verse = 'וידבר יהוה אל משה';
      for (final shown in ["ה'", 'יקוק', 'וידבר ה\' אל']) {
        expect(
          realignMarkerSegment(
            segment: segmentFor(
              0,
              verse,
              shown.contains(' ') ? 'וידבר יהוה אל' : 'יהוה',
            ),
            markText: shown,
            rawLine: verse,
          ),
          isNull,
          reason: shown,
        );
      }
    });

    test('keeps a name that the line marks and the display substituted', () {
      // "אלהים" סומן כשהוצג "אלקים"; הכתיב "אלקים" בסוף השורה אינו המקום.
      const raw =
          'ויאמר <span class="divine-name" data-k="5">אלהים</span> יהי אור '
          'ואמר אלקים';
      expect(
        realignMarkerSegment(
          segment: segmentFor(
            0,
            'ויאמר אלהים יהי אור ואמר אלקים',
            'אלהים',
          ),
          markText: 'אלקים',
          rawLine: raw,
        ),
        isNull,
      );
    });

    test('keeps a segment whose text is no longer in the paragraph', () {
      expect(
        realignMarkerSegment(
          segment: segmentFor(0, source, 'יוחנן'),
          markText: 'רבי מאיר',
          rawLine: source,
        ),
        isNull,
      );
    });
  });
}
