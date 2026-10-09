import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';

void main() {
  late PluginCorrectionSessionService service;
  late Map<int, String> source;
  late Map<String, dynamic> session;

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

  Matcher error(String code) => throwsA(
    isA<PluginCorrectionException>().having(
      (value) => value.code,
      'code',
      code,
    ),
  );

  setUp(() {
    service = PluginCorrectionSessionService();
    source = {0: 'מקור 0', 1: 'מקור 1'};
    session = service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:42',
      libraryVersion: 'v1',
      loadSource: (index) async => source[index]!,
    );
  });

  tearDown(() => service.dispose());

  test('טיוטה אינה משנה מקור ותמונת המצב עצמאית', () async {
    final result = await restore([change(0, 'תיקון 😀')]);
    expect(result['revision'], 1);
    expect(source, {0: 'מקור 0', 1: 'מקור 1'});
    expect(service.displayText('tab', 0, 'מקור 0'), 'תיקון 😀');
    expect(service.displayText('other-tab', 0, 'מקור 0'), 'מקור 0');
    expect(service.displayText('tab', 0, 'מקור אחר'), 'מקור אחר');
    (result['changes'] as List).clear();
    expect(service.get('owner', session['sessionId'])['changes'], hasLength(1));
  });

  test('פסקת איגרא רמה עם HTML נערכת כטקסט ושומרת מקור גולמי לשחזור', () async {
    const raw = '<b>בגמרא</b> חנן התם וגג <big>לחלק</big> &amp; 😀';
    const plain = 'בגמרא חנן התם וגג לחלק & 😀';
    source[0] = raw;
    expect(service.canEditParagraph('tab', raw), isTrue);
    expect(service.editableText('tab', 0, raw), plain);
    service.editParagraph('tab', 0, raw, '$plain תיקון');
    final latest = service.get('owner', session['sessionId']);
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
    expect(service.get('owner', session['sessionId'])['changes'], isEmpty);
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

  test('בעלות אינה ניתנת להעברה ואינה חושפת סשן זר', () {
    expect(
      () => service.get('other', session['sessionId']),
      error('error.not_found'),
    );
    expect(
      () => service.begin(
        owner: 'other',
        tabId: 'tab',
        bookId: 'ספר',
        bookUid: 'id:42',
        libraryVersion: 'v1',
        loadSource: (index) async => '',
      ),
      error('error.correction_busy'),
    );
  });

  test('כשל אימות בפסקה השנייה אינו מחיל את הראשונה', () async {
    source[1] = 'מקור שהשתנה';
    await expectLater(
      restore([change(0, 'א'), change(1, 'ב')]),
      error('error.source_changed'),
    );
    expect(service.get('owner', session['sessionId'])['revision'], 0);
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
    service.removeTab('tab');
    final gate = Completer<String>();
    session = service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:42',
      libraryVersion: 'v1',
      loadSource: (_) => gate.future,
    );
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
    final ended = service.end('owner', session['sessionId'], 2);
    expect(ended['changes'], hasLength(1));
    expect(service.displayText('tab', 1, 'מקור 1'), 'מקור 1');
    expect(
      () => service.get('owner', session['sessionId']),
      error('error.not_found'),
    );
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
      expect(service.get('owner', session['sessionId'])['revision'], 0);
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
    service.removeTab('tab');
    var validations = 0;
    var loads = 0;
    session = service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:42',
      libraryVersion: 'v1',
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
    expect(service.get('owner', session['sessionId'])['revision'], 0);
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
    service.removeTab('tab');
    final events = <String>[];
    session = service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:42',
      libraryVersion: 'v1',
      loadSource: (index) async => source[index]!,
      onEvent: (topic, _) => events.add(topic),
    );
    await restore([change(0, 'א')]);
    final result = await restore([change(0, 'א')], revision: 1);
    expect(result['revision'], 1);
    expect(events, ['reader.correctionSessionChanged']);
    service.removeTab('tab');
    expect(events.last, 'reader.correctionSessionEnded');
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

  test('מספר הסשנים מוגבל וסיום מפנה מקום', () {
    for (var i = 1; i < 32; i++) {
      service.begin(
        owner: 'owner',
        tabId: 'tab-$i',
        bookId: 'ספר',
        bookUid: 'id:42',
        libraryVersion: 'v1',
        loadSource: (_) async => '',
      );
    }
    expect(
      () => service.begin(
        owner: 'owner',
        tabId: 'overflow',
        bookId: 'ספר',
        bookUid: 'id:42',
        libraryVersion: 'v1',
        loadSource: (_) async => '',
      ),
      error('error.limit_exceeded'),
    );
    service.end('owner', session['sessionId'], 0);
    expect(
      service.begin(
        owner: 'owner',
        tabId: 'overflow',
        bookId: 'ספר',
        bookUid: 'id:42',
        libraryVersion: 'v1',
        loadSource: (_) async => '',
      )['revision'],
      0,
    );
  });

  test('הקלדה מקומית מתעדכנת מיד ונכללת באירוע הסיום', () {
    service.removeTab('tab');
    final events = <Map<String, dynamic>>[];
    session = service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:42',
      libraryVersion: 'v1',
      loadSource: (i) async => source[i]!,
      onEvent: (topic, payload) => events.add({'topic': topic, ...payload}),
    );
    service.editParagraph('tab', 0, 'מקור 0', 'נוסח חדש 😀');
    final latest = service.get('owner', session['sessionId']);
    expect(latest['revision'], 1);
    expect((latest['changes'] as List).single['proposedText'], 'נוסח חדש 😀');
    expect(events.single['sectionIndex'], 0);
    service.editParagraph('tab', 0, 'מקור 0', 'מקור 0');
    expect(service.get('owner', session['sessionId'])['changes'], isEmpty);
    service.editParagraph('tab', 1, 'מקור 1', 'אחרון');
    service.removeTab('tab');
    final ended = events.last;
    expect(ended['topic'], 'reader.correctionSessionEnded');
    expect(ended['reason'], 'tab_closed');
    expect(ended['snapshot']['revision'], 3);
    expect(ended['snapshot']['changes'].single['proposedText'], 'אחרון');
    expect(source, {0: 'מקור 0', 1: 'מקור 1'});
  });

  test('הקלדה בעת restore מונעת דריסת ההקלדה האחרונה', () async {
    service.removeTab('tab');
    final gate = Completer<String>();
    session = service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:42',
      libraryVersion: 'v1',
      loadSource: (_) => gate.future,
    );
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
    expect(service.get('owner', session['sessionId'])['revision'], 3);
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
}
