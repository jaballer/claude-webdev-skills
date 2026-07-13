---
name: watch-pr
description: >
  Polls a pull request on a fixed interval until it reaches a terminal state — approved,
  changes-requested, merged, or closed — then either notifies you or hands off to
  /webdev:merge-pr. Use when the user says "watch the PR", "poll PR #X", "tell me when it's
  approved", "keep checking the PR", "let me know when review comes back", or "auto-merge
  when it's approved". Takes a PR (number/URL), a check interval, and an on-approval action
  (notify | merge). Built on ScheduleWakeup: each poll re-arms the next and the loop ends
  itself on a terminal state or a safety cap. Silence is never reported as approval.
---

# Watch PR

A hands-off watcher for a PR you're waiting on. It checks the PR every N minutes and keeps
waiting while the review is still open; the moment it reaches a **terminal state** it acts once
and stops the loop. It does not merge on its own — on approval it hands to `/webdev:merge-pr`,
which owns the merge gates and confirmation. **Silence ≠ approval:** a quiet PR keeps the loop
running, it is never reported as ready.

This is the polling companion to `/webdev:review-pr` (which *responds* to review comments). Use
`watch-pr` when the work is done and you're only waiting for a verdict.

## Step 1: Parse inputs

- **PR** — an explicit number or URL if given; otherwise the current branch's PR via
  `gh pr view --json number,url,headRefName`. If none resolves, ask — don't guess.
  **If the input is a URL or names another repo**, parse its `owner/repo` and pass `--repo
  <owner>/<repo>` on **every** `gh pr`/`gh repo` command (and `-f owner=… -f repo=…` on any
  `gh api graphql`, which has no `--repo` flag). A bare number resolves against the current
  checkout — wrong PR if numbers collide across repos.
- **Interval** — `every <N>m` / `every <N>h` (default **20m**). `ScheduleWakeup` clamps to
  **[60s, 3600s]**, so the effective range is 1m–60m; if the user asks for longer, cap at 60m
  and say so (for a truly long or cross-session watch, use a cron instead — see Notes).
  Convert to seconds for `delaySeconds`.
- **On-approval action** — `notify` (default) or `merge`.
- **Safety cap** — `for <N>h` maximum lifetime (default **24h**) so an abandoned PR doesn't poll
  forever. On the first run, compute the absolute deadline once (`date -u -v+<N>H +%FT%TZ` on
  macOS/BSD, `date -u -d "+<N> hours" +%FT%TZ` on GNU) and **carry it verbatim in the re-arm
  prompt** so every re-entry shares the same deadline.

State the resolved plan in one line before starting: *"Watching owner/repo#N every 20m,
on-approval: notify, until <deadline>."*

## Step 2: Poll once

```bash
gh pr view <number> --repo <owner>/<repo> \
  --json number,title,url,state,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup,headRefOid
```

Also fetch the newest approval and the SHA it covers (an `APPROVED` `reviewDecision` can be an
approval of an *older* diff when the repo doesn't dismiss stale reviews). Query `reviews(states:
APPROVED, …)` — the same way `merge-pr` does — not `latestReviews`: the latter returns only each
user's *latest* review, so it hides an approval when the approver later submits an informational
(non-approving) review, leaving the loop re-arming forever on an already-approved PR:

```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
      reviews(states: APPROVED, last: 10){ nodes{ author{ login } state commit{ oid } submittedAt } } } } }' \
  -f owner=<owner> -f repo=<repo> -F pr=<number>
