import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:path/path.dart' as p;

/// מריץ את תור האירועים: כתיבות המאגר הישיר, שחרור ה-lease ואירוע הסיום.
Future<void> _idle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PluginCorrectionSessionService service;
  late Map<int, String> source;
  late Map<String, dynamic> session;
  late Database db;
  Directory? storageMoveDirectory;

  Map<String, dynamic> change(int index, String proposed) => {
    'sectionIndex': index,
    'originalSourceText': 'מקור $index',
    'originalText': 'מקור $index',
    'proposedText': proposed,
  };

  Future<Map<String, dynamic>> restore(
    List<dynamic> changes, {
    int revision = 0,
  }) => service.restore(
    owner: 'owner',
    id: session['sessionId'],
    expectedRevision: revision,
    bookUid: 'id:42',
    libraryVersion: 'v1',
    changes: changes,
  );

  Future<Map<String, dynamic>> current() =>
      service.get('owner', session['sessionId']);

  Future<Map<String, dynamic>> beginTab({
    String owner = 'owner',
    String tabId = 'tab',
    String bookUid = 'id:42',
    Future<String> Function(int)? loadSource,
    Future<void> Function()? validateSource,
    void Function(String, Map<String, dynamic>)? onEvent,
    int? ownerEpoch,
  }) => service.begin(
    owner: owner,
    tabId: tabId,
    bookId: 'ספר',
    bookUid: bookUid,
    libraryVersion: 'v1',
    loadSource: loadSource ?? (index) async => source[index]!,
    validateSource: validateSource,
    onEvent: onEvent,
    ownerEpoch: ownerEpoch,
  );

  /// מסיים את הסשן הנוכחי וממתין לשחרור ה-lease, כדי שאפשר יהיה לפתוח שוב.
  Future<void> closeCurrent() async {
    service.removeTab('tab');
    await _idle();
  }

  Matcher error(String code) => throwsA(
    isA<PluginCorrectionException>().having(
      (value) => value.code,
      'code',
      code,
    ),
  );

  setUp(() async {
    storageMoveDirectory = null;
    db = sqlite3.openInMemory();
    service = PluginCorrectionSessionService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    source = {0: 'מקור 0', 1: 'מקור 1'};
    session = await beginTab();
  });

  tearDown(() async {
    service.endAll('test');
    await service.flushAll();
    await _idle();
    service.dispose();
    db.close();
    if (storageMoveDirectory != null) {
      await storageMoveDirectory!.delete(recursive: true);
    }
  });

  test('טיוטה אינה משנה מקור ותמונת המצב עצמאית', () async {
    final result = await restore([change(0, 'תיקון 😀')]);
    expect(result['revision'], 1);
    expect(source, {0: 'מקור 0', 1: 'מקור 1'});
    expect(service.displayText('tab', 0, 'מקור 0'), 'תיקון 😀');
    expect(service.displayText('other-tab', 0, 'מקור 0'), 'מקור 0');
    expect(service.displayText('tab', 0, 'מקור אחר'), 'מקור אחר');
    (result['changes'] as List).clear();
    expect((await current())['changes'], hasLength(1));
  });

  test('נעילת הכנה ליציאה עוצרת עריכה ומשתחררת בביטול', () async {
    expect(service.beginProcessQuitPreparation('quit-1'), isTrue);
    expect(
      () => service.editParagraph('tab', 0, 'מקור 0', 'נוסח חדש'),
      throwsA(
        isA<PluginCorrectionException>().having(
          (error) => error.code,
          'code',
          'error.correction_busy',
        ),
      ),
    );
    service.cancelProcessQuitPreparation('stale-quit');
    expect(service.processQuitPending, isTrue);
    service.cancelProcessQuitPreparation('quit-1');
    service.editParagraph('tab', 0, 'מקור 0', 'נוסח חדש');
    expect(service.displayText('tab', 0, 'מקור 0'), 'נוסח חדש');
  });

  test(
    'ביטול הרשאת התוסף בזמן הכנה מסיים את הסשן גם אחרי ביטול היציאה',
    () async {
      expect(service.beginProcessQuitPreparation('quit-revoked-owner'), isTrue);

      service.removeOwner('owner');

      expect(service.hasSessionForTab('tab'), isFalse);
      service.cancelProcessQuitPreparation('quit-revoked-owner');
      expect(service.hasSessionForTab('tab'), isFalse);
      await _idle();
      expect(await service.flushAll(), isTrue);
    },
  );

  test('הסרת לשונית בזמן הכנה מסיימת את הסשן גם אחרי ביטול היציאה', () async {
    expect(service.beginProcessQuitPreparation('quit-removed-tab'), isTrue);

    service.removeTab('tab');

    expect(service.hasSessionForTab('tab'), isFalse);
    service.cancelProcessQuitPreparation('quit-removed-tab');
    expect(service.hasSessionForTab('tab'), isFalse);
    await _idle();
    expect(await service.flushAll(), isTrue);
  });

  test('restore שממתין למקור נדחה אם הכנת היציאה ננעלת לפני commit', () async {
    service.removeTab('tab');
    await _idle();
    final entered = Completer<void>();
    final release = Completer<void>();
    session = await beginTab(
      loadSource: (index) async {
        if (index == 0) {
          entered.complete();
          await release.future;
        }
        return source[index]!;
      },
    );
    final pending = restore([change(0, 'תיקון')]);
    await entered.future;
    expect(service.beginProcessQuitPreparation('quit-during-restore'), isTrue);
    release.complete();
    await expectLater(pending, error('error.correction_busy'));
    expect((await current())['changes'], isEmpty);
    service.cancelProcessQuitPreparation('quit-during-restore');
  });

  test('איפוס runtime סוגר את הסשן ומשאיר טיוטה לפתיחה מחדש', () async {
    service.editParagraph('tab', 0, 'מקור 0', 'תיקון');
    expect(await service.flushAll(), isTrue);
    await service.prepareForRuntimeReset();
    expect(service.hasSessionForTab('tab'), isFalse);

    service.draftRepository = PluginCorrectionDraftRepository.direct(db);
    session = await beginTab();
    expect(service.displayText('tab', 0, 'מקור 0'), 'תיקון');
  });

  test(
    'העברת מסדים ממתינה לכל ה-flush לפני סיום ושומרת את הנעילה ב-reset',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'correction-storage-move-',
      );
      storageMoveDirectory = temp;
      service.endAll('test');
      await service.flushAll();
      await _idle();
      await service.prepareForRuntimeReset();
      db.close();

      final oldDatabase = p.join(temp.path, 'old', 'plugins_host.db');
      final newDatabase = p.join(temp.path, 'new', 'plugins_host.db');
      await Directory(p.dirname(oldDatabase)).create(recursive: true);
      await Directory(p.dirname(newDatabase)).create(recursive: true);
      db = openWritableDatabase(oldDatabase, 'test');
      service.draftRepository = PluginCorrectionDraftRepository.direct(db);
      session = await beginTab();
      service.editParagraph('tab', 0, 'מקור 0', 'תיקון להעברה');
      const requestId = 'storage-move-test';
      expect(service.beginProcessQuitPreparation(requestId), isTrue);

      expect(await service.prepareForStorageMove(requestId), isTrue);
      expect(service.hasSessionForTab('tab'), isTrue);

      expect(await service.finishStorageMovePreparation(requestId), isTrue);
      expect(service.hasSessionForTab('tab'), isFalse);
      await service.prepareForRuntimeReset(requestId: requestId);
      expect(service.isProcessQuitPreparedFor(requestId), isTrue);

      service.cancelProcessQuitPreparation(requestId);
      db.close();
      await File(oldDatabase).copy(newDatabase);
      db = openWritableDatabase(newDatabase, 'test');
      service.draftRepository = PluginCorrectionDraftRepository.direct(db);
      session = await beginTab();
      expect(service.displayText('tab', 0, 'מקור 0'), 'תיקון להעברה');
    },
  );

  test('פסקת איגרא רמה עם HTML נערכת כטקסט ושומרת מקור גולמי לשחזור', () async {
    const raw = '<b>בגמרא</b> חנן התם וגג <big>לחלק</big> &amp; 😀';
    const plain = 'בגמרא חנן התם וגג לחלק & 😀';
    source[0] = raw;
    expect(service.canEditParagraph('tab', raw), isTrue);
    expect(service.editableText('tab', 0, raw), plain);
    service.editParagraph('tab', 0, raw, '$plain תיקון');
    final latest = await current();
    final edited = (latest['changes'] as List).single;
    expect(edited['originalSourceText'], raw);
    expect(edited['originalText'], plain);
    expect(edited['proposedText'], '$plain תיקון');
    expect(source[0], raw);
    service.reset('owner', session['sessionId'], 0, 1);
    expect(service.editableText('tab', 0, raw), plain);
    expect(service.displayText('other-tab', 0, raw), raw);
    await restore([edited], revision: 2);
    expect(service.editableText('tab', 0, raw), '$plain תיקון');
    service.editParagraph('tab', 0, raw, plain);
    expect((await current())['changes'], isEmpty);
    await expectLater(
      restore([
        {...edited, 'originalText': raw},
      ], revision: 4),
      error('error.invalid_params'),
    );
    source[0] = raw
        .replaceFirst('<b>', '<strong>')
        .replaceFirst('</b>', '</strong>');
    await expectLater(
      restore([edited], revision: 4),
      error('error.source_changed'),
    );
  });

  test('בעלות אינה ניתנת להעברה ואינה חושפת סשן זר', () async {
    await expectLater(
      service.get('other', session['sessionId']),
      error('error.not_found'),
    );
    await expectLater(
      beginTab(owner: 'other', loadSource: (index) async => ''),
      error('error.correction_busy'),
    );
  });

  test(
    'אותו תוסף ואותו ספר בלשונית שנייה נדחה; אותה לשונית מחזירה סשן',
    () async {
      await expectLater(
        beginTab(tabId: 'second-tab'),
        error('error.correction_busy'),
      );
      final again = await beginTab();
      expect(again['sessionId'], session['sessionId']);
    },
  );

  test('כשל אימות בפסקה השנייה אינו מחיל את הראשונה', () async {
    source[1] = 'מקור שהשתנה';
    await expectLater(
      restore([change(0, 'א'), change(1, 'ב')]),
      error('error.source_changed'),
    );
    expect((await current())['revision'], 0);
    expect(service.displayText('tab', 0, 'מקור 0'), 'מקור 0');
  });

  test('revision ישן אינו דורס תיקון חדש', () async {
    await restore([change(0, 'א')]);
    await expectLater(
      restore([change(0, 'ב')]),
      error('error.revision_conflict'),
    );
    expect(service.displayText('tab', 0, 'מקור 0'), 'א');
  });

  test('שתי בקשות מקבילות אינן דורסות זו את זו', () async {
    final results = await Future.wait([
      restore([
        change(0, 'א'),
      ]).then<Object>((value) => value, onError: (Object e) => e),
      restore([
        change(1, 'ב'),
      ]).then<Object>((value) => value, onError: (Object e) => e),
    ]);
    expect(results.whereType<Map>(), hasLength(1));
    expect(
      results.whereType<PluginCorrectionException>().single.code,
      'error.revision_conflict',
    );
  });

  test('סגירה בזמן טעינת מקור אינה מחיה סשן', () async {
    await closeCurrent();
    final gate = Completer<String>();
    session = await beginTab(loadSource: (_) => gate.future);
    final pending = restore([change(0, 'א')]);
    service.removeOwner('owner');
    gate.complete('מקור 0');
    await expectLater(pending, error('error.not_found'));
  });

  test('reset וסיום מסירים את שכבת התצוגה ומחזירים מצב אחרון', () async {
    await restore([change(0, 'א'), change(1, 'ב')]);
    final reset = service.reset('owner', session['sessionId'], 0, 1);
    expect(reset['revision'], 2);
    expect(service.displayText('tab', 0, 'מקור 0'), 'מקור 0');
    final ended = await service.end('owner', session['sessionId'], 2);
    expect(ended['changes'], hasLength(1));
    expect(ended['draft']['persisted'], isTrue);
    expect(service.displayText('tab', 1, 'מקור 1'), 'מקור 1');
    await expectLater(current(), error('error.not_found'));
  });

  for (final text in [
    '<b>טקסט</b>',
    'שתי\nפסקאות',
    '\uD800',
    '&amp;',
    '&#10;',
    '&#x0A;',
    '&unknown;',
  ]) {
    test('דוחה תוכן שאינו נתמך: ${text.codeUnits}', () async {
      await expectLater(
        restore([change(0, text)]),
        throwsA(isA<PluginCorrectionException>()),
      );
      expect((await current())['revision'], 0);
    });
  }

  test('דוחה פסקאות כפולות ומגבלות גודל לפני טעינת מקור', () async {
    await expectLater(
      restore([change(0, 'א'), change(0, 'ב')]),
      error('error.invalid_params'),
    );
    await expectLater(
      restore([change(0, 'א' * 20001)]),
      error('error.limit_exceeded'),
    );
  });

  test('מאמת הקשר גם בשחזור ריק ובסיום טעינת מקור', () async {
    await closeCurrent();
    var validations = 0;
    var loads = 0;
    session = await beginTab(
      loadSource: (index) async {
        loads++;
        return source[index]!;
      },
      validateSource: () async {
        if (++validations == 2) {
          throw const PluginCorrectionException(
            'error.source_changed',
            'מקור השתנה',
          );
        }
      },
    );
    await expectLater(restore([]), error('error.source_changed'));
    expect(loads, 0);
    expect(validations, 2);
    expect((await current())['revision'], 0);
  });

  test('שחזור מחליף את כל הטיוטה וריק מסיר אותה', () async {
    await restore([change(0, 'א'), change(1, 'ב')]);
    await restore([change(1, 'ב')], revision: 1);
    expect(service.displayText('tab', 0, 'מקור 0'), 'מקור 0');
    final result = await restore([], revision: 2);
    expect(result['changes'], isEmpty);
    expect(result['revision'], 3);
  });

  test('שחזור ללא שינוי אינו מעלה revision או שולח אירוע', () async {
    await closeCurrent();
    final events = <String>[];
    session = await beginTab(onEvent: (topic, _) => events.add(topic));
    await restore([change(0, 'א')]);
    final result = await restore([change(0, 'א')], revision: 1);
    expect(result['revision'], 1);
    await current();
    expect(events, ['reader.correctionSessionChanged']);
    service.removeTab('tab');
    await _idle();
    expect(events, [
      'reader.correctionSessionChanged',
      'reader.correctionSessionEnded',
    ]);
  });

  test('זהות ספר או גרסה זרה אינה משוחזרת', () async {
    for (final identity in [('id:43', 'v1'), ('id:42', 'v2')]) {
      await expectLater(
        service.restore(
          owner: 'owner',
          id: session['sessionId'],
          expectedRevision: 0,
          bookUid: identity.$1,
          libraryVersion: identity.$2,
          changes: [change(0, 'א')],
        ),
        error('error.source_changed'),
      );
    }
  });

  test('מגבלות מספר פסקאות וגודל מצטבר נאכפות', () async {
    await expectLater(
      restore(List.generate(501, (i) => change(i, 'א'))),
      error('error.limit_exceeded'),
    );
    await expectLater(
      restore(List.generate(100, (i) => change(i, 'א' * 10000))),
      error('error.limit_exceeded'),
    );
  });

  test('מספר הסשנים מוגבל וסיום מפנה מקום', () async {
    for (var i = 1; i < 32; i++) {
      await beginTab(
        tabId: 'tab-$i',
        bookUid: 'id:$i',
        loadSource: (_) async => '',
      );
    }
    await expectLater(
      beginTab(
        tabId: 'overflow',
        bookUid: 'id:overflow',
        loadSource: (_) async => '',
      ),
      error('error.limit_exceeded'),
    );
    await service.end('owner', session['sessionId'], 0);
    expect(
      (await beginTab(
        tabId: 'overflow',
        bookUid: 'id:overflow',
        loadSource: (_) async => '',
      ))['revision'],
      0,
    );
  });

  test('הקלדה מקומית מתעדכנת מיד ונכללת באירוע הסיום', () async {
    await closeCurrent();
    final events = <Map<String, dynamic>>[];
    session = await beginTab(
      onEvent: (topic, payload) => events.add({'topic': topic, ...payload}),
    );
    service.editParagraph('tab', 0, 'מקור 0', 'נוסח חדש 😀');
    final latest = await current();
    expect(latest['revision'], 1);
    expect((latest['changes'] as List).single['proposedText'], 'נוסח חדש 😀');
    expect(events.single['topic'], 'reader.correctionSessionChanged');
    expect(events.single['sectionIndices'], [0]);
    expect(events.single['revision'], 1);
    service.editParagraph('tab', 0, 'מקור 0', 'מקור 0');
    expect((await current())['changes'], isEmpty);
    service.editParagraph('tab', 1, 'מקור 1', 'אחרון');
    service.removeTab('tab');
    await _idle();
    final ended = events.last;
    expect(ended['topic'], 'reader.correctionSessionEnded');
    expect(ended['reason'], 'tab_closed');
    expect(ended['snapshot']['revision'], 3);
    expect(ended['snapshot']['changes'].single['proposedText'], 'אחרון');
    expect(ended['snapshot']['draft']['persisted'], isTrue);
    expect(source, {0: 'מקור 0', 1: 'מקור 1'});
  });

  test('הקלדה בעת restore מונעת דריסת ההקלדה האחרונה', () async {
    await closeCurrent();
    final gate = Completer<String>();
    session = await beginTab(loadSource: (_) => gate.future);
    final pending = restore([change(0, 'טיוטה ישנה')]);
    await Future<void>.delayed(Duration.zero);
    service.editParagraph('tab', 0, 'מקור 0', 'הקלדה אחרונה');
    gate.complete('מקור 0');
    await expectLater(pending, error('error.revision_conflict'));
    expect(service.displayText('tab', 0, 'מקור 0'), 'הקלדה אחרונה');
  });

  test('מגבלת גודל ההקלדה נשמרת אחרי restore ו-reset', () async {
    await restore([change(0, 'א' * 20000)]);
    expect(
      () => service.editParagraph('tab', 0, 'מקור 0', 'ב' * 20001),
      error('error.limit_exceeded'),
    );
    service.reset('owner', session['sessionId'], 0, 1);
    service.editParagraph('tab', 0, 'מקור 0', 'חדש');
    expect((await current())['revision'], 3);
  });

  test('מקור ריק נדחה, אך אפשר לרוקן פסקה קיימת בלי למחוק את הגבול', () async {
    await expectLater(
      restore([
        {
          'sectionIndex': 0,
          'originalSourceText': '',
          'originalText': '',
          'proposedText': 'חדש',
        },
      ]),
      error('error.unsupported_context'),
    );
    await restore([change(0, '')]);
    expect(service.displayText('tab', 0, 'מקור 0'), '');
    expect(service.canEditParagraph('tab', 'מקור 0'), isTrue);
    expect(service.canEditParagraph('tab', ''), isFalse);
  });

  test('begin שהתחיל לפני הסרת הבעלים נדחה ואינו יוצר סשן יתום', () async {
    final epoch = service.ownerEpoch('late-owner');
    service.removeOwner('late-owner');
    await expectLater(
      beginTab(
        owner: 'late-owner',
        tabId: 'late-tab',
        loadSource: (index) async => 'מקור',
        ownerEpoch: epoch,
      ),
      error('error.permission_denied'),
    );
    expect(service.hasSessionForTab('late-tab'), isFalse);
    await beginTab(
      owner: 'late-owner',
      tabId: 'late-tab',
      loadSource: (index) async => 'מקור',
      ownerEpoch: service.ownerEpoch('late-owner'),
    );
    expect(service.hasSessionForTab('late-tab'), isTrue);
  });

  test('הסרת בעלים בזמן רכישת ה-lease אינה יוצרת סשן יתום', () async {
    final pending = beginTab(
      owner: 'racing-owner',
      tabId: 'racing-tab',
      bookUid: 'id:racing',
    );
    service.removeOwner('racing-owner');
    await expectLater(pending, error('error.permission_denied'));
    expect(service.hasSessionForTab('racing-tab'), isFalse);
    await _idle();
    // ה-lease שוחרר, ולכן פתיחה חוזרת מצליחה.
    await beginTab(
      owner: 'racing-owner',
      tabId: 'racing-tab',
      bookUid: 'id:racing',
    );
    expect(service.hasSessionForTab('racing-tab'), isTrue);
  });

  group('חוזה אירועי הסיום והסרה', () {
    late List<(String, Map<String, dynamic>)> events;

    setUp(() async {
      events = [];
      await service.end('owner', session['sessionId'], 0);
      session = await beginTab(
        onEvent: (topic, payload) => events.add((topic, payload)),
      );
    });

    for (final (name, reason, remove)
        in <
          (
            String,
            String,
            Future<void> Function(PluginCorrectionSessionService),
          )
        >[
          (
            'סיום מפורש',
            'explicit',
            (s) async {
              final latest = await s.get('owner', session['sessionId']);
              await s.end(
                'owner',
                session['sessionId'],
                latest['revision'] as int,
              );
            },
          ),
          (
            'הסרת התוסף',
            'plugin_unavailable',
            (s) async {
              s.removeOwner('owner');
            },
          ),
          ('סגירת לשונית', 'tab_closed', (s) async => s.removeTab('tab')),
          ('סיום בידי המשתמש', 'user', (s) async => s.endByUser('tab')),
        ]) {
      test('$name שולח correctionSessionEnded עם סיבה ותמונה אחרונה', () async {
        service.editParagraph('tab', 0, 'מקור 0', 'הקלדה אחרונה');
        events.clear();
        await remove(service);
        expect(service.hasSessionForTab('tab'), isFalse);
        await _idle();
        final ended = events.where(
          (event) => event.$1 == 'reader.correctionSessionEnded',
        );
        expect(ended, hasLength(1));
        expect(ended.single.$2['reason'], reason);
        expect(ended.single.$2['sessionId'], session['sessionId']);
        final snapshot = ended.single.$2['snapshot'] as Map;
        expect(
          (snapshot['changes'] as List).single['proposedText'],
          'הקלדה אחרונה',
        );
        expect(snapshot['draft']['persisted'], isTrue);
      });

      test('$name משחרר את ה-lease ושומר את הטיוטה', () async {
        service.editParagraph('tab', 0, 'מקור 0', 'נשמר בסיום');
        await remove(service);
        await _idle();
        final drafts = await service.listDrafts('owner');
        expect(drafts.single['changeCount'], 1);
        expect(drafts.single['active'], isFalse);
        final again = await beginTab();
        expect(again['recovery']['restoredSectionIndices'], [0]);
      });
    }

    test('הסרת בעלים או לשונית אחרים משאירה את הסשן חי', () async {
      service.removeOwner('other-owner');
      service.removeTab('other-tab');
      await _idle();
      expect(service.hasSessionForTab('tab'), isTrue);
      expect(events, isEmpty);
    });

    test('reset של פסקה ללא תיקון או אינדקס שלילי אינו משנה revision', () {
      expect(service.reset('owner', session['sessionId'], 1, 0)['revision'], 0);
      expect(events, isEmpty);
      expect(
        () => service.reset('owner', session['sessionId'], -1, 0),
        error('error.invalid_params'),
      );
    });
  });

  group('הקלדה מקומית מאומתת מול המקור', () {
    test('ללא סשן, אינדקס שלילי ומקור שהשתנה נדחים', () {
      expect(
        () => service.editParagraph('no-tab', 0, 'מקור 0', 'א'),
        error('error.not_found'),
      );
      expect(
        () => service.editParagraph('tab', -1, 'מקור 0', 'א'),
        error('error.source_changed'),
      );
      service.editParagraph('tab', 0, 'מקור 0', 'א');
      expect(
        () => service.editParagraph('tab', 0, 'מקור אחר', 'ב'),
        error('error.source_changed'),
      );
    });

    test('מגבלת מספר הפסקאות נאכפת גם בהקלדה', () {
      for (var i = 0; i < PluginCorrectionSessionService.maxChanges; i++) {
        service.editParagraph('tab', i, 'מקור $i', 'תיקון $i');
      }
      expect(
        () => service.editParagraph('tab', 9999, 'מקור 9999', 'תיקון'),
        error('error.limit_exceeded'),
      );
      service.editParagraph('tab', 0, 'מקור 0', 'עדכון פסקה קיימת');
    });

    test('מגבלת הבתים המצטברת נאכפת גם בהקלדה', () {
      final big = 'א' * 15000;
      var accepted = 0;
      expect(() {
        for (var i = 0; i < 100; i++) {
          service.editParagraph('tab', i, 'מקור $i', big);
          accepted++;
        }
      }, error('error.limit_exceeded'));
      expect(accepted, greaterThan(0));
      expect(accepted, lessThan(100));
    });
  });

  group('שחזור מאמת כל שינוי בנפרד', () {
    test('מקור תוקפני מהתוסף אינו נסרק ברגקס לפני אימות מול המסד', () async {
      final hostile = '<' * PluginCorrectionSessionService.maxTextLength;
      final timer = Stopwatch()..start();
      await expectLater(
        restore([
          for (var i = 0; i < 40; i++)
            {
              'sectionIndex': i,
              'originalSourceText': hostile,
              'originalText': '',
              'proposedText': 'תיקון',
            },
        ]),
        throwsA(isA<PluginCorrectionException>()),
      );
      expect(
        timer.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'ניתוח HTML ריבועי על קלט לא מהימן מקפיא את הממשק',
      );
    });

    for (final (name, mutate)
        in <
          (
            String,
            Map<String, dynamic> Function(Map<String, dynamic>),
          )
        >[
          ('מפתח נוסף', (c) => {...c, 'extra': 1}),
          ('אינדקס שלילי', (c) => {...c, 'sectionIndex': -1}),
          ('אינדקס שאינו מספר', (c) => {...c, 'sectionIndex': '0'}),
          ('הצעה שאינה מחרוזת', (c) => {...c, 'proposedText': 1}),
        ]) {
      test(name, () async {
        await expectLater(
          restore([mutate(change(0, 'תיקון'))]),
          error('error.invalid_params'),
        );
        expect((await current())['revision'], 0);
      });
    }

    test('מקור ריק או surrogate פגום שנטענו מהמסד נדחים', () async {
      for (final bad in ['', 'א\uD800']) {
        source[0] = bad;
        await expectLater(
          restore([change(0, 'תיקון')]),
          throwsA(isA<PluginCorrectionException>()),
        );
        expect((await current())['changes'], isEmpty);
      }
    });
  });
}
