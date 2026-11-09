import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/ios_font_probe.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  pinIosSimulatorSemantics(binding);

  testWidgets('the Simulator enabling semantics mid-test leaves no handle', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    // The iOS Simulator engine reports semantics as enabled after startup.
    binding.platformDispatcher.semanticsEnabledTestValue = true;
    expect(binding.semanticsEnabled, isTrue);
  });
}
