import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/plugins/services/plugin_tab_info.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';

void main() {
  ToolTab plugin() => ToolTab(toolId: 'com.example.plugin', title: 'שני טורים');

  group('tabTooltipOf', () {
    test('בלי טולטיפ מותאם — הכותרת המוצגת', () {
      final tab = plugin();
      expect(tabTooltipOf(tab), 'שני טורים');
      tab.applyPluginTabInfo(PluginTabInfoUpdate.parse({'title': 'בראשית א'}));
      expect(tabTooltipOf(tab), 'בראשית א');
    });

    test('טולטיפ שהתוסף קבע מחליף את הכותרת', () {
      final tab = plugin()
        ..applyPluginTabInfo(
          PluginTabInfoUpdate.parse({
            'title': 'בראשית א',
            'tooltip': 'בראשית, פרק א\nשני טורים',
          }),
        );
      expect(tabTooltipOf(tab), 'בראשית, פרק א\nשני טורים');
    });

    test(
      'פיצול שומר כותרת רגילה בלי override ומשלב טולטיפים לפי סדר החלוניות',
      () {
        final first = plugin();
        final second = plugin()..title = 'כלי נוסף';
        final tab = CombinedTab(rightTab: first, leftTab: second);
        expect(tabTooltipOf(tab), tab.title);
        first.applyPluginTabInfo(
          PluginTabInfoUpdate.parse({
            'title': 'בראשית א',
            'tooltip': 'בראשית, פרק א',
          }),
        );
        expect(tabTooltipOf(tab), 'בראשית, פרק א\nכלי נוסף');
        second.applyPluginTabInfo(
          PluginTabInfoUpdate.parse({'tooltip': 'פרטים\nנוספים'}),
        );
        expect(tabTooltipOf(tab), 'בראשית, פרק א\nפרטים\nנוספים');
        first.applyPluginTabInfo(PluginTabInfoUpdate.parse({'tooltip': null}));
        second.applyPluginTabInfo(PluginTabInfoUpdate.parse({'tooltip': null}));
        expect(tabTooltipOf(tab), 'משולב: בראשית א | כלי נוסף');
      },
    );

    test('כלי מובנה לעולם לא מקבל טולטיפ מותאם', () {
      expect(
        tabTooltipOf(ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה')),
        'לוח שנה',
      );
    });
  });

  testWidgets('LiveTabTitleBuilder מוסר לבונה את הכותרת והטולטיפ המותאמים', (
    tester,
  ) async {
    final tab = plugin()
      ..applyPluginTabInfo(
        PluginTabInfoUpdate.parse({'title': 'בראשית א', 'tooltip': 'פרטים'}),
      );
    late String shownTitle;
    late String shownTooltip;

    await tester.pumpWidget(
      MaterialApp(
        home: LiveTabTitleBuilder(
          tab: tab,
          builder: (context, displayTitle, tooltipMessage, titleLocation) {
            shownTitle = displayTitle;
            shownTooltip = tooltipMessage;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(shownTitle, 'בראשית א');
    expect(shownTooltip, 'פרטים');
  });
}