```

The newest approval is the **last** node; compare its `commit.oid` to `headRefOid`.

## Step 3: Classify — terminal or keep waiting

**Terminal states → act once, then STOP the loop (Step 4):**

| Signal | Meaning | Action |
|---|---|---|
| `state == MERGED` | already merged | Report merged (+ merge SHA). Stop. |
| `state == CLOSED` (not merged) | closed without merging | Report closed unmerged. Stop. |
| `reviewDecision == CHANGES_REQUESTED` | reviewer wants changes | Notify; point at **`/webdev:review-pr`**. Stop. |
| `reviewDecision == APPROVED` **and** the newest `APPROVED` review's `commit.oid` **==** `headRefOid` | genuinely approved on the current head | Run the **on-approval action** below. Stop. |
| deadline exceeded | safety cap hit | Report last-seen state + "still not resolved after <N>h". Stop. |

**On-approval action:**
- **`notify`** — report *"#N approved by `<login>` on `<sha>`"*, include `statusCheckRollup`
  (green/pending/failing) so the user knows if it's mergeable, and stop. Do **not** merge.
- **`merge`** — **invoke `/webdev:merge-pr <number>`** (with `--repo`/URL if cross-repo). That
  skill re-runs every gate (checks green, threads resolved, up-to-date, approval-covers-head) and
  handles confirmation and cleanup. `watch-pr` never runs `gh pr merge` itself. Stop after it
  returns.

**Keep waiting (re-arm, Step 4)** for any non-terminal case:
- `reviewDecision` is `REVIEW_REQUIRED` or `null` (no verdict yet).
- `APPROVED` but the newest approval's `commit.oid` **≠** `headRefOid` — the approval predates the
  current head (pushing isn't reviewing). In `merge` mode this is **not** a go; keep waiting (or, if
  the user prefers, switch to `notify` and surface it). Never auto-merge an unreviewed head.
- Checks still pending on an otherwise-quiet PR.

## Step 4: Re-arm or stop

- **Terminal** → call `ScheduleWakeup` with `stop: true` to end the loop, then emit the Output.
- **Keep waiting** → call `ScheduleWakeup` with `delaySeconds = <interval>` and a `prompt` that
  re-invokes this skill with the **same PR, interval, on-approval mode, and the carried deadline**.
  Emit a one-line status (*"#N: REVIEW_REQUIRED, checks pending — next check in 20m (deadline
  <ts>)"*) so the user sees progress without noise. Set `reason` to something specific
  ("polling PR #N for approval").

Interval vs. cache cost (from the `ScheduleWakeup` guidance): intervals **< 5m** keep the prompt
cache warm but poll often; **20–30m** is the sensible default for a human/bot verdict that won't
change minute-to-minute. Don't pick exactly 5m.

## Notes

- **Commenting reviewers don't emit `APPROVED`.** Codex, CodeRabbit, and Copilot post findings but
  don't flip `reviewDecision`; it goes `APPROVED` only on a **human** approval (or when branch
  protection requires a review). If what you're actually waiting on is a *bot's findings on a new
  commit*, that's `/webdev:review-pr` Step 12 (watch for new comments), not this skill.
- **No branch protection?** `reviewDecision` can stay `null` forever on a repo that requires no
  review — such a PR is mergeable but will never self-report "approved". Say that plainly rather
  than looping indefinitely; the safety cap will end it, and the user decides.
- **Longer or cross-session watches** — `ScheduleWakeup` is bounded to 60m, and **both it and
  `CronCreate` are session-scoped**: they're restored only on `--resume`/`--continue` while
  unexpired, so neither survives a full restart or a fresh conversation. For a watcher that must
  survive restarts, hand the same poll to a **durable** scheduler instead — Cloud Routines
  (`/schedule`, runs on Anthropic infrastructure, min 1h cadence), a Desktop scheduled task, or an
  external scheduler such as GitHub Actions. Don't rely on `CronCreate` for cross-session durability.
- The user can stop the loop at any time; a single terminal result also ends it.

## What NOT to do

- **Don't report "ready to merge" from silence** — only an explicit `APPROVED`-covering-head (or a
  green, review-not-required PR the user acknowledged) is a positive signal.
- **Don't merge directly** — always hand approval-mode merges to `/webdev:merge-pr`.
- **Don't auto-merge a stale approval** — verify the approval covers `headRefOid` first.
- **Don't `sleep`** to wait between polls — that burns tokens; re-arm with `ScheduleWakeup`.
- **Don't poll a bare number in another repo** — target `--repo` explicitly.

## Output

- **PR**: `owner/repo#number` — title · **Interval**: e.g. 20m · **On-approval**: notify / merge
- **Terminal state**: approved / changes-requested / merged / closed / capped (with the covering SHA or reason)
- **Action taken**: notified / handed to `/webdev:merge-pr` / stopped
- **Polls run** · **Elapsed** · **Loop**: stopped
