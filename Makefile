###############################################################################
# One Makefile to rule them all. Override on the CLI:
#   make push IMAGE=ghcr.io/my-org/headscale VERSION=0.29.1
###############################################################################
IMAGE       ?= ghcr.io/eslam-adel92/headscale
UI_IMAGE    ?= ghcr.io/eslam-adel92/headscale-ui
VERSION     ?= 0.29.1
UI_VERSION  ?= 2026.03.17
PLATFORMS   ?= linux/amd64,linux/arm64

.PHONY: help build build-ui push push-ui scan scan-ui \
        compose-up compose-down compose-backup \
        helm-lint helm-template helm-install helm-uninstall add-device \
        pg-shell pg-backup pg-restore hash-ui-password

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Build headscale image locally
	docker buildx build --platform linux/amd64 --build-arg HEADSCALE_VERSION=$(VERSION) -t $(IMAGE):$(VERSION) --load docker/
build-ui: ## Build headscale-ui image locally
	docker buildx build --platform linux/amd64 --build-arg HEADSCALE_UI_VERSION=$(UI_VERSION) -t $(UI_IMAGE):$(UI_VERSION) --load docker/ui/

push: ## Multi-arch build & push headscale
	docker buildx build --platform $(PLATFORMS) --build-arg HEADSCALE_VERSION=$(VERSION) -t $(IMAGE):$(VERSION) -t $(IMAGE):latest --push docker/
push-ui: ## Multi-arch build & push headscale-ui
	docker buildx build --platform $(PLATFORMS) --build-arg HEADSCALE_UI_VERSION=$(UI_VERSION) -t $(UI_IMAGE):$(UI_VERSION) -t $(UI_IMAGE):latest --push docker/ui/

scan: ## Trivy scan headscale
	trivy image --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE):$(VERSION)
scan-ui: ## Trivy scan headscale-ui
	trivy image --severity HIGH,CRITICAL --ignore-unfixed $(UI_IMAGE):$(UI_VERSION)

compose-up:     ## Bring up the compose stack
	cd compose && docker compose up -d
compose-backup: ## + pg_dump backup loop
	cd compose && docker compose --profile backup up -d
compose-down:   ## Tear down
	cd compose && docker compose down

helm-lint:      ## Lint the chart
	helm lint helm/headscale
helm-template:  ## Render to stdout
	helm template headscale helm/headscale -f helm/headscale/values.yaml
helm-install:   ## Install
	helm upgrade --install headscale helm/headscale --namespace headscale --create-namespace -f helm/headscale/values.yaml
helm-uninstall: ## Remove release (keeps PVCs)
	helm uninstall headscale --namespace headscale

pg-shell:   ## psql into bundled DB
	kubectl -n headscale exec -it sts/headscale-postgresql -- psql -U headscale -d headscale
pg-backup:  ## Trigger a one-off backup Job
	kubectl -n headscale create job --from=cronjob/headscale-postgresql-backup manual-$$(date -u +%Y%m%dT%H%M%SZ)
pg-restore: ## make pg-restore FILE=./dump.dump
	@test -n "$(FILE)" || (echo "Usage: make pg-restore FILE=./dump.dump"; exit 2)
	kubectl -n headscale scale deploy/headscale --replicas=0
	kubectl -n headscale cp "$(FILE)" headscale-postgresql-0:/tmp/restore.dump
	kubectl -n headscale exec -it headscale-postgresql-0 -- pg_restore -U headscale -d headscale --clean --if-exists /tmp/restore.dump
	kubectl -n headscale scale deploy/headscale --replicas=1

add-device: ## make add-device USER=alice [TAGS=tag:laptop]
	@scripts/hs-add-device $(USER) $(if $(TAGS),--tags $(TAGS))

hash-ui-password: ## make hash-ui-password PW='yourPassword'
	@test -n "$(PW)" || (echo "Usage: make hash-ui-password PW='yourPassword'"; exit 2)
	@scripts/hs-hash-ui-password '$(PW)'
