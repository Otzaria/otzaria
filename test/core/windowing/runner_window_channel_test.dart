import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mainWindowHandle preserves a 64-bit window pointer', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const handle = 0x123456789;
    messenger.setMockMethodCallHandler(RunnerWindowChannel.channel, (call) async {
      expect(call.method, 'mainWindowHandle');
      return handle;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(RunnerWindowChannel.channel, null),
    );

    expect(await const RunnerWindowChannel().mainWindowHandle(), handle);
  });

  group('canTransfer', () {
    test('כרטיסיית כלי ניתנת להעברה', () {
      expect(
        RunnerWindowChannel.canTransfer(
          ToolTab(toolId: 'acronyms', title: 'ראשי תיבות'),
        ),
        isTrue,
      );
    });

    test('כרטיסיה שאינה שורדת סריאליזציה נחסמת ואינה זורקת', () {
      // ⚠️ זו ההגנה מפני אובדן: בלעדיה כרטיסיה שלא ניתנת לשחזור הייתה
      // נעלמת מהחלון המקורי ולא נפתחת בחדש.
      expect(RunnerWindowChannel.canTransfer(_UnserializableTab()), isFalse);
    });

    test('טאב מפוצל שאיבד חלונית נחסם — "לא זרק" אינו "נאמן"', () {
      // ⚠️ `decodeCombinedTab` בולע חלונית שנכשלה ומחזיר את השורדת. זו
      // התנהגות נכונה בשחזור מדיסק — עדיף חצי ספר מכלום — ואובדן מידע
      // בהעברה, כי הכרטיסיה כבר נמחקת מהמקור. הבדיקה הקודמת בדקה רק
      // שהסריאליזציה אינה זורקת, ולכן פיצול חצי היה עובר אותה.
      final half = CombinedTab(
        rightTab: ToolTab(toolId: 'acronyms', title: 'ראשי תיבות'),
        leftTab: _UnserializableTab(),
      );
      expect(RunnerWindowChannel.canTransfer(half), isFalse);
    });

    test('טאב מפוצל ששתי חלוניותיו שורדות עובר', () {
      final whole = CombinedTab(
        rightTab: ToolTab(toolId: 'acronyms', title: 'ראשי תיבות'),
        leftTab: ToolTab(toolId: 'gematria', title: 'גימטריה'),
      );
      expect(RunnerWindowChannel.canTransfer(whole), isTrue);
    });
  });
}

/// כרטיסיה שה-JSON שלה אינו ניתן לשחזור — `type` שאינו מוכר ל-
/// `OpenedTab.fromJson`.
class _UnserializableTab extends OpenedTab {
  _UnserializableTab() : super('כרטיסיה שבורה');

  @override
  Map<String, dynamic> toJson() => {'type': 'DefinitelyNotATabType'};

  @override
  OpenedTab clone() => _UnserializableTab();
}
