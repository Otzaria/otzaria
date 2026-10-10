import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/view/plugin_actions.dart';
import 'package:otzaria/plugins/view/plugin_settings_screen.dart';

class _RecordingPluginSystemBloc
    extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  final recorded = <PluginSystemEvent>[];

  _RecordingPluginSystemBloc() : super(PluginSystemInitial()) {
    on<PluginSystemEvent>((event, _) => recorded.add(event));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'תוסף בדיקה',
  version: '1.0.0',
  installPath: '/tmp/test.plugin',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': 'test.plugin',
    'name': 'תוסף בדיקה',
    'version': '1.0.0',
    'entrypoint': 'index.html',
  }),
);

Future<void> _pumpAction(
  WidgetTester tester,
  PluginSystemBloc bloc,
  void Function(BuildContext) action,
) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('he', 'IL'),
    supportedLocales: const [Locale('he', 'IL')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: BlocProvider<PluginSystemBloc>.value(
      value: bloc,
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => action(context),
            child: const Text('הפעל פעולה'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final confirmed in [true, false]) {
    testWidgets(
      confirmed
          ? 'איפוס נתוני התוסף שולח אירוע רק אחרי אישור'
          : 'ביטול איפוס נתוני התוסף אינו שולח אירוע',
      (tester) async {
        final bloc = _RecordingPluginSystemBloc();
        addTearDown(bloc.close);
        Future<bool>? result;
        await _pumpAction(tester, bloc, (context) {
          result = showResetPluginDataDialog(context, _plugin());
        });

        await tester.tap(find.text('הפעל פעולה'));
        await tester.pumpAndSettle();

        expect(find.text('איפוס נתוני התוסף'), findsOneWidget);
        expect(
          find.text('האם לאפס את כל הנתונים של התוסף "תוסף בדיקה"?'),
          findsOneWidget,
        );
        expect(bloc.recorded, isEmpty);

        await tester.tap(find.text(confirmed ? 'אפס' : 'ביטול'));
        await tester.pumpAndSettle();

        expect(await result!, confirmed);
        if (confirmed) {
          expect(bloc.recorded, hasLength(1));
          expect(
            (bloc.recorded.single as ResetPluginDataRequested).pluginId,
            'test.plugin',
          );
        } else {
          expect(bloc.recorded, isEmpty);
        }
      },
    );
  }

  testWidgets('השבתת תוסף פעיל שולחת DisablePluginRequested', (
    tester,
  ) async {
    final bloc = _RecordingPluginSystemBloc();
    addTearDown(bloc.close);
    await _pumpAction(
      tester,
      bloc,
      (context) => togglePluginEnabled(context, _plugin()),
    );

    await tester.tap(find.text('הפעל פעולה'));
    await tester.pump();

    expect(bloc.recorded, hasLength(1));
    expect(
      (bloc.recorded.single as DisablePluginRequested).pluginId,
      'test.plugin',
    );
  });
}
