# Team Onboarding — OMH Claude Code Plugin

Install **`omh-git-workflow`** once and every git operation (new branch, commit, PR, release, hotfix, rollback) becomes a guided slash command that enforces the company strategy.

Estimated setup time: **5 minutes** (plus a one-time MCP config if not already done).

---

## 1. Prerequisites

| Requirement | Why | How |
|---|---|---|
| Claude Code installed | Runs the plugin | https://docs.claude.com/claude-code |
| `git` in PATH | Skills shell out to git | `git --version` should print 2.x+ |
| Access to GitHub | Plugin lives in `dongquoctien/git-branch-strategy` | Public repo — no auth needed to read |
| `mcp-atlassian` MCP configured | Jira validation in skills (`/omh-new-branch`, `/omh-hotfix`…) | See §5 below |
| `mcp-bitbucket` or `gh` CLI | PR operations | See §5 below |

---

## 2. Install the marketplace (one-time)

Open Claude Code in any repo and run:

```
/plugin marketplace add https://github.com/dongquoctien/git-branch-strategy
```

> This is the current location. If the repo is later transferred to an organization, the URL will auto-redirect — you won't need to re-run this step.

Confirm:
```
/plugin marketplace list
```
You should see `ohmyhotel-tools` in the list.

---

## 3. Install the plugin

```
/plugin install omh-git-workflow@ohmyhotel-tools
```

After install, reload plugins (or restart Claude Code):
```
/reload-plugins
```

Verify the 11 commands are available — type `/omh-` and autocomplete should list them.

---

## 4. Getting updates

The plugin is versioned. When DevTools publishes a new release:

```
/plugin marketplace update ohmyhotel-tools
/plugin update omh-git-workflow@ohmyhotel-tools
```

Claude Code only offers the update when `plugin.json` `version` is bumped — so running this periodically is safe and cheap.

---

## 5. MCP dependencies

The skills talk to Jira and your git host via **MCP servers**. These are configured in your Claude Code settings (usually `~/.claude/settings.json` or `~/.claude.json`).

### 5.1 Atlassian (Jira) — required

Used by `/omh-new-branch`, `/omh-open-pr`, `/omh-hotfix`, `/omh-rollback`.

Minimal config (ask DevTools for the exact server package and credentials):

```json
{
  "mcpServers": {
    "mcp-atlassian": {
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {
        "JIRA_URL": "https://ohmyjira.atlassian.net",
        "JIRA_USERNAME": "you@ohmyhotel.com",
        "JIRA_API_TOKEN": "<your-token>"
      }
    }
  }
}
```

### 5.2 Bitbucket (if using Bitbucket)

```json
{
  "mcpServers": {
    "bitbucket": {
      "command": "npx",
      "args": ["-y", "@your-org/mcp-bitbucket"],
      "env": {
        "BITBUCKET_USERNAME": "you",
        "BITBUCKET_APP_PASSWORD": "<app-password>"
      }
    }
  }
}
```

### 5.3 GitHub (if using GitHub)

Either the GitHub MCP server OR the `gh` CLI authenticated with `gh auth login`. Skills auto-detect which remote is in use.

---

## 6. Quick start — your first work day with the plugin

**Scenario**: you have a new Jira ticket `ELS-234` "add dark mode toggle".

```
# 1. Create branch from master (skill validates Jira, kebab-case, clean tree)
/omh-new-branch ELS-234

# (implement changes in your editor)

# 2. Commit with the 50/72 convention (auto-fills type/scope from diff)
/omh-commit

# 3. Open PR to master (auto-fills all required fields from §13)
/omh-open-pr

# 4. Before asking for review, audit readiness
/omh-check-pr
```

That covers **95% of daily work**. The other 8 commands are situational (release cycle, hotfix, staging reset) — most engineers only touch `/omh-sync-local` and `/omh-cherry-pick` occasionally.

---

## 7. Full cheatsheet — all 11 commands

### Daily work (everyone)

| Command | When | Key rules |
|---|---|---|
| `/omh-new-branch <JIRA-KEY>` | Starting a ticket | Branch = `{KEY}-{desc}`, from `origin/master`, no `feature/` prefix |
| `/omh-commit` | Staging → commit | `<type>(<scope>): <subject>` ≤50 chars, body 72 wrap, auto `Refs: KEY` |
| `/omh-open-pr` | Ready for review | All 8 required fields, rebase check, risk inference |
| `/omh-check-pr` | Before merge | Field audit + CI + approvals + rebase scorecard |

### Throwaway-branch hygiene

| Command | Who | When |
|---|---|---|
| `/omh-sync-local [develop\|staging]` | Everyone | After Tech Lead resets develop/staging |
| `/omh-reset-develop` | Tech Lead only | End of deploy cycle, or develop stale |
| `/omh-reset-staging [feature\|release]` | Tech Lead only | Pre-release QA or final verification |

### Release cycle (Tech Lead)

| Command | When | Key rules |
|---|---|---|
| `/omh-release [version] [desc]` | Cut a release | Branch from master, full `v{X.Y.Z}-{desc}` name |
| `/omh-cherry-pick [sha]` | Bug found on staging | Upstream-first — only pick commits already on master |

### Emergency (Tech Lead / on-call)

| Command | When | Key rules |
|---|---|---|
| `/omh-hotfix <JIRA-KEY>` | Urgent prod fix | Branch from prod TAG, upstream-first, emergency release |
| `/omh-rollback [target-tag]` | §20 trigger fires within 30 min of deploy | Prefer pipeline re-trigger; fallback revert+re-tag |

---

## 8. What each command will NOT do (on purpose)

- **No auto-stash**: dirty working tree → skill stops, asks you to commit/stash manually
- **No auto-rebase**: behind master → skill stops, tells you to rebase (conflicts are your call)
- **No auto-merge**: skills never merge a PR without explicit Tech Lead confirmation
- **No `--no-verify`**: CI/pre-commit hooks are non-bypassable per §15
- **No `--force` on shared branches**: always `--force-with-lease`; raw `--force` is refused

If you hit a case where you think a skill should auto-resolve something, open a DevTools ticket — the conservative default is deliberate.

---

## 9. Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| `/omh-*` commands don't appear | Plugin not reloaded | `/reload-plugins` or restart Claude Code |
| Skill says "Jira ticket not found" | MCP not configured or token expired | Re-run §5.1; check token |
| Skill says "No PR found" | No upstream or PR not created yet | Run `/omh-open-pr` first |
| Skill refuses to create branch | Dirty working tree | Commit/stash first, or re-run and pick "Stash" in the UI |
| `/plugin install` fails | Marketplace URL wrong or no repo access | Re-check §2, verify you can `git clone <url>` |
| Update not appearing | `plugin.json` version not bumped by publisher | Ping DevTools; or wait for next release |

---

## 10. Contributing

The strategy doc (`README.md` in the source repo) is authoritative. If you believe a skill enforces the wrong rule:

1. Open a discussion in the team channel first — the rule may be intentional
2. If consensus says the rule is wrong, update `README.md` first, then the skill
3. PR to `dongquoctien/git-branch-strategy` with a clear `§` reference for the change
4. Version bump follows SemVer (see `CLAUDE.md` in that repo)

---

## 11. Getting help

- `#devtools` channel on Slack — plugin questions
- `#git-workflow` channel — strategy questions (branching, release cadence, etc.)
- Email: `devtools@ohmyhotel.com`
