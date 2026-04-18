# omh-git-workflow

Claude Code plugin implementing the **OhMyHotel Git Branch Strategy** as 11 interactive slash commands.

See the repo-root [README.md](../../README.md) for the full strategy document (§1–§23) and the [team onboarding guide](../../docs/TEAM-ONBOARDING.md) for install + usage.

## Commands at a glance

| Command | Purpose | Rule §§ |
|---|---|---|
| `/omh-new-branch` | Create work branch from master | §6, §11 |
| `/omh-commit` | Commit with Conventional + 50/72 | §14 |
| `/omh-open-pr` | Open PR to master with full template | §13, §15 |
| `/omh-check-pr` | Audit PR readiness before merge | §13, §15 |
| `/omh-release` | Tech Lead release flow | §8 |
| `/omh-cherry-pick` | Upstream-first bug fix to release | §9 |
| `/omh-reset-develop` | Tech Lead reset of throwaway develop | §6 |
| `/omh-reset-staging` | Tech Lead reset of throwaway staging | §7 |
| `/omh-sync-local` | Dev sync after reset | §6, §7 |
| `/omh-hotfix` | 7-phase hotfix from prod tag | §10 |
| `/omh-rollback` | Production rollback procedure | §20, §21 |

## Design principles

- **UI-first prompts**: every user input uses `AskUserQuestion` (click/arrow-keys), never raw text
- **Safety gates**: destructive actions (force push, tag, revert, cherry-pick) always require explicit confirmation
- **No silent fallbacks**: skills stop and explain rather than auto-resolve (e.g. merge conflicts, dirty working tree)
- **Hard rule enforcement**: skills refuse operations violating the branch strategy (e.g. PR to develop, cherry-pick from work branch, hotfix from master)

## Dependencies

- `mcp-atlassian` MCP server — for Jira validation
- `mcp-bitbucket` or GitHub `gh` CLI — for PR operations
