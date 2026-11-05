import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';

/// ספק שמחזיר תשובות לפי סדר — מדמה כשל חולף ואחריו הצלחה.
class _ScriptedProvider extends Fake implements LibraryProvider {
  _ScriptedProvider(this.responses);

  final List<Object> responses;
  int calls = 0;

  @override
  Future<String> getLinkContent(Link link) async {
    final response = responses[calls++];
    if (response is Exception) throw response;
    return response as String;
  }
}

Link _link(int index2) => Link(
  heRef: 'רש"י על עירובין, ב., ב, א',
  index1: 1,
  path2: 'רש"י על עירובין',
  index2: index2,
  connectionType: LinkTypes.commentary,
);

void main() {
  final manager = LibraryProviderManager.instance;

  void seed(LibraryProvider provider) => manager.seedMappingsForTesting(
    mapping: <BookCompositeKey, LibraryProvider>{},
    providers: <LibraryProvider>[provider],
  );

  tearDown(manager.resetForTesting);

  for (final mapped in [false, true]) {
    for (final lines in [false, true]) {
      test('admission rejection propagates without provider fallback '
          '(mapped=$mapped, lines=$lines)', () async {
        final provider = _ScriptedProvider([
          const DbReadWorkerBusy('test capacity'),
          'תוכן שהתאושש',
        ]);
        final fallback = _ScriptedProvider(['תוכן מספק נוסף']);
        final link = _link(9010 + (mapped ? 2 : 0) + (lines ? 1 : 0));
        manager.seedMappingsForTesting(
          mapping: {
            if (mapped)
              BookCompositeKey.create(title: link.path2, categoryId: 1):
                  provider,
          },
          providers: [provider, fallback],
        );

        Future<Object?> read() async => lines
            ? manager.getLinkContentLines(link)
            : manager.getLinkContent(link);

        await expectLater(read(), throwsA(isA<DbReadWorkerBusy>()));
        expect(provider.calls, 1);
        expect(fallback.calls, 0);
        expect((await read()).toString(), contains('תוכן שהתאושש'));
        expect(provider.calls, 2);
        expect(fallback.calls, 0);
      });
    }
  }

  test('תוצאת שגיאה אינה נשמרת במטמון — ניסיון נוסף טוען מחדש', () async {
    final provider = _ScriptedProvider(['שגיאה: מאגר לא מאותחל', 'תוכן רש"י']);
    seed(provider);
    final link = _link(9001);

    expect(await link.content, 'שגיאה: מאגר לא מאותחל');
    await Future<void>.delayed(Duration.zero);
    expect(await link.content, 'תוכן רש"י');
    expect(provider.calls, 2);
  });

  test('הודעת הספק הראשון שנכשל עוברת הלאה, לא הודעה כללית', () async {
    manager.seedMappingsForTesting(
      mapping: <BookCompositeKey, LibraryProvider>{},
      providers: <LibraryProvider>[
        _ScriptedProvider(['שגיאה בטעינת תוכן המפרש']),
        _ScriptedProvider(['שגיאה: הספר לא נמצא']),
      ],
    );

    expect(
      (await manager.getLinkContentLines(_link(9003))).single.content,
      'שגיאה בטעינת תוכן המפרש',
    );
  });

  test('תוכן ריק בלי הודעת שגיאה מציג "לא נמצא תוכן"', () async {
    seed(_ScriptedProvider(['']));

    expect(await manager.getLinkContent(_link(9004)), 'שגיאה: לא נמצא תוכן');
  });

  test('תוצאה תקינה נשמרת במטמון', () async {
    final provider = _ScriptedProvider(['תוכן רש"י']);
    seed(provider);
    final link = _link(9002);

    expect(await link.content, 'תוכן רש"י');
    await Future<void>.delayed(Duration.zero);
    expect(await link.content, 'תוכן רש"י');
    expect(provider.calls, 1);
  });
}
