import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_identity.dart';
import 'package:otzaria/search_feedback/search_feedback_queue.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import 'search_feedback_test_support.dart';

class _NoTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

void main() {
  late Directory dir;
  late MemoryConsentPersistence consent;
  late List<http.Request> requests;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sf_multiwindow');
    consent = MemoryConsentPersistence();
    requests = [];
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SearchFeedbackService makeService({
    bool secondary = false,
    Uri? baseUrl,
    Stream<String>? otherWindows,
  }) => SearchFeedbackService(
    client: MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/register')) {
        final body = jsonDecode(request.body) as Map;
        final keyId = SearchFeedbackIdentity.keyIdOf(
          base64.decode(body['publicKey'] as String),
        );
        return http.Response(jsonEncode({'keyId': keyId}), 200);
      }
      return http.Response(jsonEncode({'accepted': 1, 'duplicates': 0}), 200);
    }),
    baseUrl: baseUrl ?? Uri.parse('https://example.test'),
    clock: () => kStart.add(const Duration(seconds: 5)),
    storageDirectory: () async => dir,
    consentPersistence: consent,
    sendingAllowed: () => true,
    buildAllowsSending: true,
    appVersion: () => '1.2.3',
    platform: () => 'windows',
    osVersion: () => '10.0',
    locale: () => 'he',
    timerFactory: (_, _) => _NoTimer(),
    isSecondaryWindow: () => secondary,
    settingsChangesFromOtherWindows: otherWindows,
  );

  List<http.Request> eventPosts() =>
      requests.where((r) => r.url.path.endsWith('/events')).toList();

  List<String> queuedEventTypes() {
    final lines = <String>[];
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonl'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      lines.addAll(
        const LineSplitter().convert(file.readAsStringSync()).skip(1),
      );
    }
    return [
      for (final line in lines) (jsonDecode(line) as Map)['type'] as String,
    ];
  }

  test('האירועים נכתבים לתור בסדר שבו נרשמו', () async {
    final service = makeService(secondary: true);
    await service.grant();
    final context = searchContext();
    service.recordSearch(context);
    service.recordResultsShown(context, 0, [result()]);
    service.recordVote(context, result(), SearchFeedbackVote.like);
    await service.whenQueued();

    expect(queuedEventTypes(), ['search', 'results_shown', 'vote']);
  });

  test('חלון משני רק כותב לתור; החלון הראשי שולח גם את מקטעיו', () async {
    final secondary = makeService(secondary: true);
    await secondary.grant();
    secondary.recordSearch(searchContext());
    await secondary.whenQueued();
    await secondary.flush();
    expect(requests, isEmpty);

    final primary = makeService();
    await primary.flush();

    expect(eventPosts(), hasLength(1));
    expect(queuedEventTypes(), isEmpty);
  });

  test('ביטול בחלון אחר מוחק את המפתח, והחלון הזה אינו משחזר אותו', () async {
    final service = makeService();
    await service.grant();
    service.recordSearch(searchContext());
    await service.whenQueued();
    await service.flush();
    final keyFile = File('${dir.path}/${SearchFeedbackIdentityStore.fileName}');
    final firstKey = jsonDecode(keyFile.readAsStringSync())['seed'];

    // חלון אחר ביטל והסכים שוב: הקובץ נמחק, ויש מפתח אחר.
    keyFile.deleteSync();
    final other = makeService();
    other.recordSearch(searchContext(id: 'session_secondone'));
    await other.whenQueued();
    await other.flush();
    final secondKey = jsonDecode(keyFile.readAsStringSync())['seed'];

    service.recordSearch(searchContext(id: 'session_thirdone'));
    await service.whenQueued();
    await service.flush();

    expect(secondKey, isNot(firstKey));
    expect(jsonDecode(keyFile.readAsStringSync())['seed'], secondKey);
  });

  test('הסכמה שבוטלה בחלון אחר נקלטת בשימוש הבא', () async {
    final otherWindows = StreamController<String>();
    final service = makeService(otherWindows: otherWindows.stream);
    await service.grant();
    final changes = <SearchFeedbackConsent>[];
    service.changes.listen(changes.add);

    consent.state = 'declined';
    otherWindows.add(SettingsRepository.keySearchFeedbackConsent);
    await pumpEventQueue();

    expect(changes, [SearchFeedbackConsent.declined]);
    expect(service.isCollecting, isFalse);
    await otherWindows.close();
  });

  group('תצוגה מקדימה בפיתוח', () {
    SemanticSearchContext debugContext() =>
        searchContext(fallbackReason: kSemanticDebugPreviewFallbackReason);

    test('לעולם אינה נשלחת לשרת הייצור', () async {
      final service = makeService(
        baseUrl: SearchFeedbackService.defaultBaseUrl,
      );
      await service.grant();
      service.recordSearch(debugContext());
      await service.whenQueued();
      await service.flush();

      expect(eventPosts(), isEmpty);
      expect(queuedEventTypes(), isEmpty);
    });

    test('נשלחת לכתובת עקיפה, בלי הסימון המקומי', () async {
      final service = makeService();
      await service.grant();
      service.recordSearch(debugContext());
      await service.whenQueued();
      await service.flush();

      final post = eventPosts().single;
      final context = (jsonDecode(post.body) as Map)['context'] as Map;
      expect(context.containsKey(kSearchFeedbackLocalOnlyKey), isFalse);
    });
  });

  group('תור משותף לכמה תהליכים', () {
    SearchFeedbackQueue queue() => SearchFeedbackQueue(
      () async => dir,
      clock: () => kStart,
    );
    const context = {'app': 'otzaria'};

    test('מקטע שנלקח בתהליך אחר אינו נלקח שוב', () async {
      final mine = queue();
      await mine.append({'type': 'search'}, context);
      final names = await mine.sealAndList();
      final other = queue();
      final otherNames = await other.sealAndList();

      expect(await other.claim(otherNames.single), isNotNull);
      expect(await mine.claim(names.single), isNull);
    });

    test('כתיבה אחרי שהמקטע נלקח פותחת מקטע חדש עם context', () async {
      final writer = queue();
      final sender = queue();
      await writer.append({'type': 'search'}, context);
      final claimed = await sender.claim((await sender.sealAndList()).single);
      await sender.remove(claimed!);

      await writer.append({'type': 'vote'}, context);

      final batches = [
        for (final name in await sender.sealAndList()) await sender.read(name),
      ];
      expect(batches.single!.contextJson, contains('otzaria'));
      expect(batches.single!.eventLines.single, contains('vote'));
    });

    test('מחיקה של מקטע שכבר נמחק אינה זורקת', () async {
      final a = queue();
      await a.append({'type': 'search'}, context);
      final name = (await a.sealAndList()).single;
      File('${dir.path}/$name').deleteSync();

      await expectLater(a.remove(name), completes);
    });
  });
}
