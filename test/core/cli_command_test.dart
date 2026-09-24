import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/cli_command.dart';

/// הפקודות שהצד של Dart מטפל בהן ב-`_maybeRunCliCommand`.
const _dartCommands = {
  'pack-plugin',
  'build-release-index',
  'info',
  'reports',
};

/// הפקודות שה-runner של Windows מריץ headless (בלי mutel מופע-יחיד ובלי splash).
Set<String> _readRunnerCommands() {
  final source = File('windows/runner/main.cpp').readAsStringSync();
  final body = RegExp(
    r'static bool IsCliInvocation\([^)]*\)\s*\{(.*?)\n\}',
    dotAll: true,
  ).firstMatch(source);
  expect(body, isNotNull, reason: 'IsCliInvocation לא נמצא ב-main.cpp');

  return RegExp(
    r'EqualsIgnoreCase\(cmd,\s*"([^"]+)"\)',
  ).allMatches(body!.group(1)!).map((match) => match.group(1)!).toSet();
}

void main() {
  group('normalizeCliCommand', () {
    test('מקלף כל התווים המובילים של דגל, כמו ה-runner', () {
      for (final raw in [
        'info',
        '-info',
        '--info',
        '---info',
        '/info',
        '//info',
        '/-info',
        '-/-info',
      ]) {
        expect(normalizeCliCommand(raw), 'info', reason: raw);
      }
    });

    test('מנרמל קווים תחתונים ואותיות גדולות ורווחים', () {
      expect(normalizeCliCommand('  PACK_PLUGIN '), 'pack-plugin');
      expect(
        normalizeCliCommand('--Build_Release_Index'),
        'build-release-index',
      );
    });

    test('ארגומנט שאינו פקודה נשאר כפי שהוא', () {
      expect(normalizeCliCommand('otzaria://info/app'), 'otzaria://info/app');
      expect(normalizeCliCommand(''), '');
      expect(normalizeCliCommand('---'), '');
    });
  });

  group('שקילות עם windows/runner/main.cpp', () {
    // פער בין השניים יוצר מופע שני בלי מנעול ובלי חלון: ה-runner מדלג על
    // ה-mutex, ו-Dart לא מזהה את הפקודה ומעלה אפליקציה מלאה.
    test('כל פקודה ב-IsCliInvocation מטופלת גם ב-Dart', () {
      for (final command in _readRunnerCommands()) {
        expect(
          _dartCommands,
          contains(normalizeCliCommand(command)),
          reason:
              'main.cpp מריץ headless את "$command" אבל Dart אינו מטפל בה — '
              'המנעול נדלג והאפליקציה תעלה מלאה בלי חלון',
        );
      }
    });

    test('IsCliInvocation מכיל את `info`', () {
      expect(_readRunnerCommands(), contains('info'));
    });

    test('IsCliInvocation מכיל את `reports`', () {
      expect(_readRunnerCommands(), contains('reports'));
    });
  });
}
