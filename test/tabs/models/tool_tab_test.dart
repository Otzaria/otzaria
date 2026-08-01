import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

void main() {
  group('ToolTab', () {
    test('מזהה כלי מובנה מול תוסף', () {
      expect(
        ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה').isBuiltIn,
        isTrue,
      );
      expect(
        ToolTab(toolId: 'com.example.plugin', title: 'תוסף').isBuiltIn,
        isFalse,
      );
      expect(
        ToolTab(toolId: 'com.example.plugin', title: 'תוסף').isPlugin,
        isTrue,
      );
    });

    test('dedupeKey ייחודי לכל כלי', () {
      final calendar = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final gematria = ToolTab(toolId: 'builtin.gematria', title: 'גימטריה');
      expect(calendar.dedupeKey, 'tool:builtin.calendar');
      expect(calendar.dedupeKey, isNot(gematria.dedupeKey));
    });

    test('toJson/fromJson roundtrip', () {
      final tab = ToolTab(
        toolId: 'builtin.notes',
        title: 'הערות אישיות',
        isPinned: true,
      );
      final restored = ToolTab.fromJson(tab.toJson());
      expect(restored.toolId, tab.toolId);
      expect(restored.title, tab.title);
      expect(restored.isPinned, isTrue);
      expect(restored.dedupeKey, tab.dedupeKey);
    });

    test('OpenedTab.fromJson מפענח ToolTab', () {
      final tab = ToolTab(toolId: 'builtin.measurements', title: 'מדות');
      final restored = OpenedTab.fromJson(tab.toJson());
      expect(restored, isA<ToolTab>());
      expect((restored as ToolTab).toolId, 'builtin.measurements');
    });

    test('OpenedTab.fromJson זורק על טיפוס לא מוכר במקום ליצור טאב רפאים', () {
      expect(
        () => OpenedTab.fromJson({'type': 'SomeFutureTab', 'title': 'x'}),
        throwsFormatException,
      );
    });

    test('OpenedTab.fromJson עדיין מפענח טאב חיפוש שמור', () {
      final restored = OpenedTab.fromJson({
        'type': 'SearchingTabWindow',
        'title': 'חיפוש',
        'searchText': 'בראשית',
      });
      expect(restored.title, 'חיפוש');
    });

    // clone חייב להחזיר מופע חדש: workspace_bloc משכפל טאבים בכל החלפת
    // שולחן עבודה, ואובייקט משותף יוצר GlobalObjectKey כפול בעץ.
    test('clone מחזיר מופע נפרד', () {
      final tab = ToolTab(
        toolId: 'builtin.calendar',
        title: 'לוח שנה',
        isPinned: true,
      );
      final cloned = tab.clone();
      expect(identical(cloned, tab), isFalse);
      expect(cloned, isA<ToolTab>());
      expect((cloned as ToolTab).toolId, tab.toolId);
      expect(cloned.isPinned, isTrue);
    });

    test('OpenedTab.from משכפל ולא מחזיר את אותו אובייקט', () {
      final tab = ToolTab(toolId: 'builtin.gematria', title: 'גימטריה');
      final copy = OpenedTab.from(tab);
      expect(identical(copy, tab), isFalse);
      expect((copy as ToolTab).toolId, 'builtin.gematria');
    });

    test('כותרת גיבוי לכלי מובנה נגזרת מהקטלוג', () {
      expect(ToolTab.fallbackTitleFor('builtin.calendar'), 'לוח שנה');
      expect(ToolTab.fallbackTitleFor('unknown.plugin'), 'כלי');
    });

    test('fromJson ללא כותרת נופל לכותרת הגיבוי', () {
      final restored = ToolTab.fromJson({
        'type': 'ToolTab',
        'toolId': 'builtin.gematria',
      });
      expect(restored.title, 'גימטריה');
    });
  });
}
