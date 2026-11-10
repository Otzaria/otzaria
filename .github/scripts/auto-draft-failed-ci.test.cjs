'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const autoDraft = require('./auto-draft-failed-ci.cjs');
const clone = (value) => structuredClone(value);

function fixture() {
  const pr = {
    number: 17, node_id: 'PR_17', state: 'open', draft: false,
    user: { login: 'contributor' },
    head: { sha: 'current-head', ref: 'feature/test', repo: { id: 2 } },
    base: { ref: 'dev', repo: { id: 1 } },
  };
  const run = {
    id: 101, workflow_id: 10, run_number: 30, run_attempt: 1,
    name: 'Flutter Tests', event: 'pull_request', status: 'completed',
    conclusion: 'failure', head_sha: pr.head.sha, head_branch: pr.head.ref,
    repository: { id: 1 }, head_repository: { id: 2, owner: { login: 'fork-owner' } },
    pull_requests: [clone(pr)],
  };
  const context = {
    eventName: 'workflow_run', repo: { owner: 'Otzaria', repo: 'otzaria' },
    serverUrl: 'https://github.com', actor: 'rerun-actor',
    payload: { repository: { id: 1 }, workflow_run: clone(run) },
  };
  const state = {
    pr, run, context, calls: [], messages: [], runReads: [],
    pullPages: [[pr]], recentPages: [[clone(run)]], failAt: '', mutationDraft: true,
  };
  function record(kind, args) {
    state.calls.push({ kind, args: clone(args) });
    if (state.failAt === kind) throw new Error(`API failure: ${kind}`);
  }
  const github = {
    rest: {
      actions: {
        async getWorkflowRun(args) {
          record('getRun', args);
          return { data: clone(state.runReads.shift() ?? state.run) };
        },
        listWorkflowRuns() { throw new Error('Expected pagination'); },
      },
      pulls: {
        list() { throw new Error('Expected pagination'); },
        async get(args) {
          record('getPr', args);
          assert.equal(args.pull_number, state.pr.number);
          return { data: clone(state.pr) };
        },
      },
      issues: {
        async createComment(args) {
          record('comment', args);
          assert.equal(state.pr.draft, true, 'Notify only after conversion succeeds');
          return { data: { id: 50 } };
        },
      },
    },
    async paginate(method, args) {
      if (method === github.rest.pulls.list) {
        record('listPulls', args);
        return clone(state.pullPages.flat());
      }
      assert.equal(method, github.rest.actions.listWorkflowRuns);
      record('listRuns', args);
      return clone(state.recentPages.flat());
    },
    async graphql(query, args) {
      record('draft', args);
      assert.match(query, /convertPullRequestToDraft/);
      assert.equal(args.id, state.pr.node_id);
      state.pr.draft = state.mutationDraft;
      return { convertPullRequestToDraft: { pullRequest: { isDraft: state.mutationDraft } } };
    },
  };
  state.execute = () => autoDraft({ github, context, core: {
    info: (message) => state.messages.push(message),
    warning: (message) => state.messages.push(message),
  } });
  state.writes = () => state.calls.filter(({ kind }) => ['draft', 'comment'].includes(kind));
  return state;
}

for (const conclusion of ['failure', 'timed_out']) {
  test(`${conclusion}: converts the current PR and notifies its author`, async () => {
    const s = fixture();
    s.run.conclusion = s.context.payload.workflow_run.conclusion = conclusion;
    await s.execute();
    assert.deepEqual(s.writes().map(({ kind }) => kind), ['draft', 'comment']);
    const { args } = s.writes()[1];
    assert.equal(args.issue_number, 17);
    assert.equal(args.owner, 'Otzaria');
    assert.equal(args.repo, 'otzaria');
    assert.match(args.body, /^@contributor,/);
    assert.doesNotMatch(args.body, /@rerun-actor/);
    assert.match(args.body, /` Flutter Tests `/);
    assert.match(args.body, /https:\/\/github.com\/Otzaria\/otzaria\/actions\/runs\/101\/attempts\/1/);
    assert.match(args.body, /אנא תקן את הבעיה/);
    assert.match(args.body, /Ready for review/);
  });
}

