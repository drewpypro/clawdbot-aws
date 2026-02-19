# Branch Protection & Rulesets Guide

This document covers the GitHub branch protection ruleset configuration for `drewpypro/clawdbot-aws`, including what each setting does, why we chose our configuration, and lessons learned during setup.

---

## Table of Contents

- [Overview](#overview)
- [Ruleset Configuration](#ruleset-configuration)
  - [Bypass List](#bypass-list)
  - [Target Branches](#target-branches)
  - [Branch Rules](#branch-rules)
- [Required Status Checks](#required-status-checks)
- [Pull Request Requirements](#pull-request-requirements)
- [Environment Protection (Deployment Gates)](#environment-protection-deployment-gates)
- [Lessons Learned](#lessons-learned)

---

## Overview

We use GitHub **repository rulesets** (the newer replacement for legacy branch protection rules) to protect the `main` branch. Rulesets provide more granular control and can target multiple branches with a single configuration.

Our ruleset is named **`main`** and is set to **Active** enforcement.

![Ruleset Overview](images/ruleset-overview.png)

---

## Ruleset Configuration

### Bypass List

| Actor | Type | Permission |
|-------|------|------------|
| Repository admin | Role | Always allow |

**What it means:** Only repository admins can bypass the ruleset rules. This is important to understand — **bypass means exempt from ALL rules**, not just specific ones. A bypass actor can force push, merge without approvals, skip status checks, etc.

**Why this matters for bots:** We intentionally do NOT add the bot account (`drewpy-code-agent`) to the bypass list. If the bot were a bypass actor, it could merge PRs without any human approval, defeating the purpose of branch protection. Instead, the bot operates as a regular collaborator — it can create PRs and merge them via API, but only after all required checks and approvals are satisfied.

### Target Branches

The ruleset targets the **Default** branch (`main`). All rules apply only to pushes and merges into `main`.

### Branch Rules

| Rule | Enabled | Description |
|------|---------|-------------|
| **Restrict creations** | ✅ | Only bypass actors can create refs matching the target. Prevents accidental creation of branches that match protected patterns. |
| **Restrict updates** | ❌ | If enabled, only bypass actors could push to `main`. We leave this OFF because updates go through PRs anyway (enforced by "Require a pull request before merging"). |
| **Restrict deletions** | ✅ | Prevents anyone (except bypass actors) from deleting the `main` branch. |
| **Require linear history** | ❌ | Would prevent merge commits. We allow all merge methods (merge, squash, rebase) so this stays off. |
| **Require signed commits** | ✅ | All commits pushed to `main` must have verified GPG signatures. This ensures commit authenticity and prevents impersonation. |
| **Block force pushes** | ✅ | Prevents force pushes to `main`. History rewriting on the default branch is never acceptable. Force pushes on feature branches are fine. |

---

## Pull Request Requirements

All changes to `main` must go through a pull request. Direct pushes are blocked.

![PR and Merge Settings](images/pr-merge-settings.png)

| Setting | Value | Description |
|---------|-------|-------------|
| **Required approvals** | 1 | At least one approving review is needed before merge. |
| **Dismiss stale approvals** | ❌ | New commits don't automatically dismiss existing approvals. Consider enabling this for stricter workflows. |
| **Require Code Owner review** | ✅ | Files with designated code owners in `CODEOWNERS` require approval from those owners. |
| **Require approval of most recent push** | ❌ | The person who pushed can also be an approver. For small teams this is practical. |
| **Require conversation resolution** | ❌ | PR comments don't need to be resolved before merge. |
| **Allowed merge methods** | Merge, Squash, Rebase | All three methods are allowed. Squash is commonly used for cleaner history. |

### CODEOWNERS

The `CODEOWNERS` file (in the repo root) defines who must approve changes to specific files:

```
# Example CODEOWNERS
* @drewpypro @smoore67
```

**Important:** The usernames in CODEOWNERS must match actual GitHub usernames exactly. We learned this the hard way when `smoore5288` needed to be corrected to `smoore67`.

---

## Required Status Checks

Status checks ensure that automated tests pass before a PR can be merged.

![Status Checks Configuration](images/status-checks.png)

| Setting | Value | Description |
|---------|-------|-------------|
| **Required check** | `terraform-plan` | The GitHub Actions workflow job that must pass. |
| **Require up-to-date branches** | ❌ | PRs don't need to be rebased on latest `main` before merging. Enable for stricter workflows. |
| **Skip checks on creation** | ❌ | Status checks are required even on newly created branches. |

### How Status Check Names Work

This is a common source of confusion. The required status check name must match the **job name** in your GitHub Actions workflow, not the workflow name or file name.

```yaml
# .github/workflows/terraform-plan.yaml
name: terraform-plan          # ← workflow name
on:
  pull_request:
    paths: ['*.tf', 'userdata.sh']

jobs:
  terraform-plan:              # ← THIS is the status check name
    runs-on: ubuntu-latest
    ...
```

The required check is `terraform-plan` (the job key). GitHub reports status checks by job name.

### Path-Filtered Workflows

Our `terraform-plan` workflow only triggers on changes to `*.tf` and `userdata.sh` files. This means:

- **PRs that only change non-TF files** (like `.github/workflows/`, `docs/`, `CODEOWNERS`) will **never trigger the check**, and the PR will be stuck in a "waiting for status check" state.
- **Workaround:** Temporarily remove the required status check from the ruleset, merge the PR, then re-add it. This is acceptable for infrastructure/config-only PRs.
- **Alternative:** Add a path-agnostic "pass-through" job that always succeeds, or broaden the path filter.

---

## Environment Protection (Deployment Gates)

Beyond branch protection, we use **GitHub Environments** to gate destructive operations like `terraform destroy`.

### How It Works

1. The destroy workflow references an environment:
   ```yaml
   jobs:
     terraform-destroy:
       environment: destroy    # ← requires environment approval
       runs-on: ubuntu-latest
   ```

2. The `destroy` environment is configured with **required reviewers** — specific GitHub users who must manually approve the deployment before it runs.

3. When the workflow is triggered, it pauses at the environment gate and waits for approval in the GitHub Actions UI.

### Why This Matters

- **Prevents accidental destruction:** Even if someone (or a bot) triggers the destroy workflow, it won't execute until a human approves it.
- **Audit trail:** GitHub logs who approved each deployment and when.
- **Separation of concerns:** Branch protection controls what gets merged; environment protection controls what gets deployed/destroyed.

---

## Bot Account Security

When using a bot/service account for CI/CD automation, follow these security practices:

### Dedicated Account
Create a dedicated GitHub account for the bot (e.g., `drewpy-code-agent`) rather than using a personal account's token. This provides:
- **Auditability** — bot actions are clearly attributable in commit/PR history
- **Least privilege** — the bot account only has access to repos it needs
- **Revocability** — you can disable the bot without affecting personal access

### Personal Access Token (PAT) Scoping

| Token Type | Scope | Risk |
|-----------|-------|------|
| **Fine-grained PAT** (recommended) | Scoped to specific repos | Lowest risk — can only access named repositories |
| **Classic PAT** with `repo` scope | All repos the account can access | ⚠️ Can read/write ANY repo the account has access to, including public repos |

**⚠️ Critical warning about classic PATs:** A classic `repo`-scoped token grants read access to all public repositories and write access to any repo where the bot is a collaborator. If the bot accepts a repository invitation (something you should **never** allow), an attacker could:
1. Invite the bot to a malicious repository
2. Coax the bot into pushing commits containing sensitive data (secrets, tokens, source code)
3. Create data exfiltration paths through git push

**Mitigations:**
- Use **fine-grained PATs** scoped to only the repos the bot needs ([docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens))
- Never allow the bot to accept repository invitations automatically
- Set token expiration dates and rotate regularly
- Monitor the bot account's [security log](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/reviewing-your-security-log) for unexpected activity
- Consider using a [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) instead of a PAT for even tighter scoping (per-repo installation, no implicit public repo access)

### Self-Approval Limitation

GitHub prevents any user (including bots) from approving their own pull requests. This means:
- A bot that creates a PR **cannot** also approve it
- At least one *different* collaborator must approve before merge
- This is a security feature, not a bug — it enforces separation of duties

---

## Conditional Status Checks (Path-Filtered Workaround)

GitHub's required status checks don't natively support conditional requirements based on file paths. If a required check's workflow only triggers on `*.tf` files, docs-only PRs will be stuck forever waiting.

### Solutions

**1. Path-based pass-through job (recommended)**

Add a lightweight job to your workflow that always runs, regardless of paths changed. Use the same job name as the required check:

```yaml
on:
  pull_request:
    # No path filter — runs on ALL PRs

jobs:
  terraform-plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check for TF changes
        id: changes
        run: |
          TF_CHANGES=$(git diff --name-only origin/main...HEAD | grep -cE '\.(tf|sh)$' || true)
          echo "has_tf=$([[ $TF_CHANGES -gt 0 ]] && echo true || echo false)" >> "$GITHUB_OUTPUT"

      - name: Terraform Init
        if: steps.changes.outputs.has_tf == 'true'
        run: terraform init

      - name: Terraform Plan
        if: steps.changes.outputs.has_tf == 'true'
        run: terraform plan
```

This way the `terraform-plan` check always reports a status (satisfying the requirement), but only actually runs terraform when relevant files changed.

**2. Use `dorny/paths-filter` action**

The [paths-filter](https://github.com/dorny/paths-filter) action provides cleaner conditional logic:

```yaml
jobs:
  terraform-plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            terraform:
              - '*.tf'
              - 'userdata.sh'
      - name: Terraform Plan
        if: steps.filter.outputs.terraform == 'true'
        run: |
          terraform init
          terraform plan
```

**3. Admin bypass** — Repo admins can merge regardless of status check requirements. Quick but doesn't scale.

---

## Lessons Learned

### 1. Bypass = Exempt from EVERYTHING
Adding an actor to the bypass list exempts them from **all** rules in the ruleset — not just the merge gate. Don't add bot accounts to bypass unless you want them to have unrestricted access.

### 2. Bot Merge Flow
A bot (like `drewpy-code-agent`) with push/write access CAN merge PRs via the GitHub API — but only after all required checks and approvals are satisfied. The flow:
1. Bot creates a branch and PR
2. CI runs status checks (e.g., `terraform-plan`)
3. Code owner(s) approve the PR
4. Bot calls `PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge`
5. GitHub validates all rules are met, then merges

### 3. GPG Signing for Bots
When "Require signed commits" is enabled, bot commits must also be GPG-signed. Generate a GPG key for the bot account, upload the public key to GitHub, and configure git:
```bash
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true
```

### 4. Status Check Names ≠ Workflow Names
The required status check must match the **job name** in your workflow YAML, not the workflow `name:` field or the filename. This is a common gotcha.

### 5. Path Filters Can Block PRs
If your workflow only triggers on specific file paths, PRs that don't touch those paths will never get the required status check. Plan for this with config-only or docs-only PRs.

### 6. Force Push Policy
- **`main` branch:** Never. Block force pushes is enabled.
- **Feature branches:** Acceptable for history cleanup (e.g., adding GPG signatures to existing commits via interactive rebase).

---

## References

- [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) — GitHub's overview of repository rulesets vs legacy branch protection
- [Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) — Detailed reference for every rule option
- [Managing rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository) — Creating, editing, and deleting rulesets
- [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) — Legacy branch protection (rulesets are the newer approach)
- [About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) — CODEOWNERS file syntax and behavior
- [Required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/about-status-checks) — How status checks work with branch protection
- [Using environments for deployment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment) — Environment protection rules, required reviewers, and wait timers
- [Managing deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys) — Alternative to PATs for bot/CI access
- [Commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification) — GPG/SSH signing and vigilant mode
- [GitHub Actions: workflow syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions) — Workflow YAML reference (job names, path filters, environments)

---

## Quick Reference

```
Ruleset: main (Active)
├── Bypass: Repository admin only
├── Target: main branch
├── Branch Rules:
│   ├── ✅ Restrict creations
│   ├── ✅ Restrict deletions
│   ├── ✅ Require signed commits
│   ├── ✅ Block force pushes
│   └── ❌ Restrict updates (off — PRs handle this)
├── Pull Request:
│   ├── ✅ Required (1 approval)
│   ├── ✅ Code Owner review
│   └── Merge methods: merge, squash, rebase
├── Status Checks:
│   └── ✅ terraform-plan (GitHub Actions)
└── Environment Gates:
    └── destroy → requires manual approval
```
