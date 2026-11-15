import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';

void main() {
  test('ביקורים נדחפים לחזרה, וחזרה וקדימה עוברות ביניהם', () {
    final history = LibraryNavigationHistory()
      ..visit('/')
      ..visit('/הלכה')
      ..visit('/הלכה/אחרונים');
    expect(history.canGoForward, isFalse);
    expect(history.previous, '/הלכה');

    expect(history.back(), '/הלכה');
    // הגעה ליעד אינה ביקור חדש.
    history.visit('/הלכה');
    expect(history.previous, '/');
    expect(history.next, '/הלכה/אחרונים');

    expect(history.back(), '/');
    expect(history.canGoBack, isFalse);
    expect(history.back(), isNull);

    expect(history.forward(), '/הלכה');
    expect(history.forward(), '/הלכה/אחרונים');
    expect(history.forward(), isNull);
    expect(history.previous, '/הלכה');
  });

  test('ביקור חדש מבטל את מסלול הקדימה', () {
    final history = LibraryNavigationHistory()
      ..visit('/')
      ..visit('/הלכה');
    history.back();
    expect(history.next, '/הלכה');
    history.visit('/תנך');
    expect(history.canGoForward, isFalse);
    expect(history.previous, '/');
  });

  test('ביקור חוזר באותה תיקייה אינו נרשם, וההיסטוריה מוגבלת', () {
    var notifications = 0;
    final history = LibraryNavigationHistory(maxDepth: 3)
      ..addListener(() => notifications++)
      ..visit('/')
      ..visit('/')
      ..visit('/א');
    expect(notifications, 1);
    for (final path in ['/ב', '/ג', '/ד']) {
      history.visit(path);
    }
    final back = <String>[];
    while (history.canGoBack) {
      back.add(history.back()!);
    }
    expect(back, ['/ג', '/ב', '/א']);
  });

  for (final forward in [false, true]) {
    test(
      'מחיקת כל יעדי ${forward ? 'הקדימה' : 'החזרה'} אינה מזיזה את המיקום',
      () {
        final history = LibraryNavigationHistory()
          ..visit('/')
          ..visit('/א')
          ..visit('/ב');
        addTearDown(history.dispose);
        if (forward) {
          history.back();
          history.back();
        }
        expect(
          forward
              ? history.forward(isAvailable: (_) => false)
              : history.back(isAvailable: (_) => false),
          isNull,
        );
        expect(history.canGoBack, isFalse);
        expect(history.canGoForward, isFalse);
        history.visit('/חדש');
        expect(history.previous, forward ? '/' : '/ב');
      },
    );
  }

  test('כמה תיקיות מחוקות מדולגות בלי להפוך ליעדי קדימה', () {
    final history = LibraryNavigationHistory()
      ..visit('/')
      ..visit('/א')
      ..visit('/ב')
      ..visit('/ג');
    addTearDown(history.dispose);
    expect(history.back(isAvailable: (path) => path == '/'), '/');
    expect(history.canGoBack, isFalse);
    expect(history.forward(), '/ג');
    expect(history.canGoForward, isFalse);
  });
}
