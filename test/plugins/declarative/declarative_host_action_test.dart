import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_action_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_host_action_executor.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';

void main() {
  test('מקמפל ומבצע reader.openBook מורשה בהקשר הנכון', () async {
    final action = _compileAction();
    final opener = _BookOpener();

    final opened =
        await DeclarativeHostActionExecutor(
          bookOpener: opener,
        ).execute(
          action: action,
          plugin: _plugin(),
          grantedPermissions: const {'reader.open'},
          currentContextSignature: 'book-7',
          currentProgramGeneration: 7,
        );

    expect(opened, isTrue);
    expect(opener.identities.single, {'id': 10, 'type': 'pdf'});
    expect(opener.sidePaneFlags.single, isFalse);
    expect(() => action.args['index'] = 5, throwsUnsupportedError);
  });

  test(
    'reader.openBookInSidePane פותח את הספר כחלונית ולא ככרטיסייה',
    () async {
      final opener = _BookOpener();

      final opened =
          await DeclarativeHostActionExecutor(
            bookOpener: opener,
          ).execute(
            action: _compileAction(type: 'reader.openBookInSidePane'),
            plugin: _plugin(),
            grantedPermissions: const {'reader.open'},
            currentContextSignature: 'book-7',
            currentProgramGeneration: 7,
          );

      expect(opened, isTrue);
      expect(opener.sidePaneFlags.single, isTrue);
    },
  );

  test(
    'matchPages מועברים לפותח כ-ExternalBookMatches ממוין וללא כפולים',
    () async {
      final opener = _BookOpener();
      final action = _compiler().compileResolved(
        {
          'type': 'reader.openBook',
          'args': {
            'identity': {'id': 10, 'type': 'pdf'},
            'index': 7,
            'searchQuery': 'שבת',
            'matchPages': [12, 8, 12, 30],
            'matchedTerms': ['שבת'],
          },
        },
        contextSignature: 'book-7',
        programGeneration: 7,
      );

      await DeclarativeHostActionExecutor(bookOpener: opener).execute(
        action: action,
        plugin: _plugin(),
        grantedPermissions: const {'reader.open'},
        currentContextSignature: 'book-7',
        currentProgramGeneration: 7,
      );

      final matches = opener.externalMatches.single;
      expect(matches, isNotNull);
      expect(matches!.pages, [8, 12, 30]);
      expect(matches.matchedTerms, ['שבת']);
      expect(matches.query, 'שבת');
    },
  );

  test('matchPages עם עמוד לא חיובי נדחה בזמן קומפילציה', () {
    expect(
      () => _compiler().compileResolved(
        {
          'type': 'reader.openBook',
          'args': {
            'identity': {'id': 10},
            'matchPages': [3, 0],
          },
        },
        contextSignature: 'book-7',
        programGeneration: 7,
      ),
      _throwsProgramError('declarative.invalid_args'),
    );
  });

  test('פעולה עם נתיב קובץ נדחית בזמן קומפילציה', () {
    expect(
      () => _compiler().compileResolved(
        {
          'type': 'reader.openBook',
          'args': {
            'identity': {'id': 10, 'filePath': '/tmp/book.pdf'},
          },
        },
        contextSignature: 'book-7',
        programGeneration: 7,
      ),
      _throwsProgramError('declarative.unknown_field'),
    );
  });

  test('הרשאה שלא הוצהרה דוחה את הפעולה בזמן קומפילציה', () {
    expect(
      () =>
          const DeclarativeActionCompiler(
            declaredPermissions: {},
          ).compileResolved(
            {
              'type': 'reader.openBook',
              'args': {
                'identity': {'id': 10},
              },
            },
            contextSignature: 'book-7',
            programGeneration: 7,
          ),
      _throwsProgramError('declarative.permission_not_declared'),
    );
  });

  test('חתימת הקשר ישנה חוסמת לפני פתיחת ספר', () async {
    final opener = _BookOpener();

    await expectLater(
      DeclarativeHostActionExecutor(bookOpener: opener).execute(
        action: _compileAction(),
        plugin: _plugin(),
        grantedPermissions: const {'reader.open'},
        currentContextSignature: 'book-8',
        currentProgramGeneration: 7,
      ),
      _throwsProgramError('declarative.stale_action'),
    );
    expect(opener.identities, isEmpty);
  });

  test('דור תוכנית ישן חוסם גם כאשר הקשר לא השתנה', () async {
    final opener = _BookOpener();

    await expectLater(
      DeclarativeHostActionExecutor(bookOpener: opener).execute(
        action: _compileAction(),
        plugin: _plugin(),
        grantedPermissions: const {'reader.open'},
        currentContextSignature: 'book-7',
        currentProgramGeneration: 8,
      ),
      _throwsProgramError('declarative.stale_action'),
    );
    expect(opener.identities, isEmpty);
  });

  test('שלילת הרשאה לאחר יצירת הכפתור חוסמת את הפעולה', () async {
    final opener = _BookOpener();

    await expectLater(
      DeclarativeHostActionExecutor(bookOpener: opener).execute(
        action: _compileAction(),
        plugin: _plugin(),
        grantedPermissions: const {},
        currentContextSignature: 'book-7',
        currentProgramGeneration: 7,
      ),
      _throwsProgramError('declarative.permission_denied'),
    );
    expect(opener.identities, isEmpty);
  });

  group('storage.set / storage.remove', () {
    test(
      'מקמפל ומבצע storage.set — הכתיבה מגיעה לכותב עם מזהה התוסף',
      () async {
        final writer = _StorageWriter();

        final done =
            await DeclarativeHostActionExecutor(
              bookOpener: _BookOpener(),
              storageWriter: writer,
            ).execute(
              action: _compileStorageAction(),
              plugin: _plugin(),
              grantedPermissions: const {'plugin.storage.write'},
              currentContextSignature: 'book-7',
              currentProgramGeneration: 7,
            );

        expect(done, isTrue);
        final write = writer.sets.single;
        expect(write.pluginId, 'test.declarative.plugin');
        expect(write.key, 'savedBooks');
        expect(write.value, {'id': 10});
        expect(writer.removes, isEmpty);
      },
    );

    test('storage.remove מוחק לפי key בלבד', () async {
      final writer = _StorageWriter();

      await DeclarativeHostActionExecutor(
        bookOpener: _BookOpener(),
        storageWriter: writer,
      ).execute(
        action: _storageCompiler().compileResolved(
          {
            'type': 'storage.remove',
            'args': {'key': 'savedBooks'},
          },
          contextSignature: 'book-7',
          programGeneration: 7,
        ),
        plugin: _plugin(),
        grantedPermissions: const {'plugin.storage.write'},
        currentContextSignature: 'book-7',
        currentProgramGeneration: 7,
      );

      expect(writer.removes.single, (
        pluginId: 'test.declarative.plugin',
        key: 'savedBooks',
      ));
      expect(writer.sets, isEmpty);
    });

    test('הרשאה שלא הוצהרה במניפסט נדחית בקומפילציה', () {
      expect(
        () => _compiler().compileResolved(
          {
            'type': 'storage.set',
            'args': {'key': 'k', 'value': 1},
          },
          contextSignature: 'book-7',
          programGeneration: 7,
        ),
        _throwsProgramError('declarative.permission_not_declared'),
      );
    });

    test('הרשאה שנשללה חוסמת את הכתיבה בזמן הלחיצה', () async {
      final writer = _StorageWriter();

      await expectLater(
        DeclarativeHostActionExecutor(
          bookOpener: _BookOpener(),
          storageWriter: writer,
        ).execute(
          action: _compileStorageAction(),
          plugin: _plugin(),
          grantedPermissions: const {},
          currentContextSignature: 'book-7',
          currentProgramGeneration: 7,
        ),
        _throwsProgramError('declarative.permission_denied'),
      );
      expect(writer.sets, isEmpty);
    });

    test('חתימת הקשר ישנה חוסמת את הכתיבה', () async {
      final writer = _StorageWriter();

      await expectLater(
        DeclarativeHostActionExecutor(
          bookOpener: _BookOpener(),
          storageWriter: writer,
        ).execute(
          action: _compileStorageAction(),
          plugin: _plugin(),
          grantedPermissions: const {'plugin.storage.write'},
          currentContextSignature: 'book-8',
          currentProgramGeneration: 7,
        ),
        _throwsProgramError('declarative.stale_action'),
      );
      expect(writer.sets, isEmpty);
    });

    test('key חסר, ארוך מדי או עם תווי בקרה נדחה בקומפילציה', () {
      expect(
        () => _compileStorageAction(args: {'value': 1}),
        _throwsProgramError('declarative.invalid_args'),
      );
      expect(
        () => _compileStorageAction(args: {'key': 'k' * 129, 'value': 1}),
        _throwsProgramError('declarative.invalid_args'),
      );
      expect(
        () => _compileStorageAction(args: {'key': 'a\nb', 'value': 1}),
        _throwsProgramError('declarative.invalid_args'),
      );
    });

    test('value חסר או null נדחה בקומפילציה', () {
      expect(
        () => _compileStorageAction(args: {'key': 'k'}),
        _throwsProgramError('declarative.invalid_args'),
      );
      expect(
        () => _compileStorageAction(args: {'key': 'k', 'value': null}),
        _throwsProgramError('declarative.invalid_args'),
      );
    });

    test('value גדול או עמוק מדי נדחה בקומפילציה', () {
      expect(
        () => _compileStorageAction(
          args: {
            'key': 'k',
            'value': List.generate(300, (i) => i),
          },
        ),
        _throwsProgramError('declarative.value_too_large'),
      );
      Object deep = 1;
      for (var i = 0; i < 12; i++) {
        deep = [deep];
      }
      expect(
        () => _compileStorageAction(args: {'key': 'k', 'value': deep}),
        _throwsProgramError('declarative.value_too_large'),
      );
    });

    test('namespace אינו ארגומנט מוכר ונדחה בקומפילציה', () {
      expect(
        () => _compileStorageAction(
          args: {'key': 'k', 'value': 1, 'namespace': 'prefs'},
        ),
        _throwsProgramError('declarative.unknown_field'),
      );
    });
  });

  group('ui.showSnack', () {
    test('מציג את הטקסט של התוסף בדרגת החומרה שנבחרה', () async {
      final presenter = _SnackPresenter();

      final done =
          await DeclarativeHostActionExecutor(
            bookOpener: _BookOpener(),
            snackPresenter: presenter,
          ).execute(
            action: _compileSnack(
              args: {'message': 'הספר נשמר', 'severity': 'success'},
            ),
            plugin: _plugin(),
            grantedPermissions: const {'notifications.send'},
            currentContextSignature: 'book-7',
            currentProgramGeneration: 7,
          );

      expect(done, isTrue);
      expect(presenter.shown.single, (
        message: 'הספר נשמר',
        severity: 'success',
        pluginName: 'Declarative',
      ));
    });

    test('ההודעה מיוחסת לתוסף ואינה נראית כהודעת מערכת', () {
      expect(
        PluginMessages.declarativeSnack('הספר נשמר', 'Declarative'),
        'הספר נשמר · מאת Declarative',
      );
    });

    test('ברירת המחדל היא info', () async {
      final presenter = _SnackPresenter();

      await DeclarativeHostActionExecutor(
        bookOpener: _BookOpener(),
        snackPresenter: presenter,
      ).execute(
        action: _compileSnack(args: {'message': 'שלום'}),
        plugin: _plugin(),
        grantedPermissions: const {'notifications.send'},
        currentContextSignature: 'book-7',
        currentProgramGeneration: 7,
      );

      expect(presenter.shown.single.severity, 'info');
    });

    test('חתימת הקשר ישנה חוסמת גם הודעה', () async {
      final presenter = _SnackPresenter();

      await expectLater(
        DeclarativeHostActionExecutor(
          bookOpener: _BookOpener(),
          snackPresenter: presenter,
        ).execute(
          action: _compileSnack(args: {'message': 'שלום'}),
          plugin: _plugin(),
          grantedPermissions: const {'notifications.send'},
          currentContextSignature: 'book-8',
          currentProgramGeneration: 7,
        ),
        _throwsProgramError('declarative.stale_action'),
      );
      expect(presenter.shown, isEmpty);
    });

    test('הרשאה שנשללה חוסמת את ההודעה', () async {
      final presenter = _SnackPresenter();

      await expectLater(
        DeclarativeHostActionExecutor(
          bookOpener: _BookOpener(),
          snackPresenter: presenter,
        ).execute(
          action: _compileSnack(args: {'message': 'שלום'}),
          plugin: _plugin(),
          grantedPermissions: const {},
          currentContextSignature: 'book-7',
          currentProgramGeneration: 7,
        ),
        _throwsProgramError('declarative.permission_denied'),
      );
      expect(presenter.shown, isEmpty);
    });

    test('הרשאה שלא הוצהרה במניפסט נדחית בקומפילציה', () {
      expect(
        () => _compiler().compileResolved(
          {
            'type': 'ui.showSnack',
            'args': {'message': 'שלום'},
          },
          contextSignature: 'book-7',
          programGeneration: 7,
        ),
        _throwsProgramError('declarative.permission_not_declared'),
      );
    });

    test('טקסט ריק, ארוך מדי או severity לא מוכר נדחים בקומפילציה', () {
      expect(
        () => _compileSnack(args: {'message': '   '}),
        _throwsProgramError('declarative.invalid_args'),
      );
      expect(
        () => _compileSnack(args: {'message': 'א' * 201}),
        _throwsProgramError('declarative.invalid_args'),
      );
      expect(
        () => _compileSnack(args: {'message': 'א\nב'}),
        _throwsProgramError('declarative.invalid_args'),
      );
      expect(
        () => _compileSnack(
          args: {'message': 'שלום', 'severity': 'warning'},
        ),
        _throwsProgramError('declarative.invalid_args'),
      );
    });
  });

  group('reader.scrollToRef', () {
    test('גולל בספר הפתוח בלי לפתוח אותו מחדש', () async {
      final scroller = _ReaderScroller();
      final opener = _BookOpener();

      final done =
          await DeclarativeHostActionExecutor(
            bookOpener: opener,
            readerScroller: scroller,
          ).execute(
            action: _compiler().compileResolved(
              {
                'type': 'reader.scrollToRef',
                'args': {'ref': 'ברכות ב ע"א', 'highlight': true},
              },
              contextSignature: 'book-7',
              programGeneration: 7,
            ),
            plugin: _plugin(),
            grantedPermissions: const {'reader.open'},
            currentContextSignature: 'book-7',
            currentProgramGeneration: 7,
          );

      expect(done, isTrue);
      expect(scroller.calls.single, (ref: 'ברכות ב ע"א', highlight: true));
      expect(opener.identities, isEmpty);
    });

    test('בלי שירות מחובר הפעולה נכשלת סגור', () async {
      await expectLater(
        DeclarativeHostActionExecutor(bookOpener: _BookOpener()).execute(
          action: _compiler().compileResolved(
            {
              'type': 'reader.scrollToRef',
              'args': {'ref': 'ברכות ב'},
            },
            contextSignature: 'book-7',
            programGeneration: 7,
          ),
          plugin: _plugin(),
          grantedPermissions: const {'reader.open'},
          currentContextSignature: 'book-7',
          currentProgramGeneration: 7,
        ),
        _throwsProgramError('declarative.service_unavailable'),
      );
    });

    test('ref ריק או ארוך מדי נדחה בקומפילציה', () {
      for (final ref in ['', 'א' * 257]) {
        expect(
          () => _compiler().compileResolved(
            {
              'type': 'reader.scrollToRef',
              'args': {'ref': ref},
            },
            contextSignature: 'book-7',
            programGeneration: 7,
          ),
          _throwsProgramError('declarative.invalid_args'),
        );
      }
    });
  });

  group('search.open', () {
    test('פותח חיפוש עם השאילתה', () async {
      final search = _SearchOpener();

      final done =
          await DeclarativeHostActionExecutor(
            bookOpener: _BookOpener(),
            searchOpener: search,
          ).execute(
            action: _compiler().compileResolved(
              {
                'type': 'search.open',
                'args': {'query': 'שבת', 'autoSearch': false},
              },
              contextSignature: 'book-7',
              programGeneration: 7,
            ),
            plugin: _plugin(),
            grantedPermissions: const {'reader.open'},
            currentContextSignature: 'book-7',
            currentProgramGeneration: 7,
          );

      expect(done, isTrue);
      expect(search.calls.single, (query: 'שבת', autoSearch: false));
    });

    test('שאילתה ארוכה מדי נדחית בקומפילציה', () {
      expect(
        () => _compiler().compileResolved(
          {
            'type': 'search.open',
            'args': {'query': 'א' * 501},
          },
          contextSignature: 'book-7',
          programGeneration: 7,
        ),
        _throwsProgramError('declarative.invalid_args'),
      );
    });

    test('autoSearch שאינו בוליאני נדחה בקומפילציה', () {
      expect(
        () => _compiler().compileResolved(
          {
            'type': 'search.open',
            'args': {'query': 'שבת', 'autoSearch': 'yes'},
          },
          contextSignature: 'book-7',
          programGeneration: 7,
        ),
        _throwsProgramError('declarative.invalid_args'),
      );
    });
  });
}

