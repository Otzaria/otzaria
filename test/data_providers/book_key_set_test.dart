import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/book_key_set.dart';

BookCompositeKey key(String title, int categoryId, {String fileType = 'txt'}) =>
    BookCompositeKey.create(
      title: title,
      categoryId: categoryId,
      fileType: fileType,
    );

void main() {
  group('BookKeySet.firstMatch', () {
    test('returns null for an empty set', () {
      expect(BookKeySet().firstMatch('בראשית', 'txt'), isNull);
    });

    test('matches title and file type, optionally scoped to category', () {
      final first = key('בראשית', 1);
      final second = key('בראשית', 2);
      final pdf = key('בראשית', 1, fileType: 'pdf');
      final keys = BookKeySet()
        ..add(first)
        ..add(second)
        ..add(pdf);

      expect(keys.firstMatch('בראשית', 'txt'), same(first));
      expect(keys.firstMatch('בראשית', 'txt', 2), same(second));
      expect(keys.firstMatch('בראשית', 'pdf'), same(pdf));
      expect(keys.firstMatch('שמות', 'txt'), isNull);
    });

    test('invalidates cached misses and hits after add and remove', () {
      final keys = BookKeySet();
      expect(keys.firstMatch('בראשית', 'txt'), isNull);

      final first = key('בראשית', 1);
      keys.add(first);
      expect(keys.firstMatch('בראשית', 'txt'), same(first));

      keys.remove(first);
      expect(keys.firstMatch('בראשית', 'txt'), isNull);
    });

    test('clear removes keys and cached matches', () {
      final keys = BookKeySet()..add(key('בראשית', 1));
      expect(keys.firstMatch('בראשית', 'txt'), isNotNull);

      keys.clear();

      expect(keys, isEmpty);
      expect(keys.firstMatch('בראשית', 'txt'), isNull);
    });
  });

  test('implements normal Set semantics', () {
    final first = key('בראשית', 1);
    final equal = key('בראשית', 1);
    final keys = BookKeySet();

    expect(keys.add(first), isTrue);
    expect(keys.add(equal), isFalse);
    expect(keys.contains(equal), isTrue);
    expect(keys.lookup(equal), same(first));
    expect(keys.length, 1);
    expect(keys.toSet(), {first});
    expect(keys.remove(equal), isTrue);
    expect(keys.remove(equal), isFalse);
  });
}
