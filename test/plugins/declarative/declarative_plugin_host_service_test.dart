import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_host_action_executor.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/plugins/declarative/services/declarative_program_executor.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';

void main() {
  test('ביטול הרשאת קריאה מונע קריאת ערכים והצגתם', () async {
    final fixture = _Fixture(
      declaredPermissions: const [
        'app.startup_contributions',
        'notifications.send',
        'plugin.storage.read',
      ],
    );
    addTearDown(fixture.dispose);
    fixture.permissions.add('notifications.send');
    fixture.storageValues['secret'] = 'stored value';
    await fixture.host.dispatchSelectionAction(fixture.plugin.pluginId, {
      'type': 'ui.showSnack',
      'args': {
        'message': {r'$storage': 'secret'},
      },
    }, const {});
    expect(fixture.storageReads, isEmpty);
    expect(fixture.snacks.shown, isEmpty);
    expect(
      fixture.errors.single,
      isA<DeclarativeProgramException>().having(
        (e) => e.code,
        'code',
        'declarative.permission_denied',
      ),
    );
  });

  test('ספר ספק עם הרשאת קריאה שבוטלה אינו קורא אחסון', () async {
    final fixture = _Fixture(
      declaredPermissions: const [
        'app.startup_contributions',
        'network.localhost',
        'plugin.storage.read',
      ],
    );
    addTearDown(fixture.dispose);
    fixture.permissions.add('network.localhost');
    fixture.storageValues['port'] = 39700;
    await fixture.host.dispatchLibraryBookAction(
      fixture.plugin.pluginId,
      {
        'type': 'localService.post',
        'args': {
          'port': {r'$storage': 'port'},
          'path': '/open',
        },
      },
      const {'id': 7},
    );
    expect(fixture.storageReads, isEmpty);
    expect(fixture.localService.requests, isEmpty);
    expect(
      fixture.errors.single,
      isA<DeclarativeProgramException>().having(
        (e) => e.code,
        'code',
        'declarative.permission_denied',
      ),
    );
  });

  test('מסנכרן, מחשב ומפרסם שני פקדים ללא מנוע תוסף', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );

    final items = fixture.toolbar.getAll().map((entry) => entry.$2).toList();
    expect(items, hasLength(2));
    expect(items.first.hostAction, isNotNull);
    expect(items.last.children.single.hostAction, isNotNull);
  });

  test('לחיצה נבדקת שוב מול ההרשאות העדכניות', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );
    final action = fixture.toolbar.getAll().first.$2.hostAction!;

    fixture.permissions.remove('reader.open');
    await expectLater(
      fixture.host.executeAction(fixture.plugin.pluginId, action),
      _throwsProgramError('declarative.permission_denied'),
    );
    expect(fixture.access.opened, isEmpty);
  });

  test('סנכרון הרשאות פוסל פעולה ישנה גם כשהספר לא השתנה', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );
    final oldAction = fixture.toolbar.getAll().first.$2.hostAction!;

    fixture.permissions.remove('reader.toolbar');
    await fixture.host.syncPlugins([fixture.plugin]);

    expect(fixture.toolbar.getAll(), isEmpty);
    await expectLater(
      fixture.host.executeAction(fixture.plugin.pluginId, oldAction),
      _throwsProgramError('declarative.stale_action'),
    );
    expect(fixture.access.opened, isEmpty);
  });

  test('הסרה מבטלת את ההקשר ומוחקת את שני הפקדים מיד', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );
    expect(fixture.toolbar.getAll(), hasLength(2));

    final oldAction = fixture.toolbar.getAll().first.$2.hostAction!;
    fixture.host.removePlugin(fixture.plugin.pluginId);

    expect(fixture.toolbar.getAll(), isEmpty);
    expect(
      fixture.host.programRepository.getPluginOutputs(fixture.plugin.pluginId),
      isEmpty,
    );
    await expectLater(
      fixture.host.executeAction(fixture.plugin.pluginId, oldAction),
      _throwsProgramError('declarative.stale_action'),
    );
    expect(fixture.access.opened, isEmpty);
  });

  test('יציאה ממסך ספר מוחקת פלט ופקדים', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );

    await fixture.host.readerBookChanged(null, context: 'reader-text');

    expect(fixture.toolbar.getAll(), isEmpty);
  });

  test('סכימה פגומה נכשלת סגור ואינה מפילה סנכרון', () async {
    final fixture = _Fixture(invalidProgram: true);
    addTearDown(fixture.dispose);

    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );

    expect(fixture.toolbar.getAll(), isEmpty);
    expect(fixture.errors, hasLength(1));
  });

  test('grant ישן אינו עוקף הרשאה שהוסרה מהמניפסט', () async {
    final fixture = _Fixture(
      declaredPermissions: const ['reader.toolbar', 'reader.open'],
    );
    addTearDown(fixture.dispose);

    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );

    expect(fixture.toolbar.getAll(), isEmpty);
    expect(fixture.errors, hasLength(1));
  });

  test('פקד Host דורש reader.toolbar גם בהצהרת המניפסט', () async {
    final fixture = _Fixture(
      declaredPermissions: const [
        'app.startup_contributions',
        'reader.open',
      ],
    );
    addTearDown(fixture.dispose);

    await fixture.host.syncPlugins([fixture.plugin]);
    await fixture.host.readerBookChanged(
      TextBook(id: 1, title: 'ספר נוכחי'),
      context: 'reader-text',
    );

    expect(fixture.toolbar.getAll(), isEmpty);
    expect(fixture.errors, hasLength(1));
  });

  group('טריגרים שאינם תלויי-הקשר', () {
    test('app.startup רץ בסנכרון, בלי שנפתח ספר', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);

      await fixture.host.syncPlugins([fixture.plugin]);

      expect(
        fixture.host.programRepository.getProgramOutputs(
          fixture.plugin.pluginId,
          'boot',
        ),
        containsPair('ready', true),
      );
    });

    test('הפלט של app.startup שורד יציאה ממסך הספר', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.host.syncPlugins([fixture.plugin]);
      await fixture.host.readerBookChanged(
        TextBook(id: 1, title: 'ספר נוכחי'),
        context: 'reader-text',
      );

      await fixture.host.readerBookChanged(null, context: 'reader-text');

      final outputs = fixture.host.programRepository.getPluginOutputs(
        fixture.plugin.pluginId,
      );
      expect(outputs.keys, {'boot'});
      expect(fixture.toolbar.getAll(), isEmpty);
    });

    test('app.startup אינו נורה שוב בסנכרון חוזר ללא שינוי', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.host.syncPlugins([fixture.plugin]);
      final firstOutputs = fixture.host.programRepository.getProgramOutputs(
        fixture.plugin.pluginId,
        'boot',
      );

      await fixture.host.syncPlugins([fixture.plugin]);

      // אותו מופע פלט בדיוק: התכנית לא רצה שוב והפקד לא נעלם בדרך.
      expect(
        fixture.host.programRepository.getProgramOutputs(
          fixture.plugin.pluginId,
          'boot',
        ),
        same(firstOutputs),
      );
    });

    test('תוסף שנרשם אחרי העלייה מקבל app.startup בהתקנתו', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.host.syncPlugins(const []);
      expect(fixture.runs, 0);

      await fixture.host.syncPlugins([fixture.plugin]);

      expect(
        fixture.host.programRepository.getProgramOutputs(
          fixture.plugin.pluginId,
          'boot',
        ),
        containsPair('ready', true),
      );
    });

    test('שינוי הגדרות מריץ מחדש את התכנית, מקובץ להשהיה אחת', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.host.syncPlugins([fixture.plugin]);
      final baseline = fixture.runs;

      fixture.settingsRevision.value++;
      fixture.settingsRevision.value++;
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(fixture.runs - baseline, 1);
      expect(
        fixture.host.programRepository.getProgramOutputs(
          fixture.plugin.pluginId,
          'boot',
        ),
        containsPair('ready', true),
      );
    });
  });

  group('dispatchSelectionAction', () {
    final template = <String, dynamic>{
      'type': 'storage.set',
      'args': {
        'key': 'savedBooks',
        'value': {
          'id': {r'$selection': 'id'},
          'title': {r'$selection': 'currentBook'},
        },
      },
    };
    const payload = <String, dynamic>{
      'id': 42,
      'currentBook': 'ברכות',
      'selectedText': 'טקסט מסומן',
    };

    test('כותבת לאחסון התוסף מנתוני הסימון בלי מנוע', () async {
      final fixture = _Fixture(
        declaredPermissions: const [
          'app.startup_contributions',
          'reader.context_menu',
          'plugin.storage.write',
        ],
      );
      addTearDown(fixture.dispose);
      fixture.permissions.add('plugin.storage.write');

      await fixture.host.dispatchSelectionAction(
        fixture.plugin.pluginId,
        template,
        payload,
      );

      expect(fixture.errors, isEmpty);
      final write = fixture.storage.sets.single;
      expect(write.pluginId, fixture.plugin.pluginId);
      expect(write.key, 'savedBooks');
      expect(write.value, {'id': 42, 'title': 'ברכות'});
    });

    test('הרשאה שלא הוצהרה במניפסט חוסמת את הפעולה', () async {
      final fixture = _Fixture(
        declaredPermissions: const [
          'app.startup_contributions',
          'reader.context_menu',
        ],
      );
      addTearDown(fixture.dispose);
      fixture.permissions.add('plugin.storage.write');

      await fixture.host.dispatchSelectionAction(
        fixture.plugin.pluginId,
        template,
        payload,
      );

      expect(fixture.storage.sets, isEmpty);
      expect(fixture.errors, hasLength(1));
    });

    test('הרשאה מוצהרת אך לא מוענקת נחסמת בזמן הביצוע', () async {
      final fixture = _Fixture(
        declaredPermissions: const [
          'app.startup_contributions',
          'plugin.storage.write',
        ],
      );
      addTearDown(fixture.dispose);
      fixture.permissions.remove('plugin.storage.write');

      await fixture.host.dispatchSelectionAction(
        fixture.plugin.pluginId,
        template,
        payload,
      );

      expect(fixture.storage.sets, isEmpty);
      expect(fixture.errors, hasLength(1));
    });

    test('reader.openBook נפתר מזהות הסימון ופותח את הספר', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);

      await fixture.host.dispatchSelectionAction(fixture.plugin.pluginId, {
        'type': 'reader.openBookInSidePane',
        'args': {
          'identity': {
            'id': {r'$selection': 'id'},
          },
          'searchQuery': {r'$selection': 'selectedText'},
        },
      }, payload);

      expect(fixture.errors, isEmpty);
      expect(fixture.access.opened.single, {'id': 42});
    });

    test(r'$storage נקרא מאחסון התוסף בזמן הלחיצה', () async {
      final fixture = _Fixture(
        declaredPermissions: const [
          'app.startup_contributions',
          'reader.context_menu',
          'network.localhost',
          'plugin.storage.read',
        ],
      );
      addTearDown(fixture.dispose);
      fixture.permissions.addAll({'network.localhost', 'plugin.storage.read'});
      fixture.storageValues['servicePort'] = 39701;

      await fixture.host.dispatchSelectionAction(fixture.plugin.pluginId, {
        'type': 'localService.post',
        'args': {
          'port': {r'$storage': 'servicePort'},
          'path': '/text/search',
          'body': {
            'text': {r'$selection': 'selectedText'},
          },
        },
      }, payload);

      expect(fixture.errors, isEmpty);
      expect(fixture.storageReads, ['servicePort']);
      final request = fixture.localService.requests.single;
      expect(request.uri.toString(), 'http://127.0.0.1:39701/text/search');
      expect(jsonDecode(request.body), {'text': 'טקסט מסומן'});
    });
  });

  group('dispatchLibraryBookAction', () {
    const book = <String, dynamic>{
      'provider': 'mylib',
      'id': 7008,
      'title': 'אבני נזר',
    };
    final openAction = <String, dynamic>{
      'type': 'localService.post',
      'args': {
        'port': {r'$storage': 'servicePort'},
        'path': '/book/open',
        'body': {
          'id': {r'$book': 'id'},
          'title': {r'$book': 'title'},
        },
        'unavailableMessage': 'השירות אינו פועל',
      },
    };

    _Fixture fixtureWithService() {
      final fixture = _Fixture(
        declaredPermissions: const [
          'app.startup_contributions',
          'library.books.provide',
          'network.localhost',
          'plugin.storage.read',
        ],
      );
      fixture.permissions.addAll({'network.localhost', 'plugin.storage.read'});
      fixture.storageValues['servicePort'] = 39700;
      return fixture;
    }

    test('פונה לשירות המקומי עם זהות הספר, בלי מנוע', () async {
      final fixture = fixtureWithService();
      addTearDown(fixture.dispose);
      fixture.localService.reply = const DeclarativeLocalServiceResponse(
        status: 200,
        body: '{"message":"אבני נזר נפתח בבר אילן"}',
      );

      await fixture.host.dispatchLibraryBookAction(
        fixture.plugin.pluginId,
        openAction,
        book,
      );

      expect(fixture.errors, isEmpty);
      final request = fixture.localService.requests.single;
      expect(request.uri.toString(), 'http://127.0.0.1:39700/book/open');
      expect(jsonDecode(request.body), {'id': 7008, 'title': 'אבני נזר'});
      expect(fixture.snacks.shown.single, (
        message: 'אבני נזר נפתח בבר אילן',
        severity: 'success',
        pluginName: 'Host',
      ));
    });

    test(r'$selection אינו זמין בספר ספק', () async {
      final fixture = fixtureWithService();
      addTearDown(fixture.dispose);

      await fixture.host.dispatchLibraryBookAction(fixture.plugin.pluginId, {
        'type': 'localService.post',
        'args': {
          'port': 39700,
          'path': '/x',
          'body': {
            'text': {r'$selection': 'selectedText'},
          },
        },
      }, book);

      expect(fixture.localService.requests, isEmpty);
      expect(
        fixture.errors.single,
        isA<DeclarativeProgramException>().having(
          (error) => error.code,
          'code',
          'declarative.invalid_reference',
        ),
      );
    });

    test('פורט שלא נשמר עדיין: הודעת "אינו פועל", בלי בקשה', () async {
      final fixture = fixtureWithService();
      addTearDown(fixture.dispose);
      fixture.storageValues.remove('servicePort');

      await fixture.host.dispatchLibraryBookAction(
        fixture.plugin.pluginId,
        openAction,
        book,
      );

      expect(fixture.localService.requests, isEmpty);
      expect(fixture.errors, isEmpty);
      expect(fixture.snacks.shown.single.message, 'השירות אינו פועל');
    });

    test('הרשאת network.localhost שבוטלה חוסמת את הבקשה', () async {
      final fixture = fixtureWithService();
      addTearDown(fixture.dispose);
      fixture.permissions.remove('network.localhost');

      await fixture.host.dispatchLibraryBookAction(
        fixture.plugin.pluginId,
        openAction,
        book,
      );

      expect(fixture.localService.requests, isEmpty);
      expect(fixture.errors, isEmpty);
      expect(
        fixture.snacks.shown.single.message,
        PluginMessages.localServiceBlocked,
      );
    });
  });
}

