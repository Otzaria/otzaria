/// Scheduling identity is part of the comparison, not a performance threshold.
enum PerfBindingMode {
  integration(
    target: 'integration_test/perf_resource_probe_test.dart',
    bindingClass: 'IntegrationTestWidgetsFlutterBinding',
    framePolicy: 'fullyLive',
    platformDispatcher: 'test',
  ),
  framework(
    target: 'tool/perf_probe/framework_pdf_probe.dart',
    bindingClass: 'WidgetsFlutterBinding',
    framePolicy: 'frameworkRequested',
    platformDispatcher: 'native',
  );

  const PerfBindingMode({
    required this.target,
    required this.bindingClass,
    required this.framePolicy,
    required this.platformDispatcher,
  });

  final String target;
  final String bindingClass;
  final String framePolicy;
  final String platformDispatcher;

  static PerfBindingMode parse(String value) => switch (value) {
    'integration' => integration,
    'framework' => framework,
    _ => throw ArgumentError.value(value, 'bindingMode'),
  };

  void validateScenario(String scenario) {
    if (!const {'all', 'pdf-reader', 'pdf-book-view'}.contains(scenario) ||
        (this == framework && scenario == 'all')) {
      throw ArgumentError(
        'The $name binding does not support scenario "$scenario". '
        'The framework target accepts pdf-reader or pdf-book-view.',
      );
    }
  }

  Map<String, Object?> toComparisonJson() => {
    'bindingMode': name,
    'bindingClass': bindingClass,
    'framePolicy': framePolicy,
    'platformDispatcher': platformDispatcher,
    'probeTarget': target,
  };

  List<String> get limitations => switch (this) {
    integration => const [
      'Post-close observation means no user actions under the integration binding, not quiescent production idle.',
      'The fullyLive integration binding schedules continuous frames; CPU and frame samples include that harness work.',
    ],
    framework => const [
      'Frame scheduling uses unmodified WidgetsFlutterBinding and the native platform dispatcher.',
      'Action readiness requests explicit boundary frames through LiveWidgetController; the post-close observation requests none.',
      'Post-close means no user actions, not a guarantee of zero application or OS work; all observed frames and CPU remain in the report.',
    ],
  };
}
