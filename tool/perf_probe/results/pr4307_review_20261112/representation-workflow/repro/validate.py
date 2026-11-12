#!/usr/bin/env python3
"""Recheck this evidence bundle without building or timing either application."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

import yaml


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--actionlint', default='actionlint')
    parser.add_argument('--pwsh', default='pwsh')
    parser.add_argument('--repo', type=Path, help='Optional local repository containing the pinned candidate; enables mocked cleanup contracts.')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    metadata = json.loads((bundle / 'bundle.json').read_text())
    results = {'scope': 'Evidence/schema/PowerShell and optional mocked orchestration checks only. No Flutter tests, app build, or performance measurement.', 'checks': []}

    def run(name, command, *, cwd=None, env=None, expected=0):
        process = subprocess.run(command, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (output / (name + '.log')).write_text(process.stdout)
        results['checks'].append({'name': name, 'exit_code': process.returncode, 'expected_exit_code': expected})
        if process.returncode != expected:
            raise RuntimeError(f'{name}: expected {expected}, got {process.returncode}; inspect its log')
        return process.stdout

    for item in metadata['files']:
        contents = (bundle / item['path']).read_bytes()
        if len(contents) != item['bytes'] or hashlib.sha256(contents).hexdigest() != item['sha256']:
            raise RuntimeError('Bundle hash mismatch: ' + item['path'])
    for version in ('v1', 'v2'):
        archive = json.loads((bundle / 'publications' / ('manifest-' + version + '.json')).read_text())
        restored = archive['manifest']
        restored['files'][0]['content'] = (bundle / archive['embedded_content_file']).read_text()
        original = (json.dumps(restored, indent=2, ensure_ascii=False) + '\n').encode()
        if hashlib.sha256(original).hexdigest() != archive['original_json_sha256']:
            raise RuntimeError('Publication manifest reconstruction failed: ' + version)
    old = yaml.load((bundle / 'workflows/v1.yml').read_text(), Loader=yaml.BaseLoader)
    new = yaml.load((bundle / 'workflows/v2.yml').read_text(), Loader=yaml.BaseLoader)
    if old['jobs']['paired-profile']['steps'][1:] != new['jobs']['paired-profile']['steps'][1:]:
        raise RuntimeError('A step after setup changed')
    for key, value in new['jobs']['paired-profile']['env'].items():
        if value != old['jobs']['paired-profile']['env'][key]:
            raise RuntimeError('Source or sampling configuration changed')
    run('actionlint-v1', [args.actionlint, str(bundle / 'workflows/v1.yml')], expected=1)
    run('actionlint-v2', [args.actionlint, str(bundle / 'workflows/v2.yml')])
    blocks = []
    for index, step in enumerate(new['jobs']['paired-profile']['steps']):
        if 'run' not in step:
            continue
        target = output / f'block-{index:02d}.ps1'
        target.write_text(step['run'])
        blocks.append({'name': step['name'], 'path': str(target)})
    block_index = output / 'powershell-blocks.json'
    block_index.write_text(json.dumps(blocks, indent=2) + '\n')
    run('powershell-parse', [args.pwsh, '-NoProfile', '-File', str(bundle / 'repro/validate-powershell.ps1'), str(block_index)])
    setup_env = os.environ.copy()
    setup_env.pop('VALIDATION_ROOT', None)
    setup_env.pop('COMPARISON_ROOT', None)
    setup_temp = output / 'setup-temp'
    setup_temp.mkdir()
    github_env = output / 'github-env.txt'
    github_env.write_text('')
    setup_env.update(new['jobs']['paired-profile']['env'])
    setup_env.update(RUNNER_TEMP=str(setup_temp), GITHUB_ENV=str(github_env), GIT_CONFIG_GLOBAL=str(output / 'gitconfig'), WORKFLOW_SHA=metadata['workflow_v2_commit'])
    run('setup-contract', [args.pwsh, '-NoProfile', '-File', str(output / 'block-00.ps1')], env=setup_env)
    exported = dict(line.split('=', 1) for line in github_env.read_text().splitlines())
    expected_paths = {'VALIDATION_ROOT': str(setup_temp / 'reader-representation-validation'), 'COMPARISON_ROOT': str(setup_temp / 'reader-representation-profile')}
    if exported != expected_paths:
        raise RuntimeError('The setup did not export both expected paths')
    plan = json.loads((Path(exported['VALIDATION_ROOT']) / 'experiment-plan.json').read_text(encoding='utf-8-sig'))
    if (plan['measuredSamplesPerActionAndSide'], plan['processesPerSide']) != (16, 4):
        raise RuntimeError('Unexpected sample counts')

    if args.repo:
        repository = args.repo.resolve()
        with tempfile.TemporaryDirectory(prefix='reader-workflow-contract-') as temporary:
            checkout = Path(temporary) / 'candidate'
            subprocess.run(['git', '-C', str(repository), 'worktree', 'add', '--detach', str(checkout), metadata['candidate_commit']], check=True)
            try:
                for fail in (False, True):
                    name = 'mocked-tests-fail' if fail else 'mocked-tests-pass'
                    case = output / name
                    (case / 'temp').mkdir(parents=True)
                    (case / 'artifacts').mkdir()
                    env = os.environ.copy()
                    env.update(RUNNER_TEMP=str(case / 'temp'), VALIDATION_ROOT=str(case / 'artifacts'), CONTROL_SHA=metadata['candidate_commit'], CONTROL_BLOC_SHA256=metadata['mock_contract_candidate_bloc_sha256'], SIMULATE_TEST_FAILURE=str(fail).lower())
                    run(name, [args.pwsh, '-NoProfile', '-File', str(bundle / 'contracts/orchestration.ps1')], cwd=checkout, env=env, expected=1 if fail else 0)
                    proof = json.loads((case / 'artifacts/control-validation.json').read_text())
                    if not all(proof[key] for key in ('originalUnchanged', 'generatedRemoved', 'cleanSource')):
                        raise RuntimeError('Mocked cleanup failed: ' + name)
            finally:
                subprocess.run(['git', '-C', str(repository), 'worktree', 'remove', '--force', str(checkout)], check=True)
    results['status'] = 'passed'
    (output / 'reproduction-result.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
