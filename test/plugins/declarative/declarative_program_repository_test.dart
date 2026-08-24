import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/repository/declarative_program_repository.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

void main() {
  test('מוחק פלט ישן ומפרסם את כל תכניות התוסף אטומית', () async {
    final queue = _RunQueue();
    final repository = DeclarativeProgramRepository(runProgram: queue.call);
    final plugin = _plugin();
    repository.syncPlugin(
      plugin: plugin,
      programs: [_program('a'), _program('b')],
      grantedPermissions: const {},
    );
    final snapshots = <Set<String>>[];
    repository.addListener(() {
      snapshots.add(repository.getPluginOutputs(plugin.pluginId).keys.toSet());
    });

    final firstRun = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    queue.completeNext('a', 1);
    await queue.waitForCalls(2);
    expect(repository.getPluginOutputs(plugin.pluginId), isEmpty);
    queue.completeNext('b', 1);
    await firstRun;
    expect(repository.getPluginOutputs(plugin.pluginId).keys, {'a', 'b'});

    final secondRun = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-2',
    );
    expect(repository.getPluginOutputs(plugin.pluginId), isEmpty);
    queue.completeNext('a', 2);
    await queue.waitForCalls(4);
    expect(repository.getPluginOutputs(plugin.pluginId), isEmpty);
    queue.completeNext('b', 2);
    await secondRun;

    expect(repository.getPluginOutputs(plugin.pluginId).keys, {'a', 'b'});
    expect(snapshots, contains(isEmpty));
    expect(
      snapshots.where((snapshot) => snapshot.isNotEmpty),
      everyElement({'a', 'b'}),
    );
  });

  test('תוצאה מדור ישן אינה דורסת ספר חדש', () async {
    final queue = _RunQueue();
    final repository = DeclarativeProgramRepository(runProgram: queue.call);
    final plugin = _plugin();
    repository.syncPlugin(
      plugin: plugin,
      programs: [_program('p')],
      grantedPermissions: const {},
    );

    final oldRun = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'old-book',
    );
    final newRun = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'new-book',
    );
    await queue.waitForCalls(2);
    queue.completeAt(1, 'p', 'new');
    await newRun;
    expect(
      repository.getProgramOutputs(plugin.pluginId, 'p'),
      containsPair('value', 'new'),
    );

    queue.completeAt(0, 'p', 'old');
    await oldRun;
    expect(
      repository.getProgramOutputs(plugin.pluginId, 'p'),
      containsPair('value', 'new'),
    );
    expect(repository.getContextSignature(plugin.pluginId), 'new-book');
  });

  test('טריגר אחד אינו מוחק את הפלט של טריגר אחר', () async {
    final queue = _RunQueue();
    final repository = DeclarativeProgramRepository(runProgram: queue.call);
    final plugin = _plugin();
    repository.syncPlugin(
      plugin: plugin,
      programs: [
        _program('reader'),
        _program('boot', triggers: const ['app.startup']),
      ],
      grantedPermissions: const {},
    );

    final boot = repository.runTrigger(
      trigger: 'app.startup',
      context: const {},
      contextSignature: 'app:0',
    );
    queue.completeNext('boot', 'once');
    await boot;

    final reader = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    // הפלט של app.startup חייב להישאר זמין גם בזמן שתכנית הקריאה רצה.
    expect(
      repository.getProgramOutputs(plugin.pluginId, 'boot'),
      containsPair('value', 'once'),
    );
    queue.completeNext('reader', 'now');
    await reader;

    expect(repository.getPluginOutputs(plugin.pluginId).keys, {
      'boot',
      'reader',
    });
  });

  test('יציאה מספר משאירה פלט של תכנית שאינה תלוית-הקשר', () async {
    final queue = _RunQueue();
    final repository = DeclarativeProgramRepository(runProgram: queue.call);
    final plugin = _plugin();
    repository.syncPlugin(
      plugin: plugin,
      programs: [
        _program('reader'),
        _program('boot', triggers: const ['app.startup']),
      ],
      grantedPermissions: const {},
    );

    final boot = repository.runTrigger(
      trigger: 'app.startup',
      context: const {},
      contextSignature: 'app:0',
    );
    queue.completeNext('boot', 'once');
    await boot;
    final reader = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    queue.completeNext('reader', 'now');
    await reader;

    repository.clearContexts();

    expect(repository.getPluginOutputs(plugin.pluginId).keys, {'boot'});
    expect(repository.getContextSignature(plugin.pluginId), isNull);
  });

  test('ריצת settings.changed אינה מוחקת פלט של ריצה שעדיין באוויר', () async {
    final queue = _RunQueue();
    final repository = DeclarativeProgramRepository(runProgram: queue.call);
    final plugin = _plugin();
    repository.syncPlugin(
      plugin: plugin,
      programs: [
        _program('reader'),
        _program('prefs', triggers: const ['settings.changed']),
      ],
      grantedPermissions: const {},
    );

    final reader = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {'reader': 1},
      contextSignature: 'book-1',
    );
    await queue.waitForCalls(1);
    final prefs = repository.runTrigger(
      trigger: 'settings.changed',
      context: const {'reader': 1},
      contextSignature: 'book-1',
    );
    await queue.waitForCalls(2);
    queue.completeAt(1, 'prefs', 'p');
    await prefs;
    queue.completeAt(0, 'reader', 'r');
    await reader;

    expect(
      repository.getProgramOutputs(plugin.pluginId, 'reader'),
      containsPair('value', 'r'),
    );
    expect(
      repository.getProgramOutputs(plugin.pluginId, 'prefs'),
      containsPair('value', 'p'),
    );
  });

  test('פלט תלוי-הקשר של טריגר context-free נמחק ביציאה מספר', () async {
    final queue = _RunQueue();
    final repository = DeclarativeProgramRepository(runProgram: queue.call);
    final plugin = _plugin();
    repository.syncPlugin(
      plugin: plugin,
      programs: [
        _program('prefs', triggers: const ['settings.changed']),
      ],
      grantedPermissions: const {},
    );

    // הריצה קיבלה ספר פתוח בהקשר, ולכן הפלט עלול לשאת את זהותו.
    final run = repository.runTrigger(
      trigger: 'settings.changed',
      context: const {'reader': 1},
      contextSignature: 'book-1',
    );
    queue.completeNext('prefs', 'from-book-1');
    await run;
    expect(repository.getProgramOutputs(plugin.pluginId, 'prefs'), isNotNull);

    repository.clearContexts();

    expect(repository.getPluginOutputs(plugin.pluginId), isEmpty);
  });

  test('הסרת תוסף בזמן ריצה מבטלת את התוצאה המאוחרת', () async {
    final queue = _RunQueue();
    final repository = DeclarativeProgramRepository(runProgram: queue.call);
    final plugin = _plugin();
    repository.syncPlugin(
      plugin: plugin,
      programs: [_program('p')],
      grantedPermissions: const {},
    );

    final pending = repository.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book',
    );
    repository.removePlugin(plugin.pluginId);
    queue.completeAt(0, 'p', 'late');
    await pending;

    expect(repository.getPluginOutputs(plugin.pluginId), isEmpty);
    expect(repository.getContextSignature(plugin.pluginId), isNull);
  });
}

