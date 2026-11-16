'use strict';

function isFailedPrRun(run) {
  return run?.event === 'pull_request' && run.status === 'completed' &&
    ['failure', 'timed_out'].includes(run.conclusion);
}

function sameHead(pr, run, repositoryId) {
  return pr.base?.repo?.id === repositoryId &&
    pr.head?.repo?.id === run.head_repository.id &&
    pr.head?.ref === run.head_branch && pr.head?.sha === run.head_sha;
}

// כשל שיחזור זהה בהרצה חוזרת: אין טעם לעכב את ההעברה לטיוטה.
const NO_RETRY_WORKFLOWS = ['Lockfile Guard', 'Goldens Guard', 'UI Baseline Guard'];
const NO_RETRY_JOBS = ['Analyze', 'CI result'];

async function failedJobs(github, repo, run, attempt) {
  const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRunAttempt, {
    ...repo, run_id: run.id, attempt_number: attempt, per_page: 100,
  });
  return jobs.filter((job) => ['failure', 'timed_out'].includes(job.conclusion));
}

// `github` (GITHUB_TOKEN) כותב את ההודעה בשם github-actions. `bot` (Otzaria Bot) מעביר לטיוטה
// ומריץ שוב: GITHUB_TOKEN לא יכול להעביר לטיוטה, והרצה חוזרת שלו לא מפעילה workflow_run.
module.exports = async function autoDraft({ github, context, core, bot = github }) {
  const trigger = context.payload.workflow_run;
  if (context.eventName !== 'workflow_run' || !isFailedPrRun(trigger)) return;

  const repo = context.repo;
  const repositoryId = context.payload.repository.id;
  const getRun = async () => (await github.rest.actions.getWorkflowRun({
    ...repo, run_id: trigger.id,
  })).data;
  const isCurrentAttempt = (run) => isFailedPrRun(run) &&
    run.repository?.id === repositoryId && run.head_repository?.id &&
    run.head_branch && run.head_sha === trigger.head_sha &&
    run.run_attempt === trigger.run_attempt;

  const run = await getRun();
  if (!isCurrentAttempt(run)) {
    core.info('The failed run is no longer current; skipping.');
    return;
  }

  let candidates = run.pull_requests ?? [];
  if (candidates.length === 0) {
    // Fork runs can omit pull_requests; a SHA alone is not a PR identity.
    const pulls = await github.paginate(github.rest.pulls.list, {
      ...repo,
      state: 'open',
      head: `${run.head_repository.owner.login}:${run.head_branch}`,
      per_page: 100,
    });
    candidates = pulls.filter((pr) =>
      pr.state === 'open' && sameHead(pr, run, repositoryId));
    if (candidates.length !== 1) {
      core.warning(`Found ${candidates.length} matching PRs; skipping an unassociated run.`);
      return;
    }
  }
  candidates = candidates.filter((pr) => sameHead(pr, run, repositoryId));
  if (candidates.length === 0) return;

  // Label changes can start a new run at the same SHA, without a new attempt.
  const recentRuns = await github.paginate(github.rest.actions.listWorkflowRuns, {
    ...repo,
    workflow_id: run.workflow_id,
    event: 'pull_request',
    branch: run.head_branch,
    head_sha: run.head_sha,
    per_page: 100,
  });

  for (const candidate of candidates) {
    const superseded = recentRuns.some((other) =>
      other.run_number > run.run_number &&
      other.head_repository?.id === run.head_repository.id &&
      other.head_branch === run.head_branch && other.head_sha === run.head_sha &&
      (!(other.pull_requests?.length) ||
       other.pull_requests.some((pr) => pr.number === candidate.number)));
    if (superseded) {
      core.info(`A newer run supersedes the failure for PR #${candidate.number}.`);
      continue;
    }
    if (!isCurrentAttempt(await getRun())) {
      core.info('The workflow was rerun while resolving its PR; skipping.');
      return;
    }

    const { data: pr } = await github.rest.pulls.get({
      ...repo, pull_number: candidate.number,
    });
    if (pr.state !== 'open' || pr.draft ||
        !sameHead(pr, run, repositoryId) || pr.base.ref !== candidate.base.ref) {
      core.info(`PR #${candidate.number} is closed, draft, or has changed; skipping.`);
      continue;
    }

    // הכשל הראשון של ריצה מורץ שוב פעם אחת לפני טיוטה, גם כשהוא ב-attempt שהוסיף run-ci.
    let retried = false;
    for (let attempt = 1; attempt < run.run_attempt && !retried; attempt++) {
      retried = (await failedJobs(github, repo, run, attempt)).length > 0;
    }
    if (!retried && !NO_RETRY_WORKFLOWS.includes(run.name)) {
      const failed = await failedJobs(github, repo, run, run.run_attempt);
      if (failed.some((job) => !NO_RETRY_JOBS.includes(job.name))) {
        await bot.rest.actions.reRunWorkflowFailedJobs({ ...repo, run_id: run.id });
        core.info(`First failure for PR #${pr.number}; rerunning the failed jobs.`);
        return;
      }
    }

    const result = await bot.graphql(`
      mutation ($id: ID!) {
        convertPullRequestToDraft(input: {pullRequestId: $id}) {
          pullRequest { isDraft }
        }
      }
    `, { id: pr.node_id });
    if (!result.convertPullRequestToDraft.pullRequest.isDraft) {
      throw new Error(`GitHub did not convert PR #${pr.number} to draft.`);
    }
    core.info(`Converted PR #${pr.number} to draft.`);

    // A PR-controlled name must not break out of its Markdown code span.
    const workflowName = run.name.replace(/[\r\n]/g, ' ');
    const delimiter = '`'.repeat(Math.max(0,
      ...Array.from(workflowName.matchAll(/`+/g), (match) => match[0].length)) + 1);
    const runUrl = `${context.serverUrl}/${repo.owner}/${repo.repo}/actions/runs/${run.id}/attempts/${run.run_attempt}`;
    // GitHub נותן dir="auto" לכל פסקה: כל שורה מתחילה בעברית, והעטיפה מיישרת לימין.
    const body = [
      '<div dir="rtl">',
      '',
      `ה־CI נכשל ב־PR של @${pr.user.login}, ולכן ה־PR הועבר אוטומטית ל־Draft.` +
        (retried ? ' הכשל חזר גם בהרצה חוזרת.' : ''),
      '',
      `הבדיקה שנכשלה: ${delimiter} ${workflowName} ${delimiter} (${run.conclusion}).`,
      `[צפייה בהרצת ה־CI שנכשלה](${runUrl})`,
      '',
      'אנא תקן את הבעיה, ודא שהבדיקות עוברות, ואז החזר את ה־PR ל־**Ready for review**.',
      '',
      '</div>',
    ].join('\n');
    await github.rest.issues.createComment({ ...repo, issue_number: pr.number, body });
  }
};
