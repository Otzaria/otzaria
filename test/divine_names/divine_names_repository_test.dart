import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/models/book_source.dart';

void main() {
  final repository = DivineNamesRepository.instance;
  var loads = 0;
  final loaded = (DivineNameSpansBuilder()..add(0, 0, 5, DivineNameKind.elohim))
      .build();

  setUp(() {
    loads = 0;
    repository.clear();
    repository.debugLoader = (title, {categoryId, required source}) async {
      loads++;
      return loaded;
    };
  });
  tearDown(() {
    repository
      ..debugLoader = null
      ..debugIsDatabaseBook = null
      ..clear();
  });

  test('ספר אישי ומהדורה חלופית — ריק, בלי טעינה', () async {
    expect(
      (await repository.spansFor('ספר', source: BookSource.user)).isEmpty,
      isTrue,
    );
    expect(
      (await repository.spansFor('ספר', versionTitle: 'נוסח')).isEmpty,
      isTrue,
    );
    expect(loads, 0);
  });

  test(
    'טאב משוחזר בעלייה: המופעים מחכים לאיתור הספק ולא נשמרים ריקים',
    () async {
      // המיפוי עוד לא נבנה בזמן הקריאה; האיתור מסתיים רק אחריה.
      final providerReady = Completer<bool>();
      repository.debugIsDatabaseBook = (title, {categoryId, fileType}) =>
          providerReady.future;

      final pending = repository.spansFor('ספר', categoryId: 1);
      await Future<void>.delayed(Duration.zero);
      expect(loads, 0);
      providerReady.complete(true);
      expect(await pending, same(loaded));
      expect(await repository.spansFor('ספר', categoryId: 1), same(loaded));
      expect(loads, 1);
    },
  );

  test('ספר שמוגש מקובץ — ריק, בלי טעינה מהמסד', () async {
    repository.debugIsDatabaseBook = (title, {categoryId, fileType}) async =>
        false;
    expect((await repository.spansFor('ספר', categoryId: 1)).isEmpty, isTrue);
    expect(loads, 0);
  });
}
