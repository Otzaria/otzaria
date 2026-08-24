import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_program_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';

void main() {
  group('DeclarativeProgramCompiler', () {
    test('מקמפל תכנית תקינה עם references לאחור בלבד', () {
      final compiled = _compiler().compile(_validProgram());

      expect(compiled.id, 'parallel-editions');
      expect(compiled.commands, hasLength(4));
      expect(
        compiled.requiredPermissions,
        {'database.read', 'library.books.read'},
      );
      expect(
        () => compiled.outputs['extra'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => compiled.commands.first.args['limit'] = 100,
        throwsUnsupportedError,
      );
    });

    test('library.parallelEditions מתקמפלת כפקודת חישוב עם זהות מהקשר', () {
      final compiled = _compiler().compile({
        'id': 'native-editions',
        'version': 1,
        'triggers': ['reader.activeBookChanged'],
        'commands': [
          {
            'id': 'editions',
            'type': 'library.parallelEditions',
            'args': {
              'identity': {
                'id': {r'$context': 'reader.book.id'},
                'bookId': {r'$context': 'reader.book.bookId'},
                'type': {r'$context': 'reader.book.type'},
                'source': {r'$context': 'reader.book.source'},
                'external': {
                  'provider': {r'$context': 'reader.book.external.provider'},
                  'id': {r'$context': 'reader.book.external.id'},
                },
              },
            },
          },
        ],
        'outputs': {
          'editions': {r'$result': 'editions'},
        },
      });

      expect(compiled.commands.single.type, 'library.parallelEditions');
      expect(compiled.requiredPermissions, {'library.books.read'});
    });

    test('פקודה לא מוכרת נדחית', () {
      final program = _validProgram();
      (program['commands'] as List<dynamic>)[0] = {
        'id': 'unsafe',
        'type': 'database.rawSql',
        'args': {'sql': 'DELETE FROM books'},
      };

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.unknown_command'),
      );
    });

    test('trigger שעדיין אינו מחווט בזמן ריצה נדחה', () {
      final program = _validProgram();
      program['triggers'] = ['database.sourceChanged'];

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.invalid_trigger'),
      );
    });

    test('settings.changed ו-app.startup נתמכים, גם יחד', () {
      final program = _validProgram();
      program['triggers'] = ['app.startup', 'settings.changed'];

      final compiled = _compiler().compile(program);

      expect(compiled.triggers, ['app.startup', 'settings.changed']);
    });

    test('reader.selectionChanged אינו נתמך', () {
      final program = _validProgram();
      program['triggers'] = ['reader.selectionChanged'];

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.invalid_trigger'),
      );
    });

    test('reference לפקודה עתידית נדחה', () {
      final program = _validProgram();
      (program['commands'] as List<dynamic>).insert(0, {
        'id': 'tooEarly',
        'type': 'data.first',
        'args': {
          'items': {r'$result': 'resolved'},
        },
      });

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.forward_reference'),
      );
    });

    test(r'$row מחוץ לתבנית שורה נדחה', () {
      final program = _validProgram();
      (program['outputs'] as Map<String, dynamic>)['invalid'] = {
        r'$row': 'id',
      };

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.row_out_of_scope'),
      );
    });

    test('מקור DB שאינו מוצהר נדחה', () {
      final program = _validProgram();
      final databaseCommand =
          (program['commands'] as List<dynamic>).first as Map<String, dynamic>;
      (databaseCommand['args'] as Map<String, dynamic>)['sourceId'] =
          'app.library.main';

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.source_not_declared'),
      );
    });

    test('הרשאה חסרה נדחית בזמן קומפילציה', () {
      final compiler = DeclarativeProgramCompiler(
        declaredPermissions: const {'database.read'},
        declaredSourceIds: const {'app.library.externalCatalog'},
      );

      expect(
        () => compiler.compile(_validProgram()),
        _throwsProgramError('declarative.permission_not_declared'),
      );
    });

    test('פקודת action אינה יכולה לרוץ בתוך תכנית חישוב', () {
      final program = _validProgram();
      (program['commands'] as List<dynamic>).add({
        'id': 'open',
        'type': 'reader.openBook',
        'args': {
          'identity': {'id': 1},
        },
      });

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.invalid_phase'),
      );
    });

    test('זהות ספר אינה מקבלת filePath או URL', () {
      final program = _validProgram();
      final resolve =
          (program['commands'] as List<dynamic>)[1] as Map<String, dynamic>;
      final identity =
          (resolve['args'] as Map<String, dynamic>)['identity']
              as Map<String, dynamic>;
      identity['filePath'] = '/tmp/book.pdf';

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.unknown_field'),
      );
    });

    test('data.first דורש reference לרשימה', () {
      final program = _validProgram();
      final first =
          (program['commands'] as List<dynamic>)[3] as Map<String, dynamic>;
      (first['args'] as Map<String, dynamic>)['items'] = {
        r'$result': 'editions',
      };

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.type_mismatch'),
      );
    });

    test('data.choose בוחר ערך באמצעות תנאי מובנה', () {
      final program = _validProgram();
      (program['commands'] as List<dynamic>).insert(3, {
        'id': 'selectedEditions',
        'type': 'data.choose',
        'args': {
          'condition': {
            'op': 'equals',
            'left': {r'$context': 'reader.book.type'},
            'right': {r'$literal': 'text'},
          },
          'whenTrue': {r'$result': 'menuItems'},
          'whenFalse': {r'$literal': <Object>[]},
        },
      });

      final compiled = _compiler().compile(program);

      expect(compiled.commands[3].type, 'data.choose');
    });

    test('עץ WHERE עמוק נדחה לפני הקפאת התוכנית', () {
      final program = _validProgram();
      final args = _databaseArgs(program);
      Object where = _leafWhere();
      for (var index = 0; index < 7; index++) {
        where = {
          'op': 'and',
          'conditions': [where],
        };
      }
      args['where'] = where;

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.value_too_large'),
      );
    });

    test('עץ WHERE רחב כפוף לתקציב הצמתים הכללי', () {
      final program = _validProgram();
      final args = _databaseArgs(program);
      args['where'] = {
        'op': 'or',
        'conditions': [
          for (var group = 0; group < 9; group++)
            {
              'op': 'and',
              'conditions': [
                for (var item = 0; item < 32; item++) _leafWhere(),
              ],
            },
        ],
      };

      expect(
        () => _compiler().compile(program),
        _throwsProgramError('declarative.value_too_large'),
      );
    });
  });
}

