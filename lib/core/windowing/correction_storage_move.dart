import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/marker/storage/marker_database.dart';

class CorrectionStorageMovePreparation {
  const CorrectionStorageMovePreparation(this.requestId, this.peers);

  final String requestId;
  final List<int> peers;
}

Future<bool> synchronizeCorrectionStorageMoveDatabasePath(
  CorrectionStorageMovePreparation preparation,
  String? databasesPath,
) async {
  final replies = await Future.wait([
    for (final slot in preparation.peers)
      WindowBus.instance.request(
        slot,
        {
          'type': SettingsSync.requestChanged,
          'key': SettingsRepository.keyDatabasesPath,
          'value': databasesPath,
        },
        timeout: const Duration(seconds: 5),
      ),
  ]);
  return replies.every((reply) => reply == true) &&
      MultiWindowService.correctionQuitPeersUnchanged(preparation.peers);
}

Future<CorrectionStorageMovePreparation?> prepareCorrectionStorageMove() async {
  final corrections = PluginCorrectionSessionService.instance;
  final id =
      'storage-${WindowBus.instance.slot ?? 0}-${DateTime.now().microsecondsSinceEpoch}';
  final peers = WindowBus.instance.otherRegisteredSlots();
  if (!corrections.beginProcessQuitPreparation(id)) return null;
  try {
    if (await corrections.prepareForStorageMove(id)) {
      final replies = await Future.wait([
        for (final slot in peers)
          WindowBus.instance.request(
            slot,
            {
              'type': MultiWindowService.requestPrepareCorrectionStorageMove,
              'requestId': id,
            },
            timeout: const Duration(seconds: 20),
          ),
      ]);
      if (replies.every((reply) => reply == true) &&
          MultiWindowService.correctionQuitPeersUnchanged(peers)) {
        final finishedPeers = await Future.wait([
          for (final slot in peers)
            WindowBus.instance.request(
              slot,
              {
                'type': MultiWindowService.requestFinishCorrectionStorageMove,
                'requestId': id,
              },
              timeout: const Duration(seconds: 20),
            ),
        ]);
        if (finishedPeers.every((reply) => reply == true) &&
            MultiWindowService.correctionQuitPeersUnchanged(peers) &&
            await corrections.finishStorageMovePreparation(id)) {
          return CorrectionStorageMovePreparation(id, peers);
        }
      }
    }
  } catch (error, stackTrace) {
    debugPrint(
      'Correction storage move preparation failed: $error\n$stackTrace',
    );
  }
  await releaseCorrectionStorageMove(
    CorrectionStorageMovePreparation(id, peers),
  );
  return null;
}

Future<void> releaseCorrectionStorageMove(
  CorrectionStorageMovePreparation preparation,
) async {
  final databasesPath = Settings.getValue<String>(
    SettingsRepository.keyDatabasesPath,
  );
  if (!await synchronizeCorrectionStorageMoveDatabasePath(
    preparation,
    databasesPath,
  )) {
    debugPrint(
      'Correction storage move could not synchronize the database path; '
      'windows remain locked for safety.',
    );
    return;
  }
  PluginSystemDatabase.instance.releaseStorageMove(preparation.requestId);
  MarkerDatabase.instance.releaseStorageMove(preparation.requestId);
  PluginCorrectionSessionService.instance.cancelProcessQuitPreparation(
    preparation.requestId,
  );
  await Future.wait([
    for (final slot in preparation.peers)
      WindowBus.instance.request(
        slot,
        {
          'type': MultiWindowService.requestCancelCorrectionQuit,
          'requestId': preparation.requestId,
        },
        timeout: MultiWindowService.correctionQuitRequestTimeout,
      ),
  ]);
}
