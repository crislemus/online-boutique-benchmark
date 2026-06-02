PROJECT_ID ?= performance-analysis-2026
ZONE       ?= us-central1-a
CLUSTER    ?= boutique-bench

.PHONY: help lint init plan up connect deploy health dashboards bench charts down all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

lint: ## Static validation: terraform fmt/validate, config, yamllint, shellcheck, kustomize
	./scripts/validate.sh

init: ## terraform init
	cd terraform && terraform init -input=false

plan: ## terraform plan (shows pools derived from config/platforms.json)
	cd terraform && terraform plan -input=false

up: ## Provision infrastructure (cluster + the 2 selected node pools)
	./scripts/apply-infra.sh

connect: ## Fetch kubeconfig credentials
	./scripts/connect.sh

deploy: ## Deploy monitoring + one Online Boutique per selected platform (+ health checks)
	./scripts/deploy.sh

health: ## Run functional health checks against the deployed stack
	./scripts/healthcheck.sh

dashboards: ## Port-forward Grafana to http://localhost:3000
	kubectl -n monitoring port-forward svc/grafana 3000:3000

bench: ## Run the benchmark and capture evidence to docs/results/
	./scripts/run-benchmark.sh

charts: ## Render comparison charts (PNG) from captured results (needs matplotlib)
	python3 scripts/make-charts.py

down: ## Destroy all billable resources
	./scripts/teardown.sh

all: up connect deploy ## Provision + connect + deploy end-to-end
