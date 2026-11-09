import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/settings/services/manual_update_check.dart';
import 'package:otzaria/update/updat_compat.dart';

class _FakeLibraryUpdateBloc implements LibraryUpdateBloc {
  _FakeLibraryUpdateBloc(
    this.script, {
    this.state = const LibraryUpdateState(),
  });

  /// המצבים שהבלוק פולט אחרי [StartLibraryUpdate].
  final List<LibraryUpdateState> script;
  final events = <LibraryUpdateEvent>[];
  final _controller = StreamController<LibraryUpdateState>.broadcast();

  @override
  LibraryUpdateState state;

  @override
  Stream<LibraryUpdateState> get stream => _controller.stream;

  @override
  bool Function() get isOfflineMode =>
      () => false;

  @override
  bool Function() get areUpdatesEnabled =>
      () => true;

  @override
  void add(LibraryUpdateEvent event) {
    events.add(event);
    scheduleMicrotask(() {
      for (final next in script) {
        state = next;
        _controller.add(next);
      }
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _checking = LibraryUpdateState(status: LibraryUpdateStatus.checking);

void main() {
  group('softwareUpdateCheckMessage', () {
    Future<String?> message(UpdatStatus? status) =>
        softwareUpdateCheckMessage(() async => status);

    test('says the software is current or that an update was found', () async {
      expect(
        await message(UpdatStatus.upToDate),
        SettingsMessages.softwareUpToDate,
      );
      expect(
        await message(UpdatStatus.availableWithChangelog),
        SettingsMessages.softwareUpdateFound,
      );
    });

    test('says nothing when the check gave no answer', () async {
      expect(await message(null), isNull);
    });
  });

  group('libraryUpdateCheckMessage', () {
    test('starts the same update as the toolbar button', () async {
      final bloc = _FakeLibraryUpdateBloc([
        _checking,
        const LibraryUpdateState(status: LibraryUpdateStatus.completed),
      ]);

      expect(
        await libraryUpdateCheckMessage(bloc),
        SettingsMessages.libraryUpToDate,
      );
      expect(bloc.events, [const StartLibraryUpdate()]);
    });

    test('is quiet when an update was applied or the check failed', () async {
      final applied = _FakeLibraryUpdateBloc([
        _checking,
        const LibraryUpdateState(
          status: LibraryUpdateStatus.completed,
          hasUpdate: true,
        ),
      ]);
      expect(await libraryUpdateCheckMessage(applied), isNull);

      final failed = _FakeLibraryUpdateBloc([
        _checking,
        const LibraryUpdateState(status: LibraryUpdateStatus.error),
      ]);
      expect(await libraryUpdateCheckMessage(failed), isNull);
    });

    test('does not start a second update while one is running', () async {
      final bloc = _FakeLibraryUpdateBloc(const [], state: _checking);

      expect(await libraryUpdateCheckMessage(bloc), isNull);
      expect(bloc.events, isEmpty);
    });
  });
}
