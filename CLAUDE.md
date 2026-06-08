# CLAUDE.md — operator quick-reference

Guidance for AI assistants (and humans) working in this repo. The
[README](README.md) and [docs/architecture-automation.md](docs/architecture-automation.md) are the
full story; this file is the short "how to operate it safely" reference.

**What this is:** a parametrized GKE platform that benchmarks 2 processor families by running two
Online Boutique copies and comparing CPU/memory via Managed Service for Prometheus + Grafana.

---

## ⚠️ COST & TEARDOWN RULES — read first

A GKE cluster + node pools is **billable (~$0.40–0.60/hr)**. The cluster is **ephemeral by design**:
provision → use → **destroy**. Treat teardown as part of every task, not an afterthought.

- **ALWAYS run `make down`** (or the `cd-teardown` workflow) **as soon as** a benchmark/demo finishes.
  Never leave a cluster running unattended or overnight.
- **After any run, verify nothing remains:**
  ```bash
  gcloud container clusters list          # expect: none
  cd terraform && terraform state list    # expect: empty
  ```
- Re-provisioning is cheap (state is in GCS), so **when in doubt, tear down** — don't "keep it just in case."
- **Do NOT confuse the lifecycles** (different `terraform` configs / states):
  | Command | Destroys | Normally? |
  |---|---|---|
  | `make down` | the **ephemeral cluster** | ✅ after every run |
  | `terraform/results-history` → `make destroy` | the bucket **+ ALL benchmark history** (`force_destroy`) | ❌ rarely — wipes history |
  | `terraform/bootstrap` → `terraform destroy` | the **CI/CD WIF identity** | ❌ rarely |
  The results bucket and WIF are **persistent and near-free** — leave them.

---

## Core commands
```bash
make lint        # ALWAYS run before deploying (terraform fmt/validate, config, yamllint, shellcheck, kustomize)
make up          # terraform apply: cluster + the 2 selected node pools (~8 min)
make connect     # kubeconfig
make deploy      # monitoring + both boutiques + functional health checks
make health      # re-run health checks
make bench       # soak + capture evidence + charts + publish to results-history bucket
make down        # DESTROY the cluster (do this when done)
```

## Conventions / guardrails
- **`config/platforms.json` is the single source of truth.** `selected` must be **exactly 2** distinct
  keys from `catalog`; anything else **hard-fails** `make lint` and `terraform plan`. Change the pair
  there (or via `scripts/set-platforms.sh a b`) — never hardcode platforms elsewhere.
- **Always `make lint` before a deploy.** CI (`.github/workflows/ci.yml`) lints every push.
- **Deploy is MANUAL-ONLY** (`cd-deploy` is `workflow_dispatch`); commits never auto-provision.
- **One source of logic:** `make` and `cloudbuild/*.yaml` both call `scripts/`. Don't duplicate logic
  into the workflows — edit the scripts.
- **Never commit** secrets, `*.tfstate`, kubeconfigs, or `secrets.env` (all gitignored — keep it that way).

## Gotchas (hard-won)
- **kubectl auth on this VM:** snap-managed gcloud blocks `gke-gcloud-auth-plugin`. Drive kubectl via a
  **token kubeconfig** (build from `gcloud container clusters describe` endpoint+CA + `gcloud auth
  print-access-token`); the token **expires ~1h** — rebuild if you see `Unauthorized`. (CI uses the
  real plugin via `get-gke-credentials`, so this is a local-only workaround.)
- **Capacity stockouts:** `ZONE_RESOURCE_POOL_EXHAUSTED` = transient GCP capacity, **not** a config bug
  (`healthcheck.sh` surfaces it). Probe a family with a throwaway VM; switch family, or switch zone via
  `TF_VAR_zone=us-central1-b`. (N2-family has been flaky in `us-central1-a`; C-family reliable.)
- **Per-family boot disk:** `disk_type` is per-platform in the catalog — **C4 needs `hyperdisk-balanced`**,
  others use `pd-balanced`. Don't set a single global disk type.
- **WIF binding ordering:** SA↔WIF IAM bindings need `depends_on = [google_container_cluster.primary]`
  (the `*.svc.id.goog` pool only exists after a WI-enabled cluster).
