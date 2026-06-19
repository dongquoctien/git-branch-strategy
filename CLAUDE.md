# CLAUDE.md — Repo guide for Claude Code

## What this repo is

This repo is the **source of truth** for:

1. The OhMyHotel **Git Branch Strategy** — a formal document (see `README.md`) defining the Throwaway-Branch workflow, PR policy, release flow, hotfix procedure, and rollback rules used across all company repos (`oh-admin`, `oh-api`, `ohmytrip-pc`, etc.).
2. A **Claude Code plugin marketplace** (`ohmyhotel-tools`) that distributes slash commands implementing the company's engineering policies. Two plugins today:
   - `omh-git-workflow` — the Git Branch Strategy (cites `README.md` §§); its `/omh-voc-migration` skill additionally cites `docs/SOP-SQL-VALIDATION.md` for the VOC-SQL-to-Production flow
   - `omh-sla-workflow` — the SLA Policy: incident triage + Post-Incident Reviews (cites `docs/SLA-POLICY.md` §§)

This repo is not an application. Do not treat it as a deployable service. Changes here affect how every engineer at OhMyHotel uses Claude Code for git operations — prioritize clarity and conservative safety defaults.

## Layout

```
git-branch-strategy/
├── README.md                              Full strategy doc (§1–§23) — authoritative
├── CLAUDE.md                              This file
├── docs/
│   └── TEAM-ONBOARDING.md                 Install + quick-start for engineers
├── .claude-plugin/
│   └── marketplace.json                   Marketplace manifest (name: ohmyhotel-tools)
├── .claude/
│   └── settings.json                      Project-level permission allowlist template
└── plugins/
    └── omh-git-workflow/
        ├── .claude-plugin/
        │   └── plugin.json                Plugin manifest (version, commands, deps)
        ├── README.md                      Plugin-level overview
        └── commands/
            ├── omh-new-branch.md
            ├── omh-commit.md
            ├── omh-open-pr.md
            ├── omh-check-pr.md
            ├── omh-release.md
            ├── omh-cherry-pick.md
            ├── omh-reset-develop.md
            ├── omh-reset-staging.md
            ├── omh-sync-local.md
            ├── omh-hotfix.md
            └── omh-rollback.md
```

## How the pieces relate

- `README.md` defines the **rules**. Every skill file cites the relevant `§` sections.
- Each skill in `plugins/omh-git-workflow/commands/*.md` **enforces** those rules interactively.
- The marketplace wraps everything so engineers install with two slash commands instead of cloning this repo manually (see `docs/TEAM-ONBOARDING.md`).

## Conventions for editing skills

When modifying any `commands/omh-*.md`:

1. **Every user prompt uses `AskUserQuestion`** — never print "type 1/2/3" and wait for text. `header` ≤12 chars; first option is `(Recommended)`; destructive options last with `IRREVERSIBLE:` prefix. See the top of each skill file for the full convention block.
2. **Cite rule sections** when a skill enforces a rule — `(§10 step 5)`, `(§14 note)`, etc. This keeps skills auditable against the strategy doc.
3. **No silent auto-fixes** — skills stop and surface the problem (dirty working tree, merge conflict, rebase behind master) rather than running `git stash`, `git checkout .`, `git rebase` etc. without explicit consent.
4. **Never bypass**: `--no-verify`, `--force` (use `--force-with-lease`), `--amend` — skills refuse unless the user asks explicitly.
5. **Delegate to other skills** rather than duplicating logic. `/omh-release` calls `/omh-cherry-pick` for bugs during staging; `/omh-hotfix` calls `/omh-open-pr` for the PR phase.

## Versioning & release of the plugins

Each plugin follows SemVer **independently**. A plugin's version lives in two places that must stay in sync (the `validate-manifest` CI enforces this per plugin):

- `plugins/<plugin>/.claude-plugin/plugin.json` → `version`
- the matching `.claude-plugin/marketplace.json` `plugins[]` entry → `version`

The marketplace itself has its own version at `.claude-plugin/marketplace.json` → `metadata.version`. Bump it when the **marketplace** changes (adding/removing a plugin, editing descriptions) — CI requires this whenever `marketplace.json` changes.

When changing a skill, bump that plugin's version:

- **Patch** (`1.0.0 → 1.0.1`): bug fix, wording clarification, same interaction contract
- **Minor** (`1.0.0 → 1.1.0`): new skill added, new optional argument, new AskUserQuestion branch
- **Major** (`1.0.0 → 2.0.0`): rule change that alters what the skill refuses or forces; command rename/removal; argument signature change

