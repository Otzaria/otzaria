import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';

/// מקודד payload לפורמט TSB1 — מראה של הקוד בצינור הבנייה (build_biographies.py).
Uint8List encodeTsb1(Map<String, dynamic> payload, String key) {
  final plain = utf8.encode(jsonEncode(payload));
  final compressed = gzip.encode(plain);
  final keystream = sha256.convert(utf8.encode(key)).bytes;
  final out = BytesBuilder()..add(ascii.encode('TSB1'));
  for (var i = 0; i < compressed.length; i++) {
    out.addByte(compressed[i] ^ keystream[i % keystream.length]);
  }
  return out.toBytes();
}

// אותו מקור כמו BiographiesCodec._obfKey — מוזרק ב-CI, ריק מקומית.
// גם מפתח ריק נותן keystream תקין, כך שה-round-trip עובד בשני המצבים.
const _key = String.fromEnvironment('BIO_OBF_KEY');

void main() {
  final samplePayload = {
    'format': 'tashma-biographies',
    'version': 1,
    'entries': [
      {
        'id': 1,
        'name': null,
        'birthHebrew': null,
        'deathHebrew': {'month': 'סיון', 'day': 'כו'},
        'doc': {
          'nameFirst': {'he': 'אונקלוס', 'en': 'Onkelos'},
          'appelations': [
            {'he': 'הגר'},
          ],
          'summary': {'he': 'תנא, מתרגם התורה.'},
        },
        'resolved': {'generation': 'תנאים'},
      },
      {
        'id': 3,
        'name': 'רבינו סעדיה אלפיומי גאון',
        'doc': {
          'nameFirst': {'he': 'סעדיה'},
          'nameLast': {'he': 'אלפיומי'},
          'biographyShort': {'he': 'מגאוני בבל.'},
        },
      },
    ],
    'translation': [],
  };

  group('BiographiesCodec', () {
    test('מפענח קובץ TSB1 תקין', () {
      final decoded = BiographiesCodec.decode(encodeTsb1(samplePayload, _key));
      expect(decoded['format'], 'tashma-biographies');
      expect((decoded['entries'] as List).length, 2);
    });

    test('זורק על כותרת שגויה', () {
      final bytes = encodeTsb1(samplePayload, _key);
      bytes[0] = 0x58;
      expect(() => BiographiesCodec.decode(bytes), throwsFormatException);
    });

    test('זורק על מפתח לא תואם', () {
      final bytes = encodeTsb1(samplePayload, 'wrong-key');
      expect(() => BiographiesCodec.decode(bytes), throwsFormatException);
    });
  });

  group('Biography.fromEntry', () {
    test('מרכיב שם כשאין שם מוכן, וקורא שדות רב-לשוניים', () {
      final decoded = BiographiesCodec.decode(encodeTsb1(samplePayload, _key));
      final entries = (decoded['entries'] as List)
          .whereType<Map<String, dynamic>>()
          .map(Biography.fromEntry)
          .toList();

      final onkelos = entries.firstWhere((b) => b.id == 1);
      // הכינוי משלים שם חסר-משפחה, כמו בתצוגת אתר תא שמע.
      expect(onkelos.name, 'אונקלוס הגר');
      expect(onkelos.summary, 'תנא, מתרגם התורה.');
      expect(onkelos.appelations, ['הגר']);
      expect(onkelos.generation, 'תנאים');
      expect(onkelos.birthHebrew, isNull);
      expect(onkelos.deathHebrew?.display, 'כו סיון');

      final saadia = entries.firstWhere((b) => b.id == 3);
      expect(saadia.name, 'רבינו סעדיה אלפיומי גאון');
      expect(saadia.biographyShort, 'מגאוני בבל.');
    });
  });
}
