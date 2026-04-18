# CLAUDE.md — Repo guide for Claude Code

## What this repo is

This repo is the **source of truth** for:

1. The OhMyHotel **Git Branch Strategy** — a formal document (see `README.md`) defining the Throwaway-Branch workflow, PR policy, release flow, hotfix procedure, and rollback rules used across all company repos (`oh-admin`, `oh-api`, `ohmytrip-pc`, etc.).
2. A **Claude Code plugin marketplace** (`ohmyhotel-tools`) that distributes slash commands implementing the strategy. One plugin today: `omh-git-workflow`.

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

## Versioning & release of the plugin itself

The plugin follows SemVer in two places that must stay in sync:

- `plugins/omh-git-workflow/.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → `plugins[0].version`

When changing a skill, bump:

- **Patch** (`1.0.0 → 1.0.1`): bug fix, wording clarification, same interaction contract
- **Minor** (`1.0.0 → 1.1.0`): new skill added, new optional argument, new AskUserQuestion branch
- **Major** (`1.0.0 → 2.0.0`): rule change that alters what the skill refuses or forces; command rename/removal; argument signature change

Tag the repo with the version (e.g. `v1.1.0`) after merge. Claude Code uses git tags + `plugin.json version` to decide whether to prompt users to update. A new tag **without** a version bump will be ignored.

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

## Do NOT

- Do not remove rules from skills without updating `README.md` first — the doc is authoritative
- Do not add skills that bypass CI gates, PR approvals, or Tech Lead involvement (per §15)
- Do not commit real Jira keys, PR numbers, or internal URLs as examples — use placeholders like `ELS-123`, `OMH-4857`
- Do not store secrets in plugin files (they are git-tracked and distributed to every engineer)
