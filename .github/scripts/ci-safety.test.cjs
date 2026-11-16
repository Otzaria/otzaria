'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const workflows = path.join(__dirname, '../workflows');
function scripts(file) {
  const lines = readFileSync(path.join(workflows, file), 'utf8').split('\n');
  return lines.flatMap((line, index) => {
    const match = line.match(/^( +)run: \|$/);
    if (!match) return [];
    const indent = match[1].length + 2;
    const body = [];
    for (const next of lines.slice(index + 1)) {
      if (next.trim() && next.search(/\S/) < indent) break;
      body.push(next.slice(indent));
    }
    return [body.join('\n')];
  });
}
const mergeScript = scripts('automerge.yml')[1];
const revertScript = scripts('dev_health.yml')[0];

function check(name, suite, conclusion = 'success', id = suite * 10) {
  return { id, name, check_suite: { id: suite }, app: { slug: 'github-actions' },
    status: conclusion === null ? 'queued' : 'completed', conclusion,
    started_at: new Date(Date.parse('2026-11-16T10:00:00Z') + id * 1000).toISOString() };
}
function workflow(id, suite, conclusion = 'success', number = 1) {
  return { id: suite, workflow_id: id, check_suite_id: suite, event: 'pull_request',
    run_number: number, status: conclusion === null ? 'queued' : 'completed', conclusion };
}
function fixture(t, overrides = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'otzaria-ci-safety-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const bin = path.join(dir, 'bin'); mkdirSync(bin);
  const data = {
    pr: { state: 'open', draft: false, labels: [{ name: 'automerge' }, { name: 'run-ci' }],
      head: { sha: 'pr-head' }, base: { ref: 'dev' } },
    devHead: 'dev-head', devHeads: [], behind: 0,
    devRuns: [{ head_sha: 'dev-head', status: 'completed', conclusion: 'success' }],
    workflowRuns: [workflow(1, 10)], checks: [check('CI result', 10)],
    originalPr: { merge_commit_sha: 'squash', commits: 3 }, ...overrides,
  };
  const fixturePath = path.join(dir, 'fixture.json');
  writeFileSync(fixturePath, JSON.stringify(data));
  writeFileSync(path.join(bin, 'gh'), `#!/usr/bin/env node
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const args = process.argv.slice(2);
const file = process.env.CI_SAFETY_FIXTURE;
const data = JSON.parse(fs.readFileSync(file, 'utf8'));
fs.appendFileSync(process.env.CI_SAFETY_CALLS, JSON.stringify(args) + '\\n');
let value;
if (args[0] === 'api') {
  const route = args.find(arg => arg.startsWith('repos/'));
  if (route.endsWith('/pulls/42')) value = data.originalPr;
  else if (/\\/pulls\\/\\d+$/.test(route)) value = data.pr;
  else if (route.includes('/permission')) value = { permission: 'write' };
  else if (route.includes('/git/ref/heads/')) {
    value = { object: { sha: data.devHeads.shift() ?? data.devHead } };
    fs.writeFileSync(file, JSON.stringify(data));
  } else if (route.includes('/actions/workflows/flutter_tests.yml/runs?')) {
    const query = new URLSearchParams(route.split('?')[1]);
    let runs = data.devRuns;
    if (query.has('head_sha')) runs = runs.filter(run => run.head_sha === query.get('head_sha'));
    if (query.has('status')) runs = runs.filter(run => run.status === query.get('status'));
    value = { workflow_runs: runs };
  } else if (route.includes('/actions/runs?')) value = { workflow_runs: data.workflowRuns };
  else if (route.includes('/check-runs?')) value = { check_runs: data.checks };
  else if (route.endsWith('/status')) value = { total_count: 0, state: 'pending' };
  else if (route.includes('/compare/')) value = { behind_by: data.behind };
  else throw new Error('Unexpected API route: ' + route);
} else if (args[0] === 'pr' && args[1] === 'merge') value = 'merged';
else throw new Error('Unexpected gh command: ' + args.join(' '));
const queryIndex = args.indexOf('--jq');
if (queryIndex >= 0) {
  const result = spawnSync('jq', ['-r', args[queryIndex + 1]], { input: JSON.stringify(value), encoding: 'utf8' });
  process.stdout.write(result.stdout); process.stderr.write(result.stderr); process.exit(result.status);
}
console.log(JSON.stringify(value));
`, { mode: 0o755 });
  const callsFile = path.join(dir, 'calls.jsonl');
  const env = { ...process.env, PATH: bin + path.delimiter + process.env.PATH,
    CI_SAFETY_FIXTURE: fixturePath, CI_SAFETY_CALLS: callsFile,
    GITHUB_REPOSITORY: 'Otzaria/otzaria', RUNNER_TEMP: dir, GH_TOKEN: 'test-only',
    PR: '17', ACTION: 'labeled', ADDED_LABEL: 'automerge', SENDER: 'maintainer' };
  return { dir, data, env,
    execute(script = mergeScript, extraEnv = {}) {
      const result = spawnSync('bash', ['-c', script], { env: { ...env, ...extraEnv }, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stdout + result.stderr);
      return result.stdout;
    },
    calls: () => existsSync(callsFile) ? readFileSync(callsFile, 'utf8').trim().split('\n').map(JSON.parse) : [],
    merged() { return this.calls().some(args => args[0] === 'pr' && args[1] === 'merge'); },
  };
}

test('merges when the current dev commit and all PR checks pass', t => {
  const s = fixture(t); s.execute(); assert.equal(s.merged(), true);
});

for (const conclusion of ['failure', null]) {
  test(`a same-name check from another workflow cannot hide ${conclusion ?? 'pending'} work`, t => {
    const s = fixture(t, {
      workflowRuns: [workflow(1, 10), workflow(2, 20, conclusion), workflow(3, 30)],
      checks: [check('CI result', 10), check('test', 20, conclusion), check('test', 30)],
    });
    s.execute(); assert.equal(s.merged(), false);
  });
}

test('a newer label-triggered workflow replaces its cancelled predecessor', t => {
  const s = fixture(t, {
    workflowRuns: [workflow(1, 20, 'success', 2), workflow(1, 10, 'cancelled', 1)],
    checks: [check('CI result', 20), check('CI result', 10, 'cancelled')],
  });
  s.execute(); assert.equal(s.merged(), true);
});

test('same-name checks remain distinct even while workflow summaries still report success', t => {
  const s = fixture(t, {
    workflowRuns: [workflow(1, 10), workflow(2, 20), workflow(3, 30)],
    checks: [check('CI result', 10), check('test', 20, 'failure'), check('test', 30)],
  });
  s.execute(); assert.equal(s.merged(), false);
});

test('a successful retry replaces the earlier failed job in the same suite', t => {
  const s = fixture(t, {
    checks: [check('CI result', 10), check('test', 10, 'failure', 101), check('test', 10, 'success', 102)],
  });
  s.execute(); assert.equal(s.merged(), true);
});

test('a new pending run prevents an old successful CI result from allowing a merge', t => {
  const s = fixture(t, {
    workflowRuns: [workflow(1, 20, null, 2), workflow(1, 10, 'success', 1)],
    checks: [check('CI result', 10), check('CI result', 20, null)],
  });
  s.execute(); assert.equal(s.merged(), false);
});

test('checks from an external app still block a merge', t => {
  const external = { ...check('test', 30, 'failure'), app: { slug: 'external-ci' } };
  const s = fixture(t, { checks: [check('CI result', 10), external, check('test', 10, 'success', 400)] });
  s.execute(); assert.equal(s.merged(), false);
});

test('a successful CI result is required even when other checks pass', t => {
  const s = fixture(t, { checks: [check('test', 10)] });
  s.execute(); assert.equal(s.merged(), false);
});

for (const conclusion of [null, 'failure', 'timed_out', 'cancelled']) {
  test(`dev ${conclusion ?? 'retry in progress'} cannot fall back to an older green run`, t => {
    const s = fixture(t, { devRuns: [
      { head_sha: 'dev-head', status: conclusion === null ? 'in_progress' : 'completed', conclusion },
      { head_sha: 'older-dev', status: 'completed', conclusion: 'success' },
    ] });
    s.execute(); assert.equal(s.merged(), false);
  });
}

test('dev with no CI run on its current commit waits', t => {
  const s = fixture(t, { devRuns: [{ head_sha: 'older-dev', status: 'completed', conclusion: 'success' }] });
  s.execute(); assert.equal(s.merged(), false);
});

test('a dev update during the PR checks prevents a stale-base merge', t => {
  const s = fixture(t, { devHeads: ['dev-head', 'new-dev'] });
  s.execute(); assert.equal(s.merged(), false);
});

test('different PRs share the merge lock and retain queued requests', () => {
  const yaml = readFileSync(path.join(workflows, 'automerge.yml'), 'utf8');
  const concurrency = yaml.match(/^    concurrency:\n((?:^      .*\n)+)/m)?.[1];
  assert.ok(concurrency);
  assert.doesNotMatch(concurrency, /matrix\./);
  assert.match(concurrency, /group: automerge-\$\{\{ github\.repository \}\}/);
  assert.match(concurrency, /queue: max/);
  assert.match(concurrency, /cancel-in-progress: false/);
});

function git(cwd, ...args) {
  const result = spawnSync('git', args, { cwd, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  return result.stdout.trim();
}
function commit(repo, file) {
  writeFileSync(path.join(repo, file), file);
  git(repo, 'add', file); git(repo, 'commit', '-qm', file);
  return git(repo, 'rev-parse', 'HEAD');
}

for (const kind of ['squash', 'rebase', 'merge', 'direct']) {
  test(`revert of a ${kind} commit preserves unrelated dev changes`, t => {
    const s = fixture(t);
    const repo = path.join(s.dir, 'repo'); mkdirSync(repo);
    git(repo, 'init', '-q'); git(repo, 'config', 'user.name', 'CI test');
    git(repo, 'config', 'user.email', 'ci@example.invalid');
    commit(repo, 'base'); commit(repo, 'unrelated-A'); commit(repo, 'unrelated-B');
    if (kind === 'merge') git(repo, 'checkout', '-qb', 'feature');
    if (kind === 'rebase' || kind === 'merge') {
      commit(repo, 'feature-A'); commit(repo, 'feature-B');
    }
    let sha = commit(repo, 'feature-tip');
    if (kind === 'merge') {
      git(repo, 'checkout', '-q', '-'); git(repo, 'merge', '--no-ff', '-qm', 'Merge PR', 'feature');
      sha = git(repo, 'rev-parse', 'HEAD');
    }
    s.data.originalPr.merge_commit_sha = sha;
    writeFileSync(s.env.CI_SAFETY_FIXTURE, JSON.stringify(s.data));
    commit(repo, 'later-change');
    const targets = revertScript.slice(revertScript.indexOf('target=('), revertScript.indexOf('body="$RUNNER_TEMP/body.md"'));
    const revert = revertScript.match(/if ! (git revert [^\n]+); then/)[1];
    s.execute(`cd "$TEST_REPO"\n${targets}\n${revert}`, {
      TEST_REPO: repo, SHA: sha, R: 'Otzaria/otzaria', orig: kind === 'direct' ? '' : '42',
      parents: kind === 'merge' ? '2' : '1',
    });
    for (const file of ['unrelated-A', 'unrelated-B', 'later-change']) {
      assert.equal(existsSync(path.join(repo, file)), true, file);
    }
    assert.equal(existsSync(path.join(repo, 'feature-tip')), false);
    if (kind === 'merge') assert.equal(existsSync(path.join(repo, 'feature-A')), false);
    if (kind === 'rebase') assert.equal(existsSync(path.join(repo, 'feature-A')), true);
  });
}
