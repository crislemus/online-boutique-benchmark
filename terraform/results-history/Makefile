# Lifecycle for the PERSISTENT benchmark results-history bucket.
# Separate from the cluster's `make up`/`make down` — never tear this down as
# part of a normal benchmark teardown.

.PHONY: help init plan create destroy output

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

init: ## terraform init (GCS backend)
	terraform init -input=false

plan: init ## Show the plan
	terraform plan -input=false

create: init ## Create the results-history bucket
	terraform apply -auto-approve -input=false
	@echo "Bucket ready: $$(terraform output -raw bucket_url)"

output: ## Print the bucket name / url
	@terraform output

destroy: ## DESTROY the bucket AND ALL stored history (typed confirmation required)
	@echo "\033[31m============================ DANGER ============================\033[0m"
	@echo "This destroys the results-history bucket with force_destroy=true."
	@echo "ALL stored benchmark history will be permanently deleted."
	@echo "\033[31m===============================================================\033[0m"
	@read -p 'Type "delete-history" to confirm: ' c; \
	 if [ "$$c" = "delete-history" ]; then \
	   terraform init -input=false && terraform destroy -auto-approve -input=false; \
	 else \
	   echo "Aborted — nothing destroyed."; exit 1; \
	 fi
