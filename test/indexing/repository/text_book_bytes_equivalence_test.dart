import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';

/// האינדוקס מוסר טקסט מפוענח כבתי UTF-8: המנוע חייב לחתום ולאנדקס אותו
/// בדיוק כמו את ה-String, כולל תווים שהקידוד מחליף.
void main() {
  test('addTextBookBytes על utf8.encode זהה ל-addTextBook', () async {
    if (!await tryInitSearchEngine()) {
      markTestSkipped(searchEngineSkipReason);
      return;
    }
    final directory = await Directory.systemTemp.createTemp('bytes_equiv');
    final engine = await SearchEngine.newInstance(path: directory.path);
    addTearDown(() async {
      engine.dispose();
      await directory.delete(recursive: true);
    });

    const texts = [
      '﻿<h1>בְּרֵאשִׁית</h1>\nשורה שנייה\r\nשלישית',
      'זוג חסר \uD800 וסוגר בודד \uDC00 בסוף',
      'שורה עם <img src=""> ותמונה\n\nאחרי שורה ריקה',
    ];
    for (var i = 0; i < texts.length; i++) {
      await engine.addTextBook(
        title: 'ספר $i',
        topics: '/a',
        filePath: 'string:$i',
        catalogueOrder: i,
        generationOrder: 1,
        text: texts[i],
        textStorage: TextStorage.inIndex,
      );
      await engine.addTextBookBytes(
        title: 'ספר $i',
        topics: '/a',
        filePath: 'bytes:$i',
        catalogueOrder: i,
        generationOrder: 1,
        text: utf8.encode(texts[i]),
        textStorage: TextStorage.inIndex,
      );
    }
    await engine.commit();

    final fingerprints = await engine.getBookFingerprints();
    for (var i = 0; i < texts.length; i++) {
      expect(fingerprints['bytes:$i'], fingerprints['string:$i']);
      expect(fingerprints['bytes:$i'], isNot(BigInt.zero));
    }
  });
}
