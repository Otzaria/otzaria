import datetime
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / 'results'
OUT.mkdir(exist_ok=True)
EXECUTABLE = ROOT.parent / 'benchmark'

def read_optional(path):
    try:
        return Path(path).read_text().strip()
    except (FileNotFoundError, PermissionError):
        return None

cpu = next((line.split(':', 1)[1].strip() for line in (read_optional('/proc/cpuinfo') or '').splitlines()
            if line.startswith('model name')), None)
metadata = {
    'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'platform': platform.platform(), 'cpu_model': cpu, 'visible_cpus': os.cpu_count(),
    'cpu_quota': read_optional('/sys/fs/cgroup/cpu.max'),
    'memory_limit': read_optional('/sys/fs/cgroup/memory.max'),
    'command': './benchmark PROCESS_INDEX 8',
    'separate_processes': 4, 'samples_per_side_per_process_per_case': 8,
    'warmups': 'one correctness preflight plus four explicit warmups per side per case in every process',
    'order': 'ABBA/BAAB alternating blocks, initial orientation alternates by process',
    'percentile': 'nearest rank ceil(p*n); all samples retained',
    'gc': 'natural AOT GC included in timings; no forced GC in timed operations',
    'binary_sha256': hashlib.sha256(EXECUTABLE.read_bytes()).hexdigest(),
    'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(ROOT.iterdir()) if p.is_file()},
}
(OUT / 'environment.json').write_text(json.dumps(metadata, indent=2))
for process in range(4):
    with (OUT / f'timing-process-{process}.jsonl').open('w') as out, (OUT / f'timing-process-{process}.stderr').open('w') as err:
        subprocess.run([str(EXECUTABLE), str(process), '8'], stdout=out, stderr=err, check=True)
    print(f'Completed process {process + 1}/4', flush=True)

groups = {}
for process in range(4):
    rows = [json.loads(line) for line in (OUT / f'timing-process-{process}.jsonl').read_text().splitlines()]
    assert len([r for r in rows if r.get('source_snapshot_checks_passed')]) == 3
    for row in rows:
        if 'case' not in row:
            continue
        assert row['all_outputs_equal_before_timing']
        key = (row['lines'], row['case'])
        group = groups.setdefault(key, {'lines': row['lines'], 'case': row['case'], 'scope': row['scope'], 'operations_per_sample': row['operations_per_sample'], 'processes': []})
        assert all(len(samples) == 8 for samples in row['samples_us'].values())
        group['processes'].append(row)

summary = []
for key in sorted(groups):
    group = groups[key]
    result = {k: v for k, v in group.items() if k != 'processes'}
    for side in ['baseline', 'candidate']:
        samples = [n for process in group['processes'] for n in process['samples_us'][side]]
        ordered = sorted(samples)
        assert len(samples) == 32
        result[side] = {'n': len(samples), 'median_us': statistics.median(samples), 'p95_us': ordered[math.ceil(.95 * len(ordered)) - 1],
                        'min_us': ordered[0], 'max_us': ordered[-1],
                        'process_medians_us': [statistics.median(p['samples_us'][side]) for p in group['processes']]}
    result['candidate_over_baseline'] = result['candidate']['median_us'] / result['baseline']['median_us']
    summary.append(result)
(OUT / 'timing-summary.json').write_text(json.dumps({'unit': 'microseconds_per_operation', 'cases': summary}, indent=2))
metadata['completed_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
(OUT / 'environment.json').write_text(json.dumps(metadata, indent=2))
print(json.dumps({'completed_cases': len(summary), 'output': str(OUT / 'timing-summary.json')}))
