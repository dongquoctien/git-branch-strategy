# Git Throwaway Branch Strategy

> **Note:** The term "throwaway" used in this document is borrowed from the official Git documentation
> (gitworkflows), which describes the `seen` branch as a "throw-away integration branch."
> It is not an industry-standard term, but a team-internal term used to describe the core concept of this strategy.

> **Only one permanent branch: main. dev and stg are throwaway. Everything else is short-lived.**
>
> main = release source (production deployment baseline)
> dev = throwaway (developer integration testing, periodic reset to main)
> stg = throwaway (QA/business testing, reset to release or main+feature)

---

## Strategy Foundations

| Concept | Source | Application |
|---------|--------|------------|
| GitLab Flow | [GitLab Official](https://about.gitlab.com/topics/version-control/what-is-gitlab-flow/) | main → release → production (single direction) |
| Throwaway branch | [Git Official gitworkflows](https://git-scm.com/docs/gitworkflows) (`seen` branch) | dev, stg (throwaway, periodic reset) |
| Release branch | [Atlassian Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow) | release/v1.x (release stabilization) |
| Upstream first | [GitLab Flow](https://about.gitlab.com/topics/version-control/what-are-gitlab-flow-best-practices/), [Azure DevOps](https://learn.microsoft.com/en-us/azure/devops/repos/git/git-branching-guidance) | bugfix goes to main first → cherry-pick to release |

### Real-World Examples (Throwaway Environment Branches)

| Company | Branch | Approach |
|---------|--------|----------|
| **Git Project** | `seen` | Periodic rewind & rebuild |
| **Shopify** | `staging` | Overwritten via force-push |
| **Daangn (Korean Startup)** | `deploy` | Selective merge for testing, separated from release path |
| **Netflix** | `test` | Auto-deploy to test environment, integration testing only |

---

## Infrastructure

```
dev environment  — 1 shared server, 11 developers (local also connects to dev DB)
stg environment  — under construction, for QA/business team testing
production       — live service
```

---

## Branch Structure

| Branch | Nature | Role | Environment | Reset Baseline |
|--------|--------|------|-------------|---------------|
| **main** | **Permanent (never reset)** | Integration, release source | — | — |
| **dev** | **Throwaway** | Developer integration testing (shared by 11) | dev env | main |
| **stg** | **Throwaway** | QA/business testing + pre-release feature testing | stg env | release or main+feature |
| **release/v1.x** | Short-lived (1 per release) | Release stabilization, final stg verification | stg env (pre-deploy) | — |
| **feature/*** | Short-lived | Feature development | — | — |
| **hotfix/*** | Short-lived | Emergency fixes | — | — |

---

## Code Flow (Single Direction, No Back-Merge)

```
Release path (single direction):
  feature → main → release → tag → production
                       ↑
                 bugfix (upstream first: main first → cherry-pick to release)

Environment deployment (throwaway, NOT part of release path):
  dev ← feature (free merge, developer integration testing)
  dev ← main (periodic reset)
  stg ← release or main+feature (QA/business testing)

No reverse merges:
  ❌ production → main
  ❌ stg → main
  ❌ dev → main
  ❌ release → main (bugfix cherry-pick is the only exception)
```

---

## dev Branch (Throwaway — Developer Integration Testing)

### Role
- **Not part of the release path** — dev is for developer integration testing only
- Features not yet merged to main can be tested in dev
- Release decisions are never based on dev results
- A dirty dev has **zero impact** on main, stg, or production

### Usage

```bash
# Merge feature to dev (integration testing, no PR required)
git checkout dev
git merge feature/1124-add-user
git push origin dev
# → auto-deploy to dev environment

# Test multiple features together
git checkout dev
git merge feature/A
git merge feature/B
git merge feature/C
git push origin dev
# → dev environment has A+B+C deployed
```

### Periodic Reset

```bash
# After deployment or periodically (weekly, or when dirty)
git checkout dev
git fetch origin
git reset --hard origin/main
git push --force-with-lease
# → dev = main (clean state)
# → re-merge features as needed
```

### Team Rules
- **Never work directly on dev** — work on feature branches, then merge to dev
- **dev can be reset at any time** — never create branches from dev
- After reset, sync locally: `git checkout dev && git fetch origin && git reset --hard origin/dev`

---

## stg Branch (Throwaway — QA/Business Testing)

### Two Purposes

stg is throwaway, so it **switches purposes as needed**:

| Purpose | What goes on stg | When |
|---------|-----------------|------|
| **Pre-release feature testing** | `main + feature/B` (QA verifies before deployment decision) | Before release confirmation |
| **Final deployment verification** | `release/v1.x` (verify exact code to be deployed) | Right before deployment |

### Usage

```bash
# Pre-release testing: main + specific feature
git checkout stg
git reset --hard origin/main
git merge feature/B
git push --force-with-lease
# → deploy to stg environment → QA team tests

# Test multiple features together
git checkout stg
git reset --hard origin/main
git merge feature/A
git merge feature/B
git merge feature/C
git push --force-with-lease
# → stg = main + A + B + C

# Final deployment verification: reset to release
git checkout stg
git reset --hard release/v1.3
git push --force-with-lease
# → stg = release/v1.3 (exact deployment code)
```

**One reset to switch purposes.** No need to worry about what was on stg before.

### Team Rules
- **Throwaway** — can be reset at any time
- Never create branches from stg
- After reset, sync locally: `git fetch origin && git checkout stg && git reset --hard origin/stg`

---

## Workflow

### 1. Feature Development

```
Create feature/1124-add-user from main
    │
    ▼
Develop on feature branch
    │
    ├──→ Merge feature to dev (integration testing, no PR required)
    │         → auto-deploy to dev environment
    │         → integration test with other features
    │
    └──→ Pull latest main, rebase, create PR
         → Code review passes → merge to main
         → Delete feature branch
```

```bash
git checkout -b feature/1124-add-user main
# development work

# Integration test on dev
git checkout dev && git merge feature/1124-add-user && git push origin dev

# Prepare PR to main
git checkout feature/1124-add-user
git fetch origin
git rebase origin/main
# Resolve conflicts per commit → git rebase --continue
git push --force-with-lease
# Create PR → code review → merge to main
```

> **Note:** Use rebase only for single-developer branches. Use merge if multiple developers share the same feature branch.

---

### 2. QA Pre-Release Testing (Before Deployment Decision)

When QA/business team needs to verify feature B, but B is not yet confirmed for deployment:

```bash
# stg = main + feature/B
git checkout stg
git reset --hard origin/main
git merge feature/B
git push --force-with-lease
# → deploy to stg environment → QA team tests
```

**Features not yet merged to main can be tested on stg.**

---

### 3. Release Preparation

```
"Let's deploy A and C this Tuesday"

feature/A → merge to main (PR, code review) ✅
feature/C → merge to main (PR, code review) ✅
feature/B → do NOT merge to main ⏳ (PR stays open)

Create release/v1.3 from main (includes A and C, excludes B)
```

```bash
git checkout -b release/v1.3 main
```

---

### 4. Final stg Verification (Right Before Deployment)

```bash
# Reset stg to release (verify exact deployment code)
git checkout stg
git reset --hard release/v1.3
git push --force-with-lease
# → deploy to stg environment → QA final verification
```

---

### 5. Bug Found During stg Testing (Upstream First)

```
❌ Risky order: fix on release → merge to main (easy to forget)
✅ Safe order: fix on main → cherry-pick to release (impossible to miss)
```

```bash
# 1. Fix on main (upstream first)
git checkout -b bugfix/fix-payment main
# fix the issue
git push origin bugfix/fix-payment
# Create PR to main → review → merge

# 2. Cherry-pick to release
git checkout release/v1.3
git cherry-pick <commit hash merged to main>
git push origin release/v1.3

# 3. Reset stg to release (reflect fix)
git checkout stg
git reset --hard release/v1.3
git push --force-with-lease
# → redeploy stg, QA re-tests
```

**Why upstream first:**
- Fix goes to main first, so it's **impossible** to miss in the next release
- Policy used by Google, Red Hat, and Azure DevOps team

---

### 6. Deployment

```bash
# stg testing passed
git checkout release/v1.3
git tag -a v1.3.0 -m "Release v1.3.0: payment feature, profile improvements"
git push origin v1.3.0
# → CI/CD detects tag → deploy to production

# Delete release branch
git push origin --delete release/v1.3
```

---

### 7. Emergency Fix (Hotfix)

```bash
# 1. Fix on main (upstream first)
git checkout -b hotfix/fix-login main
# fix the issue → PR to main (1 approval + tech lead) → merge

# 2. Emergency release
git checkout -b release/v1.3.1 main

# 3. Quick stg verification
git checkout stg
git reset --hard release/v1.3.1
git push --force-with-lease
# After stg verification:

# 4. Deploy to production
git tag -a v1.3.1 -m "Hotfix v1.3.1: login error fix"
git push origin v1.3.1
# → emergency production deployment
git push origin --delete release/v1.3.1
```

**dev sync:** dev is reset to main periodically, so hotfix is naturally reflected. No back-merge needed.

**If hotfix is needed while release/v1.3 is being tested on stg:**
```bash
# hotfix → merge to main (upstream first)
# cherry-pick to release/v1.3
git checkout release/v1.3
git cherry-pick <hotfix commit hash>
# reset stg to release/v1.3
git checkout stg && git reset --hard release/v1.3 && git push --force-with-lease
# QA re-tests
```

---

## Real-World Scenario: Deploy A and C First, B Tested Separately

### Situation

```
feature/A (payment) — complete, deploy this Tuesday
feature/B (search)  — complete, needs stg testing but deploy next week
feature/C (profile) — complete, deploy this Tuesday
```

### Timeline

```
[Friday]
  Dev integration testing:
    dev reset → main
    feature/A → merge to dev
    feature/B → merge to dev
    feature/C → merge to dev
    → A+B+C integration test on dev environment (developers)

[Monday]
  QA pre-release testing for B:
    stg reset → main + feature/B merge
    → deploy to stg → QA team starts testing B

  Merge A, C to main:
    feature/A → merge to main (PR, code review)
    feature/C → merge to main (PR, code review)

  Release preparation:
    Create release/v1.3 (from main, includes A+C, excludes B)

[Tuesday morning]
  Final deployment verification:
    stg reset → release/v1.3 (A+C only)
    → QA final check

[Tuesday deployment]
  tag v1.3.0 → production (A+C deployed)
  Delete release/v1.3

[Wednesday]
  QA: "B testing passed"
  feature/B → merge to main

[Thursday deployment]
  Create release/v1.4 (includes A+C+B)
  stg reset → release/v1.4
  tag v1.4.0 → production (B added)
```

### Branch State Over Time

```
dev:     ── A+B+C merged (integration test) ─────── reset ──────
main:    ── A merge ── C merge ──────────── B merge ──
                         ↓                    ↓
release:          v1.3(A+C) → tag           v1.4(A+C+B) → tag
                                ↓                           ↓
production:              Tue deploy(A+C)             Thu deploy(+B)

stg:     main+B(pre-test) → v1.3(final check) → v1.4(final check)
         ↑ reset            ↑ reset             ↑ reset
```

---

## stg Switching Scenario

### Long-running big feature test + urgent release check

```bash
# Current: stg = main + feature/big-feature (testing for 2 weeks)
# Urgent: need to verify release/v1.3.1 (hotfix)

# Switch
git checkout stg
git reset --hard release/v1.3.1
git push --force-with-lease
# → hotfix verified

# Switch back
git checkout stg
git reset --hard origin/main
git merge feature/big-feature
git push --force-with-lease
# → continue big feature testing
```

**Throwaway means you can switch to any state, at any time.**

---

## Tags (Version Tags)

### Why Needed

| Without tags | With tags |
|-------------|-----------|
| "What's deployed to production?" → dig through commit hashes | `git tag` → v1.3.0, v1.3.1 instant list |
| Rollback: "Which commit?" | Rollback to `v1.2.0` — clear |
| CI/CD: "Which commit to deploy?" | tag push → auto deployment trigger |
| 6 months later: "What did we deploy then?" | `git show v1.3.0` → instant answer |

### 3 Key Purposes
1. **Version tracking**: record which version is deployed to production
2. **Rollback**: instantly revert to previous tag on issues
3. **CI/CD automation**: tag creation triggers deployment pipeline

### Semantic Versioning (MAJOR.MINOR.PATCH)
- feature/release deployment → MINOR bump (v1.2.0 → v1.3.0)
- hotfix deployment → PATCH bump (v1.3.0 → v1.3.1)

```bash
# Create tag
git tag -a v1.3.0 -m "Release v1.3.0: payment feature added"
git push origin v1.3.0

# Rollback — trigger previous tag redeployment via CI/CD
```

---

## Team Rules Summary

### main
- PR + code review required
- Direct push forbidden
- **Never reset**
- The only permanent branch

### dev
- **Throwaway** — can be reset at any time
- Developer integration testing only (shared by 11 developers)
- Free merge of features (no PR required)
- Periodic reset to main
- Never work directly on dev
- Never create branches from dev
- **Not part of release path** — never make deployment decisions based on dev

### stg
- **Throwaway** — can be reset at any time
- Pre-release testing: `main + feature merge`
- Final verification: `reset to release`
- Never create branches from stg

### release/*
- Created from main, contains only deployment-ready code
- No new features allowed, only bugfixes (via upstream first)
- Deleted after deployment

### feature/*
- Created from main
- Merged to main via PR + code review
- Deleted after merge
- Rebase only for single-developer branches

### hotfix/*
- Created from main
- Merged to main first (upstream first)
- Create release/v1.x.1 → stg verification → tag → emergency deployment

---

## Verification Sources

| # | Item | Source |
|---|------|--------|
| 1 | Feature branches from main | GitHub Flow, GitLab Flow standard |
| 2 | Rebase before PR | [Atlassian — Merging vs Rebasing](https://www.atlassian.com/git/tutorials/merging-vs-rebasing) |
| 3 | Throwaway branch (seen) | [Git Official — gitworkflows](https://git-scm.com/docs/gitworkflows) |
| 4 | Throwaway branch (deploy) | [Daangn — deploy branch strategy](https://medium.com/daangn/deploy-%EB%B8%8C%EB%9E%9C%EC%B9%98-%EC%A0%84%EB%9E%B5-%ED%99%9C%EC%9A%A9-%EB%B0%A9%EB%B2%95-545f278ca878) |
| 5 | Throwaway staging (force-push) | [Shopify — How we use git](https://shopify.engineering/how-we-use-git-at-shopify) |
| 6 | Throwaway test branch | [Netflix — How We Build Code](https://netflixtechblog.com/how-we-build-code-at-netflix-c5d9bd727f15) |
| 7 | Release branch stabilization | [Atlassian — Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow) |
| 8 | Main stays open during release | [Harness — Release Branching](https://www.harness.io/blog/the-basics-of-release-branching) |
| 9 | Tag-based production deployment | [Deployment Strategy using Git Tags](https://www.adamdrake.dev/blog/a-deployment-strategy-using-git-tags) |
| 10 | Upstream first (bugfix) | [GitLab Flow Best Practices](https://about.gitlab.com/topics/version-control/what-are-gitlab-flow-best-practices/) |
| 11 | Upstream first (Microsoft) | [Azure DevOps — Git branching guidance](https://learn.microsoft.com/en-us/azure/devops/repos/git/git-branching-guidance) |
| 12 | Single direction flow | [GitLab Flow Official](https://about.gitlab.com/topics/version-control/what-is-gitlab-flow/) |
| 13 | Scheduled release + release branch | [Release Train Model](https://pingcap.github.io/tidb-dev-guide/project-management/release-train-model.html) |
| 14 | Web/API service suitability | [Git Branching Strategy Comparison](https://devops.aibit.im/article/git-branching-strategy-comparison) |
| 15 | Hwahae — Git Flow migration case | [Hwahae Blog](https://blog.hwahae.co.kr/all/tech/14184) |
