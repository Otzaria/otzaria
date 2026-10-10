import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _manifest({
  List<String> permissions = const [
    'app.startup_contributions',
    'reader.toolbar',
    'reader.context_menu',
    'published_data.write',
    'search.dialog',
  ],
  String minAppVersion = '0.9.96',
  Map<String, dynamic>? startup,
}) => {
  'schemaVersion': 1,
  'id': 'test.startup.plugin',
  'name': 'Test Plugin',
  'version': '1.0.0',
  'entrypoint': 'index.html',
  'minAppVersion': minAppVersion,
  'sdkVersion': '1.x',
  'permissions': permissions,
  'contributes': {
    'toolTab': {'title': 'Test Plugin', 'order': 900, 'defaultPinned': true},
    'startup': ?startup,
  },
};

PluginValidationReport _run(Directory tempDir, Map<String, dynamic> json) {
  final dir = Directory(p.join(tempDir.path, 'plugin'))..createSync();
  File(p.join(dir.path, 'manifest.json')).writeAsStringSync(jsonEncode(json));
  File(p.join(dir.path, 'index.html')).writeAsStringSync(
    '<!doctype html><html lang="he" dir="rtl">'
    '<style>body { color: var(--color-text); }</style></html>',
  );
  return PluginExtendedValidator.validate(
    manifest: PluginManifest.fromJson(json),
    manifestJson: json,
    directoryPath: dir.path,
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria_startup_val_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> validStartup() => {
    'toolbarItems': [
      {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
    ],
    'contextMenuItems': [
      {
        'id': 'm1',
        'title': 'פריט',
        'showWhen': {
          'selectionContainsAny': ['מילה'],
        },
      },
    ],
    'publishedData': [
      {
        'type': 'calendar.event',
        'key': 'k1',
        'payload': {'title': 'אירוע'},
      },
    ],
    'activationEvents': ['app.startup'],
    'searchDialogItems': [
      {
        'id': 'include-external',
        'type': 'checkbox',
        'title': 'חפש גם במקור חיצוני',
        'visibleInModes': ['exact', 'advanced'],
      },
    ],
  };

  test('a valid startup section passes without errors', () {
    final report = _run(tempDir, _manifest(startup: validStartup()));
    expect(report.errors, isEmpty);
  });

  group('externalEditions', () {
    Map<String, dynamic> editionsManifest({
      List<String> permissions = const [
        'app.startup_contributions',
        'database.read',
        'library.books.read',
      ],
      String minAppVersion = '0.9.97',
      String sourceId = 'mapping_source',
      List<Map<String, dynamic>>? items,
    }) {
      final json = _manifest(
        permissions: permissions,
        minAppVersion: minAppVersion,
        startup: {
          'externalEditions':
              items ??
              [
                {
                  'id': 'editions-1',
                  'provider': 'extlib',
                  'sourceId': sourceId,
                  'table': 'mapping',
                  'externalIdColumn': 'ext_id',
                  'otzariaIdColumn': 'otzaria_id',
                },
              ],
        },
      );
      json['contributes'] = <String, dynamic>{
        ...(json['contributes'] as Map),
        'databaseSources': [
          {'id': 'mapping_source', 'label': 'מיפוי', 'required': true},
        ],
      };
      return json;
    }

    test('תרומה תקינה עוברת ללא שגיאות', () {
      final report = _run(tempDir, editionsManifest());
      expect(report.errors, isEmpty);
    });

    test('חסרה הרשאת database.read — שגיאה חוסמת', () {
      final report = _run(
        tempDir,
        editionsManifest(
          permissions: const [
            'app.startup_contributions',
            'library.books.read',
          ],
        ),
      );
      expect(report.errors, contains(contains('database.read')));
    });

    test('minAppVersion ישן מדי — שגיאה חוסמת', () {
      final report = _run(tempDir, editionsManifest(minAppVersion: '0.9.96'));
      expect(
        report.errors,
        contains(contains('externalEditions נתמך החל מגרסה')),
      );
    });

    test('sourceId שלא הוכרז — שגיאה חוסמת', () {
      final report = _run(tempDir, editionsManifest(sourceId: 'other_source'));
      expect(report.errors, contains(contains('other_source')));
    });

    test('מזהה כפול — שגיאה חוסמת', () {
      final item = {
        'id': 'editions-1',
        'provider': 'extlib',
        'sourceId': 'mapping_source',
        'table': 'mapping',
        'externalIdColumn': 'ext_id',
        'otzariaIdColumn': 'otzaria_id',
      };
      final report = _run(
        tempDir,
        editionsManifest(items: [item, Map.of(item)]),
      );
      expect(report.errors, contains(contains('מזהה כפול')));
    });
  });

  group('libraryBooks', () {
    Map<String, dynamic> booksManifest({
      List<String> permissions = const [
        'app.startup_contributions',
        'library.books.provide',
      ],
      String minAppVersion = '0.9.98',
      List<Map<String, dynamic>>? items,
    }) => _manifest(
      permissions: permissions,
      minAppVersion: minAppVersion,
      startup: {
        'libraryBooks':
            items ??
            [
              {
                'id': 'books',
                'provider': 'mylib',
                'title': 'הספרייה שלי',
                'icon': 'library_24_regular',
                'when': {
                  'storage': {'key': 'show', 'notEquals': false},
                },
              },
            ],
      },
    );

    test('תרומה תקינה עוברת ללא שגיאות', () {
      expect(_run(tempDir, booksManifest()).errors, isEmpty);
    });

    test('חסרה הרשאת library.books.provide — שגיאה חוסמת', () {
      final report = _run(
        tempDir,
        booksManifest(permissions: const ['app.startup_contributions']),
      );
      expect(report.errors, contains(contains('library.books.provide')));
    });

    test('minAppVersion ישן מדי — שגיאה חוסמת', () {
      final report = _run(tempDir, booksManifest(minAppVersion: '0.9.97'));
      expect(report.errors, contains(contains('libraryBooks נתמך החל מגרסה')));
    });

    test('openAction: הרשאת הפעולה חייבת להיות מוצהרת', () {
      List<Map<String, dynamic>> items() => [
        {
          'id': 'books',
          'provider': 'mylib',
          'title': 'הספרייה שלי',
          'openAction': {
            'type': 'localService.post',
            'args': {
              'port': {r'$storage': 'servicePort'},
              'path': '/book/open',
              'body': {
                'id': {r'$book': 'id'},
              },
            },
          },
        },
      ];

      final missing = _run(tempDir, booksManifest(items: items()));
      expect(missing.errors, contains(contains('network.localhost')));

      final missingStorage = _run(
        tempDir,
        booksManifest(
          permissions: const [
            'app.startup_contributions',
            'library.books.provide',
            'network.localhost',
          ],
          items: items(),
        ),
      );
      expect(missingStorage.errors, contains(contains('plugin.storage.read')));

      final valid = _run(
        tempDir,
        booksManifest(
          permissions: const [
            'app.startup_contributions',
            'library.books.provide',
            'network.localhost',
            'plugin.storage.read',
          ],
          items: items(),
        ),
      );
      expect(valid.errors, isEmpty);
    });

    test(r'openAction עם $selection — שגיאה חוסמת', () {
      final report = _run(
        tempDir,
        booksManifest(
          items: [
            {
              'id': 'books',
              'provider': 'mylib',
              'title': 'הספרייה שלי',
              'openAction': {
                'type': 'ui.showSnack',
                'args': {
                  'message': {r'$selection': 'selectedText'},
                },
              },
            },
          ],
        ),
      );
      expect(report.errors, contains(contains('openAction')));
    });

    test('שם ספק מובנה, ספק כפול ושלושה ספקים — שגיאות חוסמות', () {
      Map<String, dynamic> item(String id, String provider) => {
        'id': id,
        'provider': provider,
        'title': 'ספק',
      };
      expect(
        _run(tempDir, booksManifest(items: [item('a', 'otzar')])).errors,
        contains(contains('libraryBooks לא תקין')),
      );
      expect(
        _run(
          tempDir,
          booksManifest(items: [item('a', 'books'), item('b', 'books')]),
        ).errors,
        contains(contains('ספק כפול')),
      );
      expect(
        _run(
          tempDir,
          booksManifest(
            items: [item('a', 'one'), item('b', 'two'), item('c', 'three')],
          ),
        ).errors,
        contains(contains('מוגבל ל-2')),
      );
    });

    test('תנאי when שקורא הגדרה חסומה — שגיאה חוסמת', () {
      final report = _run(
        tempDir,
        booksManifest(
          items: [
            {
              'id': 'books',
              'provider': 'mylib',
              'title': 'הספרייה שלי',
              'when': {
                'setting': {'key': 'key-bookmarks', 'exists': true},
              },
            },
          ],
        ),
      );
      expect(report.errors, contains(contains('libraryBooks: when')));
    });
  });

  test('missing app.startup_contributions permission is a blocking error', () {
    final report = _run(
      tempDir,
      _manifest(
        permissions: const ['reader.toolbar'],
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
        },
      ),
    );
    expect(
      report.errors,
      contains(contains('app.startup_contributions')),
    );
  });

  test('minAppVersion below 0.9.96 is a blocking error', () {
    final report = _run(
      tempDir,
      _manifest(minAppVersion: '0.9.95', startup: validStartup()),
    );
    expect(report.errors, contains(contains('minAppVersion')));
  });

  test('openPluginOnSubmit דורש minAppVersion 0.9.97', () {
    final startup = validStartup();
    (startup['searchDialogItems'] as List).single['openPluginOnSubmit'] = true;

    final oldVersion = _run(
      tempDir,
      _manifest(minAppVersion: '0.9.96', startup: startup),
    );
    expect(oldVersion.errors, contains(contains('0.9.97')));

    final supportedVersion = _run(
      tempDir,
      _manifest(minAppVersion: '0.9.97', startup: startup),
    );
    expect(supportedVersion.errors, isEmpty);
  });

  test('action בתפריט ההקשר: גרסת מינימום והצהרת הרשאה', () {
    Map<String, dynamic> startup() => {
      'contextMenuItems': [
        {
          'id': 'save',
          'title': 'שמור לרשימה',
          'action': {
            'type': 'storage.set',
            'args': {
              'key': 'savedBooks',
              'value': {r'$selection': 'id'},
            },
          },
        },
      ],
    };
    const permissions = [
      'app.startup_contributions',
      'reader.context_menu',
      'plugin.storage.write',
    ];

    final oldVersion = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.96',
        startup: startup(),
      ),
    );
    expect(
      oldVersion.errors,
      contains(contains('action על פריט תפריט הקשר נתמך החל מגרסה')),
    );

    final missingPermission = _run(
      tempDir,
      _manifest(
        permissions: const ['app.startup_contributions', 'reader.context_menu'],
        minAppVersion: '0.9.97',
        startup: startup(),
      ),
    );
    expect(
      missingPermission.errors,
      contains(contains('plugin.storage.write')),
    );

    final valid = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.97',
        startup: startup(),
      ),
    );
    expect(valid.errors, isEmpty);
  });

  test('localService.post בתפריט ההקשר דורש 0.9.98 ו-network.localhost', () {
    Map<String, dynamic> startup() => {
      'contextMenuItems': [
        {
          'id': 'search',
          'title': 'חיפוש בשירות',
          'action': {
            'type': 'localService.post',
            'args': {
              'port': 39700,
              'path': '/text/search',
              'body': {
                'text': {r'$selection': 'selectedText'},
              },
            },
          },
        },
      ],
    };
    const permissions = [
      'app.startup_contributions',
      'reader.context_menu',
      'network.localhost',
    ];

    final oldVersion = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.97',
        startup: startup(),
      ),
    );
    expect(
      oldVersion.errors,
      contains(contains('localService.post נתמכת החל מגרסה 0.9.98')),
    );

    final missingPermission = _run(
      tempDir,
      _manifest(
        permissions: const ['app.startup_contributions', 'reader.context_menu'],
        minAppVersion: '0.9.98',
        startup: startup(),
      ),
    );
    expect(missingPermission.errors, contains(contains('network.localhost')));

    final valid = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.98',
        startup: startup(),
      ),
    );
    expect(valid.errors, isEmpty);
  });

  test('localService.post בתפריט ההקשר: ערך מילולי שגוי נדחה בהתקנה', () {
    final report = _run(
      tempDir,
      _manifest(
        permissions: const [
          'app.startup_contributions',
          'reader.context_menu',
          'network.localhost',
        ],
        minAppVersion: '0.9.98',
        startup: {
          'contextMenuItems': [
            {
              'id': 'search',
              'title': 'חיפוש בשירות',
              'action': {
                'type': 'localService.post',
                'args': {'port': 39700, 'path': '/text/search?q=1'},
              },
            },
          ],
        },
      ),
    );

    expect(report.errors, contains(contains('localService.post.path')));
  });

  test('localService.post בפקד דקלרטיבי דורשת minAppVersion 0.9.98', () {
    final startup = {
      'programs': [
        {
          'id': 'p1',
          'version': 1,
          'triggers': ['reader.activeBookChanged'],
          'commands': [
            {
              'id': 'c1',
              'type': 'data.first',
              'args': {
                'items': {
                  r'$literal': [1],
                },
              },
            },
          ],
          'outputs': {
            'visible': {r'$result': 'c1'},
          },
        },
      ],
      'toolbarItems': [
        {
          'id': 'b1',
          'type': 'button',
          'title': 'שלח לשירות',
          'icon': 'apps_24_regular',
          'binding': {'program': 'p1', 'visibleOutput': 'visible'},
          'action': {
            'type': 'localService.post',
            'args': {'port': 39700, 'path': '/ping'},
          },
        },
      ],
    };
    const permissions = [
      'app.startup_contributions',
      'reader.toolbar',
      'network.localhost',
    ];

    final oldVersion = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.97',
        startup: startup,
      ),
    );
    expect(
      oldVersion.errors,
      contains(contains('localService.post נתמכת החל מגרסה 0.9.98')),
    );

    final supportedVersion = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.98',
        startup: startup,
      ),
    );
    expect(supportedVersion.errors, isEmpty);
  });

  test(r'$storage בתפריט ההקשר דורש minAppVersion 0.9.98', () {
    final startup = {
      'contextMenuItems': [
        {
          'id': 'save',
          'title': 'שמור',
          'action': {
            'type': 'storage.set',
            'args': {
              'key': 'last',
              'value': {r'$storage': 'current'},
            },
          },
        },
      ],
    };
    const permissions = [
      'app.startup_contributions',
      'reader.context_menu',
      'plugin.storage.write',
      'plugin.storage.read',
    ];

    final missingStorage = _run(
      tempDir,
      _manifest(
        permissions: permissions
            .where((p) => p != 'plugin.storage.read')
            .toList(),
        minAppVersion: '0.9.98',
        startup: startup,
      ),
    );
    expect(missingStorage.errors, contains(contains('plugin.storage.read')));

    final oldVersion = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.97',
        startup: startup,
      ),
    );
    expect(
      oldVersion.errors,
      contains(contains(r'ההפניה $storage נתמכת החל מגרסה 0.9.98')),
    );
    // ולא שגיאה נוספת על storage.set, שנתמך כבר ב-0.9.97.
    expect(oldVersion.errors, hasLength(1));

    final valid = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.98',
        startup: startup,
      ),
    );
    expect(valid.errors, isEmpty);
  });

  test('פעולת storage.set בפקד דקלרטיבי דורשת minAppVersion 0.9.97', () {
    final startup = {
      'programs': [
        {
          'id': 'p1',
          'version': 1,
          'triggers': ['reader.activeBookChanged'],
          'commands': [
            {
              'id': 'c1',
              'type': 'data.first',
              'args': {
                'items': {
                  r'$literal': [1],
                },
              },
            },
          ],
          'outputs': {
            'visible': {r'$result': 'c1'},
          },
        },
      ],
      'toolbarItems': [
        {
          'id': 'b1',
          'type': 'button',
          'title': 'שמור',
          'icon': 'apps_24_regular',
          'binding': {'program': 'p1', 'visibleOutput': 'visible'},
          'action': {
            'type': 'storage.set',
            'args': {
              'key': 'saved',
              'value': {r'$output': 'visible'},
            },
          },
        },
      ],
    };
    const permissions = [
      'app.startup_contributions',
      'reader.toolbar',
      'plugin.storage.write',
    ];

    final oldVersion = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.96',
        startup: startup,
      ),
    );
    expect(
      oldVersion.errors,
      contains(contains('storage.set נתמכת החל מגרסה')),
    );

    final supportedVersion = _run(
      tempDir,
      _manifest(
        permissions: permissions,
        minAppVersion: '0.9.97',
        startup: startup,
      ),
    );
    expect(supportedVersion.errors, isEmpty);
  });

  test('data.choose דורש minAppVersion 0.9.97', () {
    final startup = {
      'programs': [
        {
          'id': 'choose-data',
          'version': 1,
          'triggers': ['reader.activeBookChanged'],
          'commands': [
            {
              'id': 'selected',
              'type': 'data.choose',
              'args': {
                'condition': {
                  'op': 'exists',
                  'value': {r'$context': 'reader.book.id'},
                },
                'whenTrue': {r'$literal': 'yes'},
                'whenFalse': {r'$literal': 'no'},
              },
            },
          ],
          'outputs': {
            'selected': {r'$result': 'selected'},
          },
        },
      ],
    };

    final oldVersion = _run(
      tempDir,
      _manifest(minAppVersion: '0.9.96', startup: startup),
    );
    expect(oldVersion.errors, contains(contains('0.9.97')));

    final supportedVersion = _run(
      tempDir,
      _manifest(minAppVersion: '0.9.97', startup: startup),
    );
    expect(supportedVersion.errors, isEmpty);
  });

  test('an invalid toolbar item (missing icon) is a blocking error', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור'},
          ],
        },
      ),
    );
    expect(report.errors, contains(contains('toolbarItems')));
  });

  test('publishedData record without a key is a blocking error', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'publishedData': [
            {'type': 'calendar.event', 'payload': {}},
          ],
        },
      ),
    );
    expect(report.errors, contains(contains('publishedData')));
  });

  test('unknown static search option id is a blocking error', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'searchDialogItems': [
            {
              'id': 'include-external',
              'type': 'checkbox',
              'title': 'חפש גם במקור חיצוני',
              'disabledSearchOptions': {
                'advanced': ['word.not-a-real-option'],
              },
            },
          ],
        },
      ),
    );

    expect(report.errors, contains(contains('searchDialogItems')));
  });

  test('unknown activation event is a warning, not an error', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
          'activationEvents': ['no.such.event'],
        },
      ),
    );
    expect(report.errors, isEmpty);
    expect(report.warnings, contains(contains('no.such.event')));
  });

  test('app.startup without app.run_on_startup permission is a warning', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
          'activationEvents': ['app.startup'],
        },
      ),
    );
    expect(report.errors, isEmpty);
    expect(report.warnings, contains(contains('app.run_on_startup')));
  });

  test('activation event without its subscribe permission is a warning', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
          'activationEvents': ['reader.sectionContentChanged'],
        },
      ),
    );
    expect(report.errors, isEmpty);
    expect(
      report.warnings,
      contains(contains('events.subscribe:reader.sectionContentChanged')),
    );
  });

  test('missing domain permission for a category is a warning', () {
    final report = _run(
      tempDir,
      _manifest(
        permissions: const ['app.startup_contributions'],
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
        },
      ),
    );
    expect(report.errors, isEmpty);
    expect(report.warnings, contains(contains('reader.toolbar')));
  });

  test('wrong-typed startup fields yield clean errors, not a crash', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'toolbarItems': 'not-a-list',
          'contextMenuItems': ['not-a-map'],
          'programs': ['not-a-map'],
          'activationEvents': [17],
        },
      ),
    );
    expect(report.errors, contains(contains('toolbarItems')));
    expect(report.errors, contains(contains('contextMenuItems')));
    expect(report.errors, contains(contains('programs')));
    expect(report.errors, contains(contains('activationEvents')));
  });

  test('an empty startup section is only a warning', () {
    final report = _run(tempDir, _manifest(startup: <String, dynamic>{}));
    expect(report.errors, isEmpty);
    expect(report.warnings, contains(contains('contributes.startup ריק')));
  });

  test('keepAlive requires both background permissions', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
          'keepAlive': true,
        },
      ),
    );

    expect(report.errors, contains(contains('app.run_on_startup')));
    expect(report.errors, contains(contains('app.background_keep_alive')));
  });

  test('keepAlive with both permissions is valid', () {
    final report = _run(
      tempDir,
      _manifest(
        permissions: const [
          'app.startup_contributions',
          'app.run_on_startup',
          'app.background_keep_alive',
          'reader.toolbar',
        ],
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
          'keepAlive': true,
        },
      ),
    );

    expect(report.errors, isEmpty);
  });

  test('keepAlive with a non-boolean value is rejected cleanly', () {
    final report = _run(
      tempDir,
      _manifest(
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
          'keepAlive': 'yes',
        },
      ),
    );

    expect(report.errors, contains(contains('keepAlive חייב להיות bool')));
  });

  test('keepAlive permission without the flag produces a warning', () {
    final report = _run(
      tempDir,
      _manifest(
        permissions: const [
          'app.startup_contributions',
          'app.background_keep_alive',
          'reader.toolbar',
        ],
        startup: {
          'toolbarItems': [
            {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
          ],
        },
      ),
    );

    expect(report.errors, isEmpty);
    expect(
      report.warnings,
      contains(contains('ללא contributes.startup.keepAlive')),
    );
  });

  test('keepAlive without any contribution or trigger is rejected', () {
    final report = _run(
      tempDir,
      _manifest(
        permissions: const [
          'app.startup_contributions',
          'app.run_on_startup',
          'app.background_keep_alive',
        ],
        startup: {'keepAlive': true},
      ),
    );

    expect(report.errors, contains(contains('מפעיל מנוע רקע')));
  });

  test('keepAlive with static data only is rejected', () {
    final report = _run(
      tempDir,
      _manifest(
        permissions: const [
          'app.startup_contributions',
          'app.run_on_startup',
          'app.background_keep_alive',
          'published_data.write',
        ],
        startup: {
          'publishedData': [
            {
              'type': 'calendar.event',
              'key': 'static',
              'payload': {'title': 'אירוע'},
            },
          ],
          'keepAlive': true,
        },
      ),
    );

    expect(report.errors, contains(contains('מפעיל מנוע רקע')));
  });

  test('תכנית Host תקינה עוברת ולידציה בלי להפעיל מנוע רקע', () {
    final report = _run(
      tempDir,
      _manifest(
        minAppVersion: '0.9.96',
        permissions: const ['app.startup_contributions'],
        startup: {
          'programs': [_validHostProgram()],
        },
      ),
    );

    expect(report.errors, isEmpty);
  });

  test('פקודה דקלרטיבית לא מוכרת היא שגיאה חוסמת', () {
    final program = _validHostProgram();
    (program['commands'] as List<dynamic>)[0] = {
      'id': 'unsafe',
      'type': 'database.rawSql',
      'args': {'sql': 'DELETE FROM books'},
    };
    final report = _run(
      tempDir,
      _manifest(
        minAppVersion: '0.9.96',
        permissions: const ['app.startup_contributions'],
        startup: {
          'programs': [program],
        },
      ),
    );

    expect(report.errors, contains(contains('unknown_command')));
  });

  test('תכנית דקלרטיבית דורשת minAppVersion 0.9.96', () {
    final report = _run(
      tempDir,
      _manifest(
        minAppVersion: '0.9.95',
        permissions: const ['app.startup_contributions'],
        startup: {
          'programs': [_validHostProgram()],
        },
      ),
    );

    expect(report.errors, contains(contains('0.9.96')));
  });

  test('שני פקדי Host דקלרטיביים עוברים ולידציה', () {
    final report = _run(
      tempDir,
      _manifest(
        minAppVersion: '0.9.96',
        permissions: const [
          'app.startup_contributions',
          'reader.toolbar',
          'reader.open',
        ],
        startup: {
          'programs': [_toolbarProgram()],
          'toolbarItems': _declarativeToolbarItems(),
        },
      ),
    );

    expect(report.errors, isEmpty);
  });

  test('פקד Host דקלרטיבי ללא reader.toolbar נדחה בהתקנה', () {
    final report = _run(
      tempDir,
      _manifest(
        minAppVersion: '0.9.96',
        permissions: const ['app.startup_contributions', 'reader.open'],
        startup: {
          'programs': [_toolbarProgram()],
          'toolbarItems': _declarativeToolbarItems(),
        },
      ),
    );

    expect(report.errors, contains(contains('reader.toolbar')));
  });

  test('פקד דקלרטיבי שמפנה לפלט חסר נדחה', () {
    final items = _declarativeToolbarItems();
    (items.first['binding'] as Map<String, dynamic>)['visibleOutput'] =
        'missing';
    final report = _run(
      tempDir,
      _manifest(
        minAppVersion: '0.9.96',
        permissions: const [
          'app.startup_contributions',
          'reader.toolbar',
          'reader.open',
        ],
        startup: {
          'programs': [_toolbarProgram()],
          'toolbarItems': items,
        },
      ),
    );

    expect(report.errors, contains(contains('output_not_found')));
  });

  group('when', () {
    Map<String, dynamic> whenManifest(
      Object? when, {
      String minAppVersion = '0.9.97',
    }) => _manifest(
      minAppVersion: minAppVersion,
      startup: {
        'toolbarItems': [
          {
            'id': 'b1',
            'title': 'כפתור',
            'icon': 'apps_24_regular',
            'when': when,
          },
        ],
      },
    );

    test('תנאי תקין עובר ללא שגיאות', () {
      final report = _run(
        tempDir,
        whenManifest({
          'all': [
            {
              'setting': {'key': 'key-dark-mode', 'equals': true},
            },
            {
              'storage': {'key': 'showButton', 'exists': true},
            },
          ],
        }),
      );

      expect(report.errors, isEmpty);
    });

    test('מפתח הגדרה שאינו זמין לתוספים — שגיאה', () {
      final report = _run(
        tempDir,
        whenManifest({
          'setting': {'key': 'key-library-path', 'equals': 'C:/books'},
        }),
      );

      expect(report.errors, contains(contains('key-library-path')));
    });

    test('סכימה לא תקינה — שגיאה', () {
      final report = _run(
        tempDir,
        whenManifest({
          'setting': {'key': 'key-dark-mode'},
        }),
      );

      expect(report.errors, contains(contains('when')));
    });

    test('minAppVersion נמוך מדי — שגיאה', () {
      final report = _run(
        tempDir,
        whenManifest({
          'setting': {'key': 'key-dark-mode', 'equals': true},
        }, minAppVersion: '0.9.96'),
      );

      expect(report.errors, contains(contains('when')));
    });

    Map<String, dynamic> eventManifest(
      Object? event, {
      String minAppVersion = '0.9.97',
    }) => _manifest(
      permissions: const [
        'app.startup_contributions',
        'reader.toolbar',
        'app.run_on_startup',
      ],
      minAppVersion: minAppVersion,
      startup: {
        'toolbarItems': [
          {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
        ],
        'activationEvents': [event],
      },
    );

    test('activationEvents בפורמט אובייקט עם תנאי תקין עובר', () {
      final report = _run(
        tempDir,
        eventManifest({
          'topic': 'app.startup',
          'when': {
            'setting': {'key': 'key-dark-mode', 'equals': true},
          },
        }),
      );

      expect(report.errors, isEmpty);
    });

    test('activationEvents — תנאי לא תקין הוא שגיאה', () {
      final report = _run(
        tempDir,
        eventManifest({
          'topic': 'app.startup',
          'when': {
            'setting': {'key': 'key-dark-mode'},
          },
        }),
      );

      expect(
        report.errors,
        contains(contains('contributes.startup.activationEvents: when')),
      );
    });

    test('activationEvents — מפתח הגדרה חסום הוא שגיאה', () {
      final report = _run(
        tempDir,
        eventManifest({
          'topic': 'app.startup',
          'when': {
            'setting': {'key': 'key-library-path', 'equals': 'C:/books'},
          },
        }),
      );

      expect(report.errors, contains(contains('key-library-path')));
    });

    test('activationEvents — תנאי דורש את רף הגרסה', () {
      final report = _run(
        tempDir,
        eventManifest({
          'topic': 'app.startup',
          'when': {
            'setting': {'key': 'key-dark-mode', 'equals': true},
          },
        }, minAppVersion: '0.9.96'),
      );

      expect(report.errors, contains(contains('when')));
    });

    test('activationEvents — מפתח לא מוכר באובייקט הוא שגיאה', () {
      final report = _run(
        tempDir,
        eventManifest({
          'topic': 'app.startup',
          'wen': {
            'setting': {'key': 'key-dark-mode', 'equals': true},
          },
        }),
      );

      expect(report.errors, contains(contains('"wen"')));
    });

    test('activationEvents — אובייקט בלי topic הוא שגיאת טיפוס', () {
      final report = _run(tempDir, eventManifest({'when': true}));

      expect(report.errors, contains(contains('activationEvents')));
    });
  });
}

Map<String, dynamic> _validHostProgram() => {
  'id': 'host-program',
  'version': 1,
  'triggers': ['reader.activeBookChanged'],
  'commands': [
    {
      'id': 'first',
      'type': 'data.first',
      'args': {
        'items': {
          r'$literal': [1],
        },
      },
    },
  ],
  'outputs': {
    'first': {r'$result': 'first'},
  },
};

Map<String, dynamic> _toolbarProgram() => {
  'id': 'book-links',
  'version': 1,
  'triggers': ['reader.activeBookChanged'],
  'commands': [
    {
      'id': 'first',
      'type': 'data.first',
      'args': {
        'items': {
          r'$literal': [
            {'id': 1, 'title': 'מהדורה'},
          ],
        },
      },
    },
  ],
  'outputs': {
    'defaultEdition': {r'$result': 'first'},
    'editions': {
      r'$literal': [
        {'id': 1, 'title': 'מהדורה'},
      ],
    },
  },
};

List<Map<String, dynamic>> _declarativeToolbarItems() => [
  {
    'id': 'default',
    'title': 'פתח מהדורת ברירת מחדל',
    'icon': 'book_24_regular',
    'binding': {
      'program': 'book-links',
      'visibleOutput': 'defaultEdition',
    },
    'action': {
      'type': 'reader.openBook',
      'args': {
        'identity': {r'$output': 'defaultEdition'},
      },
    },
  },
  {
    'id': 'editions',
    'type': 'menu',
    'title': 'פתח מהדורה אחרת',
    'icon': 'book_24_regular',
    'binding': {
      'program': 'book-links',
      'visibleOutput': 'editions',
    },
    'childrenBinding': {
      'itemsOutput': 'editions',
      'itemTemplate': {
        'id': {
          r'$concat': [
            'edition-',
            {r'$item': 'id'},
          ],
        },
        'title': {r'$item': 'title'},
        'action': {
          'type': 'reader.openBook',
          'args': {
            'identity': {
              'id': {r'$item': 'id'},
            },
          },
        },
      },
    },
  },
];
