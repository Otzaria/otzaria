import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_action_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_host_action_executor.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
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

  group('localService.post', () {
    group('קומפילציה', () {
      test('פורט, נתיב, גוף והודעות תקינים עוברים', () {
        final action = _compileLocal();
        expect(action.requiredPermission, 'network.localhost');
        expect(action.args['body'], {'q': 'נר שבת'});
      });

      test('פורט מחוץ לטווח או שאינו מספר נדחה', () {
        for (final port in [0, 65536, '39700', 1.5]) {
          expect(
            () => _compileLocal(args: {'port': port, 'path': '/x'}),
            _throwsProgramError('declarative.invalid_args'),
            reason: '$port',
          );
        }
      });

      test('נתיב עם כתובת, query או קטעי נקודה נדחה', () {
        for (final path in [
          'http://evil.example/x',
          'text/search',
          '/text/search?q=1',
          '/a/../admin',
          '/a/./b',
          '//evil.example',
          '/שלום',
        ]) {
          expect(
            () => _compileLocal(args: {'port': 39700, 'path': path}),
            _throwsProgramError('declarative.invalid_args'),
            reason: path,
          );
        }
      });

      test('גוף שאינו אובייקט, או גדול מדי, נדחה', () {
        expect(
          () => _compileLocal(
            args: {'port': 39700, 'path': '/x', 'body': 'q=1'},
          ),
          _throwsProgramError('declarative.invalid_args'),
        );
        expect(
          () => _compileLocal(
            args: {
              'port': 39700,
              'path': '/x',
              'body': {'items': List.generate(300, (i) => i)},
            },
          ),
          _throwsProgramError('declarative.value_too_large'),
        );
      });

      test('פורט ריק מותר רק בפעולת לחיצה', () {
        expect(
          () => _compileLocal(args: {'port': null, 'path': '/x'}),
          _throwsProgramError('declarative.invalid_args'),
        );
        _compileLocal(
          args: {'port': null, 'path': '/x'},
          allowMissingPort: true,
        );
      });

      test('זמן ההמתנה המרבי הוא זה של network.fetchStream', () {
        expect(
          DeclarativeActionCompiler.maxLocalServiceTimeoutMs,
          PluginNetworkFetchService.maxTimeout.inMilliseconds,
        );
      });

      test('זמן המתנה מחוץ לטווח נדחה', () {
        for (final timeoutMs in [999, 120001, 1.5]) {
          expect(
            () => _compileLocal(
              args: {'port': 39700, 'path': '/x', 'timeoutMs': timeoutMs},
            ),
            _throwsProgramError('declarative.invalid_args'),
            reason: '$timeoutMs',
          );
        }
      });

      test('בלי הצהרה על network.localhost הפעולה נדחית', () {
        expect(
          () =>
              const DeclarativeActionCompiler(
                declaredPermissions: {'reader.open'},
              ).compileResolved(
                {
                  'type': 'localService.post',
                  'args': {'port': 39700, 'path': '/x'},
                },
                contextSignature: 'book-7',
                programGeneration: 7,
              ),
          _throwsProgramError('declarative.permission_not_declared'),
        );
      });
    });

    test('שולחת JSON ל-127.0.0.1 ומציגה את ההודעה שהשירות החזיר', () async {
      final client = _LocalServiceClient(
        reply: const DeclarativeLocalServiceResponse(
          status: 200,
          body: '{"message":"בר אילן מצא 191 תוצאות","severity":"success"}',
        ),
      );
      final presenter = _SnackPresenter();

      final done = await _executeLocal(
        _compileLocal(),
        client: client,
        presenter: presenter,
      );

      expect(done, isTrue);
      final request = client.requests.single;
      expect(request.uri.toString(), 'http://127.0.0.1:39700/text/search');
      expect(jsonDecode(request.body), {'q': 'נר שבת'});
      expect(request.timeout, const Duration(seconds: 60));
      expect(presenter.shown.map((s) => (s.message, s.severity)), [
        ('מחפש בבר אילן…', 'pending'),
        ('בר אילן מצא 191 תוצאות', 'success'),
      ]);
      expect(presenter.hides, 0);
    });

    test('הצלחה בלי הודעה מסתירה את הודעת ההמתנה', () async {
      final presenter = _SnackPresenter();

      final done = await _executeLocal(
        _compileLocal(),
        client: _LocalServiceClient(
          reply: const DeclarativeLocalServiceResponse(
            status: 200,
            body: 'OK',
          ),
        ),
        presenter: presenter,
      );

      expect(done, isTrue);
      expect(presenter.shown.single.severity, 'pending');
      expect(presenter.hides, 1);
    });

    test('severity לא מוכר בתשובה: הדרגה לפי קוד התשובה', () async {
      final presenter = _SnackPresenter();

      await _executeLocal(
        _compileLocal(args: {'port': 39700, 'path': '/x'}),
        client: _LocalServiceClient(
          reply: const DeclarativeLocalServiceResponse(
            status: 200,
            body: '{"message":"נפתח","severity":"critical"}',
          ),
        ),
        presenter: presenter,
      );

      expect(presenter.shown.single.severity, 'success');
    });

    test('בלי severity בתשובה, הדרגה נקבעת לפי קוד התשובה', () async {
      final presenter = _SnackPresenter();

      final done = await _executeLocal(
        _compileLocal(args: {'port': 39700, 'path': '/x'}),
        client: _LocalServiceClient(
          reply: const DeclarativeLocalServiceResponse(
            status: 409,
            body: '{"message":"בר אילן עסוק"}',
          ),
        ),
        presenter: presenter,
      );

      expect(done, isFalse);
      expect(presenter.shown.single.message, 'בר אילן עסוק');
      expect(presenter.shown.single.severity, 'error');
    });

    test('שגיאה בלי הודעה מציגה הודעה כללית; הצלחה בלי הודעה שקטה', () async {
      final failed = _SnackPresenter();
      await _executeLocal(
        _compileLocal(args: {'port': 39700, 'path': '/x'}),
        client: _LocalServiceClient(
          reply: const DeclarativeLocalServiceResponse(
            status: 500,
            body: '<html>',
          ),
        ),
        presenter: failed,
      );
      expect(failed.shown.single.message, PluginMessages.localServiceFailed);

      final quiet = _SnackPresenter();
      final done = await _executeLocal(
        _compileLocal(args: {'port': 39700, 'path': '/x'}),
        client: _LocalServiceClient(
          reply: const DeclarativeLocalServiceResponse(status: 204, body: ''),
        ),
        presenter: quiet,
      );
      expect(done, isTrue);
      expect(quiet.shown, isEmpty);
    });

    test('הודעה ארוכה מקוצרת, ותווי בקרה מוסרים', () async {
      final presenter = _SnackPresenter();
      await _executeLocal(
        _compileLocal(args: {'port': 39700, 'path': '/x'}),
        client: _LocalServiceClient(
          reply: DeclarativeLocalServiceResponse(
            status: 200,
            body: jsonEncode({'message': 'שורה\nשנייה ${'א' * 300}'}),
          ),
        ),
        presenter: presenter,
      );

      final message = presenter.shown.single.message;
      expect(message, startsWith('שורה שנייה'));
      expect(message, hasLength(DeclarativeActionCompiler.maxSnackLength));
      expect(message, endsWith('…'));
    });

    test('סימני כיווניות בהודעת השירות מוסרים', () async {
      final presenter = _SnackPresenter();
      await _executeLocal(
        _compileLocal(args: {'port': 39700, 'path': '/x'}),
        client: _LocalServiceClient(
          reply: const DeclarativeLocalServiceResponse(
            status: 200,
            body: '{"message":"\u202Eנפתח\u2066 בבר\u200F אילן"}',
          ),
        ),
        presenter: presenter,
      );

      expect(presenter.shown.single.message, 'נפתח בבר אילן');
    });

    test('שירות שאינו עונה: הודעת התוסף, בלי חריגה', () async {
      for (final error in <Object>[
        const SocketException('refused'),
        http.ClientException('connection closed'),
        TimeoutException('slow'),
      ]) {
        final presenter = _SnackPresenter();

        final done = await _executeLocal(
          _compileLocal(),
          client: _LocalServiceClient(error: error),
          presenter: presenter,
        );

        expect(done, isFalse);
        expect(presenter.shown.last.message, 'שירות בר אילן אינו פועל');
        expect(presenter.shown.last.severity, 'error');
      }
    });

    test('תשובה שאינה UTF-8 תקין: הודעת כישלון, בלי חריגה', () async {
      final presenter = _SnackPresenter();

      final done = await _executeLocal(
        _compileLocal(),
        client: _LocalServiceClient(
          error: const FormatException('Unexpected extension byte'),
        ),
        presenter: presenter,
      );

      expect(done, isFalse);
      expect(presenter.shown.last.message, PluginMessages.localServiceFailed);
      expect(presenter.hides, 0);
    });

    test(
      'פורט ריק (\$storage שעוד לא נשמר): השירות אינו זמין, בלי בקשה',
      () async {
        final client = _LocalServiceClient();
        final presenter = _SnackPresenter();

        final done = await _executeLocal(
          _compileLocal(
            args: {'port': null, 'path': '/x'},
            allowMissingPort: true,
          ),
          client: client,
          presenter: presenter,
        );

        expect(done, isFalse);
        expect(client.requests, isEmpty);
        expect(
          presenter.shown.single.message,
          PluginMessages.localServiceUnavailable,
        );
      },
    );

    test('לחיצה חוזרת בזמן שהבקשה רצה אינה שולחת בקשה שנייה', () async {
      final release = Completer<void>();
      final client = _LocalServiceClient(gate: release.future);
      final presenter = _SnackPresenter();

      final first = _executeLocal(
        _compileLocal(),
        client: client,
        presenter: presenter,
      );
      final second = await _executeLocal(
        _compileLocal(),
        client: client,
        presenter: presenter,
      );
      release.complete();

      expect(second, isFalse);
      expect(await first, isTrue);
      expect(client.requests, hasLength(1));
      expect(
        presenter.shown.where((s) => s.severity == 'pending'),
        hasLength(1),
      );
      expect(presenter.hides, 1);
      expect(
        await _executeLocal(_compileLocal(), client: client),
        isTrue,
        reason: 'אחרי שהבקשה הסתיימה אפשר לשלוח שוב',
      );
      expect(client.requests, hasLength(2));
    });

    test('לחיצה עם גוף אחר בזמן שבקשה רצה נשלחת', () async {
      final release = Completer<void>();
      final client = _LocalServiceClient(gate: release.future);
      CompiledDeclarativeAction search(String q) => _compileLocal(
        args: {
          'port': 39700,
          'path': '/text/search',
          'body': {'q': q},
        },
      );

      final first = _executeLocal(search('נר'), client: client);
      final second = _executeLocal(search('שבת'), client: client);
      release.complete();

      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(client.requests.map((r) => jsonDecode(r.body)['q']), [
        'נר',
        'שבת',
      ]);
    });

    test('חריג לא צפוי: הודעת כישלון, והחריג ממשיך לדיווח', () async {
      final presenter = _SnackPresenter();

      await expectLater(
        _executeLocal(
          _compileLocal(),
          client: _LocalServiceClient(error: StateError('bad state')),
          presenter: presenter,
        ),
        throwsStateError,
      );
      expect(presenter.shown.last.message, PluginMessages.localServiceFailed);
      expect(presenter.hides, 0);
    });

    test('בלי unavailableMessage מוצגת ההודעה הכללית', () async {
      final presenter = _SnackPresenter();

      await _executeLocal(
        _compileLocal(args: {'port': 39700, 'path': '/x'}),
        client: _LocalServiceClient(error: const SocketException('refused')),
        presenter: presenter,
      );

      expect(
        presenter.shown.single.message,
        PluginMessages.localServiceUnavailable,
      );
    });

    test('יעד שאינו ברשימת ההיתר של התוסף נחסם לפני כל בקשה', () async {
      final client = _LocalServiceClient();
      final presenter = _SnackPresenter();

      final done = await _executeLocal(
        _compileLocal(),
        client: client,
        presenter: presenter,
        decision: PluginNetworkDecision.notAllowlisted,
      );

      expect(done, isFalse);
      expect(client.requests, isEmpty);
      expect(
        presenter.shown.single.message,
        PluginMessages.localServiceBlocked,
      );
    });

    test('בלי הרשאה מוענקת הפעולה נחסמת', () async {
      final client = _LocalServiceClient();

      final presenter = _SnackPresenter();
      expect(
        await _executeLocal(
          _compileLocal(),
          client: client,
          presenter: presenter,
          granted: const {},
        ),
        isFalse,
      );
      expect(client.requests, isEmpty);
      expect(
        presenter.shown.single.message,
        PluginMessages.localServiceBlocked,
      );
    });

    group('PluginLocalServiceClient מול שרת אמיתי', () {
      late HttpServer server;
      late Future<void> Function(HttpRequest) handler;
      late Completer<void> finished;

      setUp(() async {
        finished = Completer<void>();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) => handler(request));
      });

      tearDown(() async {
        if (!finished.isCompleted) finished.complete();
        await server.close(force: true);
      });

      test('שולח POST עם JSON ומחזיר את התשובה', () async {
        late String method;
        late String contentType;
        late String received;
        handler = (request) async {
          method = request.method;
          contentType = request.headers.contentType.toString();
          received = await utf8.decodeStream(request);
          request.response
            ..headers.contentType = ContentType.json
            ..write('{"message":"נפתח"}');
          await request.response.close();
        };

        final response = await PluginLocalServiceClient().post(
          Uri.parse('http://127.0.0.1:${server.port}/book/open'),
          '{"id":7}',
          timeout: const Duration(seconds: 5),
        );

        expect(method, 'POST');
        expect(contentType, startsWith('application/json'));
        expect(received, '{"id":7}');
        expect(response.status, 200);
        expect(response.body, '{"message":"נפתח"}');
      });

      test('תשובה איטית מזמן ההמתנה נקטעת כ-TimeoutException', () async {
        handler = (request) async {
          await finished.future;
          await request.response.close();
        };

        await expectLater(
          PluginLocalServiceClient().post(
            Uri.parse('http://127.0.0.1:${server.port}/slow'),
            '{}',
            timeout: const Duration(milliseconds: 200),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('תשובה ענקית נקראת רק עד התקרה', () async {
        handler = (request) async {
          for (var i = 0; i < 64; i++) {
            request.response.write('x' * 4096);
          }
          await request.response.close();
        };

        final response = await PluginLocalServiceClient().post(
          Uri.parse('http://127.0.0.1:${server.port}/big'),
          '{}',
          timeout: const Duration(seconds: 5),
        );

        expect(response.status, 200);
        expect(
          response.body.length,
          lessThan(PluginLocalServiceClient.maxResponseLength + 64 * 1024),
        );
        expect(response.body.length, lessThan(64 * 4096));
      });

      test('פורט שאין בו שירות נזרק כשגיאת חיבור', () async {
        final port = server.port;
        await server.close(force: true);

        await expectLater(
          PluginLocalServiceClient().post(
            Uri.parse('http://127.0.0.1:$port/x'),
            '{}',
            timeout: const Duration(seconds: 5),
          ),
          // אלה בדיוק מה שהמבצע מתרגם להודעת "השירות אינו זמין".
          throwsA(anyOf(isA<SocketException>(), isA<http.ClientException>())),
        );
      });
    });
  });
}

class _LocalServiceClient implements DeclarativeLocalServiceClient {
  final DeclarativeLocalServiceResponse reply;
  final Object? error;

  /// התשובה מתעכבת עד שה-future הזה מסתיים (בקשה שעוד רצה).
  final Future<void>? gate;
  final requests = <({Uri uri, String body, Duration timeout})>[];

  _LocalServiceClient({
    this.reply = const DeclarativeLocalServiceResponse(status: 200, body: ''),
    this.error,
    this.gate,
  });

  @override
  Future<DeclarativeLocalServiceResponse> post(
    Uri uri,
    String jsonBody, {
    required Duration timeout,
  }) async {
    requests.add((uri: uri, body: jsonBody, timeout: timeout));
    if (gate case final gate?) await gate;
    if (error case final error?) throw error;
    return reply;
  }
}

CompiledDeclarativeAction _compileLocal({
  Map<String, dynamic>? args,
  bool allowMissingPort = false,
}) =>
    const DeclarativeActionCompiler(
      declaredPermissions: {'network.localhost'},
    ).compileResolved(
      {
        'type': 'localService.post',
        'args':
            args ??
            {
              'port': 39700,
              'path': '/text/search',
              'body': {'q': 'נר שבת'},
              'pendingMessage': 'מחפש בבר אילן…',
              'unavailableMessage': 'שירות בר אילן אינו פועל',
              'timeoutMs': 60000,
            },
      },
      contextSignature: 'book-7',
      programGeneration: 7,
      allowMissingPort: allowMissingPort,
    );

Future<bool> _executeLocal(
  CompiledDeclarativeAction action, {
  required _LocalServiceClient client,
  _SnackPresenter? presenter,
  PluginNetworkDecision decision = PluginNetworkDecision.allowed,
  Set<String> granted = const {'network.localhost'},
}) =>
    DeclarativeHostActionExecutor(
      bookOpener: _BookOpener(),
      snackPresenter: presenter ?? _SnackPresenter(),
      localServiceClient: client,
      networkGate: (_, _) async => decision,
    ).execute(
      action: action,
      plugin: _plugin(),
      grantedPermissions: granted,
      currentContextSignature: 'book-7',
      currentProgramGeneration: 7,
    );

class _SnackPresenter implements DeclarativeSnackPresenter {
  final shown = <({String message, String severity, String pluginName})>[];
  var hides = 0;

  @override
  void show(String message, String severity, {required String pluginName}) {
    shown.add((message: message, severity: severity, pluginName: pluginName));
  }

  /// נרשמת כ-severity `pending`, כדי לבדוק את סדר ההודעות במקום אחד.
  @override
  void Function() showPending(String message, {required String pluginName}) {
    shown.add((message: message, severity: 'pending', pluginName: pluginName));
    return () => hides++;
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