for (const conclusion of ['success', 'cancelled', 'skipped', 'neutral', 'action_required']) {
  test(`does not draft a ${conclusion} result`, async () => {
    const s = fixture();
    s.context.payload.workflow_run.conclusion = conclusion;
    await s.execute();
    assert.deepEqual(s.calls, []);
  });
}

test('ignores incomplete runs and events other than completed PR workflows', async () => {
  for (const change of [
    (s) => { s.context.eventName = 'pull_request'; },
    (s) => { s.context.payload.workflow_run.status = 'in_progress'; },
    (s) => { s.context.payload.workflow_run.event = 'push'; },
    (s) => { s.context.payload.workflow_run.event = 'pull_request_target'; },
    (s) => { s.context.payload.workflow_run.event = 'workflow_run'; },
    (s) => { delete s.context.payload.workflow_run; },
  ]) {
    const s = fixture(); change(s);
    await s.execute();
    assert.deepEqual(s.calls, []);
  }
});

for (const [name, change] of Object.entries({
  closed: (pr) => { pr.state = 'closed'; },
  draft: (pr) => { pr.draft = true; },
  'new commit': (pr) => { pr.head.sha = 'new-head'; },
  'different source branch': (pr) => { pr.head.ref = 'another-branch'; },
  'different source repository': (pr) => { pr.head.repo.id = 3; },
  'retargeted base': (pr) => { pr.base.ref = 'main'; },
  'different base repository': (pr) => { pr.base.repo.id = 3; },
})) {
  test(`rechecks the PR before writing: ${name}`, async () => {
    const s = fixture(); change(s.pr);
    await s.execute();
    assert.deepEqual(s.writes(), []);
  });
}

test('rejects unrelated PR associations even when the head SHA is shared', async () => {
  const s = fixture();
  s.run.pull_requests[0].head.repo.id = 3;
  await s.execute();
  assert.deepEqual(s.writes(), []);
});

test('resolves an unassociated fork through paginated PRs and the complete source identity', async () => {
  const s = fixture();
  s.run.pull_requests = [];
  const otherFork = clone(s.pr); otherFork.head.repo.id = 3;
  const otherBranch = clone(s.pr); otherBranch.head.ref = 'other-branch';
  const olderCommit = clone(s.pr); olderCommit.head.sha = 'older-head';
  const foreignBase = clone(s.pr); foreignBase.base.repo.id = 3;
  const closed = clone(s.pr); closed.state = 'closed';
  s.pullPages = [[otherFork, otherBranch, olderCommit, foreignBase, closed], [s.pr]];
  await s.execute();
  assert.deepEqual(s.writes().map(({ kind }) => kind), ['draft', 'comment']);
  assert.deepEqual(s.calls.find(({ kind }) => kind === 'listPulls').args, {
    owner: 'Otzaria', repo: 'otzaria', state: 'open',
    head: 'fork-owner:feature/test', per_page: 100,
  });
});

test('skips a fork fallback with no matching PR or ambiguous target branches', async () => {
  for (const ambiguous of [false, true]) {
    const s = fixture();
    s.run.pull_requests = [];
    const second = clone(s.pr); second.number = 18; second.base.ref = 'main';
    s.pullPages = ambiguous ? [[s.pr], [second]] : [[]];
    await s.execute();
    assert.deepEqual(s.writes(), []);
    assert.ok(s.messages.some((message) => /matching PRs/.test(message)));
  }
});

for (const [name, change] of Object.entries({
  'successful rerun': (run) => { run.run_attempt = 2; run.conclusion = 'success'; },
  'failed newer attempt': (run) => { run.run_attempt = 2; },
  'rerun in progress': (run) => { run.status = 'in_progress'; run.conclusion = null; },
  'different repository': (run) => { run.repository.id = 3; },
  'different commit': (run) => { run.head_sha = 'other-head'; },
})) {
  test(`ignores an obsolete event: ${name}`, async () => {
    const s = fixture(); change(s.run);
    await s.execute();
    assert.deepEqual(s.writes(), []);
  });
}