class _Fixture {
  final toolbar = PluginToolbarRegistry.forTesting();
  final permissions = <String>{
    'app.startup_contributions',
    'reader.toolbar',
    'reader.open',
  };
  final errors = <Object>[];
  final _BookAccess access = _BookAccess();
  final _StorageWriter storage = _StorageWriter();
  final storageValues = <String, Object?>{};
  final storageReads = <String>[];
  final localService = _LocalServiceClient();
  final snacks = _SnackPresenter();
  final settingsRevision = ValueNotifier<int>(0);
  late final InstalledPlugin plugin;
  late final DeclarativePluginHostService host;

  /// מספר הריצות שהמאגר סימן לתוסף — כל runTrigger מקדם דור אחד.
  int get runs => host.programRepository.getGeneration(plugin.pluginId);

  _Fixture({
    bool invalidProgram = false,
    List<String>? declaredPermissions,
  }) {
    plugin = _plugin(
      invalidProgram: invalidProgram,
      declaredPermissions: declaredPermissions,
    );
    host = DeclarativePluginHostService(
      loadPlugin: (pluginId) async =>
          pluginId == plugin.pluginId ? plugin : null,
      loadPermissions: (_) async => Set.of(permissions),
      bookResolver: access,
      bookOpener: access,
      toolbarRegistry: toolbar,
      storageWriter: storage,
      storageReader: _StorageReader((key) {
        storageReads.add(key);
        return storageValues[key];
      }),
      localServiceClient: localService,
      networkGate: (_, _) async => PluginNetworkDecision.allowed,
      snackPresenter: snacks,
      settingsRevision: settingsRevision,
      onError: (_, error, _) => errors.add(error),
    );
  }

