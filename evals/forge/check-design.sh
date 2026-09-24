#!/usr/bin/env bash
# Lints docs/forge-adapter-design.md against the mistakes automated review kept finding, so they
# fail locally instead of costing a review round. Needs only python3; reads the repo, no network.
#
#   bash evals/forge/check-design.sh [path/to/design.md]
#
# Checks (each mirrors a class of real review finding on PR #41):
#   1. every verb in the verb table has a row in "Output contracts", and vice versa
#   2. every enum the shapes rely on is defined in "Normalized enums", plus the "unknown" rule
#   3. every verb-table row carries a verification tag (flags ✓ / GitHub ✓ / endpoint ✗ / live ✗)
#   4. paginated GitHub read endpoints (comments, status, check-runs, statuses) say --paginate
#   5. every `gh` call in the skills maps to a verb that exists in the table (no silent gaps)
#   6. no stale terms (bare `forgeHost`, a repo-only `--repo <owner/repo>` target)
# Exit 1 with a list of failures; 0 when clean.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOC="${1:-$ROOT/docs/forge-adapter-design.md}"
SKILLS="$ROOT/plugins/webdev/skills"
python3 - "$DOC" "$SKILLS" <<'PY'
import re, sys, glob, os
doc = open(sys.argv[1], encoding="utf-8").read()
skills_dir = sys.argv[2]
fails = []

def section(title_re, end_re=r"^#{2,3} "):
    m = re.search(r"^#{2,3} " + title_re + r".*$", doc, re.M)
    if not m:
        return ""
    rest = doc[m.end():]
    e = re.search(end_re, rest, re.M)
    return rest[: e.start()] if e else rest

def rows(text):
    return [l for l in text.splitlines() if l.startswith("| `")]

def verb_of(row):
    m = re.match(r"\| `([a-z][a-z-]*)", row)
    return m.group(1) if m else None

vt = section("Verb table")
verb_rows = rows(vt)
verbs = [verb_of(r) for r in verb_rows]
oc = section("Output contracts")
contract_verbs = [verb_of(r) for r in rows(oc)]

# 1
for v in verbs:
    if v not in contract_verbs:
        fails.append(f"[1] verb `{v}` has no row in 'Output contracts'")
for v in contract_verbs:
    if v not in verbs:
        fails.append(f"[1] 'Output contracts' lists `{v}` which is not in the verb table")

# 2
enums = section("Normalized enums")
for name in ["state", "checks[].state", "mergeable", "mergeState", "reviewState", "user"]:
    if f"**`{name}`**" not in enums:
        fails.append(f"[2] enum `{name}` is not defined in 'Normalized enums'")
if "unrecognized native" not in enums:
    fails.append("[2] 'Normalized enums' must state the unrecognized-value -> unknown rule")

# 3
for r in verb_rows:
    last = r.rstrip().rstrip("|").rsplit("|", 1)[-1]
    if not re.search(r"✓|✗", last):
        fails.append(f"[3] `{verb_of(r)}` row has no verification tag in its last column")

# 4
WRITES = {"comment-reply", "pr-comment", "thread-resolve", "pr-create", "pr-edit", "pr-merge"}  # POST/mutations: nothing to paginate
for r in verb_rows:
    if verb_of(r) in WRITES:
        continue
    for cell in r.split("|"):
        if "gh api" in cell and re.search(r"/(comments|status|check-runs|statuses)\b", cell) \
                and "--paginate" not in cell:
            fails.append(f"[4] `{verb_of(r)}`: a `gh api` list endpoint is not paginated")
            break

# 5 — every gh call in the skills must map to a verb in the table
SUB = {("pr","view"):"pr-view",("pr","create"):"pr-create",("pr","edit"):"pr-edit",("pr","list"):"pr-list",
       ("pr","checkout"):"pr-checkout",("pr","checks"):"pr-checks",("pr","diff"):"pr-diff",
       ("pr","merge"):"pr-merge",("pr","update-branch"):"pr-update-branch",("pr","comment"):"pr-comment",
       ("repo","view"):"repo-view",("run","list"):"ci-runs",("run","view"):"ci-logs",
       ("run","rerun"):"ci-rerun",("run","watch"):"ci-watch",("issue","view"):"issue-view"}
IGNORED = {("pr","close")}  # `sync-main` states it as a NEVER-run rule, not a call
API = [(r"repos/[^ ]*/commits/[^ ]*/(status|check-runs)", "commit-checks"),
       (r"repos/[^ ]*/branches/[^ ]*/protection", "branch-protection"),
       (r"repos/[^ ]*/pulls/[^ ]*/comments", "comments-list"),
       (r"repos/[^ ]*/issues/[^ ]*/comments", "pr-comment"),
       (r"graphql", "comments-list"), (r"\buser\b", "whoami")]
for f in sorted(glob.glob(os.path.join(skills_dir, "*", "SKILL.md"))):
    skill = os.path.basename(os.path.dirname(f))
    text = open(f, encoding="utf-8").read()
    for m in re.finditer(r"\bgh (pr|run|issue|repo) ([a-z][a-z-]*)", text):
        key = (m.group(1), m.group(2))
        if key in IGNORED:
            continue
        v = SUB.get(key)
        if v is None:
            fails.append(f"[5] {skill}: `gh {key[0]} {key[1]}` has no verb mapping in this lint or the doc")
        elif v not in verbs:
            fails.append(f"[5] {skill}: `gh {key[0]} {key[1]}` needs verb `{v}`, which is not in the verb table")
    for m in re.finditer(r"\bgh api\b[^\n]{0,120}", text):
        seg = m.group(0)
        if not re.search(r"repos/|graphql|\buser\b", seg):
            continue  # prose mention, not a call
        hit = [v for pat, v in API if re.search(pat, seg)]
        if not hit:
            fails.append(f"[5] {skill}: unmapped `gh api` call: {seg.strip()[:70]}")
        elif not any(v in verbs for v in hit):
            fails.append(f"[5] {skill}: `gh api` call needs one of {hit}, none in the verb table")

# 6
if re.search(r"forgeHost(?!s)", doc):
    fails.append("[6] stale term: bare `forgeHost` (should be `forgeHosts`)")
if re.search(r"--repo <owner/repo>", doc):
    fails.append("[6] a target contract is repo-only (`--repo <owner/repo>`); targets must carry the host")

if fails:
    print(f"design lint: {len(fails)} problem(s)")
    for x in fails:
        print("  -", x)
    sys.exit(1)
print(f"design lint: clean ({len(verbs)} verbs, {len(contract_verbs)} contracts)")
PY
