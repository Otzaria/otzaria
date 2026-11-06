import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

class _FakeRepo implements PluginRegistryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingClient extends MockClient {
  _RecordingClient() : super((_) async => http.Response('archive', 200));

  int closeCount = 0;

  @override
  void close() {
    closeCount++;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '30 window lifetimes release their registered download clients',
    () async {
      final before = HttpClientRegistry.registeredCount;
      final clients = <_RecordingClient>[];
      final countsAfterClose = <int>[];
      addTearDown(HttpClientRegistry.closeAll);

      for (var cycle = 0; cycle < 30; cycle++) {
        final client = _RecordingClient();
        clients.add(client);
        final bloc = http.runWithClient(
          () => PluginSystemBloc(repository: _FakeRepo()),
          () => client,
        );
        await bloc.close();
        countsAfterClose.add(HttpClientRegistry.registeredCount);
      }

      expect(countsAfterClose, List.filled(30, before));
      expect(clients.map((client) => client.closeCount), everyElement(1));
    },
  );
}
