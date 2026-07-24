import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tools_screen.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';

/// descriptor מינימלי לבדיקת המיון בלבד — ה-pageBuilder לעולם לא נקרא כאן.
BuiltInToolDescriptor _desc(String id, int order) => BuiltInToolDescriptor(
  toolId: id,
  label: id,
  order: order,
  pageBuilder: () => const SizedBox.shrink(),
);

/// descriptor שאינו מובנה (מדמה תוסף) לבדיקת קדימות הכלים המובנים.
/// מתודות ה-build לעולם אינן נקראות במיון, ולכן זורקות.
class _PluginDesc extends ToolDescriptor {
  final bool allowOrderBeforeBuiltIns;

  const _PluginDesc(
    String id,
    int order, {
    this.allowOrderBeforeBuiltIns = false,
  }) : super(toolId: id, label: id, order: order);

  @override
  int get sortGroupPriority => allowOrderBeforeBuiltIns ? 0 : 2;

  @override
  Widget buildTab(BuildContext context) => throw UnimplementedError();
  @override
  Widget buildPage(BuildContext context) => throw UnimplementedError();
  @override
  TopNavItem buildTopNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  }) => throw UnimplementedError();
  @override
  SidebarNavItem buildSidebarNavItem({
    required bool isSelected,
    required VoidCallback onTap,
    Key? key,
  }) => throw UnimplementedError();
}

void main() {
  group('sortToolDescriptorsStably', () {
    test('ממיין לפי order עולה', () {
      final list = [_desc('c', 30), _desc('a', 10), _desc('b', 20)];
      sortToolDescriptorsStably(list);
      expect(list.map((d) => d.toolId).toList(), ['a', 'b', 'c']);
    });

    test('שומר על הסדר היחסי של כלים בעלי order זהה (יציבות)', () {
      // מדמה את התרחיש האמיתי: כלי מובנה (order ייחודי) ואחריו כמה תוספים
      // שכולם בברירת המחדל 900 — סדרם הגיע כבר דטרמיניסטית מה-repository
      // (order → installedAt → pluginId) ואסור שהמיון ישבש אותו.
      final list = [
        _desc('builtin.calendar', 10),
        _desc('plugin.aaa', 900),
        _desc('plugin.bbb', 900),
        _desc('plugin.ccc', 900),
      ];
      sortToolDescriptorsStably(list);
      expect(
        list.map((d) => d.toolId).toList(),
        ['builtin.calendar', 'plugin.aaa', 'plugin.bbb', 'plugin.ccc'],
      );
    });

    test('אינו ממיין אלפביתית בעלי order זהה — שומר את סדר ההכנסה', () {
      // רגרסיה ל-`List.sort` הלא-יציב: הקלט מסודר ccc,bbb,aaa (לא אלפבית).
      // מיון יציב חייב להשאיר אותם בדיוק כך; מיון לא-יציב/אלפביתי היה
      // מחזיר aaa,bbb,ccc — בדיוק התסמין ש"נדמה" למשתמש שהוא רואה.
      final list = [
        _desc('plugin.ccc', 900),
        _desc('plugin.bbb', 900),
        _desc('plugin.aaa', 900),
        _desc('builtin.notes', 40),
      ];
      sortToolDescriptorsStably(list);
      expect(
        list.map((d) => d.toolId).toList(),
        ['builtin.notes', 'plugin.ccc', 'plugin.bbb', 'plugin.aaa'],
      );
    });

    test('רשימה ריקה אינה זורקת', () {
      final list = <ToolDescriptor>[];
      expect(() => sortToolDescriptorsStably(list), returnsNormally);
      expect(list, isEmpty);
    });

    test('כלים מובנים תמיד לפני תוספים — גם כשלתוסף order נמוך יותר', () {
      // תוסף עם order=5 (נמוך מכל הכלים המובנים) חייב בכל זאת להופיע אחריהם.
      final list = <ToolDescriptor>[
        const _PluginDesc('plugin.early', 5),
        _desc('builtin.gematria', 50),
        _desc('builtin.calendar', 10),
      ];
      sortToolDescriptorsStably(list);
      expect(
        list.map((d) => d.toolId).toList(),
        ['builtin.calendar', 'builtin.gematria', 'plugin.early'],
      );
    });

    test('תוסף יכול להקדים כלים מובנים רק עם הרשאה מפורשת במניפסט', () {
      final list = <ToolDescriptor>[
        const _PluginDesc('plugin.leading', 5, allowOrderBeforeBuiltIns: true),
        _desc('builtin.gematria', 50),
        _desc('builtin.calendar', 10),
      ];
      sortToolDescriptorsStably(list);
      expect(
        list.map((d) => d.toolId).toList(),
        ['plugin.leading', 'builtin.calendar', 'builtin.gematria'],
      );
    });

    test('בתוך כל קבוצה נשמר מיון לפי order, ויציבות בין שווי-order', () {
      final list = <ToolDescriptor>[
        const _PluginDesc('plugin.bbb', 900),
        _desc('builtin.notes', 40),
        const _PluginDesc('plugin.aaa', 900),
        _desc('builtin.calendar', 10),
        const _PluginDesc('plugin.top', 15, allowOrderBeforeBuiltIns: true),
        const _PluginDesc('plugin.low', 5),
      ];
      sortToolDescriptorsStably(list);
      expect(
        list.map((d) => d.toolId).toList(),
        [
          // קודם תוסף שהורשה במפורש להופיע לפני מובנים
          'plugin.top',
          // אחר כך מובנים, ממויינים לפי order
          'builtin.calendar',
          'builtin.notes',
          // אחר כך תוספים רגילים: low(5) קודם, ואז שווי-order 900 בסדר ההכנסה
          'plugin.low',
          'plugin.bbb',
          'plugin.aaa',
        ],
      );
    });
  });

  group('buildMobileToolGroups', () {
    test('שומר את סדר ה-descriptors גם כשתוסף מופיע לפני built-ins', () {
      final groups = buildMobileToolGroups(
        [
          const _PluginDesc(
            'plugin.leading',
            5,
            allowOrderBeforeBuiltIns: true,
          ),
          _desc('builtin.calendar', 10),
          const _PluginDesc('plugin.regular', 900),
        ],
        groupDefs: const [
          (label: 'לוח שנה', toolIds: <String>['builtin.calendar']),
        ],
      );

      expect(groups.map((g) => g.label).toList(), [
        'תוספים',
        'לוח שנה',
        'תוספים',
      ]);
      expect(
        groups.expand((g) => g.tools).map((d) => d.toolId).toList(),
        ['plugin.leading', 'builtin.calendar', 'plugin.regular'],
      );
    });

    test('מאחד descriptors עוקבים בעלי אותה קבוצה לאותו כרטיס', () {
      final groups = buildMobileToolGroups(
        [
          _desc('builtin.calendar', 10),
          _desc('builtin.notes', 20),
          const _PluginDesc('plugin.regular', 900),
        ],
        groupDefs: const [
          (label: 'לוח שנה', toolIds: <String>['builtin.calendar']),
          (label: 'תורה שלמדתי', toolIds: <String>['builtin.notes']),
        ],
      );

      expect(groups.map((g) => g.label).toList(), [
        'לוח שנה',
        'תורה שלמדתי',
        'תוספים',
      ]);
      expect(groups.last.tools.map((d) => d.toolId).toList(), [
        'plugin.regular',
      ]);
    });
  });
}