  void dispose() {
    host.dispose();
    settingsRevision.dispose();
  }
}

class _StorageReader implements DeclarativeStorageReader {
  final Object? Function(String key) read;

  _StorageReader(this.read);

  @override
  Future<Object?> get(String pluginId, String key) async => read(key);
}

class _LocalServiceClient implements DeclarativeLocalServiceClient {
  DeclarativeLocalServiceResponse reply = const DeclarativeLocalServiceResponse(
    status: 204,
    body: '',
  );
  final requests = <({Uri uri, String body})>[];

  @override
  Future<DeclarativeLocalServiceResponse> post(
    Uri uri,
    String jsonBody, {
    required Duration timeout,
  }) async {
    requests.add((uri: uri, body: jsonBody));
    return reply;
  }
}

class _SnackPresenter implements DeclarativeSnackPresenter {
  final shown = <({String message, String severity, String pluginName})>[];

  @override
  void show(String message, String severity, {required String pluginName}) {
    shown.add((message: message, severity: severity, pluginName: pluginName));
  }

  @override
  void Function() showPending(String message, {required String pluginName}) =>
      () {};
}

class _StorageWriter implements DeclarativeStorageWriter {
  final sets = <({String pluginId, String key, Object? value})>[];

  @override
  Future<void> set(String pluginId, String key, Object? value) async {
    sets.add((pluginId: pluginId, key: key, value: value));
  }

