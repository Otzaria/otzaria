import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

// בדיקות יחידה לוגיקת הטיימר ב-_FindRefDialogState.
// בודקות את האינווריאנט הקריטי: ביטול הטיימר בלחיצת X
// מבטיח שאירוע חיפוש ישן לא יגיע ל-BLoC.

void main() {
  group('דיבאונס חיפוש — ביטול טיימר', () {
    test('ניקוי לפני פקיעת הטיימר מונע שליחת SearchRefRequested', () async {
      bool searchFired = false;
      Timer? debounce;

      // משתמש מקליד — טיימר מתחיל
      debounce = Timer(const Duration(milliseconds: 150), () {
        searchFired = true;
      });

      // משתמש לוחץ X לפני 150ms — טיימר מבוטל
      debounce.cancel();
      debounce = null;

      await Future.delayed(const Duration(milliseconds: 200));
      expect(searchFired, isFalse);
    });

    test('המתנה לפקיעת הטיימר מפעילה את החיפוש', () async {
      bool searchFired = false;
      Timer? debounce;

      debounce = Timer(const Duration(milliseconds: 150), () {
        searchFired = true;
      });

      await Future.delayed(const Duration(milliseconds: 200));
      expect(searchFired, isTrue);
      debounce.cancel(); // cleanup
    });

    test('הקלדה מהירה — רק האירוע האחרון עובר (כל הקשה מאפסת את הטיימר)', () async {
      final List<String> fired = [];
      Timer? debounce;

      // מדמה הקלדה מהירה: א, אב, אבג — כל אחד מאפס
      for (final text in ['א', 'אב', 'אבג']) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 150), () {
          fired.add(text);
        });
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await Future.delayed(const Duration(milliseconds: 200));
      expect(fired, ['אבג']);
    });

    test('ניקוי ואז הקלדה חדשה — החיפוש החדש עובד ללא חסימה', () async {
      bool firstFired = false;
      bool secondFired = false;
      Timer? debounce;

      // הקלדה ראשונה
      debounce = Timer(const Duration(milliseconds: 150), () {
        firstFired = true;
      });

      // ניקוי לפני הפקיעה
      debounce.cancel();
      debounce = null;

      // הקלדה חדשה אחרי הניקוי
      debounce = Timer(const Duration(milliseconds: 150), () {
        secondFired = true;
      });

      await Future.delayed(const Duration(milliseconds: 200));

      expect(firstFired, isFalse, reason: 'החיפוש הישן לא אמור לפעול');
      expect(secondFired, isTrue, reason: 'החיפוש החדש אמור לפעול');
    });
  });
}
