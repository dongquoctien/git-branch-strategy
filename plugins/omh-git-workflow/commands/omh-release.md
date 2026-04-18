# Create Release (OMH Git Strategy §8)

**Usage**: `/omh-release [version] [description]`

Examples:
- `/omh-release v1.3.0 payment-search`
- `/omh-release` — infer version from latest tag, ask for description

Parse arguments from: $ARGUMENTS
- Optional: version in `v{MAJOR}.{MINOR}.{PATCH}` format
- Optional: kebab-case description

---

## Rules (from README §8 Release Flow + §11 Release branch naming + §15 Tech Lead Policy)

- **Tech Lead responsibility** — creating release branch and pushing tags must be done by Tech Lead (or delegated in team channel)
- Release branch pattern: `release/v{MAJOR}.{MINOR}.{PATCH}-{description}` — full 3-part SemVer + kebab-case slug mandatory
- Abbreviated forms like `release/v1.3` are **NOT permitted** (§11)
- Production deploys **only from tag** on release branch — never from master directly
- Release branch is source of truth — tag on release, not on master
- After deploy: delete release branch (within 1 day per §12)
- Bugs found during staging QA → upstream-first: fix on master → cherry-pick to release (use `/omh-cherry-pick`, never fix directly on release)

---

## Interaction convention — ALWAYS use AskUserQuestion

Use the `AskUserQuestion` tool for every prompt. Do not print numbered text.

Rules:
- `header` ≤12 chars
- 2–4 options; first = recommended (suffix `" (Recommended)"`)
- Destructive last, description prefix `"IRREVERSIBLE: "`
- Tool auto-adds "Other" for free-text — do NOT add it manually
- Bundle independent questions in one call (max 4)

---

## Workflow

### Step 1 — Preflight checks

Run in parallel:
```bash
git branch --show-current
git fetch origin --tags --prune
git tag --sort=-version:refname | head -5
git log origin/master..HEAD --oneline    # ensure local master == remote
git status --porcelain
```

Checks:
- Current user identity — verify this is Tech Lead or delegated person. Ask via `AskUserQuestion`:
  ```
  question: "Release branch creation requires Tech Lead per §15. Who are you?"
  header:   "Role"
  options:
    - "Tech Lead" (Recommended) — description: "Proceed with full flow"
    - "Delegate (announced in team channel)" — description: "Proceed; recorded as delegated"
    - "Neither — cancel" — description: "Stop; escalate to Tech Lead"
  ```
- Working tree must be clean — if not, stop and redirect user to `/omh-commit` or stash
- Local master must match remote — if behind, run `git checkout master && git pull origin master` first
- Extract latest tag → suggest next MINOR bump (e.g. v1.2.0 → v1.3.0)

### Step 2 — Determine version + description

Call `AskUserQuestion` with up to 3 bundled questions:

**Q1 — Bump type** (only if version not supplied):
```
question: "Which version bump?"
header:   "Bump"
options:
  - "Minor (v{X}.{Y+1}.0)" (Recommended) — description: "Standard feature release"
  - "Major (v{X+1}.0.0)" — description: "Breaking changes, platform upgrades"
  - "Patch (v{X}.{Y}.{Z+1})" — description: "Hotfix-style release (usually use /omh-hotfix instead)"
```

**Q2 — Description** (only if not supplied):
Generate 3 candidates from merged commits since last tag (look at `git log {last-tag}..origin/master --oneline`):
```
question: "Choose release description (short slug)"
header:   "Desc"
options:
  - "<candidate-A>" — description: "Primary feature theme"
  - "<candidate-B>" — description: "Most impactful module"
  - "<candidate-C>" — description: "Generic catch-up: multi-feature-batch"
```
Validate picked description: kebab-case, not in `["release", "fix", "update", "hotfix"]`.

**Q3 — Feature scope confirmation**:
List merged PRs since last tag. Ask user to confirm all intended features are merged:
```
question: "N PRs merged to master since {last-tag}. Ready to cut release?"
header:   "Scope"
options:
  - "Yes, cut release with all merged PRs" (Recommended) — description: "Includes all N commits"
  - "Wait — missing feature X" — description: "Cancel; merge the missing PR first"
  - "Exclude some commits" — description: "Requires reverting commits on master first per §8 tip"
```

### Step 3 — Create release branch