class _RunQueue {
  final calls = <Completer<DeclarativeProgramResult>>[];

  Future<DeclarativeProgramResult> call({
    required CompiledDeclarativeProgram program,
    required InstalledPlugin plugin,
    required Set<String> grantedPermissions,
    required Map<String, dynamic> context,
  }) {
    final completer = Completer<DeclarativeProgramResult>();
    calls.add(completer);
    return completer.future;
  }

  void completeNext(String programId, Object? value) {
    final completer = calls.firstWhere((call) => !call.isCompleted);
    completer.complete(
      DeclarativeProgramResult(
        programId: programId,
        outputs: {'value': value},
      ),
    );
  }

  void completeAt(int index, String programId, Object? value) {
    calls[index].complete(
      DeclarativeProgramResult(
        programId: programId,
        outputs: {'value': value},
      ),
    );
  }

  Future<void> waitForCalls(int count) async {
    while (calls.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

CompiledDeclarativeProgram _program(
  String id, {
  List<String> triggers = const ['reader.activeBookChanged'],
}) => CompiledDeclarativeProgram(
  id: id,
  version: 1,
  triggers: triggers,
  when: null,
  commands: const [],
  outputs: const {},
  requiredPermissions: const {},
);

InstalledPlugin _plugin() {
  final now = DateTime(2026);
  return InstalledPlugin(
    pluginId: 'test.declarative.plugin',
    name: 'Declarative',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: false,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: 'test.declarative.plugin',
      name: 'Declarative',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '0.9.98',
      sdkVersion: '1.x',
      permissions: const ['app.startup_contributions'],
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: 'Declarative',
      toolTabOrder: 900,
      defaultPinned: false,
      publishedDataTypes: const [],
    ),
    installedAt: now,
    updatedAt: now,
  );
}
