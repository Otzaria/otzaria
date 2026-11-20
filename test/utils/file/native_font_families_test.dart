import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/native_font_families.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(nativeFontFamiliesChannelName);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('שם הערוץ והשיטה הם החוזה מול קוד ה-Swift', () {
    expect(nativeFontFamiliesChannelName, 'otzaria/native_fonts');
    expect(nativeFontFamiliesMethod, 'hebrewFamilies');
  });

  test('הערוץ מתורגם לרשימת משפחות עם סימון תמיכה בטעמים', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return [
        {'family': 'Arial Hebrew', 'taamim': false},
        {'family': 'Times New Roman', 'taamim': true},
      ];
    });
    final families = await const ChannelNativeFontFamilySource()
        .hebrewFamilies();
    expect(seen?.method, nativeFontFamiliesMethod);
    expect(families.map((f) => f.family), ['Arial Hebrew', 'Times New Roman']);
    expect(families.map((f) => f.supportsTaamim), [false, true]);
  });

  test(
    'רשומות פגומות מדולגות, כפילויות מאוחדות, שמות מנוקים מרווחים',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => [
          {'family': '  Damascus  ', 'taamim': true},
          {'family': 'damascus', 'taamim': true},
          {'family': '', 'taamim': true},
          {'family': 7, 'taamim': true},
          {'taamim': true},
          'Plain',
          null,
          {'family': 'NoFlag'},
        ],
      );
      final families = await const ChannelNativeFontFamilySource()
          .hebrewFamilies();
      expect(families.map((f) => f.family), ['Damascus', 'NoFlag']);
      // דגל חסר = תומך: אזהרה שגויה גרועה מהחמצה (כמו בגופני מערכת אחרים).
      expect(families.last.supportsTaamim, isTrue);
    },
  );

  test('כשל בערוץ או היעדרו מחזירים רשימה ריקה ולא זורקים', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    expect(
      await const ChannelNativeFontFamilySource().hebrewFamilies(),
      isEmpty,
    );

    messenger.setMockMethodCallHandler(channel, null);
    expect(
      await const ChannelNativeFontFamilySource().hebrewFamilies(),
      isEmpty,
    );

    messenger.setMockMethodCallHandler(channel, (call) async => 'not a list');
    expect(
      await const ChannelNativeFontFamilySource().hebrewFamilies(),
      isEmpty,
    );
  });
}
