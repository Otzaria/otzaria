import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/plugins/services/plugin_note_location.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';

const _line = '<b>וַיֹּאמֶר</b> אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר';
const _source = 'וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר';

Map<String, dynamic> _range(String text, int utf16Start, int utf16End) {
  final start = text.substring(0, utf16Start).characters.length;
  final end = text.substring(0, utf16End).characters.length;
  return const ReaderSelectionService()
      .buildRangeAnchor(
        text: text,
        startGrapheme: start,
        endGrapheme: end,
        layer: 'source',
        sourceTextHash: sha256.convert(utf8.encode(text)).toString(),
      )!
      .toJson();
}

Future<String?> _loadLine() async => _line;

Matcher _throwsCode(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

void main() {
  test('בלי range ובלי text — הערה על השורה כולה', () async {
    expect(await parsePluginNoteAnchor({}, _loadLine), isNull);
  });

  test('range מ-reader.getSelection מאותר בשורה', () async {
    final at = _source.lastIndexOf('אוֹר');
    final anchor = await parsePluginNoteAnchor({
      'range': _range(_source, at, at + 'אוֹר'.length),
    }, _loadLine);
    expect(anchor?.text, 'אוֹר');
    expect(anchor?.offset, at);
    expect(anchor?.fromSource, isTrue);
  });

  test('text ו-occurrence עוברים כמות שהם', () async {
    final anchor = await parsePluginNoteAnchor({
      'text': 'אור',
      'occurrence': 1,
    }, _loadLine);
    expect(anchor?.text, 'אור');
    expect(anchor?.occurrence, 1);
    expect(anchor?.fromSource, isFalse);
  });

  test('פרמטרים לא תקינים', () async {
    final range = _range(_source, 0, 2);
    await expectLater(
      parsePluginNoteAnchor({'range': range, 'text': 'אור'}, _loadLine),
      _throwsCode('error.invalid_params'),
    );
    await expectLater(
      parsePluginNoteAnchor({'occurrence': 1}, _loadLine),
      _throwsCode('error.invalid_params'),
    );
    await expectLater(
      parsePluginNoteAnchor({'text': '  '}, _loadLine),
      _throwsCode('error.invalid_params'),
    );
    await expectLater(
      parsePluginNoteAnchor({'range': 'x'}, _loadLine),
      _throwsCode('error.invalid_params'),
    );
    await expectLater(
      parsePluginNoteAnchor({'range': range}, () async => null),
      _throwsCode('error.invalid_params'),
    );
  });

  test('range של שורה אחרת אינו נמצא', () async {
    const other = 'טקסט אחר לגמרי';
    await expectLater(
      parsePluginNoteAnchor({'range': _range(other, 0, 4)}, _loadLine),
      _throwsCode('error.not_found'),
    );
  });

  group('parsePluginNoteLocation', () {
    var reads = 0;
    Future<List<String>> lines() async {
      reads++;
      return const ['שורה ראשונה', _line, 'שורה שלישית'];
    }

    setUp(() => reads = 0);

    test('הסוג נקבע לפי הפרמטרים', () async {
      final line = await parsePluginNoteLocation({'lineNumber': 2}, lines);
      expect(line.scope, PersonalNoteScope.lines);
      expect(reads, 0, reason: 'קריאה ותיקה אינה טוענת את הספר');

      final range = await parsePluginNoteLocation({
        'lineNumber': 1,
        'endLineNumber': 3,
      }, lines);
      expect((range.scope, range.endLineNumber), (PersonalNoteScope.lines, 3));

      final words = await parsePluginNoteLocation({
        'lineNumber': 2,
        'text': 'אור',
      }, lines);
      expect(words.scope, PersonalNoteScope.words);
      expect(words.anchor?.text, 'אור');

      final book = await parsePluginNoteLocation({'scope': 'book'}, lines);
      expect((book.scope, book.lineNumber), (PersonalNoteScope.book, null));
    });

    test('פרמטרים סותרים או מחוץ לספר', () async {
      for (final args in <Map<String, dynamic>>[
        {'scope': 'page', 'lineNumber': 1},
        {'scope': 'book', 'lineNumber': 1},
        {'lineNumber': 0},
        {'lineNumber': 3, 'endLineNumber': 2},
        {'lineNumber': 1, 'endLineNumber': 2, 'text': 'שורה'},
        {'lineNumber': 1, 'endLineNumber': 4},
        {'scope': 'words', 'lineNumber': 1},
        {'scope': 'lines', 'lineNumber': 1, 'text': 'שורה'},
      ]) {
        await expectLater(
          parsePluginNoteLocation(args, lines),
          _throwsCode('error.invalid_params'),
          reason: '$args',
        );
      }
    });
  });

  test('pluginNoteJson מחזיר את המיקום המלא', () {
    final now = DateTime(2026, 11, 11);
    final json = pluginNoteJson(
      PersonalNote(
        id: 'n',
        bookId: 'ספר',
        lineNumber: 2,
        endLineNumber: 4,
        lastKnownLineNumber: null,
        status: PersonalNoteStatus.located,
        content: 'הערה',
        contentPlain: 'הערה',
        contentFormat: PersonalNoteContentFormat.plain,
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(json, containsPair('scope', 'lines'));
    expect(json, containsPair('endLineNumber', 4));
    expect(json, containsPair('status', 'located'));
    expect(json, containsPair('updatedAt', now.toIso8601String()));
  });
}