class _SnackPresenter implements DeclarativeSnackPresenter {
  final shown = <({String message, String severity, String pluginName})>[];

  @override
  void show(String message, String severity, {required String pluginName}) {
    shown.add((message: message, severity: severity, pluginName: pluginName));
  }
}

class _ReaderScroller implements DeclarativeReaderScroller {
  final calls = <({String ref, bool highlight})>[];

  @override
  Future<bool> scrollToRef(String ref, {bool highlight = false}) async {
    calls.add((ref: ref, highlight: highlight));
    return true;
  }
}

class _SearchOpener implements DeclarativeSearchOpener {
  final calls = <({String query, bool autoSearch})>[];

  @override
  Future<bool> openSearch(String query, {bool autoSearch = true}) async {
    calls.add((query: query, autoSearch: autoSearch));
    return true;
  }
}

DeclarativeActionCompiler _snackCompiler() => const DeclarativeActionCompiler(
  declaredPermissions: {'notifications.send'},
);

CompiledDeclarativeAction _compileSnack({
  required Map<String, dynamic> args,
}) => _snackCompiler().compileResolved(
  {'type': 'ui.showSnack', 'args': args},
  contextSignature: 'book-7',
  programGeneration: 7,
);

class _BookOpener implements DeclarativeBookOpener {
  final identities = <Map<String, dynamic>>[];
  final sidePaneFlags = <bool>[];
  final externalMatches = <ExternalBookMatches?>[];

