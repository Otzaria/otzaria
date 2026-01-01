import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/constants/fonts.dart';

void main() {
  test('list fonts', () async {
    try {
      // רשימת הגופנים שהאפליקציה מציגה למשתמש.
      // בדסקטופ: כוללת רק גופני מערכת שתומכים בעברית.
      for (final font in AppFonts.availableFonts) {
        debugPrint('Font: ${font.label}, family: ${font.value}');
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  });
}
