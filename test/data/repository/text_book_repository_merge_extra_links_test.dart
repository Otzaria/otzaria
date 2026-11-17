import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';

Link _link({
  int? index1End,
  int? targetCategoryId,
  int? targetBookId,
  String? targetFileType,
  int? anchorStart,
  BookSource targetSource = BookSource.official,
}) => Link(
  heRef: 'א',
  index1: 1,
  index1End: index1End,
  path2: 'מפרש',
  index2: 1,
  connectionType: 'COMMENTARY',
  targetCategoryId: targetCategoryId,
  targetBookId: targetBookId,
  targetFileType: targetFileType,
  targetSource: targetSource,
  anchorStart: anchorStart,
);

void main() {
  test('מקורות פתוחים נטענים במקביל ומתמזגים לפי סדר המקורות', () async {
    final base = Completer<List<Link>>();
    final user = Completer<List<Link>>();
    final external = Completer<List<Link>>();
    final started = <String>[];
    final baseLink = _link(targetBookId: 1);
    final userLink = _link(targetBookId: 2);
    final externalLink = _link(targetBookId: 3);
    final result = TextBookRepository.loadLinkSources(
      base: base.future,
      userReady: true,
      externalReady: true,
      loadUser: () {
        started.add('user');
        return user.future;
      },
      loadExternal: () {
        started.add('external');
        return external.future;
      },
    );

    expect(started, ['user', 'external']);
    external.complete([userLink, externalLink]);
    user.complete([baseLink, userLink]);
    base.complete([baseLink]);
    expect(await result, [baseLink, userLink, externalLink]);
  });

  test('מקור שעדיין סגור ממתין לטעינת הבסיס', () async {
    final base = Completer<List<Link>>();
    final started = <String>[];
    final result = TextBookRepository.loadLinkSources(
      base: base.future,
      userReady: false,
      externalReady: true,
      loadUser: () async {
        started.add('user');
        return [];
      },
      loadExternal: () async {
        started.add('external');
        return [];
      },
    );

    expect(started, ['external']);
    base.complete([]);
    expect(await result, isEmpty);
    expect(started, ['external', 'user']);
  });

  test('שגיאה מוקדמת ממקור מאוחר אינה עוקפת את שגיאת הבסיס', () async {
    final base = Completer<List<Link>>();
    final external = Completer<List<Link>>();
    final baseError = StateError('base');
    final result = TextBookRepository.loadLinkSources(
      base: base.future,
      userReady: false,
      externalReady: true,
      loadUser: () async => fail('טעינת המשתמש לא אמורה להתחיל'),
      loadExternal: () => external.future,
    );
    final expectation = expectLater(result, throwsA(same(baseError)));
    external.completeError(StateError('external'));
    await Future<void>.delayed(Duration.zero);
    base.completeError(baseError);
    await expectation;
  });

  test('mergeExtraLinks משמר טווחים, עוגנים ומקורות יעד שונים', () {
    final links = [
      _link(index1End: 3),
      _link(index1End: 4),
      _link(anchorStart: 2),
      _link(anchorStart: 5),
      _link(targetCategoryId: 1),
      _link(targetCategoryId: 2),
      _link(targetSource: BookSource.user),
    ];
    expect(TextBookRepository.mergeExtraLinks([], links), links);
    expect(TextBookRepository.mergeExtraLinks([links.first], [links.first]), [
      links.first,
    ]);
  });

  test('mergeExtraLinks משמר ספרי יעד וסוגי קובץ שונים', () {
    final links = [
      _link(targetBookId: 10, targetFileType: 'txt'),
      _link(targetBookId: 20, targetFileType: 'txt'),
      _link(targetBookId: 10, targetFileType: 'pdf'),
    ];
    expect(TextBookRepository.mergeExtraLinks([], links), links);
  });
}
