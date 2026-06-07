# terraform/results-history — durable benchmark results bucket

This Terraform config provisions a **persistent GCS bucket** that stores the history of
benchmark runs (one folder per run: `manifest.json`, `metrics-snapshot.json`, `summary.md`,
charts, `index.html`). It is the system-of-record the **ops AI agent** reads for regression
analysis, and the durable home for results that would otherwise be overwritten in
`docs/results/` or expire as GitHub Actions artifacts.

## Why it's a separate Terraform config

The main stack (`../`, the GKE cluster) is **ephemeral** — `make down` / the `cd-teardown`
workflow destroys it after every run. This bucket is **persistent** and must survive those
teardowns, so it has its **own Terraform state** (state prefix `…/results-history` in the shared
state bucket) and its **own create/destroy lifecycle**. Same rationale as `../bootstrap` (the
long-lived Workload Identity setup).

```
terraform/                ephemeral cluster, node pools, GMP, WI bindings  (make up / make down)
terraform/bootstrap/      one-time WIF identity for CI/CD                    (apply once)
terraform/results-history/ THIS — persistent results bucket                 (make create / make destroy)
```

## Usage

```bash
cd terraform/results-history
make create     # provision the bucket
make output     # print bucket name / gs:// url
make plan       # preview changes
make destroy    # tear it down — DESTROYS ALL HISTORY (typed confirmation required)
```

The bucket name is conventional (`performance-analysis-2026-benchmark-results`) so the benchmark
publish step references it by name — no Terraform state read required.

## ⚠️ Destroying the bucket deletes all history

`force_destroy = true` is set so `terraform destroy` works even when the bucket holds run
history. **That means one `make destroy` permanently wipes every stored benchmark run.** The
`make destroy` target requires you to type `delete-history` to confirm. Never run this as part
of a normal cluster teardown — it is intentionally separate from `make up`/`make down`.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `bucket_name` | `performance-analysis-2026-benchmark-results` | Globally-unique bucket name |
| `region` | `us-central1` | Bucket location |
| `retention_days` | `365` | Auto-delete runs older than N days; `0` = keep forever |

## Prerequisites

- The active identity needs `roles/storage.admin` (the local compute SA has Editor; the CI
  `gha-deployer` SA has `storage.admin`).
- The shared Terraform state bucket `performance-analysis-2026-tfstate` must exist (it does).
