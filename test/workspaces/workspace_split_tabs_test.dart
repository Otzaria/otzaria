import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../helpers/memory_settings_cache.dart';

/// שולחן עבודה עם טאב מפוצל: מה נשמר, מה נגזם, ומה עולה ממצב שנשמר בגרסה
/// שתמכה בפיצול מקונן.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab pdf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  Map<String, dynamic> splitJson(
    Map<String, dynamic> right,
    Map<String, dynamic> left,
  ) => {
    'type': 'CombinedTab',
    'rightTab': right,
    'leftTab': left,
    'splitRatio': 0.5,
    'isPinned': false,
  };

  group('הלוך-ושוב', () {
    test('טאב מפוצל נשמר ומשוחזר עם שתי החלוניות', () {
      final workspace = Workspace(
        name: 'עבודה',
        tabs: [CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'))],
        activeTabIndex: 0,
      );

      final restored = Workspace.fromJson(workspace.toJson());

      expect(restored.tabs, hasLength(1));
      expect(leafPanes(restored.tabs.single).map((p) => p.title).toList(), [
        'א',
        'ב',
      ]);
    });

    test('חלונית מפרשי PDF נגזמת ואחותה נשארת ככרטיסייה', () {
      final source = pdf('מקור');
      final workspace = Workspace(
        name: 'עבודה',
        tabs: [
          CombinedTab(
            rightTab: pdf('ספר'),
            leftTab: PdfCommentatorsTab(sourceTab: source),
          ),
        ],
        activeTabIndex: 0,
      );

      final restored = Workspace.fromJson(workspace.toJson());

      expect(restored.tabs, hasLength(1));
      expect(restored.tabs.single, isNot(isA<CombinedTab>()));
      expect(restored.tabs.single.title, 'ספר');
    });
  });

  group('מצב שנשמר בגרסה שתמכה בקינון', () {
    test('פיצול מקונן עולה כפיצול אחד והשאר ככרטיסיות', () {
      final restored = Workspace.fromJson({
        'name': 'ישן',
        'currentTab': 0,
        'tabs': [
          splitJson(
            pdf('א').toJson(),
            splitJson(pdf('ב').toJson(), pdf('ג').toJson()),
          ),
        ],
      });

      expect(restored.tabs, hasLength(2));
      expect(leafPanes(restored.tabs[0]).map((p) => p.title).toList(), [
        'א',
        'ב',
      ]);
      expect(restored.tabs[1].title, 'ג');
    });

    test('מפרשי PDF שישבו בעומק אינם שורדים את השחזור', () {
      final commentators = PdfCommentatorsTab(sourceTab: pdf('מקור')).toJson();

      final restored = Workspace.fromJson({
        'name': 'ישן',
        'currentTab': 0,
        'tabs': [
          splitJson(
            pdf('א').toJson(),
            splitJson(pdf('ב').toJson(), commentators),
          ),
        ],
      });

      final titles = [
        for (final tab in restored.tabs) ...leafPanes(tab).map((p) => p.title),
      ];
      expect(titles, ['א', 'ב']);
    });

    test('הכרטיסייה הפעילה נשארת אותה כרטיסייה אחרי פירוק הקינון', () {
      final restored = Workspace.fromJson({
        'name': 'ישן',
        'currentTab': 1,
        'tabs': [
          splitJson(
            pdf('א').toJson(),
            splitJson(pdf('ב').toJson(), pdf('ג').toJson()),
          ),
          pdf('אחרון').toJson(),
        ],
      });

      expect(restored.tabs[restored.activeTabIndex].title, 'אחרון');
    });

    test('אינדקס פעיל שחורג אחרי הגיזום נחסם לגבולות הרשימה', () {
      final restored = Workspace.fromJson({
        'name': 'ישן',
        'currentTab': 5,
        'tabs': [pdf('יחיד').toJson()],
      });

      expect(restored.activeTabIndex, 0);
    });
  });
}
