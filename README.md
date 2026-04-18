# Git Branch Strategy

# Git Branch Strategy

## 1. Overview

The Git strategy is designed to support a structured workflow across Development, Staging, and Production environments. It ensures code stability, controlled releases, and efficient collaboration among development, QA, and DevOps teams.

This strategy adopts the **Throwaway Branch** model: only `master` is permanent. `develop` and `staging` are throwaway — they are reset freely and are never part of the release path. All release decisions flow through `master` and `release/*` branches only.

---

## 2. Branch Structure

- `master` → Production release source (permanent, never reset)
- `staging` → **Throwaway** — QA/UAT testing environment (reset freely)
- `develop` → **Throwaway** — Developer integration testing (reset freely)
- `{JIRA-KEY}-description` → Work branches (features, bugfixes — from master, no prefix)
- `hotfix/{JIRA-KEY}-description` → Urgent production fixes (from master, only branch type with a prefix)
- `release/*` → Release stabilization, final staging verification before deployment

---

## 3. Core Principles

- Only `master` is permanent — `develop` and `staging` are throwaway and can be reset at any time
- Work branches (features and bugfixes) are created from master using the Jira ticket key as the branch name
- Each feature is independently deployable
- Release decisions are **never** based on develop or staging results — only on master and release branches
- All code flows in a single direction: work branch → master → release → production
- No reverse merges: staging → master, develop → master, or production → master are all forbidden
- Bugfixes found during staging go to master first (upstream first), then cherry-picked to the release branch
- develop syncs to master via periodic reset — no back-merge required

---

## 4. Workflow Diagram

```
Release path (single direction):
  {JIRA-KEY}-desc → master → release/* → tag → production
                         ↑
               fix (upstream first: master first → cherry-pick to release)

Environment deployment (throwaway — NOT part of release path):
  develop ← work branch merge (integration testing, no PR required)
  develop ← master (periodic reset)
  staging ← master + work branch (pre-release QA testing)
  staging ← release/* (final deployment verification)

Forbidden reverse merges:
  ❌ production → master
  ❌ staging → master
  ❌ develop → master
```