```bash
git checkout master
git pull origin master
git checkout -b release/v{X}.{Y}.{Z}-{description} origin/master
git push -u origin release/v{X}.{Y}.{Z}-{description}
```

Report the SHA at HEAD so Tech Lead can reference it later.

### Step 4 — Reset staging to release (§8 step 3)

Confirm via `AskUserQuestion` because it force-pushes staging:
```
question: "Reset staging to release branch? (deploys to Staging env for QA final verification)"
header:   "Reset stg"
options:
  - "Reset staging" (Recommended) — description: "git reset --hard release/... + force-with-lease push"
  - "Skip — will reset later" — description: "Staging reset deferred; do manually with /omh-reset-staging"
  - "Cancel" — description: "Don't reset"
```

If confirmed:
```bash
git checkout staging
git fetch origin staging
git reset --hard release/v{X}.{Y}.{Z}-{description}
git push --force-with-lease origin staging
git checkout release/v{X}.{Y}.{Z}-{description}
```

Remind user: **announce the staging reset in team channel** per §15, and coordinate with QA on timing. Ask via `AskUserQuestion` if already announced.

### Step 5 — Wait for QA sign-off (pause point)

This skill pauses here. The flow resumes with `/omh-release-tag` OR the user re-runs this skill with a `--tag` flag later (see Step 6).

Print status:
> **Release branch**: `release/v{X}.{Y}.{Z}-{description}` pushed
> **Staging**: reset + deploy triggered
> **Next**: QA full regression. If bugs found, use `/omh-cherry-pick` (upstream-first, never fix directly on release)
> After QA sign-off, re-run `/omh-release {version} {description} --tag` to tag and cleanup

### Step 6 — Tag and deploy (when `--tag` flag present OR user confirms)

Preflight re-checks:
- Current branch = release branch (checkout if needed)
- Tag `v{X}.{Y}.{Z}` does not already exist
- QA sign-off confirmation via `AskUserQuestion`:
  ```
  question: "QA has signed off? Tagging will trigger production deploy."
  header:   "QA sign"
  options:
    - "Yes, tag and deploy" (Recommended) — description: "Tech Lead confirmed QA sign-off; CI/CD deploys to prod"
    - "Not yet" — description: "Cancel; wait for QA"
    - "QA found bugs" — description: "Stop; use /omh-cherry-pick for upstream-first fix"
  ```

If confirmed:
```bash
git checkout release/v{X}.{Y}.{Z}-{description}
git tag -a v{X}.{Y}.{Z} -m "Release v{X}.{Y}.{Z}: {description}"
git push origin v{X}.{Y}.{Z}
```

### Step 7 — Post-deploy cleanup

After 30-minute post-deploy validation window (§19) and Tech Lead sign-off, prompt:
```
question: "Deployment validated (error rate OK, health check OK)? Delete release branch?"
header:   "Cleanup"
options:
  - "Delete branch" (Recommended) — description: "Per §12, delete within 1 day of deploy"
  - "Keep branch temporarily" — description: "Hold for potential rollback reference"
  - "Initiate rollback" — description: "Run /omh-rollback instead"
```

If delete:
```bash
git push origin --delete release/v{X}.{Y}.{Z}-{description}
git branch -d release/v{X}.{Y}.{Z}-{description}   # local cleanup
```

### Step 8 — Report

- **Release**: `v{X}.{Y}.{Z}` — {description}
- **Tag pushed**: `v{X}.{Y}.{Z}` at {commit-sha}
- **Production deploy**: triggered by CI/CD
- **Branch**: deleted / kept
- **Next**: Tech Lead monitors §19 Deployment Validation gates for 30 min, signs off

---

## Hard refusals

- Do NOT create release branch from `develop` / `staging` / work branch — only from `origin/master`
- Do NOT tag on master — tag on release branch per §8
- Do NOT push tag without QA sign-off confirmation (production deploys automatically)
- Do NOT merge release → master (release is tagged and deployed, never merged back per §16)
- Do NOT allow release branch names missing patch version (e.g. `release/v1.3` is rejected per §11)

---

## What this skill does NOT do

- Does not approve / merge individual feature PRs (those follow `/omh-open-pr` flow)
- Does not fix bugs during staging (use `/omh-cherry-pick`)
- Does not run hotfix flow (use `/omh-hotfix` — different branching rules)
- Does not perform rollback (use `/omh-rollback`)
- Does not reset develop (use `/omh-reset-develop` after release cycle)
