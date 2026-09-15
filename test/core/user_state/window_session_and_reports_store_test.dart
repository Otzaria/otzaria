import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';

void main() {
  late Directory tmp;
  late UserStateDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria_user_state_');
    db = UserStateDatabase.openAt(
      '${tmp.path}${Platform.pathSeparator}user_state.db',
    );
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  group('WindowSessionStore', () {
    test('שמירה, טעינה, עדכון חלקי ומחיקה', () async {
      final store = WindowSessionStore(database: db);
      expect(await store.load(1), isNull);

      await store.save(1, tabsJson: '[{"a":1}]', currentIndex: 0);
      await store.saveCurrentIndex(1, 3);
      await store.saveActiveWorkspace(1, 'ws-1');
      await store.saveBounds(1, '{"w":800}');

      final session = (await store.load(1))!;
      expect(session.tabsJson, '[{"a":1}]');
      expect(session.currentIndex, 3);
      expect(session.activeWorkspaceId, 'ws-1');
      expect(session.boundsJson, '{"w":800}');

      // שולחן לפני כרטיסיות — השורה נוצרת ריקה ולא נופלת.
      await store.saveActiveWorkspace(2, 'ws-2');
      expect((await store.load(2))!.tabsJson, '[]');

      expect(await store.loadAll(), hasLength(2));
      await store.delete(1);
      expect(await store.load(1), isNull);
      expect(await store.loadAll(), hasLength(1));
    });
  });

  group('PendingReportStore', () {
    test('הוספה פר-שורה, רשימה לפי סוג, מחיקה לפי מזהה, קיצוץ', () async {
      final store = PendingReportStore(database: db);
      final first = await store.add('errors/pending', {'m': 1});
      await store.add('errors/pending', {'m': 2});
      await store.add('plugins/pending', {'p': 1});

      final errors = await store.listByKind('errors/pending');
      expect(errors.map((r) => r.payload['m']), [1, 2]);
      expect(await store.countByKind('plugins/pending'), 1);

      await store.deleteIds([first]);
      expect(
        (await store.listByKind('errors/pending')).single.payload['m'],
        2,
      );

      for (var i = 0; i < 5; i++) {
        await store.add('errors/sent', {'i': i});
      }
      await store.trimKind('errors/sent', 2);
      expect(
        (await store.listByKind('errors/sent')).map((r) => r.payload['i']),
        [3, 4],
      );

      await store.deleteAllOfKind('errors/pending');
      expect(await store.countByKind('errors/pending'), 0);
      expect(await store.countByKind('plugins/pending'), 1);
    });
  });
}
