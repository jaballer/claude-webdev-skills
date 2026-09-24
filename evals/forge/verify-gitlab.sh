#!/usr/bin/env bash
# Read-only verification of the READ-side glab rows in docs/forge-adapter-design.md.
#
# Run from inside a clone of a GitLab project, authenticated with `glab auth login`.
# Never merges, creates, comments, resolves, or retries anything — it only reads. The
# write-side verbs (pr-create, pr-checkout, comment-reply, thread-resolve, ci-retry, pr-merge,
# ci-watch exit codes) are NOT exercised here; see "Scratch-project probes" in the design doc.
#
#   bash evals/forge/verify-gitlab.sh [MR_IID] [JOB_ID]
#
# MR_IID  an existing merge request in any state (default: the most recently updated one).
# JOB_ID  an existing CI job id, to exercise `glab ci trace` (optional).
#
# PRIVACY: by default this prints only exit codes, JSON key names, counts, and enum values —
# never MR/issue titles, descriptions, comments, usernames, or error text — so the output is
# safe to paste into the design PR. VERBOSE=1 prints raw command output for local debugging;
# NEVER paste VERBOSE output anywhere shared.
#
# Exit: 2 if glab is missing or unauthenticated (nothing was verified); otherwise 0 when at
# least one command succeeded. Data-dependent failures (e.g. no issues) are reported, not fatal.
set -u

MR="${1:-}"
JOB="${2:-}"
VERBOSE="${VERBOSE:-0}"
pass=0; fail=0; LAST_OUT=""; LAST_RC=0

run() {  # run <label> <cmd...> — records exit code; raw output only when VERBOSE=1
  local label="$1"; shift
  echo; echo "### $label"
  LAST_OUT="$("$@" 2>&1)"; LAST_RC=$?
  echo "exit: $LAST_RC"
  if [ "$VERBOSE" = 1 ]; then printf '%s\n' "$LAST_OUT" | head -"${LINES_SHOWN:-12}"; fi
  if [ "$LAST_RC" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
}

keys() {  # top-level key NAMES of the last output. Handles one JSON doc, an array, or NDJSON
  printf '%s' "$LAST_OUT" | python3 -c '
import json,sys
raw=sys.stdin.read()
try:
    docs=[json.loads(raw)]
except Exception:
    docs=[]
    for line in raw.splitlines():
        line=line.strip()
        if not line: continue
        try: docs.append(json.loads(line))
        except Exception: pass
    if not docs:
        print("  (output was not JSON)"); sys.exit()
    print("  ndjson docs:", len(docs))
d=docs[0]
if isinstance(d, list):
    print("  array of", len(d)); d = d[0] if d else {}
print("  keys:", ", ".join(sorted(d.keys())) if isinstance(d, dict) else type(d).__name__)'
}

command -v glab >/dev/null 2>&1 || { echo "glab not installed — nothing verified"; exit 2; }
echo "glab: $(glab --version 2>&1 | grep -aEo '^glab [0-9][0-9A-Za-z.+-]*' | head -1)"

run "auth" glab auth status
if [ "$LAST_RC" -ne 0 ]; then
  echo; echo "glab is not authenticated for this repo's host — nothing verified."
  echo "Run \`glab auth login\` (add --hostname for self-hosted), then re-run."
  exit 2
fi

run "whoami (glab api user)" glab api user --jq .username
run "mr list --merged (JSON)" glab mr list --merged -F json --per-page 3; keys
if [ -z "$MR" ]; then
  # bare `mr list` is open-only; --all covers merged/closed so projects with no open MR still work
  MR="$(glab mr list --all -o updated_at -S desc -F json --per-page 1 --jq '.[0].iid' 2>/dev/null)"
fi
case "$MR" in ''|*[!0-9]*) MR="" ;; esac   # must be a plain iid, never an error message

