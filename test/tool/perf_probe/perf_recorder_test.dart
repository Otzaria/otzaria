import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;

import '../../../integration_test/support/perf_recorder.dart';

FrameTiming frame({required int buildEpochUs, int engineOrigin = 100000}) =>
    FrameTiming(
      vsyncStart: engineOrigin,
      buildStart: engineOrigin + 1000,
      buildFinish: engineOrigin + 3000,
      rasterStart: engineOrigin + 3500,
      rasterFinish: engineOrigin + 7000,
      rasterFinishWallTime: buildEpochUs + 6000,
    );

class _HeapService extends Fake implements vm.VmService {
  _HeapService(this.inventory, this.memory);

  final vm.VM inventory;
  final Map<String, vm.MemoryUsage> memory;
  final groupRequests = <String>[];
  final errors = <String, Object>{};
  final inventoryErrors = <Object>[];

  @override
  Future<vm.VM> getVM() async {
    if (inventoryErrors.isNotEmpty) {
      throw inventoryErrors.removeAt(0);
    }
    return inventory;
  }

  @override
  Future<vm.MemoryUsage> getIsolateGroupMemoryUsage(
    String isolateGroupId,
  ) async {
    groupRequests.add(isolateGroupId);
    final error = errors[isolateGroupId];
    if (error != null) {
      throw error;
    }
    return memory[isolateGroupId]!;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('frame windows use engine wall timestamps, not callback arrival', () {
    final before = frame(buildEpochUs: 99999);
    final first = frame(buildEpochUs: 100000);
    final last = frame(buildEpochUs: 199999, engineOrigin: 9000000);
    final after = frame(buildEpochUs: 200000);
    final delayedBatch = [after, last, before, first];
    expect(frameBuildEpochUs(last), 199999);
    expect(framesInWindow(delayedBatch, 100000, 200000), [last, first]);
    expect(frameMeasurements([first]), {
      'count': 1,
      'buildMs': [2.0],
      'rasterMs': [3.5],
      'totalMs': [7.0],
    });
  });

  test(
    'an interval with no frames remains missing, not a zero-duration frame',
    () {
      final result = frameMeasurements([]);
      expect(result['count'], 0);
      expect(result['buildMs'], isEmpty);
      expect(result['unavailableReason'], isNotNull);
    },
  );

  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'perf-recorder-test-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('failed actions are persisted as failed and still propagate', () async {
    final file = File('${directory.path}/phases.jsonl');
    final recorder = PerfRecorder(file, binding, launchIndex: 4);
    final error = StateError('A real failure');
    try {
      await expectLater(
        recorder.phase('open', () async => throw error, sampleHeap: false),
        throwsA(same(error)),
      );
    } finally {
      await recorder.dispose();
    }
    final record =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(record['status'], 'failed');
    expect(record['error'], contains('A real failure'));
    expect(record['launchIndex'], 4);
    expect(record['heapBefore'], isNull);
    expect(record['heapUnavailableReason'], isNotNull);
  });

  test(
    'an asynchronously captured application error fails its phase',
    () async {
      final file = File('${directory.path}/phases.jsonl');
      final recorder = PerfRecorder(file, binding, launchIndex: 0);
      recorder.verifyAction = () => throw StateError('Captured widget error');
      try {
        await expectLater(
          recorder.phase('render', () async {}, sampleHeap: false),
          throwsStateError,
        );
      } finally {
        await recorder.dispose();
      }
      final record =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(record['status'], 'failed');
      expect(record['error'], contains('Captured widget error'));
    },
  );

  test(
    'warmup and explicit unavailable phases cannot masquerade as samples',
    () async {
      final file = File('${directory.path}/phases.jsonl');
      final recorder = PerfRecorder(file, binding, launchIndex: 0);
      try {
        await recorder.phase(
          'warm',
          () async {},
          warmup: true,
          iteration: 2,
          sampleHeap: false,
        );
        await recorder.phase(
          'unsupported',
          () async => throw const PerfSkipped('No device'),
          sampleHeap: false,
        );
      } finally {
        await recorder.dispose();
      }
      final records = (await file.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(records[0]['warmup'], isTrue);
      expect(records[0]['iteration'], 2);
      expect(records[1]['status'], 'skipped');
      expect(records[1]['reason'], 'No device');
    },
  );

  test(
    'heap sums each shared isolate group once and preserves raw samples',
    () async {
      final service = _HeapService(
        vm.VM(
          isolates: [
            vm.IsolateRef(id: 'main', isolateGroupId: 'shared'),
            vm.IsolateRef(id: 'worker', isolateGroupId: 'shared'),
            vm.IsolateRef(id: 'other', isolateGroupId: 'separate'),
          ],
          isolateGroups: [
            vm.IsolateGroupRef(id: 'shared'),
            vm.IsolateGroupRef(id: 'shared'),
            vm.IsolateGroupRef(id: 'separate'),
          ],
        ),
        {
          'shared': vm.MemoryUsage(
            heapUsage: 100,
            heapCapacity: 200,
            externalUsage: 10,
          ),
          'separate': vm.MemoryUsage(
            heapUsage: 300,
            heapCapacity: 400,
            externalUsage: 20,
          ),
        },
      );
      final sampler = PerfHeapSampler(service: service);
      final sample = await sampler.sample();
      expect(service.groupRequests, ['shared', 'separate']);
      expect(sample, {
        'heapUsage': 400,
        'heapCapacity': 600,
        'externalUsage': 30,
        'isolateCount': 3,
        'isolateGroupCount': 2,
        'aggregation': 'unique-application-isolate-groups',
        'measurement': 'current-usage-without-forced-gc',
        'isolateGroups': [
          {
            'id': 'shared',
            'isolateIds': ['main', 'worker'],
            'heapUsage': 100,
            'heapCapacity': 200,
            'externalUsage': 10,
          },
          {
            'id': 'separate',
            'isolateIds': ['other'],
            'heapUsage': 300,
            'heapCapacity': 400,
            'externalUsage': 20,
          },
        ],
      });
      expect(sampler.unavailableReason, isNull);
    },
  );

  test('heap excludes system isolates and system groups', () async {
    final service = _HeapService(
      vm.VM(
        isolates: [
          vm.IsolateRef(id: 'main', isolateGroupId: 'app'),
          vm.IsolateRef(
            id: 'system-isolate',
            isolateGroupId: 'app',
            isSystemIsolate: true,
          ),
          vm.IsolateRef(id: 'system-group-member', isolateGroupId: 'system'),
          vm.IsolateRef(
            id: 'separate-system-member',
            isolateGroupId: 'separate-system',
          ),
        ],
        isolateGroups: [
          vm.IsolateGroupRef(id: 'app'),
          vm.IsolateGroupRef(id: 'system', isSystemIsolateGroup: true),
        ],
        systemIsolateGroups: [vm.IsolateGroupRef(id: 'separate-system')],
      ),
      {'app': vm.MemoryUsage(heapUsage: 7, heapCapacity: 9, externalUsage: 1)},
    );
    final sample = await PerfHeapSampler(service: service).sample();
    expect(service.groupRequests, ['app']);
    expect(sample?['heapUsage'], 7);
    expect(sample?['isolateCount'], 1);
    expect(sample?['isolateGroupCount'], 1);
  });

  for (final entry in <String, vm.VM>{
    'missing group inventory': vm.VM(
      isolates: [vm.IsolateRef(id: 'main', isolateGroupId: 'app')],
    ),
    'missing isolate inventory': vm.VM(
      isolateGroups: [vm.IsolateGroupRef(id: 'app')],
    ),
    'unknown group': vm.VM(
      isolates: [vm.IsolateRef(id: 'main', isolateGroupId: 'unknown')],
      isolateGroups: [vm.IsolateGroupRef(id: 'app')],
    ),
    'missing group id': vm.VM(
      isolates: [vm.IsolateRef(id: 'main')],
      isolateGroups: [vm.IsolateGroupRef(id: 'app')],
    ),
    'empty group id': vm.VM(
      isolates: [vm.IsolateRef(id: 'main', isolateGroupId: '')],
      isolateGroups: [vm.IsolateGroupRef(id: '')],
    ),
  }.entries) {
    test('heap remains unavailable for ${entry.key}', () async {
      final service = _HeapService(entry.value, {});
      final sampler = PerfHeapSampler(service: service);
      expect(await sampler.sample(), isNull);
      expect(sampler.unavailableReason, startsWith('Heap sample unavailable'));
      expect(service.groupRequests, isEmpty);
    });
  }

  test(
    'heap never returns partial totals after a group error or incomplete sample',
    () async {
      final service = _HeapService(
        vm.VM(
          isolates: [
            vm.IsolateRef(id: 'first', isolateGroupId: 'a'),
            vm.IsolateRef(id: 'second', isolateGroupId: 'b'),
          ],
          isolateGroups: [
            vm.IsolateGroupRef(id: 'a'),
            vm.IsolateGroupRef(id: 'b'),
          ],
        ),
        {
          'a': vm.MemoryUsage(
            heapUsage: 10,
            heapCapacity: 20,
            externalUsage: 1,
          ),
          'b': vm.MemoryUsage(heapUsage: 30, externalUsage: 2),
        },
      );
      final sampler = PerfHeapSampler(service: service);
      expect(await sampler.sample(), isNull);
      expect(
        sampler.unavailableReason,
        contains('Incomplete VM group memory sample: b'),
      );
      service.errors['b'] = StateError('group exited');
      expect(await sampler.sample(), isNull);
      expect(sampler.unavailableReason, contains('group exited'));
      service.errors.clear();
      service.memory['b'] = vm.MemoryUsage(
        heapUsage: 30,
        heapCapacity: 50,
        externalUsage: 2,
      );
      expect((await sampler.sample())?['heapUsage'], 40);
      expect(sampler.unavailableReason, isNull);
    },
  );

  test(
    'a failed heap-before reason survives successful heap-after sampling',
    () async {
      final service = _HeapService(
        vm.VM(
          isolates: [vm.IsolateRef(id: 'main', isolateGroupId: 'app')],
          isolateGroups: [vm.IsolateGroupRef(id: 'app')],
        ),
        {
          'app': vm.MemoryUsage(
            heapUsage: 10,
            heapCapacity: 20,
            externalUsage: 0,
          ),
        },
      )..inventoryErrors.add(StateError('inventory unavailable before action'));
      final file = File('${directory.path}/heap-recovery.jsonl');
      final recorder = PerfRecorder(
        file,
        binding,
        launchIndex: 0,
        heap: PerfHeapSampler(service: service),
      );
      try {
        await recorder.phase('heap-recovery', () async {});
      } finally {
        await recorder.dispose();
      }
      final row = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(row['heapBefore'], isNull);
      expect(row['heapAfter']['heapUsage'], 10);
      expect(
        row['heapUnavailableReason'],
        contains('inventory unavailable before action'),
      );
    },
  );
}
