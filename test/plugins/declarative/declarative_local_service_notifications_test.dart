import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_action_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_host_action_executor.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';

void main() {
  testWidgets('תשובה שקטה אינה מסתירה הודעה חדשה יותר', (tester) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
    );
    addTearDown(UiSnack.hide);
    final release = Completer<void>();
    final executor = DeclarativeHostActionExecutor(
      bookOpener: _BookOpener(),
      localServiceClient: _LocalServiceClient(gate: release.future),
      networkGate: (_, _) async => PluginNetworkDecision.allowed,
    );
    final running = executor.execute(
      action: _compileLocal(),
      plugin: _plugin(),
      grantedPermissions: const {'network.localhost'},
      currentContextSignature: 'book-7',
      currentProgramGeneration: 7,
    );
    await tester.pump();
    UiSnack.showSuccess('הודעה חדשה');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('הודעה חדשה'), findsOneWidget);
    release.complete();
    await tester.pump();
    await running;
    await tester.pump();
    expect(find.text('הודעה חדשה'), findsOneWidget);
    UiSnack.hide();
    await tester.pump();
  });

  testWidgets('סיום בקשה אחת אינו מסתיר המתנה לבקשה אחרת', (tester) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
    );
    addTearDown(UiSnack.hide);
    final firstDone = Completer<void>();
    final secondDone = Completer<void>();
    Future<bool> send(String text, Completer<void> done) =>
        DeclarativeHostActionExecutor(
          bookOpener: _BookOpener(),
          localServiceClient: _LocalServiceClient(gate: done.future),
          networkGate: (_, _) async => PluginNetworkDecision.allowed,
        ).execute(
          action: _compileLocal(
            args: {
              'port': 39700,
              'path': '/x',
              'body': {'q': text},
              'pendingMessage': text,
            },
          ),
          plugin: _plugin(),
          grantedPermissions: const {'network.localhost'},
          currentContextSignature: 'book-7',
          currentProgramGeneration: 7,
        );
    final first = send('בקשה ראשונה', firstDone);
    await tester.pump();
    final second = send('בקשה שנייה', secondDone);
    await tester.pump();
    expect(find.textContaining('בקשה שנייה'), findsOneWidget);
    firstDone.complete();
    await tester.pump();
    await first;
    await tester.pump();
    expect(find.textContaining('בקשה שנייה'), findsOneWidget);
    secondDone.complete();
    await tester.pump();
    await second;
    await tester.pump();
    expect(find.textContaining('בקשה שנייה'), findsNothing);
  });
}

class _LocalServiceClient implements DeclarativeLocalServiceClient {
  final Future<void> gate;
  _LocalServiceClient({required this.gate});
  @override
  Future<DeclarativeLocalServiceResponse> post(
    Uri uri,
    String jsonBody, {
    required Duration timeout,
  }) async {
    await gate;
    return const DeclarativeLocalServiceResponse(status: 204, body: '');
  }
}

CompiledDeclarativeAction _compileLocal({
  Map<String, dynamic>? args,
  bool allowMissingPort = false,
}) =>
    const DeclarativeActionCompiler(
      declaredPermissions: {'network.localhost'},
    ).compileResolved(
      {
        'type': 'localService.post',
        'args':
            args ??
            {
              'port': 39700,
              'path': '/text/search',
              'body': {'q': 'נר שבת'},
              'pendingMessage': 'מחפש בבר אילן…',
              'unavailableMessage': 'שירות בר אילן אינו פועל',
              'timeoutMs': 60000,
            },
      },
      contextSignature: 'book-7',
      programGeneration: 7,
      allowMissingPort: allowMissingPort,
    );

class _BookOpener implements DeclarativeBookOpener {
  final identities = <Map<String, dynamic>>[];
  final sidePaneFlags = <bool>[];
  final externalMatches = <ExternalBookMatches?>[];

  @override
  Future<bool> openUnique(
    Map<String, dynamic> identity, {
    required int index,
    required String searchQuery,
    bool inSidePane = false,
    ExternalBookMatches? externalMatches,
  }) async {
    identities.add(identity);
    sidePaneFlags.add(inSidePane);
    this.externalMatches.add(externalMatches);
    return true;
  }
}

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
      permissions: const ['network.localhost'],
      networkEnabled: true,
      networkAllowlist: const ['127.0.0.1'],
      toolTabTitle: 'Declarative',
      toolTabOrder: 900,
      defaultPinned: false,
      publishedDataTypes: const [],
    ),
    installedAt: now,
    updatedAt: now,
  );
}