### Tag scheme (multi-plugin)

- `omh-git-workflow` keeps the **historical bare scheme**: `v<version>` (e.g. `v2.0.0`). Do NOT rename the existing `v1.x`/`v2.x` tags — they're git-workflow's.
- Every other plugin is **namespaced**: `<plugin-name>-v<version>` (e.g. `omh-sla-workflow-v1.0.0`).

### Tagging is automated

`.github/workflows/auto-tag-plugin.yml` runs on every push to `master` that touches a manifest. For each plugin whose version changed it creates and pushes the correct tag (per the scheme above), and refuses to move an existing tag. **So after a version-bump PR merges, you normally do nothing** — the tag appears automatically. Claude Code uses these tags + `plugin.json version` to decide whether to offer users an update; a tag without a version bump is ignored.

Manual fallback (only if the workflow is disabled/broken), tagging the master merge commit:
```bash
git fetch origin master && git checkout master && git pull
# omh-git-workflow:
git tag -a vX.Y.Z -m "Release vX.Y.Z: <short>" && git push origin vX.Y.Z
# any other plugin:
git tag -a <plugin>-vX.Y.Z -m "Release <plugin> vX.Y.Z" && git push origin <plugin>-vX.Y.Z
```
Keep old tags on patch rollovers — they're historical markers; never delete.

## Adding a new skill

1. Create `plugins/omh-git-workflow/commands/omh-<action>.md`
2. Top section: `**Usage**:`, `**Example**:`, `**Parse arguments from**: $ARGUMENTS`
3. `## Rules` block quoting the relevant `§` sections from `README.md`
4. `## Interaction convention — ALWAYS use AskUserQuestion` block (copy from any existing skill)
5. `## Workflow` — ordered Steps, each ending with a `AskUserQuestion` call or a git command block
6. `## Hard refusals` — operations the skill must not perform even if asked
7. `## What this skill does NOT do` — delegation pointers to other `/omh-*` skills
8. Add entry to `plugin.json` `commands` array + bump version
9. Add entry to `docs/TEAM-ONBOARDING.md` cheatsheet
10. Commit all three files together

## Adding a new plugin to the marketplace

1. Create `plugins/<plugin-name>/` mirroring the `omh-git-workflow` layout
2. Add an entry to `.claude-plugin/marketplace.json` `plugins` array
3. Bump marketplace `metadata.version`
4. Tag repo; users pick it up via `/plugin marketplace update ohmyhotel-tools`

## Roadmap (deferred)

Phase 5B — 3 items logged for future consideration after pilot feedback on v1.2.0. All items must remain rule-aligned (§) to stay in scope:

1. **`/omh-validate-deploy`** — monitor §19 Deployment Validation gates for 30 min post-tag-push (health check, error rate, logs, business metrics). Maps §19 + §15 post-deploy responsibility.
2. **`/omh-request-ai-review`** — trigger §18 AI review tools (Copilot, Claude, SonarQube). Complements `/omh-ci-status` which only monitors.
3. **`generate-release-notes.yml`** — GitHub Action: on tag push, generate GitHub Release notes from commits + Jira keys. Maps §23. Plugin-repo infra like `validate-manifest.yml`.

Explicitly **NOT** on the roadmap (rejected as out-of-scope for git-branch-strategy): `/omh-stash`, `/omh-babysit-pr` (built-in `/loop` covers it), `/omh-weekly-report`, `/omh-jira-update` (belongs in a potential separate `omh-jira-workflow` plugin).

## Do NOT

- Do not remove rules from skills without updating `README.md` first — the doc is authoritative
- Do not add skills that bypass CI gates, PR approvals, or Tech Lead involvement (per §15)
- Do not add skills that don't map to a specific `§` section of a governing policy doc — `omh-git-workflow` skills map to `README.md` (the `/omh-voc-migration` skill also maps to `docs/SOP-SQL-VALIDATION.md`); `omh-sla-workflow` skills map to `docs/SLA-POLICY.md`. A skill that fits no policy doc needs a new doc (add it first) or a new plugin.
- Do not commit real Jira keys, PR numbers, or internal URLs as examples — use placeholders like `ELS-123`, `OMH-4857`
- Do not store secrets in plugin files (they are git-tracked and distributed to every engineer)
