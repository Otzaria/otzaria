import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/plugins/services/plugin_update_check_service.dart';
import 'package:otzaria/plugins/view/widgets/plugin_update_chip.dart';

import '../services/plugin_update_check_service_test.dart' show buildPlugin;

class MockPluginSystemBloc
    extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

const _downloadUrl = 'https://otzaria.org/api/plugins/abc@2.0.0/download';

PluginUpdateInfo update(String version) => PluginUpdateInfo(
  pluginId: 'org.a',
  version: version,
  downloadUrl: _downloadUrl,
);

/// קוביט אמיתי שמוזן מתשובת רשת מדומה עם עדכון ל-org.a גרסה 2.0.0.
Future<PluginUpdatesCubit> cubitWithUpdate() async {
  final cubit = PluginUpdatesCubit(
    service: PluginUpdateCheckService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'updates': [
              {
                'uid': 'org.a',
                'hasUpdate': true,
                'version': '2.0.0',
                'downloadUrl': '/api/plugins/abc@2.0.0/download',
              },
            ],
          }),
          200,
        ),
      ),
      updatesAllowedReader: () => true,
    ),
    appVersionLoader: () async => '0.9.97',
  );
  await cubit.ensureChecked([buildPlugin(pluginId: 'org.a')]);
  return cubit;
}

Widget harness({
  required PluginUpdatesCubit cubit,
  required PluginSystemBloc bloc,
  required Widget child,
}) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: MultiBlocProvider(
      providers: [
        BlocProvider<PluginUpdatesCubit>.value(value: cubit),
        BlocProvider<PluginSystemBloc>.value(value: bloc),
      ],
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  setUpAll(() {
    registerFallbackValue(const InstallRemotePluginRequested(''));
  });

  group('shouldShowUpdateChip', () {
    test('רק גרסה גבוהה ממש מהמותקנת מציגה צ\'יפ', () {
      expect(shouldShowUpdateChip(null, '1.0.0'), false);
      expect(shouldShowUpdateChip(update('2.0.0'), '1.0.0'), true);
      expect(shouldShowUpdateChip(update('1.0.0'), '1.0.0'), false);
      expect(shouldShowUpdateChip(update('1.0.0'), '2.0.0'), false);
      expect(shouldShowUpdateChip(update('abc'), '1.0.0'), false);
    });
  });

  testWidgets('הצ\'יפ מוצג, ולחיצה מזרימה את מסלול ההתקנה עם ה-URL', (
    tester,
  ) async {
    final cubit = await cubitWithUpdate();
    final bloc = MockPluginSystemBloc();
    whenListen(
      bloc,
      const Stream<PluginSystemState>.empty(),
      initialState: const PluginSystemLoaded([]),
    );

    await tester.pumpWidget(
      harness(
        cubit: cubit,
        bloc: bloc,
        child: PluginUpdateChip(plugin: buildPlugin(pluginId: 'org.a')),
      ),
    );

    expect(find.text('עדכון זמין'), findsOneWidget);
    await tester.tap(find.text('עדכון זמין'));
    verify(
      () => bloc.add(
        any(
          that: isA<InstallRemotePluginRequested>().having(
            (e) => e.downloadUrl,
            'downloadUrl',
            _downloadUrl,
          ),
        ),
      ),
    ).called(1);
    await cubit.close();
  });

  testWidgets('לחיצה על X מסתירה את הצ\'יפ', (tester) async {
    final cubit = await cubitWithUpdate();
    final bloc = MockPluginSystemBloc();
    whenListen(
      bloc,
      const Stream<PluginSystemState>.empty(),
      initialState: const PluginSystemLoaded([]),
    );

    await tester.pumpWidget(
      harness(
        cubit: cubit,
        bloc: bloc,
        child: PluginUpdateChip(plugin: buildPlugin(pluginId: 'org.a')),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.text('עדכון זמין'), findsNothing);
    await cubit.close();
  });

  testWidgets('אחרי עדכון מוצלח הצ\'יפ נעלם מעצמו (הגרסה המותקנת השתוותה)', (
    tester,
  ) async {
    final cubit = await cubitWithUpdate();
    final bloc = MockPluginSystemBloc();
    whenListen(
      bloc,
      const Stream<PluginSystemState>.empty(),
      initialState: const PluginSystemLoaded([]),
    );

    await tester.pumpWidget(
      harness(
        cubit: cubit,
        bloc: bloc,
        child: PluginUpdateChip(
          plugin: buildPlugin(pluginId: 'org.a', version: '2.0.0'),
        ),
      ),
    );

    expect(find.text('עדכון זמין'), findsNothing);
    await cubit.close();
  });
}
