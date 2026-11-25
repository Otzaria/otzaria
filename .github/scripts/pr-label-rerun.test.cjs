'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { tmpdir } = require('node:os');
const { spawnSync } = require('node:child_process');

const workflowPath = path.join(__dirname, '../workflows/pr_labels.yml');
const workflow = fs.readFileSync(workflowPath, 'utf8');
const rerunJob = workflow.slice(workflow.indexOf('  rerun_on_label:'));
const lines = rerunJob.split('\n');
const start = lines.findIndex(line => /^ +run: \|$/.test(line));
assert.notEqual(start, -1, 'The test must execute the production rerun script.');
const indent = lines[start].search(/\S/) + 2;
const body = [];
for (const line of lines.slice(start + 1)) {
  if (line.trim() && line.search(/\S/) < indent) break;
  body.push(line.slice(indent));
}
const script = body.join('\n');
// GitHub's explicit bash shell enables pipefail; its implicit Linux shell does not.
const shellArguments = /\n        shell: bash\n        run: \|/.test(rerunJob)
  ? ['--noprofile', '--norc', '-e', '-o', 'pipefail']
  : ['-e'];
const head = 'a'.repeat(40);
const nextHead = 'b'.repeat(40);

// This executable replaces only the GitHub boundary. Bash, jq and the exact
// workflow script remain real, including pagination arguments and run sorting.
function fakeGh() {
  const fs = require('node:fs');
  const { spawnSync } = require('node:child_process');
  const args = process.argv.slice(2);
  const file = process.env.LABEL_RERUN_FIXTURE;
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  fs.appendFileSync(process.env.LABEL_RERUN_CALLS, JSON.stringify(args) + '\n');
  function race(event) {
    data.events[event] = (data.events[event] || 0) + 1;
    if (data.race && data.race.on === event &&
        data.events[event] === (data.race.occurrence || 1)) {
      Object.assign(data.pr, data.race.change);
    }
  }
  let value;
  if (args[0] === 'api') {
    const route = args.find(arg => arg.startsWith('repos/'));
    if (route.endsWith('/pulls/5894')) {
      if (data.prError) {
        process.stdout.write(data.prError.stdout || '');
        process.stderr.write('GitHub PR read failed\n');
        process.exit(data.prError.code);
      }
      if (data.rawPr !== undefined) {
        process.stdout.write(data.rawPr);
        process.exit(0);
      }
      value = data.pr;
    } else if (route.includes('/actions/runs?')) {
      if (data.listError) {
        process.stdout.write(data.listError.stdout || '');
        process.stderr.write('GitHub workflow list failed\n');
        process.exit(data.listError.code);
      }
      const query = new URLSearchParams(route.split('?')[1]);
      value = { workflow_runs: data.runs.filter(run =>
        run.head_sha === query.get('head_sha') && run.event === query.get('event')) };
      race('list');
    } else {
      const match = route.match(/\/actions\/runs\/(\d+)$/);
      if (!match) throw new Error('Unexpected API route: ' + route);
      const run = data.runs.find(run => run.id === Number(match[1]));
      if (!run) throw new Error('Unknown run: ' + match[1]);
      value = { ...run };
      race('status');
    }
  } else if (args[0] === 'run' && ['cancel', 'rerun'].includes(args[1])) {
    const run = data.runs.find(run => run.id === Number(args[2]));
    if (!run) throw new Error('Unknown mutation target: ' + args[2]);
    if (args[1] === 'cancel' && !data.cancelKeepsRunning) run.status = 'completed';
    race(args[1]);
    value = { accepted: true };
  } else {
    throw new Error('Unexpected gh command: ' + args.join(' '));
  }
  fs.writeFileSync(file, JSON.stringify(data));
  const queryIndex = args.indexOf('--jq');
  if (queryIndex >= 0) {
    const result = spawnSync('jq', ['-r', args[queryIndex + 1]], {
      input: JSON.stringify(value), encoding: 'utf8',
    });
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
    process.exit(result.status);
  }
  console.log(JSON.stringify(value));
}

function run(id, name, status = 'completed', workflowId = id, number = 1) {
  return {
    id, name, status, workflow_id: workflowId, run_number: number,
    head_sha: head, event: 'pull_request',
  };
}

