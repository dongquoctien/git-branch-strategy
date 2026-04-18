# omh-git-workflow

Claude Code plugin implementing the **OhMyHotel Git Branch Strategy** as 17 interactive slash commands.

See the repo-root [README.md](../../README.md) for the full strategy document (§1–§23) and the [team onboarding guide](../../docs/TEAM-ONBOARDING.md) for install + usage.

## Commands at a glance

### Daily work (everyone)

| Command | Purpose | Rule §§ |
|---|---|---|
| `/omh-new-branch` | Create work branch from master | §6, §11 |
| `/omh-commit` | Commit with Conventional + 50/72 | §14 |
| `/omh-sync-master` | Rebase/merge branch onto latest master | §16 |
| `/omh-open-pr` | Open PR to master with full template | §13, §15 |
| `/omh-check-pr` | Audit PR readiness (read-only scorecard) | §13, §15 |
| `/omh-fix-pr` | Walk through PR blockers and fix them | §13, §15 |
| `/omh-ci-status` | Check CI gate results per §15 | §15 |
| `/omh-reviewers` | Assign reviewers per Tech Lead Policy | §15 |
| `/omh-delete-branch` | Clean up merged branches | §12 |
| `/omh-status` | Dashboard: branch + PRs + releases + stale | cross-ref |

### Throwaway-branch hygiene

| Command | Who | When |
|---|---|---|
| `/omh-sync-local` | Everyone | After Tech Lead resets develop/staging |
| `/omh-reset-develop` | Tech Lead | End of deploy cycle |
| `/omh-reset-staging` | Tech Lead | Pre-release QA or final verification |

### Release cycle (Tech Lead)

| Command | Purpose | Rule §§ |
|---|---|---|
| `/omh-release` | Tech Lead release flow | §8 |
| `/omh-cherry-pick` | Upstream-first bug fix to release | §9 |

### Emergency (Tech Lead / on-call)

| Command | Purpose | Rule §§ |
|---|---|---|
| `/omh-hotfix` | 7-phase hotfix from prod tag | §10 |
| `/omh-rollback` | Production rollback procedure | §20, §21 |

## Design principles

- **UI-first prompts**: every user input uses `AskUserQuestion` (click/arrow-keys), never raw text
- **Safety gates**: destructive actions (force push, tag, revert, cherry-pick) always require explicit confirmation
- **No silent fallbacks**: skills stop and explain rather than auto-resolve (e.g. merge conflicts, dirty working tree)
- **Hard rule enforcement**: skills refuse operations violating the branch strategy (e.g. PR to develop, cherry-pick from work branch, hotfix from master)
- **Read-first**: `/omh-status` and `/omh-check-pr` never modify state — safe to run anytime

## Dependencies

- `mcp-atlassian` MCP server — for Jira validation
- `mcp-bitbucket` or GitHub `gh` CLI — for PR operations
