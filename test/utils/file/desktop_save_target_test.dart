import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/utils/file/desktop_save_target.dart';
import 'package:otzaria/widgets/dialogs/input_dialog.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:windows_file_picker/windows_file_picker.dart';

void main() {
  late Directory directory;
  late _FolderPicker picker;
  late FilePickerPlatform previousPicker;
  int? previousOwner;
  Object? nativeArguments;
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('save-target-');
    picker = _FolderPicker(() async => directory.path);
    previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    previousOwner = DialogOwner.hwnd();
    DialogOwner.mainWindowHwnd = 101;
    nativeArguments = null;
    if (Platform.isMacOS) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeArguments = call.arguments;
            if (call.method != 'dir') {
              throw StateError('Unexpected write picker');
            }
            return picker.getDirectoryPath();
          });
    }
  });
  tearDown(() {
    FilePickerPlatform.instance = previousPicker;
    DialogOwner.mainWindowHwnd = previousOwner;
    if (Platform.isMacOS) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    directory.deleteSync(recursive: true);
  });

  Future<BuildContext> build(WidgetTester tester) async {
    late BuildContext origin;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) {
              origin = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    return origin;
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await _waitFor(
      tester,
      () => find.byType(InputDialog).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('שמור'));
    await tester.pump();
  }

  testWidgets('selection returns a path and leaves the directory empty', (
    tester,
  ) async {
    final origin = await build(tester);
    final future = chooseDesktopSaveTarget(
      context: origin,
      fileName: 'report.PDF',
      extension: '.PDF',
      dialogTitle: 'ייצוא PDF',
    );
    await _waitFor(
      tester,
      () => find.byType(InputDialog).evaluate().isNotEmpty,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'report.PDF',
    );
    expect(directory.listSync(), isEmpty);
    if (Platform.isMacOS) {
      expect((nativeArguments as Map)['viewId'], tester.view.viewId);
    } else {
      expect(picker.title, 'בחירת תיקייה — ייצוא PDF');
      final options = picker.windowsOptions! as FilePickerWindowsOptions;
      expect(options.lockParentWindow, isTrue);
      expect(options.parentWindowHandle, 101);
      expect(picker.linuxOptions!.lockParentWindow, isTrue);
    }
    await enterName(tester, 'report.PDF');
    final target = await _settle(tester, future);
    expect(target!.path, p.join(directory.path, 'report.PDF'));
    expect(target.overwriteApproved, isFalse);
    expect(directory.listSync(), isEmpty);
  });

  testWidgets('cancelling either selection step does not create a file', (
    tester,
  ) async {
    final origin = await build(tester);
    picker.select = () async => null;
    expect(
      await _settle(
        tester,
        chooseDesktopSaveTarget(
          context: origin,
          fileName: 'report',
          extension: 'pdf',
        ),
      ),
      isNull,
    );
    expect(find.byType(InputDialog), findsNothing);
    picker.select = () async => directory.path;
    final future = chooseDesktopSaveTarget(
      context: origin,
      fileName: 'report',
      extension: 'pdf',
    );
    await _waitFor(
      tester,
      () => find.byType(InputDialog).evaluate().isNotEmpty,
    );
    await tester.tap(find.text('ביטול'));
    expect(await _settle(tester, future), isNull);
    expect(directory.listSync(), isEmpty);
  });

  testWidgets(
    'an existing file stays unchanged through overwrite confirmation',
    (tester) async {
      final existing = File(p.join(directory.path, 'report.pdf'))
        ..writeAsStringSync('keep');
      final origin = await build(tester);
      final future = chooseDesktopSaveTarget(
        context: origin,
        fileName: 'report',
        extension: 'pdf',
      );
      await enterName(tester, 'report');
      await _waitFor(
        tester,
        () => find.text('הקובץ כבר קיים').evaluate().isNotEmpty,
      );
      expect(existing.readAsStringSync(), 'keep');
      expect(directory.listSync(), hasLength(1));
      await tester.tap(find.text('החלפה'));
      final target = await _settle(tester, future);
      expect(target!.path, existing.path);
      expect(target.overwriteApproved, isTrue);
      expect(existing.readAsStringSync(), 'keep');
    },
  );

  testWidgets('declining replacement preserves the existing file', (
    tester,
  ) async {
    final existing = File(p.join(directory.path, 'report.pdf'))
      ..writeAsStringSync('keep');
    final origin = await build(tester);
    final future = chooseDesktopSaveTarget(
      context: origin,
      fileName: 'report',
      extension: 'pdf',
    );
    await enterName(tester, 'report');
    await _waitFor(
      tester,
      () => find.text('הקובץ כבר קיים').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('ביטול'));
    expect(await _settle(tester, future), isNull);
    expect(existing.readAsStringSync(), 'keep');
  });

  testWidgets(
    'owner disposal while the native picker waits cancels the request',
    (tester) async {
      final folder = Completer<String?>();
      picker.select = () => folder.future;
      final origin = await build(tester);
      final future = chooseDesktopSaveTarget(
        context: origin,
        fileName: 'report',
        extension: 'pdf',
      );
      try {
        await _waitFor(tester, () => picker.calls == 1);
        await tester.pumpWidget(const SizedBox.shrink());
        folder.complete(directory.path);
        expect(await _settle(tester, future), isNull);
        expect(find.byType(InputDialog), findsNothing);
        expect(directory.listSync(), isEmpty);
      } finally {
        if (!folder.isCompleted) folder.complete(null);
        await _settle(tester, future);
      }
    },
  );

  testWidgets('owner disposal during overwrite confirmation does not approve', (
    tester,
  ) async {
    final existing = File(p.join(directory.path, 'report.pdf'))
      ..writeAsStringSync('keep');
    final origin = await build(tester);
    final approval = Completer<bool>();
    String? confirmedName;
    final future = chooseDesktopSaveTarget(
      context: origin,
      fileName: 'report',
      extension: 'pdf',
      confirmOverwrite: (name) {
        confirmedName = name;
        return approval.future;
      },
    );
    try {
      await enterName(tester, 'report');
      await _waitFor(tester, () => confirmedName != null);
      expect(confirmedName, 'report.pdf');
      await tester.pumpWidget(const SizedBox.shrink());
      approval.complete(true);
      expect(await _settle(tester, future), isNull);
      expect(existing.readAsStringSync(), 'keep');
    } finally {
      if (!approval.isCompleted) approval.complete(false);
      await _settle(tester, future);
    }
  });

  testWidgets(
    'cancelled export never opens the name dialog on a mounted owner',
    (
      tester,
    ) async {
      final folder = Completer<String?>();
      picker.select = () => folder.future;
      final origin = await build(tester);
      var cancelled = false;
      final future = chooseDesktopSaveTarget(
        context: origin,
        fileName: 'report',
        extension: 'pdf',
        isCancelled: () => cancelled,
      );
      try {
        await _waitFor(tester, () => picker.calls == 1);
        cancelled = true;
        folder.complete(directory.path);
        expect(await _settle(tester, future), isNull);
        expect(origin.mounted, isTrue);
        expect(find.byType(InputDialog), findsNothing);
        expect(directory.listSync(), isEmpty);
      } finally {
        if (!folder.isCompleted) folder.complete(null);
        await _settle(tester, future);
      }
    },
  );

  testWidgets('an already disposed owner never opens the native picker', (
    tester,
  ) async {
    final origin = await build(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      await chooseDesktopSaveTarget(
        context: origin,
        fileName: 'report',
        extension: 'pdf',
      ),
      isNull,
    );
    expect(picker.calls, 0);
    expect(directory.listSync(), isEmpty);
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'The destination selection did not settle.');
}

Future<T> _settle<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  future.then<void>(
    (_) {
      done = true;
    },
    onError: (Object _, StackTrace _) {
      done = true;
    },
  );
  await _waitFor(tester, () => done);
  return future;
}

class _FolderPicker extends FilePickerPlatform with MockPlatformInterfaceMixin {
  _FolderPicker(this.select);
  Future<String?> Function() select;
  var calls = 0;
  String? title;
  WindowsOptions? windowsOptions;
  LinuxOptions? linuxOptions;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    calls++;
    title = dialogTitle;
    this.windowsOptions = windowsOptions;
    this.linuxOptions = linuxOptions;
    return select();
  }
}
