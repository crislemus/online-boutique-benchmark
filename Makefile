PROJECT_ID ?= performance-analysis-2026
ZONE       ?= us-central1-a
CLUSTER    ?= boutique-bench

.PHONY: help init plan up connect deploy dashboards bench down all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: ## terraform init
	cd terraform && terraform init -input=false

plan: ## terraform plan
	cd terraform && terraform plan -input=false

up: ## Provision infrastructure (cluster + node pools)
	cd terraform && terraform apply -auto-approve -input=false

connect: ## Fetch kubeconfig credentials
	./scripts/connect.sh

deploy: ## Deploy monitoring stack + both Online Boutique copies
	./scripts/deploy.sh

dashboards: ## Port-forward Grafana to http://localhost:3000
	kubectl -n monitoring port-forward svc/grafana 3000:3000

bench: ## Run the benchmark and capture evidence to docs/results/
	./scripts/run-benchmark.sh

down: ## Destroy all billable resources
	./scripts/teardown.sh

all: up connect deploy ## Provision + connect + deploy end-to-end
