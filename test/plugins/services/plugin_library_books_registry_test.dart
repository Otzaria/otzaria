import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/models/plugin_library_book_provider.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';

class _FakeRepo implements PluginRegistryRepository {
  final Map<String, String> kv = {};
  int writes = 0;

  static String _key(String pluginId, String namespace, String key) =>
      '$pluginId|$namespace|$key';

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv[_key(pluginId, namespace, key)];

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {
    writes++;
    kv[_key(pluginId, namespace, key)] = valueJson;
  }

  @override
  Future<void> removeKV(String pluginId, String namespace, String key) async =>
      kv.remove(_key(pluginId, namespace, key));

  @override
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async => {
    for (final key in keys) key: ?kv[_key(pluginId, namespace, key)],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Dispatched = ({
  String pluginId,
  String topic,
  Map<String, dynamic> payload,
});

const _storedKey = 'p1|otzaria.library-books|mylib';

Map<String, dynamic> _provider({
  String id = 'books',
  String provider = 'mylib',
  String title = 'הספרייה שלי',
  Object? when,
}) => {
  'id': id,
  'provider': provider,
  'title': title,
  'when': ?when,
};

/// הטעינה מה-DB מפוענחת ב-isolate, ולכן לוקחת זמן אמיתי.
Future<void> _eventually(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late _FakeRepo repo;
  late PluginConditionEvaluator conditions;
  late PluginLibraryBooksRegistry registry;
  late List<_Dispatched> dispatched;

  setUp(() {
    repo = _FakeRepo();
    conditions = PluginConditionEvaluator.forTesting(
      settingReader: (_) => null,
    );
    dispatched = [];
    registry = PluginLibraryBooksRegistry.forTesting(
      dispatch: (pluginId, topic, payload) async =>
          dispatched.add((pluginId: pluginId, topic: topic, payload: payload)),
      conditions: conditions,
      repository: repo,
    );
  });

  group('שם הספק', () {
    test('שם באותיות קטנות שאינו מתנגש מתקבל', () {
      for (final name in ['mylib', 'my-lib', 'lib2']) {
        expect(
          PluginLibraryBookProvider.isValidProviderName(name),
          isTrue,
          reason: name,
        );
      }
    });

    test('ספק מובנה, קידומת מובנית ושם שנקרא כספק מובנה נדחים', () {
      for (final name in [
        'hebrewbooks',
        'otzar',
        'hb',
        'oh',
        'otz',
        'hebrew',
        'myoh',
        'myhb',
        'xotzarx',
        'otzaria-books',
        'MyLib',
        'r',
        '1books',
      ]) {
        expect(
          PluginLibraryBookProvider.isValidProviderName(name),
          isFalse,
          reason: name,
        );
      }
    });
  });

  group('רישום', () {
    test('שדה לא מוכר, מזהה חסר, אייקון שגוי ושם ארוך נדחים', () {
      for (final item in [
        {..._provider(), 'extra': 1},
        {..._provider()}..remove('id'),
        {..._provider(), 'icon': 'not-an-icon'},
        {..._provider(), 'title': ''},
        {..._provider(), 'title': 'א' * 41},
        {..._provider(), 'when': 'yes'},
        {..._provider(), 'openAction': 'open'},
        {
          ..._provider(),
          'openAction': {
            'type': 'storage.get',
            'args': {'key': 'k'},
          },
        },
        // נתוני הסימון אינם קיימים בלחיצה על ספר.
        {
          ..._provider(),
          'openAction': {
            'type': 'storage.set',
            'args': {
              'key': 'k',
              'value': {r'$selection': 'selectedText'},
            },
          },
        },
      ]) {
        expect(
          () => registry.registerPayload('p1', item),
          throwsA(isA<PluginLibraryBooksException>()),
          reason: '$item',
        );
      }
    });

    test('ספק ששייך לתוסף אחר נדחה', () {
      registry.registerPayload('p1', _provider());

      expect(
        () => registry.registerPayload('p2', _provider()),
        throwsA(isA<PluginLibraryBooksException>()),
      );
      expect(registry.isOwner('p1', 'mylib'), isTrue);
    });

    test('עד שני ספקים לתוסף', () {
      registry.registerPayload('p1', _provider(id: 'a', provider: 'first'));
      registry.registerPayload('p1', _provider(id: 'b', provider: 'second'));

      expect(
        () => registry.registerPayload(
          'p1',
          _provider(id: 'c', provider: 'third'),
        ),
        throwsA(isA<PluginLibraryBooksException>()),
      );
    });

    test('אייקון התוסף משמש כשהספק לא הצהיר על אייקון', () {
      registry.registerPayload(
        'p1',
        _provider(),
        fallbackIconName: 'library_24_regular',
      );

      expect(registry.providers.single.iconName, 'library_24_regular');
    });

    test('ספק רשום נטען מה-DB ומופיע בלי שהתוסף רץ', () async {
      repo.kv[_storedKey] = jsonEncode({
        'version': 1,
        'books': [
          [7, 'אבני נזר', 'רבי אברהם בורנשטיין', '/שו"ת/אחרונים'],
        ],
      });

      registry.registerPayload('p1', _provider());
      await _eventually(() => registry.visibleBooks.isNotEmpty);

      final book = registry.visibleBooks.single;
      expect(book.title, 'אבני נזר');
      expect(book.author, 'רבי אברהם בורנשטיין');
      expect(book.categoryPath, 'שו"ת, אחרונים');
      expect(book.externalLibraryId, 'mylib:7');
      expect(registry.providerOf(book)?.provider, 'mylib');
    });

    test('רשימה שמורה פגומה אינה מפילה את הרישום', () async {
      repo.kv[_storedKey] = '{not json';

      registry.registerPayload('p1', _provider());
      await pumpEventQueue();

      expect(registry.isOwner('p1', 'mylib'), isTrue);
      expect(registry.visibleBooks, isEmpty);
    });

    test('רישום חוזר שומר את הספרים, והסרה מוחקת אותם מהזיכרון', () async {
      registry.registerPayload('p1', _provider());
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);

      registry.registerPayload('p1', _provider(title: 'שם חדש'));
      expect(registry.visibleBooks, hasLength(1));
      expect(registry.providers.single.title, 'שם חדש');

      registry.remove('p1', 'books');
      expect(registry.isOwner('p1', 'mylib'), isFalse);
      expect(registry.visibleBooks, isEmpty);
      expect(repo.kv, contains(_storedKey), reason: 'הרשאה שתוחזר תשחזר');
    });

    test('רישום חוזר זהה אינו מודיע (כל LoadPlugins מסנכרן)', () async {
      registry.registerPayload('p1', _provider());
      await pumpEventQueue();
      var notifications = 0;
      registry.addListener(() => notifications++);

      registry.registerPayload('p1', _provider());
      expect(notifications, 0);
      registry.registerPayload('p1', _provider(title: 'שם אחר'));
      expect(notifications, 1);
    });

    test('רשימת הספרים הגלויה נשמרת עד לשינוי ואינה ניתנת לשינוי', () async {
      registry.registerPayload('p1', _provider());
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);

      final snapshot = registry.visibleBooks;
      expect(identical(registry.visibleBooks, snapshot), isTrue);
      expect(() => snapshot.clear(), throwsUnsupportedError);

      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'ב'},
      ]);

      expect(identical(registry.visibleBooks, snapshot), isFalse);
      expect(registry.visibleBooks.single.title, 'ב');
    });

    test('שינוי שם הספק באותו פריט מסיר את הישן', () async {
      registry.registerPayload('p1', _provider(id: 'main', provider: 'foo'));
      await registry.setBooks('p1', 'foo', [
        {'id': 1, 'title': 'א'},
      ]);
      registry.registerPayload('p1', _provider(id: 'main', provider: 'bar'));

      expect(registry.isOwner('p1', 'foo'), isFalse);
      expect(registry.isOwner('p1', 'bar'), isTrue);
      expect(registry.visibleBooks, isEmpty);
      // המכסה אינה תפוסה בידי הספק הישן.
      registry.registerPayload('p1', _provider(id: 'second', provider: 'baz'));
      expect(registry.isOwner('p1', 'baz'), isTrue);
    });
  });

  group('setBooks', () {
    setUp(() => registry.registerPayload('p1', _provider()));

    test('מחליף את הרשימה ושומר אותה בצורה המקוצרת', () async {
      final count = await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': ' חידושי הרשב"א ', 'author': 'הרשב"א'},
        {'id': 2, 'title': 'אבני נזר', 'categoryPath': 'שו"ת/ אחרונים/'},
      ]);

      expect(count, 2);
      expect(registry.booksOf('mylib').map((b) => b.title), [
        'חידושי הרשב"א',
        'אבני נזר',
      ]);
      expect(registry.booksOf('mylib').last.categoryPath, 'שו"ת, אחרונים');
      expect(jsonDecode(repo.kv[_storedKey]!), {
        'version': 1,
        'books': [
          [1, 'חידושי הרשב"א', 'הרשב"א', null],
          [2, 'אבני נזר', null, '/שו"ת/אחרונים'],
        ],
      });
    });

    test('תווי בקרה וכיוון בטקסט מוחלפים ברווח אחד', () async {
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'שורה\nשנייה', 'author': '\u200Fרבי\t יוסף\u202E'},
      ]);

      final book = registry.booksOf('mylib').single;
      expect(book.title, 'שורה שנייה');
      expect(book.author, 'רבי יוסף');
    });

    test('אותה רשימה שוב אינה נכתבת ואינה מודיעה', () async {
      final books = [
        {'id': 1, 'title': 'א', 'categoryPath': '/שו"ת'},
      ];
      await registry.setBooks('p1', 'mylib', books);
      var notifications = 0;
      registry.addListener(() => notifications++);
      final writes = repo.writes;

      expect(await registry.setBooks('p1', 'mylib', books), 1);
      expect(repo.writes, writes);
      expect(notifications, 0);

      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א', 'categoryPath': '/שו"ת/אחרונים'},
      ]);
      expect(repo.writes, writes + 1);
      expect(notifications, 1);
    });

    test('שתי שליחות חופפות: האחרונה קובעת, גם כשהיא הרשימה המוצגת', () async {
      final shown = [
        {'id': 1, 'title': 'מוצג'},
      ];
      await registry.setBooks('p1', 'mylib', shown);

      final first = registry.setBooks('p1', 'mylib', [
        {'id': 2, 'title': 'ביניים'},
      ]);
      final second = registry.setBooks('p1', 'mylib', shown);
      await Future.wait([first, second]);

      expect(registry.booksOf('mylib').single.title, 'מוצג');
      expect(
        (jsonDecode(repo.kv[_storedKey]!) as Map)['books'],
        [
          [1, 'מוצג', null, null],
        ],
      );
    });

    test('ספר שלא השתנה שומר את האובייקט (והתצוגה המקדימה נשארת)', () async {
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
        {'id': 2, 'title': 'ב'},
      ]);
      final before = registry.booksOf('mylib');

      await registry.setBooks('p1', 'mylib', [
        {'id': 2, 'title': 'ב'},
        {'id': 1, 'title': 'א מתוקן'},
        {'id': 3, 'title': 'ג'},
      ]);
      final after = registry.booksOf('mylib');

      expect(after[0], same(before[1]));
      expect(after[1], isNot(same(before[0])));
      expect(after[1].title, 'א מתוקן');
      expect(registry.providerOf(after[2])?.provider, 'mylib');
    });

    test('רשימה ריקה שוב אינה נכתבת ואינה מודיעה', () async {
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);
      await registry.setBooks('p1', 'mylib', []);
      var notifications = 0;
      registry.addListener(() => notifications++);

      await registry.setBooks('p1', 'mylib', []);

      expect(notifications, 0);
    });

    test('נתיב: נרמול, אורך אחרי הנרמול, ושמירה שנטענת שוב', () async {
      final longest = '/${'א' * 299}';
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א', 'categoryPath': '//שו"ת// אחרונים//'},
        {'id': 2, 'title': 'ב', 'categoryPath': '/'},
        {'id': 3, 'title': 'ג', 'categoryPath': 'א' * 299},
      ]);
      expect(registry.booksOf('mylib').map((b) => b.categoryPath), [
        'שו"ת, אחרונים',
        null,
        'א' * 299,
      ]);
      await expectLater(
        registry.setBooks('p1', 'mylib', [
          {'id': 1, 'title': 'א', 'categoryPath': 'א' * 300},
        ]),
        throwsA(isA<PluginLibraryBooksException>()),
        reason: 'עם ה-"/" שנוסף הנתיב ארוך מ-300',
      );

      final restored = PluginLibraryBooksRegistry.forTesting(
        dispatch: (_, _, _) async {},
        conditions: conditions,
        repository: repo,
      );
      restored.registerPayload('p1', _provider());
      await _eventually(() => restored.visibleBooks.length == 3);
      expect(restored.visibleBooks.last.categoryPath, longest.substring(1));
    });

    test('רשימה ריקה מסירה את הספרים גם מה-DB', () async {
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);
      await registry.setBooks('p1', 'mylib', []);

      expect(registry.booksOf('mylib'), isEmpty);
      expect(repo.kv, isNot(contains(_storedKey)));
    });

    test('רשימה לא תקינה נדחית בשלמותה', () async {
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'קיים'},
      ]);
      for (final raw in <Object?>[
        null,
        'books',
        [
          {'id': 0, 'title': 'א'},
        ],
        [
          {'id': 1.5, 'title': 'א'},
        ],
        [
          {'id': 1},
        ],
        [
          {'id': 1, 'title': '  '},
        ],
        [
          {'id': 1, 'title': 'א', 'author': 3},
        ],
        [
          {'id': 1, 'title': 'א', 'categoryPath': 5},
        ],
        [
          {'id': 1, 'title': 'א' * 301},
        ],
        [
          {'id': 1, 'title': 'א'},
          {'id': 1, 'title': 'ב'},
        ],
        // הצורה המקוצרת מתקבלת רק מהאחסון, לא מהתוסף.
        [
          [1, 'א', null, null],
        ],
      ]) {
        await expectLater(
          registry.setBooks('p1', 'mylib', raw),
          throwsA(
            isA<PluginLibraryBooksException>().having(
              (e) => e.notFound,
              'notFound',
              isFalse,
            ),
          ),
          reason: '$raw',
        );
      }
      expect(registry.booksOf('mylib').single.title, 'קיים');
    });

    test('ספק שאינו של התוסף: notFound', () async {
      for (final provider in ['mylib', 'unknown']) {
        await expectLater(
          registry.setBooks('p2', provider, []),
          throwsA(
            isA<PluginLibraryBooksException>().having(
              (e) => e.notFound,
              'notFound',
              isTrue,
            ),
          ),
        );
      }
    });

    test('טעינה מה-DB שמסתיימת אחרי setBooks אינה דורסת אותו', () async {
      repo.kv['p1|otzaria.library-books|late'] = jsonEncode({
        'version': 1,
        'books': [
          [9, 'ישן', null, null],
        ],
      });
      registry.registerPayload('p1', _provider(id: 'late', provider: 'late'));
      await registry.setBooks('p1', 'late', [
        {'id': 1, 'title': 'חדש'},
      ]);
      await pumpEventQueue();

      expect(registry.booksOf('late').single.title, 'חדש');
    });

    test('איפוס נתונים מנקה את הספרים ומשאיר את הספק לשליחה מחדש', () async {
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);

      registry.clearBooks('p1');
      expect(registry.visibleBooks, isEmpty);
      expect(registry.isOwner('p1', 'mylib'), isTrue);

      // אותה רשימה אחרי האיפוס נשמרת שוב: היא כבר אינה ב-DB.
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);
      expect(registry.visibleBooks.single.title, 'א');
      expect(repo.kv, contains(_storedKey));
    });

    test('כתיבה שהחלה לפני איפוס או הסרה אינה מחזירה את הרשימה', () async {
      final writing = registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);
      registry.clearBooks('p1');
      await writing;
      expect(repo.kv, isNot(contains(_storedKey)));
      expect(registry.visibleBooks, isEmpty);

      final uninstalling = registry.setBooks('p1', 'mylib', [
        {'id': 2, 'title': 'ב'},
      ]);
      registry.removePlugin('p1');
      await uninstalling;
      expect(repo.kv, isNot(contains(_storedKey)));
      expect(registry.visibleBooks, isEmpty);
    });
  });

  group('תנאי when', () {
    test('ספק שהתנאי שלו לא מתקיים אינו מוצג, ונחשף מיד כשמתקיים', () async {
      registry.registerPayload(
        'p1',
        _provider(
          when: {
            'storage': {'key': 'show', 'notEquals': false},
          },
        ),
      );
      await registry.setBooks('p1', 'mylib', [
        {'id': 1, 'title': 'א'},
      ]);
      var notifications = 0;
      registry.addListener(() => notifications++);

      repo.kv['p1|default|show'] = 'false';
      await conditions.registerStorageKeys('p1', {'show'}, repo);
      expect(registry.visibleBooks, isEmpty);
      expect(notifications, 1);

      repo.kv['p1|default|show'] = 'true';
      await conditions.registerStorageKeys('p1', {'show'}, repo);
      expect(registry.visibleBooks, hasLength(1));
      expect(notifications, 2);
    });

    test('שינוי מפתח שאינו משנה את הנראות אינו מודיע', () async {
      registry.registerPayload('p1', _provider());
      var notifications = 0;
      registry.addListener(() => notifications++);

      repo.kv['p2|default|other'] = '1';
      await conditions.registerStorageKeys('p2', {'other'}, repo);

      expect(notifications, 0);
    });
  });

  group('פתיחה וזהות', () {
    late ExternalLibraryBook book;

    setUp(() async {
      registry.registerPayload('p1', _provider());
      await registry.setBooks('p1', 'mylib', [
        {'id': 7008, 'title': 'אבני נזר', 'author': 'רבי אברהם'},
      ]);
      book = registry.booksOf('mylib').single;
    });

    test('פתיחה נמסרת לתוסף הבעלים עם זהות הספר', () {
      expect(registry.open(book), isTrue);

      expect(dispatched.single.pluginId, 'p1');
      expect(
        dispatched.single.topic,
        PluginLibraryBooksRegistry.openRequestedTopic,
      );
      expect(dispatched.single.payload, {
        'provider': 'mylib',
        'id': 7008,
        'title': 'אבני נזר',
        'author': 'רבי אברהם',
      });
    });

    test('openAction מבוצע בלי לשלוח אירוע לתוסף', () async {
      final action = {
        'type': 'localService.post',
        'args': {
          'port': {r'$storage': 'servicePort'},
          'path': '/book/open',
          'body': {
            'id': {r'$book': 'id'},
          },
        },
      };
      registry.registerPayload('p1', {..._provider(), 'openAction': action});
      final runs = <(String, Map<String, dynamic>, Map<String, dynamic>)>[];

      expect(
        registry.open(
          book,
          actionDispatcher: (pluginId, template, payload) async =>
              runs.add((pluginId, template, payload)),
        ),
        isTrue,
      );

      expect(dispatched, isEmpty);
      expect(runs.single.$1, 'p1');
      expect(runs.single.$2, action);
      expect(runs.single.$3, {
        'provider': 'mylib',
        'id': 7008,
        'title': 'אבני נזר',
        'author': 'רבי אברהם',
      });
    });

    test('openAction בלי מבצע (עץ בלי מערכת התוספים): נשלח האירוע', () {
      registry.registerPayload('p1', {
        ..._provider(),
        'openAction': {
          'type': 'ui.showSnack',
          'args': {'message': 'פתיחה'},
        },
      });

      expect(registry.open(book), isTrue);

      expect(
        dispatched.single.topic,
        PluginLibraryBooksRegistry.openRequestedTopic,
      );
    });

    test('שינוי openAction בלבד הוא שינוי ברישום', () {
      registry.registerPayload('p1', _provider());
      var notified = 0;
      registry.addListener(() => notified++);

      registry.registerPayload('p1', {
        ..._provider(),
        'openAction': {
          'type': 'ui.showSnack',
          'args': {'message': 'פתיחה'},
        },
      });

      expect(notified, 1);
    });

    test('ספר מובנה או ספר של ספק שהוסר אינו נפתח דרך התוסף', () {
      final hebrewBook = ExternalLibraryBook(
        title: 'ספר',
        id: 5,
        link: 'https://hebrewbooks.org/5',
        externalLibraryId: 'hb:5',
      );
      expect(registry.open(hebrewBook), isFalse);

      registry.removePlugin('p1');
      expect(registry.open(book), isFalse);
      expect(dispatched, isEmpty);
    });

    test('ספר שנשאר מתוסף שהוסר אינו נמסר לתוסף שתפס את שם הספק', () {
      registry.removePlugin('p1');
      registry.registerPayload('p2', _provider());

      expect(registry.providerOf(book), isNull);
      expect(registry.open(book), isFalse);
      expect(dispatched, isEmpty);
    });

    test('ספר עם מזהה של ספק שלא נוצר ברשימה אינו של התוסף', () {
      final forged = ExternalLibraryBook(
        title: 'אבני נזר',
        id: 7008,
        link: '',
        externalLibraryId: 'mylib:7008',
      );

      expect(registry.providerOf(forged), isNull);
    });

    test('ספר ספק אינו נחשף כזהות חיצונית ל-SDK: נפתח רק מהספרייה', () {
      expect(registry.providerOf(book)?.provider, 'mylib');
      expect(PluginBookIdentity.externalOf(book), isNull);
      expect(PluginBookIdentity.toJson(book).containsKey('external'), isFalse);
    });
  });
}
