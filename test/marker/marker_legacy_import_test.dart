import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/marker/legacy/legacy_marker_import.dart';
import 'package:otzaria/marker/legacy/legacy_note_html.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/services/marker_transfer.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

import 'marker_test_helpers.dart';

const _line = 'וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר';
const _line2 = 'וַיַּרְא אֱלֹהִים אֶת הָאוֹר כִּי טוֹב';

Map<String, dynamic> _record(
  String id, {
  int section = 0,
  String source = _line,
  String phrase = 'יְהִי אוֹר',
  String? groupId,
  Object? sourceRange,
  Map<String, dynamic> extra = const {},
}) => {
  'highlightId': id,
  'groupId': groupId,
  'bookId': 'בראשית',
  'bookUid': 'id:183',
  'book': 'בראשית',
  'sectionIndex': section,
  'colorId': 'green',
  'color': '#8bcf8d',
  'style': {'backgroundColor': '#8BCF8D', 'markerMode': 'text-background'},
  'text': 'יהי אור',
  'ref': 'בראשית פרק א',
  'note': '',
  'noteHtml': '',
  'tags': ['בריאה'],
  'favorite': false,
  'sourceRange': sourceRange ?? anchorFor(source, phrase).toJson(),
  'version': 1,
  'etag': 'x',
  'status': 'active',
  'timestamp': 1760947200000,
  ...extra,
};

Map<String, dynamic> _backup(List<Object?> highlights, {int version = 2}) => {
  'format': 'otzaria-marker-backup',
  'schemaVersion': version,
  'pluginVersion': '0.9.6',
  'exportedAt': '2026-10-20T08:15:42.117Z',
  'settings': {
    'colors': [
      {'id': 'yellow', 'hex': '#F1E784', 'label': 'צהוב', 'enabled': true},
      {'id': 'green', 'hex': '#8BCF8D', 'label': 'ירוק', 'enabled': true},
    ],
    'defaultColorId': 'green',
  },
  'highlights': highlights,
};

