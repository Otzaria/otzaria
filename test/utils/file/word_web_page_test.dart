// דף אינטרנט שנשמר בשם `.doc` — Word פותח אותו כרגיל, ולכן הוא מגיע לאוצריא
// כ"מסמך Word" ונכשל בממיר הבינארי (issue #2459).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/legacy_word_to_otzaria.dart';
import 'package:otzaria/utils/file/word_web_page.dart';
import 'package:path/path.dart' as p;

const _title = 'ספר';
const _boundary = '----=_NextPart_01DD66D6.0438F8E0';

final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAj'
  'CB0C8AAAAASUVORK5CYII=',
);

Uint8List _utf16le(String text) {
  final bytes = <int>[];
  for (final unit in text.codeUnits) {
    bytes
      ..add(unit & 0xFF)
      ..add(unit >> 8);
  }
  return Uint8List.fromList(bytes);
}

/// base64 בשורות של 76 תווים, כמו ש-Word כותב.
String _wrappedBase64(List<int> bytes) {
  final encoded = base64Encode(bytes);
  return [
    for (var i = 0; i < encoded.length; i += 76)
      encoded.substring(i, i + 76 > encoded.length ? encoded.length : i + 76),
  ].join('\r\n');
}

/// ארכיון במבנה ש-Word שומר: הקדמה, דף ראשי ב-UTF-16 בלי BOM, תמונה ודף
/// כותרת עליונה שאינו חלק מגוף המסמך.
Uint8List _wordMhtml(String body, {String extraHeaders = ''}) {
  final html =
      '<html><head><meta http-equiv=Content-Type '
      'content="text/html; charset=unicode"></head><body>$body</body></html>';
  final text = [
    'MIME-Version: 1.0',
    'Content-Type: multipart/related; boundary="$_boundary"$extraHeaders',
    '',
    'מסמך זה הוא דף אינטרנט עם קובץ יחיד.',
    '',
    '--$_boundary',
    'Content-Location: file:///C:/AA4764F1/file5617.htm',
    'Content-Transfer-Encoding: base64',
    'Content-Type: text/html; charset="unicode"',
    '',
    _wrappedBase64(_utf16le(html)),
    '',
    '--$_boundary',
    'Content-Location: file:///C:/AA4764F1/file5617.files/image001.png',
    'Content-Transfer-Encoding: base64',
    'Content-ID: <image001.png@01DD66D6>',
    'Content-Type: image/png',
    '',
    _wrappedBase64(_tinyPng),
    '',
    '--$_boundary',
    'Content-Location: file:///C:/AA4764F1/file5617.files/header.htm',
    'Content-Transfer-Encoding: quoted-printable',
    'Content-Type: text/html; charset="utf-8"',
    '',
    '<html><body><p>כותרת עליונה</p></body></html>',
    '',
    '--$_boundary--',
    '',
  ].join('\r\n');
  return Uint8List.fromList(utf8.encode(text));
}

List<String> _bodyLines(String output) {
  final lines = output.split('\n');
  expect(lines.first, '<h1>$_title</h1>');
  return lines.skip(1).toList();
}

