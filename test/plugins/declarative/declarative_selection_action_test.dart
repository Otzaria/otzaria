import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_action_compiler.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_selection_action.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';

void main() {
  group('validateTemplate', () {
    test('תבנית storage.set עם הפניות סימון תקינה עוברת', () {
      DeclarativeSelectionAction.validateTemplate(
        _storageTemplate(),
        declaredPermissions: {'plugin.storage.write'},
      );
    });

    test('פקודת חישוב נדחית — רק פעולות מותרות', () {
      expect(
        () => DeclarativeSelectionAction.validateTemplate({
          'type': 'storage.get',
          'args': {'key': 'k'},
        }),
        _throwsProgramError('declarative.invalid_phase'),
      );
    });

    test('הרשאה שלא הוצהרה נדחית כשההרשאות מסופקות', () {
      expect(
        () => DeclarativeSelectionAction.validateTemplate(
          _storageTemplate(),
          declaredPermissions: {'reader.open'},
        ),
        _throwsProgramError('declarative.permission_not_declared'),
      );
    });

    test('בלי הרשאות (רישום בגשר) הבדיקה המבנית עדיין רצה', () {
      DeclarativeSelectionAction.validateTemplate(_storageTemplate());
      expect(
        () => DeclarativeSelectionAction.validateTemplate({
          'type': 'storage.set',
          'args': {'key': 'k', 'value': 1, 'extra': true},
        }),
        _throwsProgramError('declarative.unknown_field'),
      );
    });

    test('נתיב סימון שאינו ברשימה המותרת נדחה', () {
      expect(
        () => DeclarativeSelectionAction.validateTemplate({
          'type': 'storage.set',
          'args': {
            'key': 'k',
            'value': {r'$selection': 'selection'},
          },
        }),
        _throwsProgramError('declarative.invalid_reference'),
      );
    });

    test(r'הפניות $output ו-$result אינן זמינות בתפריט הקשר', () {
      for (final ref in const [r'$output', r'$result', r'$context', r'$row']) {
        expect(
          () => DeclarativeSelectionAction.validateTemplate({
            'type': 'storage.set',
            'args': {
              'key': 'k',
              'value': {ref: 'anything'},
            },
          }),
          _throwsProgramError('declarative.invalid_reference'),
        );
      }
    });

    test('תבנית עמוקה או גדולה מדי נדחית', () {
      Object deep = 1;
      for (var i = 0; i < 12; i++) {
        deep = {'nested': deep};
      }
      expect(
        () => DeclarativeSelectionAction.validateTemplate({
          'type': 'storage.set',
          'args': {'key': 'k', 'value': deep},
        }),
        _throwsProgramError('declarative.value_too_large'),
      );
    });
  });

  group('מקור הלחיצה', () {
    Map<String, dynamic> template(Map<String, dynamic> value) => {
      'type': 'storage.set',
      'args': {'key': 'k', 'value': value},
    };

    test(r'$book מותר רק בספר ספק, ו-$selection רק בתפריט הקשר', () {
      DeclarativeSelectionAction.validateTemplate(
        template({r'$book': 'id'}),
        source: DeclarativeClickSource.libraryBook,
      );
      expect(
        () => DeclarativeSelectionAction.validateTemplate(
          template({r'$book': 'id'}),
        ),
        _throwsProgramError('declarative.invalid_reference'),
      );
      expect(
        () => DeclarativeSelectionAction.validateTemplate(
          template({r'$selection': 'selectedText'}),
          source: DeclarativeClickSource.libraryBook,
        ),
        _throwsProgramError('declarative.invalid_reference'),
      );
    });

    test(r'נתיב $book שאינו ברשימה המותרת נדחה', () {
      expect(
        () => DeclarativeSelectionAction.validateTemplate(
          template({r'$book': 'externalLibraryId'}),
          source: DeclarativeClickSource.libraryBook,
        ),
        _throwsProgramError('declarative.invalid_reference'),
      );
    });

    test(r'$storage דורש הצהרת קריאה בשני מקורות הלחיצה', () {
      for (final source in DeclarativeClickSource.values) {
        final action = template({r'$storage': 'saved'});
        expect(
          () => DeclarativeSelectionAction.validateTemplate(
            action,
            source: source,
            declaredPermissions: const {'plugin.storage.write'},
          ),
          _throwsProgramError('declarative.permission_not_declared'),
        );
        DeclarativeSelectionAction.validateTemplate(
          action,
          source: source,
          declaredPermissions: const {
            'plugin.storage.write',
            'plugin.storage.read',
          },
        );
        DeclarativeSelectionAction.validateTemplate(
          template({
            r'$literal': {r'$storage': 'notRead'},
          }),
          source: source,
          declaredPermissions: const {'plugin.storage.write'},
        );
      }
    });

    test(r'$storage מותר בשני המקורות, עם מפתח תקין בלבד', () {
      for (final source in DeclarativeClickSource.values) {
        DeclarativeSelectionAction.validateTemplate(
          template({r'$storage': 'servicePort'}),
          source: source,
        );
      }
      for (final key in <Object?>['', 'א' * 129, 'a\nb', 7, null]) {
        expect(
          () => DeclarativeSelectionAction.validateTemplate(
            template({r'$storage': key}),
          ),
          _throwsProgramError('declarative.invalid_reference'),
          reason: '$key',
        );
      }
    });
  });

  group('localService.post בהתקנה', () {
    Map<String, dynamic> local(Map<String, dynamic> args) => {
      'type': 'localService.post',
      'args': {'port': 39700, 'path': '/x', ...args},
    };

    test('ערך מילולי שגוי נדחה כבר בבדיקת התבנית', () {
      for (final args in <Map<String, dynamic>>[
        {'port': 70000},
        {'port': null},
        {'path': '/a?b=1'},
        {'path': '/a/../b'},
        {'timeoutMs': 10},
        {'body': 'q=1'},
        {'pendingMessage': ''},
      ]) {
        expect(
          () => DeclarativeSelectionAction.validateTemplate(local(args)),
          _throwsProgramError('declarative.invalid_args'),
          reason: '$args',
        );
      }
    });

    test('הפניות נבדקות רק בזמן הלחיצה', () {
      DeclarativeSelectionAction.validateTemplate(
        local({
          'port': {r'$storage': 'servicePort'},
          'path': {
            r'$concat': [
              '/',
              {r'$storage': 'route'},
            ],
          },
          'body': {
            'q': {r'$selection': 'selectedText'},
          },
          'unavailableMessage': {r'$storage': 'offlineText'},
        }),
      );
    });
  });

  group('storageKeys', () {
    test(r'אוסף את כל מפתחות $storage, ומדלג על ליטרלים', () {
      final keys = DeclarativeSelectionAction.storageKeys({
        'type': 'localService.post',
        'args': {
          'port': {r'$storage': 'port'},
          'path': '/x',
          'body': {
            'token': {
              r'$concat': [
                'id-',
                {r'$storage': 'token'},
              ],
            },
            'raw': {
              r'$literal': {r'$storage': 'notRead'},
            },
            'list': [
              {r'$storage': 'port'},
            ],
          },
        },
      });

      expect(keys, {'port', 'token'});
    });
  });

  group('resolve', () {
    test('טקסט ארוך מנתוני הלחיצה נחתך, ונשאר תקין לפעולה', () {
      final resolved = DeclarativeSelectionAction.resolve(
        {
          'type': 'storage.set',
          'args': {
            'key': 'k',
            'value': {r'$selection': 'selectedText'},
          },
        },
        {'selectedText': 'א' * 10000},
      );

      expect(
        (resolved['args'] as Map)['value'],
        hasLength(DeclarativeActionCompiler.maxJsonStringLength),
      );
    });

    test('סימון של כמה שורות עובר כשורה אחת, ונשאר תקין לפעולה', () {
      final template = {
        'type': 'localService.post',
        'args': {
          'port': 39700,
          'path': '/text/search',
          'body': {
            'q': {r'$selection': 'selectedText'},
          },
        },
      };

      final resolved = DeclarativeSelectionAction.resolve(template, {
        'selectedText': 'נר\r\nשבת\tקודש\n\nויום',
      });

      expect(resolved['args']['body'], {'q': 'נר שבת קודש ויום'});
      const DeclarativeActionCompiler(
        declaredPermissions: {'network.localhost'},
      ).compileResolved(
        resolved,
        contextSignature: 'reader.selection',
        programGeneration: 1,
      );
    });

    test('חיתוך אינו מפצל זוג surrogate', () {
      const max = DeclarativeActionCompiler.maxJsonStringLength;
      final resolved = DeclarativeSelectionAction.resolve(
        {
          'type': 'storage.set',
          'args': {
            'key': 'k',
            'value': {r'$selection': 'selectedText'},
          },
        },
        {'selectedText': '${'א' * (max - 1)}😀סוף'},
      );

      final value = (resolved['args'] as Map)['value'] as String;
      expect(value, hasLength(max - 1));
      expect(value.codeUnitAt(value.length - 1), 'א'.codeUnitAt(0));
    });

    test(r'מציב ערכי $book ו-$storage; מפתח שאינו קיים נפתר ל-null', () {
      final resolved = DeclarativeSelectionAction.resolve(
        {
          'type': 'localService.post',
          'args': {
            'port': {r'$storage': 'port'},
            'path': '/book/open',
            'body': {
              'id': {r'$book': 'id'},
              'title': {r'$book': 'title'},
              'missing': {r'$storage': 'missing'},
            },
          },
        },
        {'id': 7, 'title': 'אבני נזר'},
        storage: {
          'port': 39701,
          'missing': null,
        },
      );

      expect(resolved['args'], {
        'port': 39701,
        'path': '/book/open',
        'body': {'id': 7, 'title': 'אבני נזר', 'missing': null},
      });
    });

    test('מציב ערכי סימון, ליטרלים ו-concat', () {
      final resolved = DeclarativeSelectionAction.resolve(_storageTemplate(), {
        'id': 42,
        'currentBook': 'ברכות',
        'currentIndex': 7,
      });

      expect(resolved['type'], 'storage.set');
      expect(resolved['args'], {
        'key': 'savedBooks',
        'value': {
          'id': 42,
          'title': 'ברכות',
          'label': 'ברכות (7)',
          'pinned': true,
        },
      });
    });

    test('נתיב שחסר ב-payload נפתר ל-null', () {
      final resolved = DeclarativeSelectionAction.resolve(
        {
          'type': 'storage.set',
          'args': {
            'key': 'k',
            'value': {r'$selection': 'currentRef'},
          },
        },
        const {'currentBook': 'ברכות'},
      );

      expect((resolved['args'] as Map)['value'], isNull);
    });
  });
}

Map<String, dynamic> _storageTemplate() => {
  'type': 'storage.set',
  'args': {
    'key': 'savedBooks',
    'value': {
      'id': {r'$selection': 'id'},
      'title': {r'$selection': 'currentBook'},
      'label': {
        r'$concat': [
          {r'$selection': 'currentBook'},
          ' (',
          {r'$selection': 'currentIndex'},
          ')',
        ],
      },
      'pinned': {r'$literal': true},
    },
  },
};

Matcher _throwsProgramError(String code) => throwsA(
  isA<DeclarativeProgramException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);
