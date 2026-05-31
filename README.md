# Online Boutique — Processor Performance Benchmark

Automated platform to benchmark **CPU/memory performance of different processor generations** by
running the [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo)
microservices demo on GKE node pools pinned to each processor, collecting metrics with **Managed
Service for Prometheus**, and comparing them in **Grafana**. Built to be re-run for new processors
and (later) other cloud providers.

> Deliverable #1 of a two-part exercise. The AI-agent design is in the companion repo
> [`ops-ai-agent`](../ops-ai-agent).

## What it does

- Provisions a **GKE Standard** cluster with two node pools — **`pool-n2`** (`n2-standard-4`,
  prev-gen Intel) and **`pool-c3`** (`c3-standard-4`, Sapphire Rapids).
- Deploys **two identical copies** of Online Boutique, one pinned to each pool, each driven by an
  identical Locust load.
- Collects per-container **CPU/memory** via kubelet/cAdvisor into Managed Service for Prometheus.
- Visualizes a head-to-head comparison in a provisioned **Grafana dashboard**.
- Captures a benchmark **summary + raw evidence** to [`docs/results/`](docs/results).

See **[docs/architecture-automation.md](docs/architecture-automation.md)** for the architecture,
design decisions, methodology, and diagram.

## Latest result (PoC snapshot)

At identical load, **C3 (Sapphire Rapids) was ~40% more CPU-efficient per request** than N2, with
lower latency and equal memory. Details: [`docs/results/summary.md`](docs/results/summary.md).

## Prerequisites

- `gcloud`, `terraform` ≥ 1.5, `kubectl`, and **`gke-gcloud-auth-plugin`**
  (`gcloud components install gke-gcloud-auth-plugin` on a non-snap SDK).
- A GCP project with billing; APIs: container, compute, monitoring, artifactregistry, cloudbuild.
- A versioned **GCS bucket** for Terraform state (default `performance-analysis-2026-tfstate`);
  update `terraform/versions.tf` to your bucket.

## Quick start

```bash
make up         # terraform apply: VPC + GKE + node pools (~8 min)
make connect    # fetch kubeconfig
make deploy     # GMP scraping + frontend + Grafana + both Online Boutique copies
make dashboards # port-forward Grafana -> http://localhost:3000 (anon viewer; admin/admin)
make bench      # soak + capture evidence to docs/results/
make down       # terraform destroy (tear down to control cost)
```

CI/CD equivalents live in [`cloudbuild/`](cloudbuild) (`provision.yaml`, `teardown.yaml`).

## Layout

```
terraform/    IaC: VPC, GKE cluster, pool-n2 / pool-c3, GMP, remote state
k8s/base      vendored Online Boutique (pinned v0.10.5)
k8s/overlays  boutique-n2 / boutique-c3 (namespace + nodeSelector per processor)
k8s/monitoring OperatorConfig (kubelet scraping), GMP query frontend, Grafana
dashboards/   Grafana dashboard JSON (provisioned)
cloudbuild/   Cloud Build pipelines
scripts/      connect / deploy / run-benchmark / teardown
docs/         architecture doc, diagram, results/
```

## Notes & limitations

- This is a **proof of concept**. The runtime service account available in the exercise project
  had Editor but could not set IAM policy, so the deployment uses the **node service account** for
  monitoring access rather than Workload Identity. The cluster is WI-ready; see the *Production
  hardening* section of the architecture doc for the recommended setup.
- `gke-gcloud-auth-plugin` is required by `kubectl` for GKE; on a snap-managed gcloud you may need
  a separate SDK install or a token-based kubeconfig.
