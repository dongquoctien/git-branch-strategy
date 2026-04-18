# Plugin Install — Quickstart

Install the **`omh-git-workflow`** Claude Code plugin in under 3 minutes. This guide covers the fastest path; for the full onboarding (MCP setup, cheatsheet, troubleshooting) see [`TEAM-ONBOARDING.md`](./TEAM-ONBOARDING.md).

---

## 1. Introduction

`omh-git-workflow` is a Claude Code plugin distributed via the `ohmyhotel-tools` marketplace. It ships 11 slash commands that automate the OhMyHotel Git Branch Strategy (new branch, commit, PR, release, hotfix, rollback, …).

Once installed, any Claude Code session can use the `/omh-*` commands.

## 2. Prerequisites

| Requirement | Check with |
|---|---|
| Claude Code installed and running | Open Claude Code — CLI, Desktop app, or IDE extension |
| Network access to GitHub.com | `git ls-remote https://github.com/dongquoctien/git-branch-strategy` returns refs |
| Git installed (≥ 2.x) | `git --version` |

> No admin / sudo required. The plugin installs into your **user scope** at `~/.claude/plugins/cache/` — fully isolated from system paths.

For MCP server setup (Jira, Bitbucket/GitHub), see [`TEAM-ONBOARDING.md` §5](./TEAM-ONBOARDING.md#5-mcp-dependencies). Without MCPs the Jira-validating and PR-creating skills will degrade gracefully.

## 3. Installation Steps

Run these three commands inside Claude Code (not your terminal):

### 3.1 Add the marketplace

```
/plugin marketplace add https://github.com/dongquoctien/git-branch-strategy
```

Expected output:
```
Successfully added marketplace: ohmyhotel-tools
```

### 3.2 Install the plugin

```
/plugin install omh-git-workflow@ohmyhotel-tools
```

Choose **"Install for you (user scope)"** when prompted — this makes the commands available in every repo, not just the current one.

Expected output:
```
✓ Installed omh-git-workflow. Run /reload-plugins to apply.
```

### 3.3 Reload plugins

```
/reload-plugins
```

Expected output:
```
Reloaded: 1 plugin · 11 skills · 5 agents · 0 hooks · ...
```

## 4. Configuration

No configuration needed for the plugin itself — skills work out of the box.

**Optional**: if the repo you're working in is under the OhMyHotel git strategy, copy the project `.claude/settings.json` from this repo to pre-approve read-only git commands and deny force-pushes to master:

```bash
cp /path/to/git-branch-strategy/.claude/settings.json .claude/settings.json
```

## 5. Verification

Type `/omh-` in any Claude Code session. Autocomplete should show all 11 commands:

```
/omh-check-pr          Audit PR readiness before merge
/omh-cherry-pick       Upstream-first cherry-pick
/omh-commit            Create commit with Conventional + 50/72
/omh-hotfix            7-phase hotfix from prod tag
/omh-new-branch        Create work branch from master
/omh-open-pr           Open PR to master
/omh-release           Tech Lead release flow
/omh-reset-develop     Tech Lead reset develop → master
/omh-reset-staging     Tech Lead reset staging
/omh-rollback          Production rollback
/omh-sync-local        Sync local develop/staging after reset
```

Smoke test with a safe read-only skill:
```
/omh-check-pr
```
If you're not on a branch with an open PR it should stop cleanly with *"No PR found for branch…"* — that means the skill loaded correctly.

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `/omh-*` commands not in autocomplete | Plugin not reloaded | Run `/reload-plugins` or restart Claude Code |
| `/plugin install` fails with "invalid manifest" | You're on a cached older version (e.g. v1.0.0) | `/plugin marketplace remove ohmyhotel-tools` → re-add → reinstall |
| `/doctor` reports "Plugin error" | Same as above, stale cache | Remove + re-add marketplace |
| Skill reports "Jira ticket not found" on a valid key | `mcp-atlassian` MCP not configured | See [`TEAM-ONBOARDING.md` §5.1](./TEAM-ONBOARDING.md#51-atlassian-jira--required) |
| Skill refuses with "dirty working tree" | Uncommitted changes | Commit or stash first — skills do NOT auto-stash by design |
| Skill refuses PR target `develop` / `staging` | By design — §15 forbids | Open PR to `master` only; develop merges are direct (no PR needed) |

More detail: [`TEAM-ONBOARDING.md` §9 Troubleshooting](./TEAM-ONBOARDING.md#9-troubleshooting).

## 7. Getting Updates

When DevTools publishes a new version (e.g. v1.0.2):

```
/plugin marketplace update ohmyhotel-tools
/plugin update omh-git-workflow@ohmyhotel-tools
/reload-plugins
```

Claude Code only shows the update prompt if `plugin.json` `version` is bumped.

## 8. Support

- **Bug reports / feature requests**: open an issue at https://github.com/dongquoctien/git-branch-strategy/issues
- **Strategy questions** (branching, release cadence): `#git-workflow` on Slack
- **Plugin install issues**: `#devtools` on Slack, or email `devtools@ohmyhotel.com`
