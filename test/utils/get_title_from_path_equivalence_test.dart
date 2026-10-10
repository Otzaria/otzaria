import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

// אורקל: המימוש הקודם, עם מפריד הנתיב כפרמטר כדי לבדוק את Windows ואת POSIX.
String _oracleTitleFromPath(String path, String separator) {
  path = path.replaceAll('/', separator).replaceAll('\\', separator);
  final fileName = path.split(separator).last;
  final lastDotIndex = fileName.lastIndexOf('.');
  if (lastDotIndex == -1) {
    return fileName;
  }
  return fileName.substring(0, lastDotIndex);
}

void main() {
  test(
    'getTitleFromPath matches the old split on both separators',
    () {
      final inputs = <String>[
        '',
        '.',
        '..',
        '/',
        '\\',
        'בראשית',
        'בראשית.txt',
        '.hidden',
        'dir/.hidden',
        'רש"י על בראשית.v2.txt',
        'C:\\אוצריא\\תנך\\בראשית.txt',
        '/home/user/אוצריא/תנך/בראשית.pdf',
        'C:\\אוצריא/תנך\\מעורב/בראשית.txt',
        'dir/',
        'dir\\',
        'dir.v1/file',
        'dir.v1\\file',
        'dir/file.',
        '//',
        'a\\/b.c',
      ];
      final random = Random(7);
      const alphabet = ['/', '\\', '.', 'a', 'ב', ' ', '😀'];
      for (var i = 0; i < 2000; i++) {
        final length = random.nextInt(20);
        inputs.add(
          [
            for (var j = 0; j < length; j++)
              alphabet[random.nextInt(alphabet.length)],
          ].join(),
        );
      }
      for (final input in inputs) {
        for (final separator in {'/', '\\', Platform.pathSeparator}) {
          expect(
            getTitleFromPath(input),
            _oracleTitleFromPath(input, separator),
            reason: 'separator $separator: $input',
          );
        }
      }
    },
  );
}