function fixture(t, overrides = {}) {
  const dir = fs.mkdtempSync(path.join(tmpdir(), 'otzaria-label-rerun-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(bin);
  const data = {
    pr: { state: 'open', draft: true, head: { sha: head }, labels: [{ name: 'run-ci' }] },
    runs: [run(101, 'Flutter Tests', 'queued'), run(201, 'Android PDF file export')],
    events: {}, ...overrides,
  };
  const fixturePath = path.join(dir, 'fixture.json');
  const callsPath = path.join(dir, 'calls.jsonl');
  fs.writeFileSync(fixturePath, JSON.stringify(data));
  fs.writeFileSync(path.join(bin, 'gh'),
    '#!/usr/bin/env node\n(' + fakeGh.toString() + ')();\n', { mode: 0o755 });
  return {
    data,
    execute() {
      return spawnSync('bash', [...shellArguments, '-c', 'sleep() { :; }\n' + script], {
        encoding: 'utf8', timeout: 20000,
        env: {
          ...process.env, PATH: bin + path.delimiter + process.env.PATH,
          LABEL_RERUN_FIXTURE: fixturePath, LABEL_RERUN_CALLS: callsPath,
          GITHUB_REPOSITORY: 'Otzaria/otzaria', PR: '5894', SHA: head,
          GH_TOKEN: 'fixture-only',
        },
      });
    },
    calls() {
      return fs.existsSync(callsPath)
        ? fs.readFileSync(callsPath, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse)
        : [];
    },
    mutations() {
      return this.calls().filter(args => args[0] === 'run')
        .map(args => [args[1], Number(args[2])]);
    },
  };
}

function succeeded(result) {
  assert.equal(result.status, 0, result.stdout + result.stderr);
}

test('a queued label event cannot rerun an old head and cancel current-head CI', t => {
  const s = fixture(t, {
    pr: { state: 'open', head: { sha: nextHead }, labels: [{ name: 'run-ci' }] },
  });
  succeeded(s.execute());
  assert.deepEqual(s.mutations(), []);
  assert.equal(s.calls().some(args => args.some(arg => arg.includes('/actions/runs?'))), false);
});

for (const [name, change] of [
  ['removed run-ci label', { labels: [] }],
  ['closed PR', { state: 'closed' }],
]) {
  test(name + ' stops an old label worker before any write', t => {
    const s = fixture(t);
    const pr = { ...s.data.pr, ...change };
    const stopped = fixture(t, { pr });
    succeeded(stopped.execute());
    assert.deepEqual(stopped.mutations(), []);
  });
}

test('the current labeled head still cancels then reruns gated work for a draft', t => {
  const s = fixture(t);
  succeeded(s.execute());
  assert.deepEqual(s.mutations(), [['cancel', 101], ['rerun', 101], ['rerun', 201]]);
});

test('latest run per workflow is selected and ungated workflows remain untouched', t => {
  const s = fixture(t, { runs: [
    run(11, 'Flutter Tests', 'completed', 1, 1),
    run(12, 'Flutter Tests', 'completed', 1, 2),
    run(21, 'Lockfile Guard'), run(22, 'Goldens Guard'),
    run(23, 'UI Baseline Guard'), run(24, 'CI Automation Tests'),
  ] });
  succeeded(s.execute());
  assert.deepEqual(s.mutations(), [['rerun', 12]]);
});

for (const event of ['list', 'status']) {
  test('a push during ' + event + ' lookup prevents cancellation of the old run', t => {
    const s = fixture(t, { race: { on: event, change: { head: { sha: nextHead } } } });
    succeeded(s.execute());
    assert.deepEqual(s.mutations(), []);
  });
}

test('a push while cancellation is in flight prevents the subsequent rerun', t => {
  const s = fixture(t, { race: { on: 'cancel', change: { head: { sha: nextHead } } } });
  succeeded(s.execute());
  assert.deepEqual(s.mutations(), [['cancel', 101]]);
});

test('revocation at the completed cancellation poll prevents rerun', t => {
  const s = fixture(t, {
    race: { on: 'status', occurrence: 2, change: { labels: [] } },
  });
  succeeded(s.execute());
  assert.deepEqual(s.mutations(), [['cancel', 101]]);
});

test('a push after one rerun stops the remaining workflows in the batch', t => {
  const s = fixture(t, {
    runs: [run(101, 'Flutter Tests'), run(201, 'Android PDF file export')],
    race: { on: 'rerun', change: { head: { sha: nextHead } } },
  });
  succeeded(s.execute());
  assert.deepEqual(s.mutations(), [['rerun', 101]]);
});

test('a failed PR read discards valid-looking partial output and performs no writes', t => {
  const s = fixture(t);
  const failed = fixture(t, { prError: { stdout: JSON.stringify(s.data.pr), code: 1 } });
  const result = failed.execute();
  assert.notEqual(result.status, 0);
  assert.deepEqual(failed.mutations(), []);
});

test('malformed live PR metadata cannot cause a cancel or rerun', t => {
  const s = fixture(t, { rawPr: '{broken' });
  const result = s.execute();
  assert.notEqual(result.status, 0);
  assert.deepEqual(s.mutations(), []);
});

test('a failed workflow listing cannot rerun its valid-looking partial output', t => {
  const s = fixture(t, {
    listError: { stdout: '101\t1\t101\tFlutter Tests\n', code: 1 },
  });
  const result = s.execute();
  assert.notEqual(result.status, 0);
  assert.deepEqual(s.mutations(), []);
});

test('the production rerun shell enables pipefail just like the harness', () => {
  assert.match(rerunJob, /\n        shell: bash\n        run: \|/);
});

test('a run that never finishes cancellation is not rerun', t => {
  const s = fixture(t, { cancelKeepsRunning: true, runs: [run(101, 'Flutter Tests', 'queued')] });
  succeeded(s.execute());
  assert.deepEqual(s.mutations(), [['cancel', 101]]);
});

test('the privileged label workflow never checks out pull-request code', () => {
  assert.match(workflow, /pull_request_target:/);
  assert.doesNotMatch(workflow, /uses:\s*actions\/checkout@/);
});

test('CI automation tests are triggered by edits to the label workflow', () => {
  const ci = fs.readFileSync(path.join(__dirname, '../workflows/ci-automation-tests.yml'), 'utf8');
  assert.match(ci, /- '\.github\/workflows\/pr_labels\.yml'/);
});