void main() {
  group('זיהוי', () {
    test('ארכיון MHTML מזוהה לפי הכותרות שלו', () {
      expect(sniffWordWebPage(_wordMhtml('<p>א</p>')), WordWebPageKind.mhtml);
    });

    test('HTML רגיל מזוהה, גם ב-UTF-16 וגם אחרי הצהרת XML', () {
      expect(
        sniffWordWebPage(Uint8List.fromList(utf8.encode('<html><p>א</p>'))),
        WordWebPageKind.html,
      );
      expect(
        sniffWordWebPage(
          Uint8List.fromList([0xFF, 0xFE, ..._utf16le('<!DOCTYPE html>')]),
        ),
        WordWebPageKind.html,
      );
      expect(
        sniffWordWebPage(
          Uint8List.fromList(utf8.encode('<?xml version="1.0"?>\n<html>')),
        ),
        WordWebPageKind.html,
      );
    });

    test('טקסט רגיל ותג שאינו פותח את המסמך אינם דף אינטרנט', () {
      expect(
        sniffWordWebPage(Uint8List.fromList(utf8.encode('שלום <html>'))),
        isNull,
      );
      expect(
        sniffWordWebPage(
          Uint8List.fromList(utf8.encode('Subject: x\r\n\r\nbody')),
        ),
        isNull,
      );
    });
  });

  group('MHTML', () {
    test('הדף הראשי מפוענח מ-UTF-16, והכותרת העליונה אינה נכנסת לגוף', () {
      final lines = _bodyLines(
        legacyWordToText(_wordMhtml('<p>מוקצה בסוכה</p>'), _title),
      );
      expect(lines, ['מוקצה בסוכה']);
    });

    test('תמונה נשלפת מהארכיון לפי מיקום יחסי ולפי cid', () {
      const body =
          '<p><img src="file5617.files/image001.png"></p>'
          '<p><img src="cid:image001.png@01DD66D6"></p>';
      final lines = _bodyLines(legacyWordToText(_wordMhtml(body), _title));
      final expected = 'data:image/png;base64,${base64Encode(_tinyPng)}';
      expect(lines, hasLength(2));
      expect(lines.every((line) => line.contains(expected)), isTrue);
    });

    test('תמונה שאינה בארכיון אינה נפלטת', () {
      final lines = _bodyLines(
        legacyWordToText(
          _wordMhtml('<p>טקסט<img src="file5617.files/missing.png"></p>'),
          _title,
        ),
      );
      expect(lines, ['טקסט']);
    });

    test('בלי הטמעת תמונות מספר השורות זהה', () {
      final bytes = _wordMhtml(
        '<p>א</p><p><img src="file5617.files/image001.png"></p><p>ב</p>',
      );
      final full = legacyWordToText(bytes, _title);
      final light = legacyWordToText(bytes, _title, embedImages: false);
      expect(light.split('\n'), hasLength(full.split('\n').length));
      expect(light, isNot(contains('base64')));
    });

    test('quoted-printable עם שבירה רכה ובייטים מקודדים', () {
      final html = utf8.encode(
        '<html><head><meta charset="utf-8"></head><body><p>שבת</p></body>'
        '</html>',
      );
      final encoded = StringBuffer();
      for (final byte in html) {
        encoded.write(
          byte < 0x80 && byte != 0x3D
              ? String.fromCharCode(byte)
              : '=${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
        );
      }
      final qp = encoded.toString();
      final half = qp.indexOf('<body>');
      final text = [
        'MIME-Version: 1.0',
        'Content-Type: multipart/related;',
        '\tboundary="b1"',
        '',
        '--b1',
        'Content-Transfer-Encoding: quoted-printable',
        'Content-Type: text/html',
        '',
        '${qp.substring(0, half)}=',
        qp.substring(half),
        '--b1--',
      ].join('\r\n');
      final lines = _bodyLines(
        legacyWordToText(Uint8List.fromList(utf8.encode(text)), _title),
      );
      expect(lines, ['שבת']);
    });

    test('הדף הראשי נבחר לפי start ולא לפי הסדר', () {
      final text = [
        'MIME-Version: 1.0',
        'Content-Type: multipart/related; boundary="b2"; start="<main>"',
        '',
        '--b2',
        'Content-Type: text/html',
        '',
        '<p>לא זה</p>',
        '--b2',
        'Content-ID: <main>',
        'Content-Type: text/html',
        '',
        '<p>זה</p>',
        '--b2--',
      ].join('\r\n');
      final lines = _bodyLines(
        legacyWordToText(Uint8List.fromList(utf8.encode(text)), _title),
      );
      expect(lines, ['זה']);
    });

    test('ארכיון בלי boundary או בלי דף HTML הוא קובץ פגום', () {
      Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
      expect(
        () => legacyWordToText(
          bytes('MIME-Version: 1.0\r\nContent-Type: multipart/related\r\n\r\n'),
          _title,
        ),
        throwsA(isA<CorruptedDocumentException>()),
      );
      expect(
        () => legacyWordToText(
          bytes(
            'Content-Type: multipart/related; boundary="b"\r\n\r\n'
            '--b\r\nContent-Type: image/png\r\n\r\nxx\r\n--b--\r\n',
          ),
          _title,
        ),
        throwsA(
          isA<CorruptedDocumentException>().having(
            (e) => e.format,
            'format',
            DocumentFormat.doc,
          ),
        ),
      );
    });
  });

  group('מסלול הקובץ', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('word_web_page'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('HTML בשם .doc מומר עם תמונה מהתיקייה שלו', () {
      File(p.join(dir.path, 'a.png')).writeAsBytesSync(_tinyPng);
      final file = File(p.join(dir.path, 'מסמך.doc'))
        ..writeAsStringSync(
          '<html><body><h1>פרק</h1><p>טקסט</p><img src="a.png"></body></html>',
        );
      final output = convertDocumentFileSync(file.path);
      expect(output, contains('טקסט'));
      expect(output, contains('data:image/png;base64,'));
    });

    test('MHTML בשם .doc נקרא במסלול של ספר מקובץ', () async {
      final file = File(p.join(dir.path, 'מוקצה בסוכה.doc'))
        ..writeAsBytesSync(_wordMhtml('<p>עצי סוכה</p>'));
      final output = await readFileBackedBookText(file, 'doc', _title);
      expect(output, contains('עצי סוכה'));
    });

    test('קובץ .doc שאינו Word ואינו דף אינטרנט עדיין נדחה', () {
      final file = File(p.join(dir.path, 'x.doc'))
        ..writeAsStringSync('סתם טקסט');
      expect(
        () => convertDocumentFileSync(file.path),
        throwsA(isA<DocumentConversionException>()),
      );
    });
  });
}
