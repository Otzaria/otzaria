import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/installed_plugin_memory_pressure.dart';

class _PressureObserver extends WidgetsBindingObserver {
  _PressureObserver(this.name, this.events);

  final String name;
  final List<String> events;

  @override
  void didHaveMemoryPressure() => events.add(name);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'system pressure notifies existing observers before its reply',
    () async {
      final events = <String>[];
      final first = _PressureObserver('first', events);
      final second = _PressureObserver('second', events);
      binding.addObserver(first);
      binding.addObserver(second);
      try {
        await notifyInstalledPluginMemoryPressure();
        events.add('acknowledged');
        expect(events, ['first', 'second', 'acknowledged']);

        // A second message still reaches the installed framework handler.
        events.clear();
        await notifyInstalledPluginMemoryPressure();
        events.add('acknowledged');
        expect(events, ['first', 'second', 'acknowledged']);
      } finally {
        binding.removeObserver(second);
        binding.removeObserver(first);
      }
    },
  );
}
