import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/category_merge_targets.dart';
import 'package:otzaria/library/models/library.dart';

Category category(String title) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

String normalizeTitle(String title) =>
    title.replaceAll(RegExp(r'''['"״׳’”“]'''), '').trim();

void main() {
  test('finds categories by normalized title', () {
    final torah = category('תנ״ך');
    final targets = CategoryMergeTargets([torah], normalizeTitle);

    expect(targets.find('תנך'), same(torah));
    expect(targets.find('  תנ״ך  '), same(torah));
    expect(targets.find('משנה'), isNull);
  });

  test('first existing category wins for duplicate normalized titles', () {
    final first = category('תנ״ך');
    final second = category('תנך');
    final targets = CategoryMergeTargets([first, second], normalizeTitle);

    expect(targets.find('תנך'), same(first));
  });

  test('add updates both the source list and lookup index', () {
    final categories = <Category>[category('תנ״ך')];
    final targets = CategoryMergeTargets(categories, normalizeTitle);
    final newCategory = category('משנה');

    targets.add(newCategory);

    expect(categories, [categories.first, newCategory]);
    expect(targets.find('משנה'), same(newCategory));
  });

  test('adding an equivalent title does not replace the first match', () {
    final first = category('תנ״ך');
    final categories = <Category>[first];
    final targets = CategoryMergeTargets(categories, normalizeTitle);
    final duplicate = category('תנך');

    targets.add(duplicate);

    expect(targets.find('תנ״ך'), same(first));
    expect(categories, hasLength(2));
  });
}