test('rechecks the attempt after resolving candidates', async () => {
  const s = fixture();
  const rerun = clone(s.run); rerun.run_attempt = 2; rerun.conclusion = 'success';
  s.runReads = [clone(s.run), rerun];
  await s.execute();
  assert.deepEqual(s.writes(), []);
});

test('accepts the failure of the current rerun and links to that attempt', async () => {
  const s = fixture();
  s.run.run_attempt = s.context.payload.workflow_run.run_attempt = 2;
  await s.execute();
  assert.match(s.writes()[1].args.body, /\/attempts\/2\)/);
});

for (const status of ['queued', 'in_progress', 'completed']) {
  test(`ignores a failure superseded by a ${status} same-SHA label run on another page`, async () => {
    const s = fixture();
    const newer = { ...clone(s.run), id: 102, run_number: 31, status, conclusion: 'success' };
    s.recentPages = [[clone(s.run)], [newer]];
    await s.execute();
    assert.deepEqual(s.writes(), []);
  });
}

test('a newer unassociated run for the same fork also supersedes the failure', async () => {
  const s = fixture();
  s.recentPages = [[{ ...clone(s.run), id: 102, run_number: 31, pull_requests: [] }]];
  await s.execute();
  assert.deepEqual(s.writes(), []);
});

test('runs for another source or another target PR do not supersede this failure', async () => {
  for (const change of [
    (run) => { run.head_repository.id = 3; },
    (run) => { run.head_branch = 'other-branch'; },
    (run) => { run.head_sha = 'different-head'; },
    (run) => { run.pull_requests[0].number = 18; },
  ]) {
    const s = fixture();
    const newer = { ...clone(s.run), id: 102, run_number: 31 }; change(newer);
    s.recentPages = [[newer]];
    await s.execute();
    assert.equal(s.writes().length, 2);
  }
});

for (const kind of ['getRun', 'listPulls', 'listRuns', 'getPr', 'draft', 'comment']) {
  test(`propagates ${kind} API errors without reporting a successful notification`, async () => {
    const s = fixture();
    if (kind === 'listPulls') s.run.pull_requests = [];
    s.failAt = kind;
    await assert.rejects(s.execute, new RegExp(`API failure: ${kind}`));
    if (kind !== 'comment') assert.ok(s.calls.every((call) => call.kind !== 'comment'));
    if (!['draft', 'comment'].includes(kind)) assert.deepEqual(s.writes(), []);
  });
}

test('does not notify if GitHub reports that conversion did not succeed', async () => {
  const s = fixture(); s.mutationDraft = false;
  await assert.rejects(s.execute, /did not convert/);
  assert.deepEqual(s.writes().map(({ kind }) => kind), ['draft']);
});

test('two failed workflow events processed serially notify only once', async () => {
  const s = fixture();
  await s.execute();
  s.run = { ...clone(s.run), id: 202, workflow_id: 20, name: 'Goldens Guard' };
  s.context.payload.workflow_run = clone(s.run);
  s.recentPages = [[clone(s.run)]];
  await s.execute();
  assert.deepEqual(s.writes().map(({ kind }) => kind), ['draft', 'comment']);
});

test('contains hostile Markdown, HTML, mentions and backticks inside a code span', async () => {
  const s = fixture();
  s.run.name = '```</code>[spoof](https://attacker.invalid/) @victim\r\n<img src=x> & ` `` ```';
  s.run.html_url = 'https://untrusted-run.invalid/fake-run';
  await s.execute();
  const body = s.writes()[1].args.body;
  assert.ok(body.split('\n').includes(
    'הבדיקה שנכשלה: ```` ```</code>[spoof](https://attacker.invalid/) @victim  <img src=x> & ` `` ``` ```` (failure).',
  ));
  assert.doesNotMatch(body, /untrusted-run\.invalid|\r/);
  assert.match(body, /https:\/\/github.com\/Otzaria\/otzaria\/actions\/runs\/101\/attempts\/1/);
});
