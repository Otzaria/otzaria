import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_semantic_status_publisher.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';

void main() {
  tearDown(PluginSemanticStatusPublisher.stopForTesting);

  test('נשלח רק כשהשלב שתוסף רואה משתנה', () async {
    final changes = StreamController<SemanticAvailability>();
    final sent = <Map<String, dynamic>>[];
    PluginSemanticStatusPublisher.start(
      changes: changes.stream,
      sink: (topic, payload) async {
        expect(topic, PluginSemanticStatusPublisher.topic);
        sent.add(payload);
      },
    );

    for (final availability in const [
      SemanticAvailability(
        phase: SemanticAvailabilityPhase.downloading,
        consentGranted: true,
      ),
      SemanticAvailability(
        phase: SemanticAvailabilityPhase.downloading,
        consentGranted: true,
        progress: SemanticDownloadProgress(
          item: SemanticDownloadItem.vectors,
          receivedBytes: 10,
        ),
      ),
      SemanticAvailability(
        phase: SemanticAvailabilityPhase.ready,
        consentGranted: true,
      ),
      SemanticAvailability(
        phase: SemanticAvailabilityPhase.ready,
        consentGranted: false,
      ),
    ]) {
      changes.add(availability);
    }
    await pumpEventQueue();

    expect(sent, [
      {'phase': 'downloading'},
      {'phase': 'ready'},
      {'phase': 'consentRequired'},
    ]);
    await changes.close();
  });
}
