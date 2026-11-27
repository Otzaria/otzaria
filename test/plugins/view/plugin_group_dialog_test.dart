import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_group.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/view/plugin_group_dialog.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

InstalledPlugin _plugin(
  String id,
  String name, {
  bool enabled = true,
  bool showInTools = true,
}) => InstalledPlugin(
  pluginId: id,
  name: name,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: enabled,
  pinned: false,
  showInTools: showInTools,
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: name,
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.0.0',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: name,
    toolTabOrder: 900,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
);

Future<void> _openEditor(
  WidgetTester tester, {
  PluginGroup? group,
  List<PluginGroup> groups = const [],
  List<InstalledPlugin>? plugins,
  List<String> initialIds = const [],
  Future<void> Function(String, List<String>)? onSave,
  ThemeData? theme,
  double textScale = 1,
  SettingsLanguage language = SettingsLanguage.source,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: language.textDirection,
          child: SettingsTextScope(language: language, child: child!),
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => ActionButton.neutral(
            text: 'open',
            onPressed: () => showDialogUntilTornDown<void>(
              context: context,
              builder: (_) => PluginGroupEditor(
                group: group,
                plugins:
                    plugins ?? [_plugin('a', 'חזרות'), _plugin('b', 'כתיבה')],
                groups: groups,
                initialPluginIds: initialIds,
                onSave: onSave ?? (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder get _name => find.byKey(const ValueKey('plugin-group-name'));
Finder get _search => find.byKey(const ValueKey('plugin-group-search'));

void main() {
  testWidgets('canceling an untouched editor does not save', (tester) async {
    var saves = 0;
    await _openEditor(tester, onSave: (_, _) async => saves++);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PluginGroupEditor), findsNothing);
    expect(saves, 0);
  });

  for (final action in ['cancel', 'escape', 'close', 'barrier']) {
    testWidgets('dirty editor guards $action and keeps selections', (
      tester,
    ) async {
      await _openEditor(tester);
      await tester.enterText(_name, 'לימוד');
      await tester.tap(find.text('חזרות'));
      await tester.pump();
      switch (action) {
        case 'cancel':
          await tester.tap(find.text('ביטול'));
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'close':
          await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular).first);
        case 'barrier':
          await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
      await tester.tap(find.text('המשך לערוך'));
      await tester.pumpAndSettle();
      expect(find.text('לימוד'), findsOneWidget);
      expect(find.text('נבחרו 1 תוספים'), findsOneWidget);
    });
  }

  testWidgets('Enter on cancel follows the cancel action', (tester) async {
    await _openEditor(tester);
    final cancel = find.ancestor(
      of: find.text('ביטול'),
      matching: find.byType(ActionButton),
    );
    final button = find.descendant(
      of: cancel,
      matching: find.byType(FilledButton),
    );
    Focus.of(tester.element(button)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PluginGroupEditor), findsNothing);
  });

  testWidgets('search preserves selection and save waits for persistence', (
    tester,
  ) async {
    final completion = Completer<void>();
    String? savedName;
    List<String>? savedIds;
    await _openEditor(
      tester,
      initialIds: ['a'],
      onSave: (name, ids) {
        savedName = name;
        savedIds = ids;
        return completion.future;
      },
    );
    await tester.enterText(_name, '  לימוד  ');
    await tester.enterText(_search, 'כתיבה');
    await tester.pump();
    expect(find.text('חזרות'), findsNothing);
    await tester.tap(find.text('כתיבה'));
    await tester.tap(find.text('שמור'));
    await tester.pump();
    expect(savedName, 'לימוד');
    expect(savedIds, ['a', 'b']);
    expect(find.byType(PluginGroupEditor), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(PluginGroupEditor), findsOneWidget);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PluginGroupEditor), findsNothing);
  });

  testWidgets('failure retains the draft and allows retry', (tester) async {
    var attempts = 0;
    await _openEditor(
      tester,
      onSave: (_, _) async {
        if (++attempts == 1) throw StateError('disk unavailable');
      },
    );
    await tester.enterText(_name, 'קבוצה אישית');
    await tester.tap(find.text('חזרות'));
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();
    expect(find.text(PluginMessages.pluginGroupSaveFailed), findsOneWidget);
    expect(find.text('קבוצה אישית'), findsOneWidget);
    expect(find.text('נבחרו 1 תוספים'), findsOneWidget);
    expect(find.textContaining('disk unavailable'), findsNothing);
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(PluginGroupEditor), findsNothing);
  });

  testWidgets('empty and duplicate names are rejected without writes', (
    tester,
  ) async {
    var saves = 0;
    await _openEditor(
      tester,
      groups: [PluginGroup(id: 'one', name: 'לימוד', pluginIds: [])],
      onSave: (_, _) async => saves++,
    );
    await tester.enterText(_name, '  ');
    await tester.tap(find.text('שמור'));
    await tester.pump();
    expect(find.text('הזן שם לקבוצה'), findsOneWidget);
    await tester.enterText(_name, ' לימוד ');
    await tester.tap(find.text('שמור'));
    await tester.pump();
    expect(find.text('כבר קיימת קבוצה בשם זה'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('editing preserves hidden and disabled members', (tester) async {
    List<String>? savedIds;
    final group = PluginGroup(id: 'one', name: 'לימוד', pluginIds: ['b', 'a']);
    await _openEditor(
      tester,
      group: group,
      groups: [group],
      plugins: [
        _plugin('a', 'חזרות', enabled: false),
        _plugin('b', 'כתיבה', showInTools: false),
      ],
      onSave: (_, ids) async => savedIds = ids,
    );
    expect(find.textContaining('מושבת'), findsOneWidget);
    expect(find.textContaining('מוסתר מלוח הכלים'), findsOneWidget);
    await tester.enterText(_name, 'לימוד יומי');
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();
    expect(savedIds, ['b', 'a']);
  });

  for (final width in [360.0, 1000.0]) {
    for (final style in ['light', 'dark', 'white']) {
      testWidgets('editor fits $style at $width and 1.3 text', (tester) async {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final dark = style == 'dark';
        final white = style == 'white';
        final scheme = AppThemeData.createColorScheme(
          white ? AppSeedColors.white : AppSeedColors.defaultLight,
          dark ? Brightness.dark : Brightness.light,
        );
        await _openEditor(
          tester,
          theme: dark
              ? AppThemeData.dark(scheme)
              : AppThemeData.light(
                  scheme,
                  variant: white
                      ? AppThemeVariant.white
                      : AppThemeVariant.standard,
                ),
          textScale: 1.3,
          plugins: List.generate(
            30,
            (i) =>
                _plugin('$i', 'תוסף ללימוד חזרה וכתיבה עם שם ארוך במיוחד $i'),
          ),
        );
        await tester.enterText(_name, 'לימוד');
        await tester.drag(find.byType(ListView), const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('שמור'), findsOneWidget);
      });
    }
  }
}