void main() {
  group('plugin backup', () {
    test('a v2 record keeps its id, anchor, colour, tags and date', () {
      final data = parseLegacyMarkerBackup(_backup([_record('marker-a')]));
      final mark = data.highlights.single;
      expect(mark.id, 'marker-a');
      expect(mark.bookTitle, 'בראשית');
      expect(mark.bookUid, 'id:183');
      expect(mark.colorId, 'green');
      expect(mark.colorHex, '#8BCF8D');
      expect(mark.tags, ['בריאה']);
      expect(mark.createdAt.millisecondsSinceEpoch, 1760947200000);
      final segment = mark.segments.single;
      expect(segment.range.exactText, 'יְהִי אוֹר');
      expect(segment.status, MarkerAnchorStatus.active);
      expect(segment.legacyId, 'marker-a');
      expect(data.palette!.defaultColorId, 'green');
    });

    test('v1 backups are accepted, other formats are refused', () {
      expect(
        parseLegacyMarkerBackup(
          _backup([_record('a')], version: 1),
        ).highlights,
        hasLength(1),
      );
      expect(
        () => parseLegacyMarkerBackup({'format': 'other'}),
        throwsA(isA<LegacyMarkerFormatException>()),
      );
      expect(
        () => parseLegacyMarkerBackup(_backup([], version: 3)),
        throwsA(isA<LegacyMarkerFormatException>()),
      );
    });

    test('parts of one selection across paragraphs become one mark', () {
      final data = parseLegacyMarkerBackup(
        _backup([
          _record(
            'part-2',
            section: 4,
            source: _line2,
            phrase: 'אֶת הָאוֹר',
            groupId: 'g-1',
          ),
          _record('part-1', section: 3, groupId: 'g-1'),
        ]),
      );
      final mark = data.highlights.single;
      expect(mark.id, 'g-1');
      expect(mark.segments.map((s) => s.sectionIndex), [3, 4]);
      expect(mark.segments.map((s) => s.legacyId), ['part-1', 'part-2']);
    });

    test('parts that were edited apart stay separate marks', () {
      final data = parseLegacyMarkerBackup(
        _backup([
          _record('part-1', section: 3, groupId: 'g-1'),
          _record(
            'part-2',
            section: 4,
            source: _line2,
            phrase: 'אֶת הָאוֹר',
            groupId: 'g-1',
            extra: {'note': 'הערה על החלק השני', 'colorId': 'red'},
          ),
        ]),
      );
      expect(data.highlights.map((h) => h.id), ['g-1', 'part-2']);
      expect(data.highlights.last.note?.plain, 'הערה על החלק השני');
      expect(data.highlights.last.colorId, 'red');
    });

    test('broken and duplicate records are counted, not imported', () {
      final data = parseLegacyMarkerBackup(
        _backup([
          _record('ok'),
          _record('ok'),
          {'highlightId': 'bad id!', 'bookId': 'x', 'sectionIndex': 0},
          {'highlightId': 'no-anchor', 'bookId': 'x', 'sectionIndex': 0},
          _record('negative', section: -1),
          'not a record',
        ]),
      );
      expect(data.highlights.map((h) => h.id), ['ok']);
      expect(data.invalid, 5);
    });

    test('a partial anchor is rebuilt from its text and checked later', () {
      final data = parseLegacyMarkerBackup(
        _backup([
          _record(
            'old',
            sourceRange: {
              'type': 'text-range-v1',
              'start': {'utf16': 10, 'grapheme': 10},
              'end': {'utf16': 19, 'grapheme': 19},
              'exactText': 'יְהִי אוֹר',
            },
          ),
        ]),
      );
      final segment = data.highlights.single.segments.single;
      expect(segment.status, MarkerAnchorStatus.stale);
      expect(segment.range.exactText, 'יְהִי אוֹר');
      // העוגן ששוחזר עובר את הבדיקה המלאה של המודל.
      expect(
        () => MarkerSegment.fromJson(
          jsonDecode(jsonEncode(segment.toJson())) as Map<String, dynamic>,
        ),
        returnsNormally,
      );
    });

    test('a rich note becomes an editor note; a plain one stays plain', () {
      final data = parseLegacyMarkerBackup(
        _backup([
          _record(
            'rich',
            extra: {
              'note': 'פתיחה\nלעיין',
              'noteHtml': '<p><b>פתיחה</b></p><p>לעיין</p>',
            },
          ),
          _record('plain', extra: {'note': 'הערה פשוטה'}),
        ]),
      );
      final rich = data.highlights.firstWhere((h) => h.id == 'rich').note!;
      expect(rich.format, PersonalNoteContentFormat.quillDelta);
      expect(rich.plain, 'פתיחה\nלעיין');
      final plain = data.highlights.firstWhere((h) => h.id == 'plain').note!;
      expect(plain.format, PersonalNoteContentFormat.plain);
      expect(plain.content, 'הערה פשוטה');
    });

    test('a rich note without a plain copy gets one from its text', () {
      final data = parseLegacyMarkerBackup(
        _backup([
          _record('rich', extra: {'noteHtml': '<p>לעיין <b>שם</b></p>'}),
        ]),
      );
      expect(data.highlights.single.note?.plain, 'לעיין שם');
      expect(data.highlights.single.hasNote, isTrue);
    });
  });

  group('note html', () {
    List<Map<String, dynamic>> ops(String html) =>
        (jsonDecode(legacyNoteHtmlToDelta(html)!) as List)
            .cast<Map<String, dynamic>>();

    test('keeps the formatting the editor supports', () {
      final delta = ops(
        '<h2>כותרת</h2><p><b>מודגש</b> <i>נטוי</i> <u>קו</u> <s>מחוק</s> '
        '<mark>מסומן</mark> <span style="font-size: large">גדול</span></p>'
        '<ul><li>א</li><li>ב</li></ul><ol><li>ג</li></ol>'
        '<blockquote>ציטוט</blockquote>',
      );
      Map<String, dynamic>? attrs(String text) =>
          delta.firstWhere((op) => op['insert'] == text)['attributes']
              as Map<String, dynamic>?;
      expect(attrs('מודגש'), {'bold': true});
      expect(attrs('נטוי'), {'italic': true});
      expect(attrs('קו'), {'underline': true});
      expect(attrs('מחוק'), {'strike': true});
      expect(attrs('מסומן'), {'background': '#fff59d'});
      expect(attrs('גדול'), {'size': 20.0});
      final newlines = delta.where((op) => op['insert'] == '\n').toList();
      expect(newlines.map((op) => op['attributes']), [
        {'header': 2},
        null,
        {'list': 'bullet'},
        {'list': 'bullet'},
        {'list': 'ordered'},
        {'blockquote': true},
      ]);
      // Quill מקבל את התוצאה כמסמך תקין.
      expect(
        quill.Document.fromJson(delta).toPlainText(),
        startsWith('כותרת\n'),
      );
    });

    test('only http links survive and scripts become plain text', () {
      final delta = ops(
        '<p><a href="https://example.org/x">קישור</a> '
        '<a href="javascript:alert(1)">רע</a>'
        '<script>alert(2)</script><img src=x onerror=alert(3)></p>',
      );
      expect(
        delta.firstWhere((op) => op['insert'] == 'קישור')['attributes'],
        {'link': 'https://example.org/x'},
      );
      final text = delta.map((op) => op['insert']).join();
      expect(text, contains('רע'));
      expect(text, contains('alert(2)'));
      expect(
        delta.where((op) => (op['attributes'] as Map?)?['link'] != null),
        hasLength(1),
      );
    });

    test('an empty note gives nothing', () {
      expect(legacyNoteHtmlToDelta('<p><br></p>'), isNull);
    });
  });

  group('native backup', () {
    test('round-trips every field', () async {
      final store = openTestMarkerStore();
      final transfer = MarkerTransfer(repository: store.repository);
      final original = highlightFor(
        'mk-1',
        [segmentFor(2, _line, 'אוֹר', occurrence: 1)],
        tags: ['א', 'ב'],
        favorite: true,
        note: const MarkerNote(content: '[{"insert":"x\\n"}]', plain: 'x'),
      );
      final bytes = await transfer.encodeBackup(
        palette: MarkerPalette.defaults(),
        only: [original],
      );
      final parsed = parseMarkerBackup(jsonDecode(utf8.decode(bytes)));
      expect(parsed.highlights.single, original);
      expect(parsed.palette, MarkerPalette.defaults());
      store.db.close();
    });

    test('a newer backup format is refused rather than half-read', () {
      expect(
        () => parseMarkerBackup({
          'format': MarkerTransfer.format,
          'schemaVersion': MarkerTransfer.schemaVersion + 1,
          'highlights': [],
        }),
        throwsA(isA<MarkerBackupFormatException>()),
      );
    });

    test('importing a preview twice adds the records once', () async {
      final store = openTestMarkerStore();
      final transfer = MarkerTransfer(repository: store.repository);
      final data = parseLegacyMarkerBackup(
        _backup([_record('a'), _record('b')]),
      );
      final firstPreview = MarkerImportPreview(highlights: data.highlights);
      expect((await transfer.apply(firstPreview)).added, 2);
      expect((await transfer.apply(firstPreview)).added, 0);
      expect(await store.repository.countAll(), 2);
      store.db.close();
    });

    test(
      'importing from the plugin again skips marks deleted since',
      () async {
        final store = openTestMarkerStore();
        final transfer = MarkerTransfer(repository: store.repository);
        final registry = _FakeRegistry({
          'highlight:a': jsonEncode(_record('a')),
          'highlight:b': jsonEncode(_record('b', phrase: 'וַיְהִי')),
        });
        final first = await transfer.previewLegacyPlugin(registry: registry);
        await transfer.apply(first!);
        await store.repository.delete(['a']);
        final again = await transfer.previewLegacyPlugin(registry: registry);
        expect(again!.deletedSinceImport, 1);
        expect(again.highlights.map((h) => h.id), ['b']);
        expect(again.toAdd, 0);
        store.db.close();
      },
    );
  });
}

class _FakeRegistry implements PluginRegistryRepository {
  final Map<String, String> values;

  _FakeRegistry(this.values);

  @override
  Future<List<String>> listKVKeys(String pluginId, String namespace) async =>
      values.keys.toList();

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async => {
    for (final key in keys)
      if (values.containsKey(key)) key: values[key]!,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
