import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';

void main() {
  final redactor = AppReportRedactor(
    environment: const {
      'USERPROFILE': r'C:\Users\Moshe',
      'USERNAME': 'Moshe',
    },
  );

  group('AppReportRedactor', () {
    test('מחליף את תיקיית הפרופיל בכל צורות הלוכסן ובלי תלות ברישיות', () {
      expect(
        redactor.redactText(r'C:\Users\Moshe\AppData\Roaming\otzaria'),
        r'%USERPROFILE%\AppData\Roaming\otzaria',
      );
      expect(
        redactor.redactText('file:///c:/users/moshe/x.dart'),
        'file:///%USERPROFILE%/x.dart',
      );
      expect(
        redactor.redactText(r'{"path":"C:\\Users\\Moshe\\books"}'),
        r'{"path":"%USERPROFILE%\\books"}',
      );
    });

    test('אינו נוגע בפרופיל אחר שמתחיל באותן אותיות', () {
      expect(
        redactor.redactText(r'C:\Users\Moshe2\x'),
        r'C:\Users\Moshe2\x',
      );
    });

    test('שם המשתמש מוחלף רק כמילה שלמה', () {
      expect(
        redactor.redactText('owner moshe, MosheBooks, Moshe_1'),
        'owner <user>, MosheBooks, Moshe_1',
      );
    });

    test('הסתרה חוזרת אינה משנה טקסט מוסתר (שם המשתמש User)', () {
      final user = AppReportRedactor(
        environment: const {
          'USERPROFILE': r'C:\Users\User',
          'USERNAME': 'User',
        },
      );
      final once = user.redactText(r'user C:\Users\User\x a@b.com');
      expect(once, r'<user> %USERPROFILE%\x <email>');
      expect(user.redactText(once), once);
    });

    test('שם משתמש קצר משלוש אותיות אינו מוחלף', () {
      final short = AppReportRedactor(environment: const {'USERNAME': 'ab'});
      expect(short.redactText('ab cd'), 'ab cd');
    });

    test('מסתיר כתובות מייל', () {
      expect(
        redactor.redactText('contact a.b+c@mail.example.co.il now'),
        'contact <email> now',
      );
    });

    test('עובד רקורסיבית על JSON, כולל מפתחות', () {
      final result = redactor.redactJson({
        r'C:\Users\Moshe\books': [
          'x@y.com',
          {'n': 5, 'user': 'Moshe'},
        ],
      });
      expect(result, {
        r'%USERPROFILE%\books': [
          '<email>',
          {'n': 5, 'user': '<user>'},
        ],
      });
    });

    test('HOME בלינוקס ונתיב קצר מדי מדולג', () {
      final linux = AppReportRedactor(
        environment: const {'HOME': '/home/dani', 'USER': 'dani'},
      );
      expect(linux.redactText('/home/dani/.local'), '%USERPROFILE%/.local');
      final root = AppReportRedactor(environment: const {'HOME': '/'});
      expect(root.redactText('/usr/lib'), '/usr/lib');
    });
  });

  group('AppReportRedactor: כתובות מייל', () {
    String red(String s) => redactor.redactText(s);

    test('משמעות ההסתרה נשמרת', () {
      expect(red('-a@b.com'), '-<email>');
      expect(red('a@b@c.com'), 'a@<email>');
      expect(red('a..b@c.com'), '<email>');
      expect(red('user+tag@sub.example.org.'), '<email>.');
      expect(red('שלוםa@b.com!'), 'שלום<email>!');
      expect(red('a@b.com, c@d.org;e@f.net'), '<email>, <email>;<email>');
      expect(red('<a@b.com>'), '<<email>>');
      expect(red('mailto:a@b.com'), 'mailto:<email>');
      expect(red('a@b.com:443'), '<email>:443');
      expect(red('שלום a@b.com תודה'), 'שלום <email> תודה');
      expect(red('a@b.com1'), '<email>1');
      expect(red('a@b.com..x.org'), '<email>..x.org');
      expect(red('a@b.co-x.y'), '<email>-x.y');
      expect(red('a@b.cc.dd.ee'), '<email>');
      expect(red('a@b.cc.d'), '<email>.d');
      expect(red('a@b.ccd'), '<email>');
      expect(red('a@b.cc.ddd1'), '<email>1');
      expect(red('a.@b.com'), '<email>');
      expect(red('éa@b.com'), 'é<email>');
    });

    test('טקסט שאינו מייל נשאר כמות שהוא', () {
      for (final s in ['a@b', 'a@b.c', '@b.com', 'a@', '-@b.com', 'a@.com']) {
        expect(red(s), s);
      }
    });

    test('הסתרה חוזרת אינה משנה את התוצאה', () {
      for (final s in [
        'a@b.com x@y.org',
        '-a@b.com',
        'a@b@c.com',
        '<email>@b.com',
      ]) {
        expect(red(red(s)), red(s));
      }
    });

    test('קלט ארוך ועוין מסתיים מהר', () {
      final inputs = <String>[
        'a' * 200000,
        r'\' + 'a' * 200000,
        'a@' * 100000,
        'a@b.' * 70000,
        '@' * 200000,
        ('a' * 64 + '@') * 3000,
        'a.' * 100000,
        'a-' * 100000,
        '${'a' * 200000}@',
      ];
      for (final input in inputs) {
        final watch = Stopwatch()..start();
        red(input);
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 2)),
          reason: 'קלט באורך ${input.length}',
        );
      }
    });

    test('טוקן ארוך עם מייל בסופו מוסתר במלואו', () {
      expect(red('${'a' * 200000}@b.com'), '<email>');
    });
  });
}
