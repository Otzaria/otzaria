import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/main.dart' show flutterErrorDetailsForLog;

/// כמו ErrorDescription ב-release: שם toString הוא "Instance of ...".
class _ReleaseLikeDescription extends DiagnosticsProperty<void> {
  _ReleaseLikeDescription(String message)
    : super(null, null, description: message, level: DiagnosticLevel.info);

  @override
  String toString({
    TextTreeConfiguration? parentConfiguration,
    DiagnosticLevel minLevel = DiagnosticLevel.info,
  }) => "Instance of 'ErrorDescription'";
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Context נרשם כטקסט ההקשר, גם כש-toString אינו מתאר אותו (#3172)', () {
    final details = flutterErrorDetailsForLog(
      FlutterErrorDetails(
        exception: StateError('boom'),
        library: 'printing',
        context: _ReleaseLikeDescription('while generating a PDF'),
      ),
    );
    expect(details['Context'], 'while generating a PDF');
  });

  test('formatEntry כותב Version לפני Exception', () {
    ErrorLogFile.setAppVersion('9.8.7+65');

    final output = ErrorLogFile.formatEntry(
      title: 'FlutterError',
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('stack-line-1\nstack-line-2'),
      details: const {
        'Library': 'widgets library',
        'Context': 'while building test widget',
      },
    );

    expect(output, contains('FlutterError'));
    expect(output, contains('Version: 9.8.7+65'));
    expect(output, contains('Bad state: boom'));
    expect(output, contains('widgets library'));
    expect(output, contains('while building test widget'));
    expect(output, contains('stack-line-1'));
  });

  test('formatEntry מטפל בפרטים מרובי שורות', () {
    final output = ErrorLogFile.formatEntry(
      title: 'Initialization Warning',
      error: ArgumentError('bad input'),
      stackTrace: StackTrace.fromString('platform-stack'),
      details: const {
        'Information': 'line 1\nline 2',
      },
    );

    expect(output, contains('Initialization Warning'));
    expect(output, contains('Invalid argument(s): bad input'));
    expect(output, contains('Information:'));
    expect(output, contains('line 1'));
    expect(output, contains('line 2'));
    expect(output, contains('platform-stack'));
  });
}