| Branch | Nature | Environment | Reset Baseline | Branched From |
| --- | --- | --- | --- | --- |
| master | Permanent | — | Never reset | — |
| staging | Throwaway | Pre-production / QA | master or release/* | master |
| develop | Throwaway | Development | master | master |
| {JIRA-KEY}-description | Short-lived | Local / Dev | — | master |
| release/* | Short-lived | Staging (pre-deploy) | — | master |
| hotfix/{JIRA-KEY}-desc | Short-lived | — | — | master |

---

## 5. Workflow Overview

**Development (integration testing — not release path):**`{JIRA-KEY}-desc → develop → Dev environment`

**Staging — Pre-release QA (before deployment decision):**`master + {JIRA-KEY}-desc → staging → QA`

**Staging — Final deployment verification:**`release/* → staging → QA sign-off`

**Production:**`{JIRA-KEY}-desc → master → release/* → tag → PROD`

---

## 6. Development Flow

`develop` is a throwaway integration branch. It exists for developers to test work together before it is ready for master. It has no influence on release decisions.

1. Create a work branch from master using the Jira ticket key:
    
    ```bash
    git checkout -b ELS-123-description master
    ```
    
2. Each developer working on the same ticket may create a personal sub-branch and merge back into the work branch
3. Merge the work branch into develop for integration testing (no PR required):
    
    ```bash
    git checkout develop
    git merge ELS-123-description
    git push origin develop
    # → auto-deploy to Development environment
    ```
    
4. When the work is ready: rebase onto, or merge with, latest master — then open a PR to master
5. Merge into master after CI + review (see §15 PR Policy)

**Team rules for develop:**
- Never work directly on develop — always work on your own branch
- develop can be reset at any time by the Tech Lead — never create branches from develop
- After a reset, sync your local copy:
`bash   git checkout develop && git fetch origin && git reset --hard origin/develop`

### Periodic develop Reset

Reset develop to master after each deployment cycle, or whenever it becomes stale:

```bash
git checkout develop
git fetch origin
git reset --hard origin/master
git push --force-with-lease
# → develop = master (clean state)
# → re-merge in-progress work branches as needed
```

> **Note:** develop reset eliminates the need for back-merge after hotfixes. Developers keep their work branches rebased onto master — develop reflects the latest integrated state on the next reset.
> 

---

## 7. Staging Flow

`staging` is a throwaway branch with two distinct purposes. One reset switches it between them — no cleanup needed.

| Purpose | What goes on staging | When |
| --- | --- | --- |
| **Pre-release feature testing** | `master + {JIRA-KEY}-desc` | Before deployment decision — QA verifies a feature independently |
| **Final deployment verification** | `release/*` | Right before production deployment — verifies exact code to be deployed |

### Pre-release Feature Testing

```bash
# staging = master + work branch under test
git checkout staging
git reset --hard origin/master
git merge ELS-123-description
git push --force-with-lease
# → deploy to Staging environment → QA team tests
```

Features not yet merged to master can be tested on staging. Testing on staging does not constitute a deployment decision.

### Final Deployment Verification

```bash
# staging = exact release code (right before deploy)
git checkout staging
git reset --hard release/v1.3.0-description
git push --force-with-lease
# → deploy to Staging environment → QA final sign-off
```

**After QA sign-off:** tag the release branch and deploy to production (see §8 Release Flow).

**Team rules for staging:**
- staging can be reset at any time by the Tech Lead — never create branches from staging
- After a reset, sync your local copy:
`bash   git fetch origin && git checkout staging && git reset --hard origin/staging`

---

## 8. Release Flow

`release/*` is the release source of truth. Production is always deployed from a release branch tag — never from master directly.

1. Confirm which features are included in this release. Merge all approved features to master first:
    
    ```bash
    # Each feature merges to master via PR (2 approvals, must include Tech Lead)
    # Work not ready stays on its work branch — do not block the release
    ```
    
2. Create release branch from master:
    
    ```bash
    git checkout -b release/v1.2.0-description master
    ```
    
3. Reset staging to the release branch for final verification:
    
    ```bash
    git checkout staging
    git reset --hard release/v1.2.0-description
    git push --force-with-lease
    # → deploy to Staging environment → QA final verification
    ```
    
4. QA performs full regression. If a bug is found, apply the upstream-first fix (see §9 Bug Fix During Staging) — do not fix directly on the release branch.
> **Tip:** Tech Lead should merge features into master in order of risk — stable, low-conflict features first, higher-risk or widely-touching features last. If the last-merged feature fails QA, reverting only that merge commit keeps the removal clean and minimises impact on other features.
5. After QA sign-off: tag the release branch and deploy to production:
    
    ```bash
    git tag -a v1.2.0 -m "Release v1.2.0: description"
    git push origin v1.2.0
    # → CI/CD detects tag → deploy to production
    ```
    
6. Delete the release branch:
    
    ```bash
    git push origin --delete release/v1.2.0-description
    ```
    

---

## 9. Bug Fix During Staging (Upstream First)

When a bug is found during staging QA, the fix must go to **master first**, then be cherry-picked to the release branch. Never fix directly on the release branch — fixes applied only to release will be missing from future releases.

```
❌ Risky order: fix on release → merge to master (easy to forget, causes future regressions)
✅ Safe order:  fix on master  → cherry-pick to release (impossible to miss)
```

```bash
# 1. Create a work branch from master and fix
git checkout -b ELS-123-fix-description master
# implement fix
git push origin ELS-123-fix-description
# Open PR → master (code review → merge)

# 2. Cherry-pick the fix to the release branch
git checkout release/v1.2.0-description
git cherry-pick <commit-hash-merged-to-master>
git push origin release/v1.2.0-description

# 3. Reset staging to release (reflect the fix)
git checkout staging
git reset --hard release/v1.2.0-description
git push --force-with-lease
# → redeploy staging → QA re-tests
```

> **Cherry-pick rule:** only cherry-pick commits that are already merged to master. Never cherry-pick from a work branch directly to release.
> 

---

## 10. Hotfix Flow

Hotfixes always follow the upstream-first rule: the fix merges to `master` first, then flows to production via an emergency release branch. `hotfix/*` branches never deploy directly — staging and production deployment always happen through a `release/*` branch.

**Always create the hotfix branch from the latest production tag**, not from master or any release branch. This guarantees the hotfix contains only what is currently in production with no unreleased work included.

**Merge strategy rules:**
- Cherry-pick only the hotfix commit into any active release branch — do not merge the entire hotfix branch
- Never merge the hotfix branch into a release branch — this risks pulling in unrelated commits
- The release branch must remain a clean release candidate

---

**Step 1 — Branch creation**

```bash
# Identify the latest production tag
git fetch --tags
git tag --sort=-version:refname | head -5
# e.g. latest production tag is v1.2.0

# Create hotfix branch from that tag — NOT from master or a release branch
git checkout -b hotfix/OMH-4857-fix-code-generator v1.2.0
```

**Step 2 — Development**

Implement the fix with targeted changes only. No refactoring, no unrelated improvements. Keep commits narrow and single-purpose — the commit SHA will be used for cherry-picking if an active release branch exists.

```bash
git add .
git commit -m "fix(payment): correct coupon code generator overflow"
git push origin hotfix/OMH-4857-fix-code-generator
```

**Step 3 — Merge to master (upstream first)**

Open a PR from the hotfix branch to `master`. This ensures the fix is in master and cannot be missed in any future release.

```bash
# PR: hotfix/OMH-4857-fix-code-generator → master
# 1 approval (need Tech Lead) + CI must pass
```

**Step 4 — Create emergency release branch**

Create the emergency release branch from `master` after the hotfix is merged, bumping the patch version.

```bash
git checkout -b release/v1.2.1-fix-code-generator origin/master
git push origin release/v1.2.1-fix-code-generator
```

**Step 5 — Handle active release branch (if staging is occupied)**

If a release branch is currently being tested on staging, cherry-pick the hotfix commit into it. Use the merge commit SHA from master — never merge the hotfix branch directly.

```bash
# Cherry-pick the hotfix commit into the active release branch
git checkout release/v1.4.0-payment-search
git cherry-pick a3f9c12
git push origin release/v1.4.0-payment-search
```

> ❌ **Never do this:**
> 
> 
> ```bash
> git merge hotfix/OMH-4857-fix-code-generator  # Merges the entire branch history
> ```
> 
> ✅ **Always do this:**
> 
> ```bash
> git cherry-pick <merge-commit-sha-from-master>  # Applies only the specific fix
> ```
> 

If staging is free, skip this step.

**Step 6 — Testing on staging**

Reset staging to the emergency release branch (or the updated active release branch if step 5 was applied) and deploy for QA verification.

> **Tech Lead decides which option applies** based on whether staging is currently occupied by an active release branch.
> 

```bash
# Standard hotfix — reset to the emergency release branch
git checkout staging
git reset --hard release/v1.2.1-fix-code-generator
git push --force-with-lease
# → deploy to Staging → QA targeted regression test

# If an active release branch was updated in step 5, reset staging to that instead
git checkout staging
git reset --hard release/v1.4.0-payment-search
git push --force-with-lease
# → QA re-tests the release candidate with the hotfix applied
```

**Step 7 — Deployment**

After QA approval, tag the release branch and push. CI/CD detects the tag and deploys to production immediately.

```bash
git checkout release/v1.2.1-fix-code-generator
git tag -a v1.2.1 -m "Hotfix v1.2.1: fix coupon code generator overflow"
git push origin v1.2.1
# → CI/CD detects tag → emergency production deployment

# Clean up
git push origin --delete release/v1.2.1-fix-code-generator
git push origin --delete hotfix/OMH-4857-fix-code-generator
```

**develop sync:** develop is reset to master periodically, so the hotfix is naturally reflected on the next reset cycle. No immediate back-merge is required.

---

## 11. Branch Creation Policy

| Type | Pattern | Example | Jira Required? |
| --- | --- | --- | --- |
| Work branch | `{JIRA-KEY}-description` | `ELS-123-add-login-with-google` | Yes |
| release/* | `release/v{MAJOR.MINOR.PATCH}-{description}` | `release/v1.2.0-payment-search` | Yes |
| hotfix/* | `hotfix/{JIRA-KEY}-{desc}` | `hotfix/OMH-4857-fix-code-generator` | Yes |

> `hotfix/*` is the **only** branch type that uses a prefix. All other work branches (features, bugfixes, tasks) use the bare Jira key as the branch name.
> 

**Release branch naming standard:**

The release branch must always use the full three-part semantic version followed by a short description. Abbreviated formats (`release/v1.3`, `release/v1.2`) are not permitted.

| ✅ Correct | ❌ Not permitted |
| --- | --- |
| `release/v1.3.0-payment-search` | `release/v1.3` |
| `release/v1.2.1-hotfix` | `release/v1.2` |
| `release/v2.0.0-platform-upgrade` | `release/v2.0` |

The description must be a short slug (kebab-case, no spaces) that identifies the primary feature or purpose of the release. This makes the branch list scannable and the tag history self-documenting.

**Rules:**
- Must link to a Jira ticket — the Jira key in the branch name is the link
- Description must be clear and specific
- No generic names (e.g., `fix-bug`, `update-code`, `ELS-123`)

---

## 12. Branch Lifecycle

- Work branches must be deleted within 3 days of merging to master
- Stale work branches (no commits for 30+ days) must be reviewed and either closed or rebased
- Stale branches can have an exception for long-running planned work (over 30+ days)
- Release branches must be deleted within 1 day after production deployment
- Hotfix branches must be deleted immediately after merging to master
- develop and staging have no lifecycle — they are reset, not deleted

---

## 13. Pull Request Standards

**Title format:** `<type>(scope): description`

**Types:** `feat`, `fix`, `refactor`, `infra`, `hotfix`, `docs`, `test`, `other`

**Scope** identifies the product domain or service module affected by the change. It must match the area of the codebase — not the Jira project key. Use lowercase, single-word or hyphenated values.

| Scope | Area |
| --- | --- |
| `auth` | Authentication & authorization |
| `payment` | Payment processing |
| `search` | Search and filtering |
| `booking` | Booking and reservation flows |
| `infra` | Infrastructure and DevOps |
| `ui` | Frontend / design system components |
| `api` | Backend API layer |
| `notification` | Email, push, and in-app notifications |

> The PR title follows the conventional commit format. The branch name (e.g. `ELS-123-add-login`) is separate from and does not need to mirror the PR title.
> 

**Example PR:**

```
Title:   feat(auth): add Google OAuth login

Branch:  ELS-123-add-google-oauth-login
Jira:    ELS-123

Summary:
Adds Google OAuth 2.0 as a login option on the web and mobile login screens.
This replaces the manual Google sign-in workaround and reduces login drop-off
for new users who prefer OAuth. No changes to existing email/password flow.

Changed files / components:
- auth-service: OAuthController, GoogleOAuthProvider
- frontend: LoginPage, OAuthButton component
- infra: added GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET to env config

Test evidence:
- Manual test: OAuth login flow verified on Chrome and Safari (screenshots attached)
- Unit tests: OAuthController — 12 new tests, all passing
- CI run: https://ci.example.com/builds/4821

Risk level: Low
- Isolated to auth-service and login UI; no shared utilities modified; easily reverted by feature flag

Rebase confirmation: ✅ Branch rebased onto latest master as of 2026-04-01
```

### Required PR Fields Policy

All fields below are mandatory before a PR can be submitted for review. Reviewers must reject PRs that are missing any field — do not approve and leave a comment asking to fill it in later.

| Field | Required | Guidance |
| --- | --- | --- |
| **Summary** | Always | What changed and why — not how. 2–5 sentences maximum. Focus on intent and business impact. |
| **Changed files / components** | Always | List affected services, modules, or files. Helps reviewers scope their focus and identify unintended side effects. |
| **Test evidence** | Always | Screenshots, test run output, or manual test steps. Incomplete or missing evidence is grounds for rejection. |
| **Risk level** | Always | Low / Medium / High. High risk requires a written justification and triggers mandatory Tech Lead review. |
| **Jira ticket(s)** | Always | At least one linked ticket. PRs without a Jira link must not be merged. |
| **Rebase confirmation** | Always | Author confirms the branch is rebased onto the latest master before requesting review. |
| **Rollback plan** | High-risk PRs | Required when risk level is High. Describe how to revert if the change fails in production. |
| **Migration notes** | DB / infra changes | Required for any schema change, index addition, or infrastructure modification. Include estimated run time and whether it is zero-downtime. |

**Risk level definitions:**

- **Low** — isolated change, single module, no shared dependencies, easily reverted
- **Medium** — touches shared utilities, multiple modules, or has external service dependencies
- **High** — cross-service impact, database migrations, changes to auth/payment/core booking flows, or any change that cannot be quickly reverted

**If test evidence is unavailable** (e.g. environment issue), the author must add a comment explaining why and tag the Tech Lead for explicit sign-off before the PR can proceed.

---

## 14. Git Commit Convention

All commits must follow the **Conventional Commits** format combined with the **50/72 rule** from [Tim Pope’s commit message guidelines](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html).

### Format

```
<type>(<scope>): <subject>          ← subject line: 50 chars or less
                                    ← blank line (mandatory)
<body>                              ← body: wrap at 72 chars per line
                                    ← blank line (optional)
<footer>                            ← footer: issue refs, breaking changes
```

### 50/72 Rule

| Part | Rule | Why |
| --- | --- | --- |
| Subject line | 50 characters or less | Fits cleanly in `git log --oneline`, `git rebase -i`, GitHub UI, and email subjects |
| Body lines | Wrap at 72 characters | Readable in an 80-column terminal after 4-column indent on each side; works correctly with `git format-patch` and email |
| Blank line | Mandatory between subject and body | Required by Git tooling — `git rebase` and other commands break if subject and body are merged |

### Subject line rules

- **50 characters or less** — hard target, not a soft guideline
- **Imperative mood** — write “Fix bug” not “Fixed bug” or “Fixes bug”; this matches messages generated by `git merge` and `git revert`
- **No full stop** at the end of the subject line
- **Lowercase after the type/scope** — e.g. `feat(auth): add Google OAuth login`, not `Add Google OAuth Login`
- **No vague subjects** — “fix bug”, “update code”, “WIP” are not acceptable

### Body rules

- Separate from the subject with a **blank line**
- Wrap each line at **72 characters**
- Explain **what** changed and **why** — not how (the diff shows how)
- Use bullet points where multiple points need covering; use a hyphen or asterisk followed by a single space

### Footer rules

- Reference Jira tickets: `Refs: ELS-123`
- Note breaking changes: `BREAKING CHANGE: <description>`
- One footer entry per line

### Full example

```
feat(auth): add Google OAuth login

Allow users to sign in with their Google account via OAuth 2.0.
This replaces the manual Google sign-in workaround that required
a separate password reset step and reduces login drop-off for new
users who prefer OAuth.

- Adds OAuthController and GoogleOAuthProvider to auth-service
- Adds OAuthButton component to the frontend login screen
- Requires GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in env config

Refs: ELS-123
```

### Quick reference

```
feat(payment): add Apple Pay support        ← 42 chars ✅
fix(booking): resolve session timeout       ← 39 chars ✅
refactor(search): extract filter utilities  ← 43 chars ✅
infra(deploy): add SonarQube quality gate   ← 43 chars ✅
docs(api): update booking endpoint docs     ← 42 chars ✅
fix(auth): fix token expiry edge case       ← 38 chars ✅
```

> **Note:** Commit types and branch types are independent namespaces. `infra` used as a commit type refers to infrastructure-related changes; as a scope it refers to the affected module. `hotfix/*` is a branch naming convention — for the corresponding commit, use `fix` as the type to avoid confusion with the branch prefix.
> 

### Editor setup

Configure your editor to enforce the 72-character body wrap:

```bash
# Git global config — wraps body at 72 chars in the default editor
git config --global core.editor "vim"

# Vim — add to ~/.vimrc
autocmd Filetype gitcommit setlocal spell textwidth=72

# VS Code — install the "Git Commit Lint" extension
# or set in settings.json:
# "git.inputValidationLength": 50
# "git.inputValidationSubjectLength": 50
```

---

## 15. PR Policy

- Pull Request required for all merges **to master**
- develop merges do not require a PR — free merge for integration testing
- Approval requirements by target branch:
    - → `develop`: no PR required — direct merge for integration testing
    - → `master` (work branch): 2 approvals (must include Tech Lead)
    - → `master` (hotfix): 1 approval (need Tech Lead)
- Unit test coverage ≥ 70%
- All PRs must be rebased onto or merged with latest master before creation (zero conflicts required)
- Follow naming and commit conventions

### Tech Lead Involvement Policy

The Tech Lead is a required approver, not an optional reviewer. The following table defines when Tech Lead involvement is mandatory and what their specific responsibility is at each gate.

| Trigger | Tech Lead Action | Blocking? |
| --- | --- | --- |
| Any PR to master (work branch) | Final approval — must be the second approver or explicitly delegate | Yes — merge blocked without approval |
| Any PR to master (hotfix) | Sole required approver — must approve before merge | Yes — merge blocked without approval |
| PR with risk level: High | Must review and sign off on the rollback plan before any other review begins | Yes — reviewers should not start until Tech Lead has acknowledged |
| develop reset | Announces reset in team channel with the sync command; confirms timing does not conflict with active integration tests | Yes — no reset without announcement |
| staging reset | Executes or explicitly delegates the reset; coordinates with QA team on timing | Yes — QA must confirm staging is not mid-test before reset |
| Release branch creation | Creates the release branch from master; confirms included feature list with PM/QA | Yes — no release branch from any other team member without explicit delegation |
| Release tagging | Creates and pushes the version tag; responsible for triggering the CI/CD deployment | Yes — tag must not be pushed by developers |
| Cherry-pick to release | Reviews cherry-pick commit SHA before it is applied to the release branch | Yes — cherry-picks must not be applied without Tech Lead verification |
| Post-deployment (any) | Monitors deployment validation gates for 30 minutes post-deploy; signs off deployment success | Yes — deployment is not considered complete without sign-off |
| Rollback decision | Makes the rollback call; notifies Manager; oversees the rollback procedure | Yes — only Tech Lead or Manager may initiate a rollback |

**Delegation:** If the Tech Lead is unavailable, they must explicitly designate a senior developer as delegate and notify the team. Delegation must be recorded in the team channel before the gated action proceeds.

### CI Enforcement Policy

CI checks are a hard gate — no PR may be merged to master unless all checks pass. There are no exceptions, including for hotfixes.

**Required checks before merge to master:**

| Check | Scope | Failure action |
| --- | --- | --- |
| Build | All PRs to master | Block merge. Author fixes before re-requesting review. |
| Unit tests (≥ 70% coverage) | All PRs to master | Block merge. Coverage drop below threshold is not acceptable even for small PRs. |
| Lint / static analysis | All PRs to master | Block merge. Auto-fixable issues must be fixed locally — do not merge with suppressed warnings. |
| SonarQube quality gate | All PRs to master | Block merge. New critical or blocker issues must be resolved, not marked as won’t fix, without Tech Lead approval. |
| AI code review (automated) | All PRs to master | Non-blocking by default, but flagged High-severity AI findings must be addressed or explicitly acknowledged by a reviewer before approval. |
| Integration tests | staging / release/* deploys | Failure blocks QA sign-off. Must re-run after any fix is applied. |
| Smoke tests | Post-production deploy | Failure triggers rollback procedure (see §22 Rollback Procedure). |

**Fast-track CI for hotfixes:**

Hotfix PRs follow the same CI gate requirements. However, the following accommodations apply:
- The Tech Lead may pre-approve the PR before CI completes, but the merge is still held until CI passes
- If CI fails on a hotfix, the Tech Lead decides whether to fix the failure or roll back the strategy (revert on master)
- Skipping CI on a hotfix is not permitted under any circumstance

**Flaky test policy:**

If a CI check fails due to a known flaky test (i.e. not related to the PR’s changes), the author must:
1. Document the flaky test failure in the PR comment with a link to the known issue
2. Re-run the CI pipeline — if it passes on the second run, the PR may proceed
3. If it fails again, the flaky test must be fixed before the PR is merged, or the Tech Lead must explicitly approve skipping that specific check with a written justification

---

## 16. Merge Strategy

To maintain a clean, readable git history:

- `{JIRA-KEY}-desc → develop`: Direct merge (no PR — integration testing only)
- `{JIRA-KEY}-desc → master`: Rebase before PR (single-developer branches); merge commit for multi-developer branches
- `release → master`: Not applicable — release is tagged and deployed directly, never merged back
- `hotfix/* → master`: Merge commit (preserves hotfix history for audit)
- `master → {JIRA-KEY}-desc` (sync): Rebase (keeps work branches linear)

---

## 17. CI/CD Pipeline Mapping

| Branch | Environment | Deploy Trigger | Tests Run | Merge Requirements |
| --- | --- | --- | --- | --- |
| develop | Development | Auto on push | Unit tests | No PR required |
| staging | Staging / QA | Manual trigger after reset | Integration + E2E tests | No PR required (reset only) |
| release/* | Staging (final) | Manual trigger after reset | Integration + E2E tests | — |
| master | — | No direct deploy | — | 2 approvals (must include Tech Lead) |
| tag push | Production | Auto on tag push | Smoke tests post-deploy | Tag created by Tech Lead |
| hotfix/* | — | No direct deploy | — | 1 approval (need Tech Lead) |

> Production deployments are triggered by tag push, not by a direct deploy from master.
> 

> `hotfix/*` branches merge to master only — they do not deploy directly. Staging verification and production deployment happen via the emergency `release/v{MAJOR.MINOR.PATCH}-hotfix` branch created in §10 Hotfix Flow.
> 

> ⚠️ **CI/CD automation impact:** Previous pipelines that used `feature/**` or `bugfix/**` branch patterns for triggering or filtering must be updated. Work branches now follow the bare `{JIRA-KEY}-*` pattern (e.g. `ELS-*`, `OMH-*`). The only prefixed branch type remaining is `hotfix/**`. Update all pipeline trigger rules, branch filters, and environment guards to match the new naming convention before rolling this strategy out.
> 

---

## 18. AI-Assisted Code Review

- Automated code review (security, performance, code quality)
- Auto comments and suggestions
- PR summary generation
- Risk labeling

**Tools:** GitHub Copilot, Claude, SonarQube

---

## 19. Deployment Validation

All production deployments must pass the following gates before being considered successful:

- Deployment job completed without errors
- Health check endpoint returns HTTP 200
- Error rate within 10 minutes post-deploy is ≤ baseline ± 5%
- Application logs show no new FATAL or ERROR-level entries
- Key business metrics (e.g., booking creation, search, login success rate) are stable

---

## 20. Rollback Trigger

Initiate an immediate rollback if any of the following are observed within 30 minutes of deployment:

- Error rate spike > 5% above baseline
- Critical path failure (search, booking, login, payment processing)
- Database migration failure or data integrity issue
- Critical alert fired in monitoring system

---

## 21. Rollback Procedure

When a rollback trigger is detected, follow these steps immediately:

- **Preferred:** Re-trigger the previous version tag via CI/CD pipeline (fastest, safest):
    
    ```bash
    # CI/CD re-deploys the previously tagged release — no git changes needed
    ```
    
- **If pipeline is unavailable:** revert the merge commit on master and re-tag:
    
    ```bash
    git revert <merge-commit-sha> --no-edit
    git push origin master
    git tag -a v1.2.2 -m "Rollback v1.2.2: revert to pre-v1.2.1 state"
    git push origin v1.2.2
    ```
    
- **Responsible party:** on-call engineer executes rollback; Tech Lead, Manager must be notified immediately
- **Post-rollback:** notify the incident channel, open a post-mortem Jira ticket within 24 hours
- **Version tagging:** new patch tag (e.g., v1.2.2) is required after a rollback-and-refix cycle

---

## 22. Branch Protection Rules

### master (Production release source)

- Require pull request reviews before merging: 2 approvals (must include Tech Lead). Hotfix needs 1 approval (need Tech Lead)
- Dismiss stale approvals when new commits are pushed
- Require status checks to pass before merging: CI pipeline + SonarQube gate
- Direct push forbidden
- Do not allow force pushes or deletions

### staging (Throwaway — Pre-production)

- No PR required — staging is reset directly, not merged into
- Allow force pushes: Tech Leads only (required for staging reset)
- No branch deletion restriction — staging is permanent but freely reset

### develop (Throwaway — Integration)

- No PR required — direct work branch merges allowed for integration testing
- Allow force pushes: Tech Leads only (required for develop reset)
- No branch deletion restriction — develop is permanent but freely reset

---

## 23. Version Tagging

Tags are created on the **release branch** immediately before production deployment. Responsibility: Tech Lead or Manager on duty.

**Semantic versioning convention (MAJOR.MINOR.PATCH):**

- Feature / release deployment → bump MINOR (e.g., v1.2.0 → v1.3.0)
- Hotfix deployment → bump PATCH (e.g., v1.2.0 → v1.2.1)

**Tagging commands:**

```bash
git tag -a v1.3.0 -m "Release v1.3.0: description" && git push origin v1.3.0
git tag -a v1.2.1 -m "Hotfix v1.2.1: brief-description" && git push origin v1.2.1
```

> Tag push triggers the CI/CD deployment pipeline automatically. Do not deploy to production without a tag.
>