  @override
  Future<bool> openUnique(
    Map<String, dynamic> identity, {
    required int index,
    required String searchQuery,
    bool inSidePane = false,
    ExternalBookMatches? externalMatches,
  }) async {
    identities.add(identity);
    sidePaneFlags.add(inSidePane);
    this.externalMatches.add(externalMatches);
    return true;
  }
}

class _StorageWriter implements DeclarativeStorageWriter {
  final sets = <({String pluginId, String key, Object? value})>[];
  final removes = <({String pluginId, String key})>[];

  @override
  Future<void> set(String pluginId, String key, Object? value) async {
    sets.add((pluginId: pluginId, key: key, value: value));
  }

  @override
  Future<void> remove(String pluginId, String key) async {
    removes.add((pluginId: pluginId, key: key));
  }
}

DeclarativeActionCompiler _compiler() => const DeclarativeActionCompiler(
  declaredPermissions: {'reader.open'},
);

DeclarativeActionCompiler _storageCompiler() => const DeclarativeActionCompiler(
  declaredPermissions: {'plugin.storage.write'},
);

CompiledDeclarativeAction _compileStorageAction({
  Map<String, dynamic>? args,
}) => _storageCompiler().compileResolved(
  {
    'type': 'storage.set',
    'args':
        args ??
        {
          'key': 'savedBooks',
          'value': {'id': 10},
        },
  },
  contextSignature: 'book-7',
  programGeneration: 7,
);

CompiledDeclarativeAction _compileAction({
  String type = 'reader.openBook',
}) => _compiler().compileResolved(
  {
    'type': type,
    'args': {
      'identity': {'id': 10, 'type': 'pdf'},
      'index': 1,
    },
  },
  contextSignature: 'book-7',
  programGeneration: 7,
);

InstalledPlugin _plugin() {
  final now = DateTime(2026);
  return InstalledPlugin(
    pluginId: 'test.declarative.plugin',
    name: 'Declarative',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: false,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: 'test.declarative.plugin',
      name: 'Declarative',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '0.9.98',
      sdkVersion: '1.x',
      permissions: const ['reader.open'],
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: 'Declarative',
      toolTabOrder: 900,
      defaultPinned: false,
      publishedDataTypes: const [],
    ),
    installedAt: now,
    updatedAt: now,
  );
}

Matcher _throwsProgramError(String code) => throwsA(
  isA<DeclarativeProgramException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);