  @override
  Future<void> remove(String pluginId, String key) async {}
}

class _BookAccess implements DeclarativeBookResolver, DeclarativeBookOpener {
  final opened = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>?>> resolveUniqueBatch(
    List<Map<String, dynamic>> identities,
  ) async => identities;

  @override
  Future<bool> openUnique(
    Map<String, dynamic> identity, {
    required int index,
    required String searchQuery,
    bool inSidePane = false,
    ExternalBookMatches? externalMatches,
  }) async {
    opened.add(identity);
    return true;
  }
}

InstalledPlugin _plugin({
  required bool invalidProgram,
  List<String>? declaredPermissions,
}) {
  final now = DateTime(2026);
  final program = <String, dynamic>{
    'id': 'book-links',
    'version': 1,
    'triggers': ['reader.activeBookChanged'],
    'commands': [
      {
        'id': 'first',
        'type': invalidProgram ? 'javascript.eval' : 'data.first',
        'args': {
          'items': {
            r'$literal': [
              {
                'title': 'מהדורה',
                'identity': {'id': 7},
              },
            ],
          },
        },
      },
    ],
    'outputs': {
      'defaultEdition': {r'$result': 'first'},
      'editions': {
        r'$literal': [
          {
            'title': 'מהדורה',
            'identity': {'id': 7},
          },
        ],
      },
    },
  };
  return InstalledPlugin(
    pluginId: 'test.host.plugin',
    name: 'Host',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: false,
    manifest: PluginManifest.fromJson({
      'schemaVersion': 1,
      'id': 'test.host.plugin',
      'name': 'Host',
      'version': '1.0.0',
      'entrypoint': 'index.html',
      'minAppVersion': '0.9.98',
      'permissions':
          declaredPermissions ??
          [
            'app.startup_contributions',
            'reader.toolbar',
            'reader.open',
          ],
      'contributes': {
        'startup': {
          'programs': [program, _bootProgram()],
          'toolbarItems': _toolbarItems(),
        },
      },
    }),
    installedAt: now,
    updatedAt: now,
  );
}

