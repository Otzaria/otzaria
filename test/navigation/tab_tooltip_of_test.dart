import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/plugins/services/plugin_tab_info.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

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