Map<String, dynamic> _databaseArgs(Map<String, dynamic> program) {
  final command =
      (program['commands'] as List<dynamic>).first as Map<String, dynamic>;
  return command['args'] as Map<String, dynamic>;
}

Map<String, dynamic> _leafWhere() => {
  'op': '=',
  'left': 'm.internal_id',
  'value': {r'$literal': 1},
};

DeclarativeProgramCompiler _compiler() => const DeclarativeProgramCompiler(
  declaredPermissions: {
    'database.read',
    'library.books.read',
    'reader.open',
  },
  declaredSourceIds: {'app.library.externalCatalog'},
);

Map<String, dynamic> _validProgram() => {
  'id': 'parallel-editions',
  'version': 1,
  'triggers': ['reader.activeBookChanged'],
  'when': {
    'op': 'equals',
    'left': {r'$context': 'reader.book.type'},
    'right': {r'$literal': 'text'},
  },
  'commands': [
    {
      'id': 'editions',
      'type': 'database.select',
      'args': {
        'sourceId': 'app.library.externalCatalog',
        'from': {'table': 'mapping', 'alias': 'm'},
        'select': [
          {'expr': 'm.external_id', 'as': 'id'},
          {'expr': 'm.title', 'as': 'title'},
        ],
        'where': {
          'op': '=',
          'left': 'm.internal_id',
          'value': {r'$context': 'reader.book.id'},
        },
        'limit': 20,
        'rowFormat': 'object',
      },
    },
    {
      'id': 'resolved',
      'type': 'library.resolveBooks',
      'args': {
        'items': {r'$result': 'editions.rows'},
        'identity': <String, dynamic>{
          'type': {r'$literal': 'pdf'},
          'source': {r'$literal': 'library'},
          'external': {
            'provider': {r'$literal': 'hebrewbooks'},
            'id': {r'$row': 'id'},
          },
        },
        'keepInputFields': true,
        'limit': 20,
      },
    },
    {
      'id': 'menuItems',
      'type': 'data.map',
      'args': {
        'items': {r'$result': 'resolved'},
        'template': {
          'id': {
            r'$concat': [
              {r'$literal': 'edition-'},
              {r'$row': 'identity.id'},
            ],
          },
          'title': {r'$row': 'title'},
          'identity': {r'$row': 'identity'},
        },
        'maxItems': 20,
      },
    },
    {
      'id': 'defaultEdition',
      'type': 'data.first',
      'args': {
        'items': {r'$result': 'resolved'},
      },
    },
  ],
  'outputs': {
    'editions': {r'$result': 'menuItems'},
    'defaultEdition': {r'$result': 'defaultEdition'},
  },
};

Matcher _throwsProgramError(String code) => throwsA(
  isA<DeclarativeProgramException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);