/// תכנית שאינה תלוית-הקשר: רצה בעלייה ובכל שינוי הגדרות.
Map<String, dynamic> _bootProgram() => {
  'id': 'boot',
  'version': 1,
  'triggers': ['app.startup', 'settings.changed'],
  'commands': [
    {
      'id': 'flag',
      'type': 'data.first',
      'args': {
        'items': {
          r'$literal': [true],
        },
      },
    },
  ],
  'outputs': {
    'ready': {r'$result': 'flag'},
  },
};

List<Map<String, dynamic>> _toolbarItems() => [
  {
    'id': 'default',
    'title': 'פתח ברירת מחדל',
    'icon': 'book_24_regular',
    'binding': {
      'program': 'book-links',
      'visibleOutput': 'defaultEdition',
    },
    'action': {
      'type': 'reader.openBook',
      'args': {
        'identity': {r'$output': 'defaultEdition.identity'},
      },
    },
  },
  {
    'id': 'editions',
    'type': 'menu',
    'title': 'פתח מהדורה',
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
            {r'$item': 'identity.id'},
          ],
        },
        'title': {r'$item': 'title'},
        'action': {
          'type': 'reader.openBook',
          'args': {
            'identity': {
              'id': {r'$item': 'identity.id'},
            },
          },
        },
      },
    },
  },
];

Matcher _throwsProgramError(String code) => throwsA(
  isA<DeclarativeProgramException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);
