import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_toolbar_template_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/models/declarative_toolbar_template.dart';
import 'package:otzaria/plugins/declarative/repository/declarative_program_repository.dart';
import 'package:otzaria/plugins/declarative/services/declarative_toolbar_binding_service.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';

void main() {
  test('מפרסם שני פקדים עם פעולות Host בלבד', () async {
    final runner = _RunQueue();
    final programs = DeclarativeProgramRepository(runProgram: runner.call);
    final toolbar = PluginToolbarRegistry.forTesting();
    final binding = DeclarativeToolbarBindingService(
      programRepository: programs,
      toolbarRegistry: toolbar,
    );
    addTearDown(binding.dispose);
    final plugin = _plugin();
    programs.syncPlugin(
      plugin: plugin,
      programs: [_program()],
      grantedPermissions: const {'reader.open'},
    );
    binding.syncPlugin(
      plugin: plugin,
      templates: _compiledTemplates(),
      grantedPermissions: const {'reader.open'},
    );

    final run = programs.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    runner.completeNext(_outputs());
    await run;

    final items = toolbar.getAll().map((entry) => entry.$2).toList();
    expect(items, hasLength(2));
    expect(items.first.hostAction!.contextSignature, 'book-1');
    expect(items.first.hostAction!.args['identity'], {'id': 101});
    expect(items.last.children, hasLength(2));
    expect(items.last.children.first.hostAction!.args['identity'], {'id': 101});
    expect(items.last.children.last.hostAction!.args['identity'], {'id': 102});
    expect(items.every((item) => item.onClickEvent == null), isTrue);
    // placement ו-order מהתבנית מגיעים עד הפריט שנרשם בפועל.
    expect(items.last.placement, 'overflow');
    expect(items.last.order, 55);
    expect(items.first.placement, 'primary');
    expect(items.first.order, PluginToolbarItem.defaultOrder);
    // גם bookTypes: פקד קשור מסונן לפי הספר של כל סרגל, כמו פקד רגיל.
    expect(items.last.bookTypes, ['text', 'pdf']);
    expect(items.last.bookSources, ['library']);
    expect(items.first.bookTypes, isEmpty);
  });

  test(
    'דור חדש מסתיר את שני הפקדים יחד ותוצאה ישנה אינה מחזירה אותם',
    () async {
      final runner = _RunQueue();
      final programs = DeclarativeProgramRepository(runProgram: runner.call);
      final toolbar = PluginToolbarRegistry.forTesting();
      final binding = DeclarativeToolbarBindingService(
        programRepository: programs,
        toolbarRegistry: toolbar,
      );
      addTearDown(binding.dispose);
      final plugin = _plugin();
      programs.syncPlugin(
        plugin: plugin,
        programs: [_program()],
        grantedPermissions: const {'reader.open'},
      );
      binding.syncPlugin(
        plugin: plugin,
        templates: _compiledTemplates(),
        grantedPermissions: const {'reader.open'},
      );
      final snapshots = <int>[];
      toolbar.addListener(() => snapshots.add(toolbar.getAll().length));

      final firstRun = programs.runTrigger(
        trigger: 'reader.activeBookChanged',
        context: const {},
        contextSignature: 'book-1',
      );
      runner.completeAt(0, _outputs());
      await firstRun;
      expect(toolbar.getAll(), hasLength(2));

      final staleRun = programs.runTrigger(
        trigger: 'reader.activeBookChanged',
        context: const {},
        contextSignature: 'book-2',
      );
      expect(toolbar.getAll(), isEmpty);
      final currentRun = programs.runTrigger(
        trigger: 'reader.activeBookChanged',
        context: const {},
        contextSignature: 'book-3',
      );
      await runner.waitForCalls(3);
      runner.completeAt(1, _outputs());
      await staleRun;
      expect(toolbar.getAll(), isEmpty);

      runner.completeAt(2, _outputs());
      await currentRun;
      expect(toolbar.getAll(), hasLength(2));
      expect(snapshots, isNot(contains(1)));
    },
  );

  test('השבתת התוסף מוחקת מיד את קבוצת הפקדים', () async {
    final runner = _RunQueue();
    final programs = DeclarativeProgramRepository(runProgram: runner.call);
    final toolbar = PluginToolbarRegistry.forTesting();
    final binding = DeclarativeToolbarBindingService(
      programRepository: programs,
      toolbarRegistry: toolbar,
    );
    addTearDown(binding.dispose);
    final plugin = _plugin();
    programs.syncPlugin(
      plugin: plugin,
      programs: [_program()],
      grantedPermissions: const {'reader.open'},
    );
    binding.syncPlugin(
      plugin: plugin,
      templates: _compiledTemplates(),
      grantedPermissions: const {'reader.open'},
    );
    final run = programs.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    runner.completeNext(_outputs());
    await run;
    expect(toolbar.getAll(), hasLength(2));

    final disabled = plugin.copyWith(enabled: false);
    programs.syncPlugin(
      plugin: disabled,
      programs: [_program()],
      grantedPermissions: const {'reader.open'},
    );
    binding.syncPlugin(
      plugin: disabled,
      templates: _compiledTemplates(),
      grantedPermissions: const {'reader.open'},
    );

    expect(toolbar.getAll(), isEmpty);
  });

  test('פעולה שהרשאתה לא הוענקה מסתירה את כל הקבוצה', () async {
    final runner = _RunQueue();
    final programs = DeclarativeProgramRepository(runProgram: runner.call);
    final toolbar = PluginToolbarRegistry.forTesting();
    final binding = DeclarativeToolbarBindingService(
      programRepository: programs,
      toolbarRegistry: toolbar,
    );
    addTearDown(binding.dispose);
    final plugin = _plugin();
    programs.syncPlugin(
      plugin: plugin,
      programs: [_program()],
      grantedPermissions: const {},
    );
    binding.syncPlugin(
      plugin: plugin,
      templates: _compiledTemplates(),
      grantedPermissions: const {},
    );

    final run = programs.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    runner.completeNext(_outputs());
    await run;

    expect(toolbar.getAll(), isEmpty);
  });

  test('כפתור קשור עם openPlugin: מוצג לפי הפלט, ופותח את דף התוסף', () async {
    final runner = _RunQueue();
    final programs = DeclarativeProgramRepository(runProgram: runner.call);
    final toolbar = PluginToolbarRegistry.forTesting();
    final binding = DeclarativeToolbarBindingService(
      programRepository: programs,
      toolbarRegistry: toolbar,
    );
    addTearDown(binding.dispose);
    final plugin = _plugin();
    programs.syncPlugin(
      plugin: plugin,
      programs: [_program()],
      grantedPermissions: const {},
    );
    final button = Map<String, dynamic>.from(_templateJson().first)
      ..remove('action')
      ..['openPlugin'] = true;
    binding.syncPlugin(
      plugin: plugin,
      templates: DeclarativeToolbarTemplateCompiler(
        declaredPermissions: const {'reader.toolbar'},
        programs: {'book-links': _program()},
      ).compileAll('test.declarative.plugin', [button]),
      grantedPermissions: const {},
    );

    final shown = programs.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    runner.completeNext(_outputs());
    await shown;
    final item = toolbar.getAll().single.$2;
    expect(item.openPlugin, isTrue);
    expect(item.hostAction, isNull);
    expect(item.type, 'button');

    // ספר שהתכנית לא החזירה לו פלט — הכפתור אינו מוצג
    final hidden = programs.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-2',
    );
    runner.completeNext(_outputs()..['defaultEdition'] = null);
    await hidden;
    expect(toolbar.getAll(), isEmpty);
  });

  test('פלט חלקי אינו מפרסם פקד יחיד', () async {
    final runner = _RunQueue();
    final programs = DeclarativeProgramRepository(runProgram: runner.call);
    final toolbar = PluginToolbarRegistry.forTesting();
    final binding = DeclarativeToolbarBindingService(
      programRepository: programs,
      toolbarRegistry: toolbar,
    );
    addTearDown(binding.dispose);
    final plugin = _plugin();
    programs.syncPlugin(
      plugin: plugin,
      programs: [_program()],
      grantedPermissions: const {'reader.open'},
    );
    binding.syncPlugin(
      plugin: plugin,
      templates: _compiledTemplates(),
      grantedPermissions: const {'reader.open'},
    );
    final snapshots = <int>[];
    toolbar.addListener(() => snapshots.add(toolbar.getAll().length));

    final run = programs.runTrigger(
      trigger: 'reader.activeBookChanged',
      context: const {},
      contextSignature: 'book-1',
    );
    final outputs = _outputs()..['editions'] = const [];
    runner.completeNext(outputs);
    await run;

    expect(toolbar.getAll(), isEmpty);
    expect(snapshots, isNot(contains(1)));
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

  void completeNext(Map<String, dynamic> outputs) {
    final index = calls.indexWhere((call) => !call.isCompleted);
    completeAt(index, outputs);
  }

  void completeAt(int index, Map<String, dynamic> outputs) {
    calls[index].complete(
      DeclarativeProgramResult(programId: 'book-links', outputs: outputs),
    );
  }

  Future<void> waitForCalls(int count) async {
    while (calls.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

CompiledDeclarativeProgram _program() => const CompiledDeclarativeProgram(
  id: 'book-links',
  version: 1,
  triggers: ['reader.activeBookChanged'],
  when: null,
  commands: [],
  outputs: {'defaultEdition': null, 'editions': null},
  requiredPermissions: {},
);

List<CompiledDeclarativeToolbarTemplate> _compiledTemplates() =>
    DeclarativeToolbarTemplateCompiler(
      declaredPermissions: const {'reader.toolbar', 'reader.open'},
      programs: {'book-links': _program()},
    ).compileAll('test.declarative.plugin', _templateJson());

List<Map<String, dynamic>> _templateJson() => [
  {
    'id': 'open-default',
    'type': 'button',
    'title': 'פתח במהדורת ברירת המחדל',
    'icon': 'book_24_regular',
    'binding': {
      'program': 'book-links',
      'visibleOutput': 'defaultEdition',
    },
    'action': {
      'type': 'reader.openBook',
      'args': {
        'identity': {r'$output': 'defaultEdition.identity'},
      },
    },
  },
  {
    'id': 'open-editions',
    'type': 'menu',
    'title': 'פתח מהדורה אחרת',
    'icon': 'book_24_regular',
    'placement': 'overflow',
    'order': 55,
    'bookTypes': ['text', 'pdf'],
    'bookSources': ['library'],
    'binding': {
      'program': 'book-links',
      'visibleOutput': 'editions',
    },
    'childrenBinding': {
      'itemsOutput': 'editions',
      'itemTemplate': {
        'id': {
          r'$concat': [
            'edition-',
            {r'$item': 'identity.id'},
          ],
        },
        'title': {r'$item': 'title'},
        'action': {
          'type': 'reader.openBook',
          'args': {
            'identity': {r'$item': 'identity'},
          },
        },
      },
    },
  },
];

Map<String, dynamic> _outputs() => {
  'defaultEdition': {
    'title': 'מהדורת ברירת מחדל',
    'identity': {'id': 101},
  },
  'editions': [
    {
      'title': 'מהדורה א',
      'identity': {'id': 101},
    },
    {
      'title': 'מהדורה ב',
      'identity': {'id': 102},
    },
  ],
};

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
      permissions: const [
        'app.startup_contributions',
        'reader.toolbar',
        'reader.open',
      ],
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