if [ -n "$MR" ]; then
  echo; echo "== using MR !$MR =="
  run "mr view (JSON)" glab mr view "$MR" -F json; keys
  echo "  fields skills read (presence only):"
  printf '%s' "$LAST_OUT" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("  (skipped: output was not JSON)"); sys.exit()
for k in ["iid","web_url","state","draft","work_in_progress","title","description","target_branch",
          "source_branch","sha","diff_refs","detailed_merge_status","merge_status","has_conflicts",
          "head_pipeline","pipeline","source_project_id","target_project_id","merged_at","merged_by",
          "changes_count","user_notes_count","blocking_discussions_resolved",
          "merge_when_pipeline_succeeds","auto_merge_enabled","squash","should_remove_source_branch"]:
    print(f"    {k:32}", "PRESENT" if k in d else "-")
print("  detailed_merge_status =", d.get("detailed_merge_status"))'
  run "mr view --comments --unresolved (JSON)" glab mr view "$MR" --comments --unresolved -F json; keys
  run "mr note list (EXPERIMENTAL)" glab mr note list "$MR"
  run "mr diff --raw" glab mr diff "$MR" --raw
  # multi-page output is not one JSON document; ndjson is glab's documented per-item format
  run "raw discussions API (ndjson)" glab api "projects/:id/merge_requests/$MR/discussions" --paginate --output ndjson
  keys
  run "approvers" glab mr approvers "$MR" -F json; keys
  run "approval state (raw API)" glab api "projects/:id/merge_requests/$MR/approval_state"; keys
  run "ci get for MR (JSON)" glab ci get --merge-request "$MR" -F json; keys
  run "ci get, failed jobs only" glab ci get --merge-request "$MR" --status failed -F json; keys
else
  echo; echo "!! no MR found in any state — skipping MR checks (pass an MR iid as \$1)"
fi

run "repo view (JSON)" glab repo view -F json; keys
run "project merge settings (raw API)" glab api "projects/:id"
echo "  merge-policy fields (presence only):"
printf '%s' "$LAST_OUT" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("  (skipped: output was not JSON)"); sys.exit()
for k in ["default_branch","merge_method","squash_option","only_allow_merge_if_pipeline_succeeds",
          "only_allow_merge_if_all_discussions_are_resolved","remove_source_branch_after_merge","merge_trains_enabled"]:
    print(f"    {k:52}", "PRESENT" if k in d else "-")'
run "protected branches (raw API)" glab api "projects/:id/protected_branches"; keys

run "ci status (JSON, current branch)" glab ci status -F json; keys
# `--help` exits 0 on every version, so grep for the flag instead of counting the exit code
echo; echo "### ci status --wait / --pipeline-id in help"
CIHELP="$(glab ci status --help 2>&1)"
for f in --wait --live --pipeline-id; do
  if printf '%s' "$CIHELP" | grep -q -- "$f"; then echo "  ci status $f: PRESENT"; else echo "  ci status $f: absent"; fi
done
run "ci list" glab ci list --per-page 3
[ -n "$JOB" ] && run "ci trace <job>" glab ci trace "$JOB"

# `glab issue list -F` is --output-format (details|ids|urls), not JSON — so use the API here.
ISSUE="$(glab api 'projects/:id/issues?per_page=1' --jq '.[0].iid' 2>/dev/null)"
case "$ISSUE" in ''|*[!0-9]*) echo; echo "!! no issue found — skipping issue view" ;;
  *) run "issue view (JSON)" glab issue view "$ISSUE" -F json; keys ;; esac

echo
echo "--- not covered here (needs a scratch project; see design doc) ---"
echo "  pr-create, pr-checkout, comment-reply, thread-resolve, ci-retry, pr-merge (incl. wrong --sha refusal), ci status --wait exit code"
echo
echo "summary: $pass commands exited 0, $fail non-zero (non-zero is expected where no data exists)"
[ "$pass" -gt 0 ] || exit 2
