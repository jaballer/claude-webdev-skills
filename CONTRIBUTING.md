# Contributing

Contributions are welcome. The bar for merging is that a new or changed skill reads like the
existing ones — the house style below is deliberate, not incidental.

## House style for skills

**Atomic vs orchestrator.** A skill either does one job (`run-tests`, `new-branch`) or sequences
other skills (`new-feature`, `ship-it`). Orchestrators delegate with an explicit
**Invoke `/webdev:<skill>`** line — they never re-describe another skill's steps. If you find
yourself copying steps between skills, extract or reference instead.

**Decision logic, not command lists.** The value of a skill is the judgment it encodes — when to
run the full suite vs a targeted one, when a branch is safe to delete, when an inventory is
warranted. A bare list of commands belongs in a README, not a skill. Every rule should say *why*
so the model can generalize it correctly.

**Stack-agnostic.** No skill hardcodes `npm test` or `phpunit`. Anything that runs a project
command resolves it through `/webdev:detect-stack` (which honors `.claude/webdev.json` first).
If your skill needs a command detect-stack doesn't resolve yet, add it to detect-stack's
detection tables *and* its Output contract *and* `examples/webdev.json` — those three must stay
in sync.

**An `## Output` contract per skill.** Every skill ends with a short list of what it reports
back. Callers (orchestrators, users) rely on this shape.

**Frontmatter description = trigger phrases.** The `description:` is what makes the skill fire
automatically. Include concrete user phrasings ("run tests", "ship it", "is this safe?"), what
the skill is for, and — when there's a sibling skill it could be confused with — an explicit
disambiguation line (see `qa-review` vs `post-merge-review`).

**Human authorship by default.** Skills must not add AI co-author trailers or "generated with"
footers unless the project opts in via `webdev.json` (`coAuthorTrailer` / `prFooter`).

**Keep it portable.** No personal project names, local-machine assumptions, or references that
only make sense in one repo. Note BSD vs GNU differences when a shell command diverges.

## Checklist for a PR that adds or changes a skill

- [ ] Frontmatter `description` contains realistic trigger phrases and disambiguates siblings
- [ ] Commands are resolved via `/webdev:detect-stack`, never hardcoded
- [ ] `## Output` contract present and accurate
- [ ] Any new `webdev.json` key is documented in `examples/webdev.json` and the README key table
- [ ] README skill table updated (one row per skill)
- [ ] No AI-attribution defaults; no personal/project-specific references
