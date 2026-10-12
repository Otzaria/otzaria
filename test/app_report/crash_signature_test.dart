import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

void main() {
  group('CrashSignature.normalizeFrame', () {
    test('מסיר מספור, שורה:עמודה ונתיב מוחלט', () {
      expect(
        CrashSignature.normalizeFrame(
          '#0      Foo.bar (package:otzaria/a/b.dart:12:5)',
        ),
        'Foo.bar (package:otzaria/a/b.dart)',
      );
      expect(
        CrashSignature.normalizeFrame(
          '#3 main (file:///C:/Users/x/proj/test/main_test.dart:3:4)',
        ),
        'main (main_test.dart)',
      );
      expect(
        CrashSignature.normalizeFrame(
          r'  C:\Users\x\lib\foo.dart 12:5  Foo.bar',
        ),
        'foo.dart Foo.bar',
      );
    });

    test('שומר מודול+RVA ומדלג על כתובות גולמיות והשהיות', () {
      expect(
        CrashSignature.normalizeFrame('  flutter_windows.dll+0x81bb05'),
        'flutter_windows.dll+0x81bb05',
      );
      expect(CrashSignature.normalizeFrame('  0x1f8e8b92bbc'), isNull);
      expect(
        CrashSignature.normalizeFrame('<asynchronous suspension>'),
        isNull,
      );
      expect(CrashSignature.normalizeFrame('   '), isNull);
    });
  });

  group('CrashSignature.selectFrames', () {
    const stack = '''
#0      List.[] (dart:core-patch/growable_array.dart:264:36)
#1      Foo.a (package:otzaria/x/foo.dart:10:3)
<asynchronous suspension>
#2      Bar.b (package:flutter/src/widgets/framework.dart:5:1)
#3      Baz.c (package:otzaria/y/baz.dart:20:7)
#4      Qux.d (package:otzaria/z/qux.dart:30:9)
#5      Last.e (package:otzaria/z/last.dart:1:1)
''';

    test('מעדיף את שלושת הפריימים הראשונים של אוצריא', () {
      expect(CrashSignature.selectFrames(stack), [
        'Foo.a (package:otzaria/x/foo.dart)',
        'Baz.c (package:otzaria/y/baz.dart)',
        'Qux.d (package:otzaria/z/qux.dart)',
      ]);
    });

    test('בלי פריימים של אוצריא — הפריימים הראשונים', () {
      const foreign = '''
#0      A.a (package:flutter/a.dart:1:1)
#1      B.b (dart:async/b.dart:2:2)
''';
      expect(CrashSignature.selectFrames(foreign), [
        'A.a (package:flutter/a.dart)',
        'B.b (dart:async/b.dart)',
      ]);
    });

    test('דטרמיניסטי: מספרי שורות שונים נותנים אותה חתימה ואותו hash', () {
      final a = CrashSignature.fromLogText(
        exceptionMessage: 'StateError: Bad state: x',
        stackText: stack,
      );
      final b = CrashSignature.fromLogText(
        exceptionMessage: 'StateError: Bad state: y',
        stackText: stack.replaceAll(':10:3', ':99:1'),
      );
      expect(a, b);
      expect(a.hash, b.hash);
      expect(a.hash, hasLength(64));
    });
  });

  group('CrashSignature.exceptionTypeFromMessage', () {
    test('לוקח את שם הטיפוס שלפני הנקודתיים', () {
      expect(
        CrashSignature.exceptionTypeFromMessage('FormatException: bad input'),
        'FormatException',
      );
    });

    test('הודעה חופשית מנורמלת ממספרים ומחרוזות', () {
      expect(
        CrashSignature.exceptionTypeFromMessage(
          "Null check operator used on item 42 of 'abc'",
        ),
        "Null check operator used on item # of ''",
      );
    });
  });

  test('fromError משתמש בטיפוס בזמן ריצה', () {
    final signature = CrashSignature.fromError(
      const FormatException('x'),
      StackTrace.fromString('#0 A.b (package:otzaria/a.dart:1:2)'),
    );
    expect(signature.exceptionType, 'FormatException');
    expect(signature.frames, ['A.b (package:otzaria/a.dart)']);
  });
}
