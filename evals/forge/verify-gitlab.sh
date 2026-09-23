#!/usr/bin/env bash
# Read-only verification of the glab rows in docs/forge-adapter-design.md.
#
# Run from inside a clone of a GitLab project, authenticated with `glab auth login`.
# Never merges, creates, comments, resolves, or retries anything — it only reads.
#
#   bash evals/forge/verify-gitlab.sh [MR_IID] [JOB_ID]
#
# MR_IID  an existing merge request (default: the most recent one, if any).
# JOB_ID  an existing CI job id, to exercise `glab ci trace` (optional).
#
# Paste the full output back into the design PR: it records glab's version, the exit code
# of each command, and the top-level JSON keys — the field names the normalized `pr-view`
# shape has to map from.
set -u

MR="${1:-}"
JOB="${2:-}"
pass=0; fail=0

run() {  # run <label> <cmd...>; prints exit code and a short head of output
  local label="$1"; shift
  echo; echo "### $label"; echo "\$ $*"
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  echo "exit: $rc"
  printf '%s\n' "$out" | head -"${LINES_SHOWN:-12}"
  if [ $rc -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
  LAST_OUT="$out"; LAST_RC=$rc
}

keys() {  # print top-level keys of the last JSON output (object, or first array element)
  printf '%s' "$LAST_OUT" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception as e:
    print("  (not valid JSON:", e, ")"); sys.exit()
if isinstance(d, list):
    print("  array of", len(d)); d = d[0] if d else {}
print("  keys:", ", ".join(sorted(d.keys())) if isinstance(d, dict) else type(d).__name__)'
}

echo "glab: $(glab --version 2>&1 | head -1)"
echo "remote: $(git remote get-url origin 2>&1)"
run "auth" glab auth status

run "whoami (glab api user)" glab api user --jq .username
run "mr list --merged (JSON)" glab mr list --merged -F json --per-page 3; keys
if [ -z "$MR" ]; then
  MR="$(glab mr list -F json --per-page 1 --jq '.[0].iid' 2>/dev/null)"
fi
case "$MR" in ''|*[!0-9]*) MR="" ;; esac   # must be a plain iid, never an error message

if [ -n "$MR" ]; then
  echo; echo "== using MR !$MR =="
  run "mr view (JSON)" glab mr view "$MR" -F json; keys
  echo "  looking for the fields skills read:"
  printf '%s' "$LAST_OUT" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("  (skipped: output was not JSON)"); sys.exit()
for k in ["iid","web_url","state","draft","work_in_progress","target_branch","source_branch",
          "sha","diff_refs","detailed_merge_status","merge_status","has_conflicts",
          "head_pipeline","pipeline","source_project_id","target_project_id",
          "approvals_before_merge","blocking_discussions_resolved","merge_when_pipeline_succeeds","auto_merge_enabled"]:
    print(f"    {k:32}", "PRESENT" if k in d else "-")
print("  detailed_merge_status =", d.get("detailed_merge_status"))'
  run "mr view --comments --unresolved (JSON)" glab mr view "$MR" --comments --unresolved -F json; keys
  run "mr note list (EXPERIMENTAL)" glab mr note list "$MR"
  run "raw discussions API" glab api "projects/:id/merge_requests/$MR/discussions" --paginate
  keys
  run "approvers" glab mr approvers "$MR" -F json
  run "approval state (raw API)" glab api "projects/:id/merge_requests/$MR/approval_state"
  run "ci get for MR (JSON)" glab ci get --merge-request "$MR" -F json; keys
  run "ci get, failed jobs only" glab ci get --merge-request "$MR" --status failed -F json
else
  echo; echo "!! no MR found — skipping MR checks (pass an MR iid as \$1)"
fi

run "ci status (JSON, current branch)" glab ci status -F json; keys
run "ci status --wait accepted?" glab ci status --help
run "ci list" glab ci list --per-page 3
[ -n "$JOB" ] && LINES_SHOWN=5 run "ci trace <job>" glab ci trace "$JOB"

# note: `glab issue list -F` is --output-format (details|ids|urls), not JSON — so use the API here.
ISSUE="$(glab api 'projects/:id/issues?per_page=1' --jq '.[0].iid' 2>/dev/null)"
case "$ISSUE" in ''|*[!0-9]*) echo; echo "!! no issue found — skipping issue view" ;;
  *) run "issue view (JSON)" glab issue view "$ISSUE" -F json; keys ;; esac

echo
echo "--- exit-code probes (state only; nothing changes) ---"
echo "Manual, needs a scratch MR you own — do NOT run against a real one:"
echo "  glab mr merge <scratch-iid> --sha <WRONG_SHA> --auto-merge=false --yes   # expect refusal; record exit code"
echo "  glab ci status --wait   # on a failing pipeline: is the exit code non-zero?"
echo
echo "summary: $pass commands exited 0, $fail non-zero (non-zero is expected where no data exists)"
