# CI/CD setup — GitHub Actions + Workload Identity Federation (keyless)

This repo ships a real CI/CD pipeline that authenticates to GCP **without any service-account
keys**, using GitHub's OIDC token federated to a dedicated, repo-scoped GCP service account.

```
PR / push ──► ci.yml (lint + validate, no cloud creds)
push main ──► deploy.yml: plan ─► [manual approval: production] ─► apply-infra ─► deploy ─► health
 dispatch ──► teardown.yml: [manual approval] ─► destroy
              auth: GitHub OIDC ──► WIF pool/provider ──► gha-deployer SA (short-lived creds)
```

## What each piece is
- **`.github/workflows/ci.yml`** — runs `make lint` on every push/PR. No GCP credentials (safe for
  any PR). Fast feedback.
- **`.github/workflows/deploy.yml`** — `plan` job, then a `deploy` job gated by the **`production`**
  Environment (manual approval). Keyless auth → `apply-infra.sh` → `get-gke-credentials` →
  `deploy.sh` (which runs the functional health checks). Triggers on merge to `main` or manually.
- **`.github/workflows/teardown.yml`** — manual-only, approval-gated `terraform destroy`.
- **`terraform/bootstrap/`** — the foundational identity (WIF pool + GitHub OIDC provider +
  `gha-deployer` SA + repo-scoped trust). Applied **once by an admin**, never by the pipeline.

## One-time setup

### 1. (GCP, admin) Allow the bootstrap to create the WIF pool
Our runtime SA can create SAs and set IAM, but **not** Workload Identity pools. Grant it once:
```bash
gcloud projects add-iam-policy-binding performance-analysis-2026 \
  --member="serviceAccount:651992227630-compute@developer.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityPoolAdmin"
```

### 2. Apply the bootstrap (creates pool, provider, deployer SA, repo-scoped trust)
```bash
cd terraform/bootstrap
terraform init
terraform apply -var="github_repo=OWNER/REPO"   # e.g. crislemus/online-boutique-benchmark
terraform output github_setup_summary            # prints the 3 values for step 3
```

### 3. (GitHub) Set Actions Variables — Settings ▸ Secrets and variables ▸ Actions ▸ Variables
These are **non-secret** (keyless federation), set as *Variables* (not Secrets):

| Variable | Value (from `terraform output`) |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/651992227630/locations/global/workloadIdentityPools/github-actions/providers/github` |
| `GCP_SERVICE_ACCOUNT` | `gha-deployer@performance-analysis-2026.iam.gserviceaccount.com` |
| `GCP_PROJECT` | `performance-analysis-2026` |

### 4. (GitHub) Create the approval gate — Settings ▸ Environments ▸ **New environment** `production`
- Add **Required reviewers** (yourself). This is what pauses `deploy`/`teardown` for approval.

### 5. Push the repo
```bash
git remote add origin git@github.com:OWNER/REPO.git
git push -u origin main
```
`ci.yml` runs immediately; `deploy.yml` runs on the push and waits at the `production` gate.

## On-demand runs & parameters

Both delivery workflows can be triggered manually from **Actions ▸ (workflow) ▸ Run workflow**.

**`cd-deploy`** offers two processor dropdowns:

| Input | Default | Notes |
|---|---|---|
| `platform_a` | `c3` | First node pool — pick from the catalog (`n2,n2d,c3,c3d,c4`) |
| `platform_b` | `c4` | Second node pool |

On dispatch, `scripts/set-platforms.sh` writes the chosen pair into `config/platforms.json` before
plan/apply, and **validates** it (picking the same platform twice, or an unknown key, fails the run
with a clear message). A normal **push to `main`** ignores the inputs and uses the *committed*
`config/platforms.json`.

**`cd-teardown`** takes a single `confirm` input — you must type `destroy` to proceed (a safety
gate). It takes **no platform parameters by design**:

> **Deploy ↔ teardown tie.** GitHub `workflow_dispatch` inputs are per-run; there is no native way
> to hand the deploy's inputs to a later, separate teardown run. The link is the **Terraform remote
> state in GCS** — `terraform destroy` reads state and removes exactly what the deploy created,
> whatever processors that was. Teardown reads the deployed platforms *back from state* purely to
> display them. So: deploy `n2 vs c3d` on demand → later run teardown with just `confirm: destroy`
> → it tears down `n2`+`c3d`, because state remembers.

> ⚠️ Triggering `cd-deploy` (push or on-demand) creates a **billable cluster** after approval.
> Always follow with `cd-teardown`.

**Troubleshooting a failed deploy:** if `deploy` fails at the health-check step with
`no Ready node for proc=<x>`, the health check now prints the node pool's provisioning error. A
`ZONE_RESOURCE_POOL_EXHAUSTED` means that machine type is temporarily **stocked out** in the zone
(transient GCP capacity, not a config error) — re-run with a different `platform_*` (e.g.
`n2d`/`c3d`/`c3`/`c4`) or try later. See the README "Processor availability" note.

## Results artifacts

When `cd-deploy` is run on demand with **`run_benchmark: true`**, it runs the benchmark and uploads
`docs/results/` (charts, `summary.md`, `metrics-snapshot.json`, CSV, loadgen logs, and an
`index.html` navigator) as a **downloadable GitHub Actions artifact** (`Actions ▸ run ▸ Artifacts`).
Artifacts are retained for a bounded window (`retention-days`) and each run is a few hundred KB —
well within the free storage quota. Open `index.html` from the extracted artifact to browse a run
(date, platforms, commit, metrics, charts).

## Security properties
- **No keys**: short-lived credentials minted per run via OIDC; nothing long-lived stored in GitHub.
- **Repo-scoped trust**: the WIF provider's `attribute_condition` *and* the SA binding both restrict
  to `OWNER/REPO`; no other repo can assume the identity. (Tighten further to a branch with
  `attribute.ref` if desired.)
- **Privileged steps gated**: `apply`/`deploy`/`teardown` require manual approval via the
  `production` Environment; PRs never get cloud credentials (lint only).
- **Least-ish privilege**: the `gha-deployer` SA holds only the roles needed to provision this
  stack. `roles/resourcemanager.projectIamAdmin` is the broadest — for stricter setups, replace it
  with a custom role limited to the specific `setIamPolicy` calls the stack makes.
