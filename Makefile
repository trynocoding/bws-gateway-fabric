# variables that should not be overridden by the user
VERSION = 2.6.6
SELF_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CHART_DIR = $(SELF_DIR)charts/bws-gateway-fabric
NGINX_CONF_DIR = internal/controller/nginx/conf
NJS_DIR = internal/controller/nginx/modules/src
KIND_CONFIG_FILE = $(SELF_DIR)config/cluster/kind-cluster.yaml
BUILD_AGENT = local

PROD_TELEMETRY_ENDPOINT = ## Production telemetry endpoint. Leave empty to disable product telemetry reporting.
# the telemetry related variables below are also configured in goreleaser.yml
TELEMETRY_REPORT_PERIOD = 24h
TELEMETRY_ENDPOINT=# if empty, BWS Gateway Fabric will report telemetry in its logs at debug level.
TELEMETRY_ENDPOINT_INSECURE = false

ENABLE_EXPERIMENTAL ?= false
ENABLE_INFERENCE_EXTENSION ?= false

# go build flags - should not be overridden by the user
GO_LINKER_FlAGS_VARS = -X main.version=${VERSION} -X main.telemetryReportPeriod=${TELEMETRY_REPORT_PERIOD} -X main.telemetryEndpoint=${TELEMETRY_ENDPOINT} -X main.telemetryEndpointInsecure=${TELEMETRY_ENDPOINT_INSECURE}
GO_LINKER_FLAGS_OPTIMIZATIONS = -s -w
GO_LINKER_FLAGS = $(GO_LINKER_FLAGS_OPTIMIZATIONS) $(GO_LINKER_FlAGS_VARS)

# tools versions
# renovate: datasource=github-tags depName=golangci/golangci-lint
GOLANGCI_LINT_VERSION = v2.11.4
# renovate: datasource=docker depName=kindest/node
KIND_K8S_VERSION = v1.35.1
# renovate: datasource=github-tags depName=norwoodj/helm-docs
HELM_DOCS_VERSION = v1.14.2
# renovate: datasource=github-tags depName=ahmetb/gen-crd-api-reference-docs
GEN_CRD_API_REFERENCE_DOCS_VERSION = v0.3.0
# renovate: datasource=go depName=sigs.k8s.io/controller-tools
CONTROLLER_TOOLS_VERSION = v0.20.1
# renovate: datasource=docker depName=node
NODE_VERSION = 24
# renovate: datasource=docker depName=quay.io/helmpack/chart-testing
CHART_TESTING_VERSION = v3.14.0
# renovate: datasource=github-tags depName=dadav/helm-schema
HELM_SCHEMA_VERSION = 0.23.2

# variables that can be overridden by the user
PREFIX ?= bws-gateway-fabric## The name of the BWS Gateway Fabric image. For example, bws-gateway-fabric
BWS_PREFIX ?= $(PREFIX)/bws## The name of the BWS data plane image.
BWS_CONTROL_PLANE_PREFIX ?= $(PREFIX)## The name of the BWS Gateway Fabric control plane image.
BWS_AGENT_DIR ?= $(abspath $(SELF_DIR)../bws-agent)## Path to the BWS Agent source repository.
BWS_AGENT_BINARY_DIR ?= $(BWS_AGENT_DIR)/build## Directory containing the built BWS Agent binary.
BWS_PACKAGE ?= $(abspath $(SELF_DIR)../bws-3.2.0-LINUX-X64.tar_94b299d8d6b5c686ffbe0ee912c79cbb304b93dc.gz)## Path to the BWS distribution archive.
BWS_PACKAGE_SHA256 ?= 885a2ea9fb91b6837971259dac118854fc5d3b6236a432819f8f1dac6e7fd95f## Expected BWS archive SHA-256.
BWS_INSTALL_DEBUG_TOOLS ?= true## Install development troubleshooting tools in the BWS image.
BUILD_OS ?= ## The OS of the BWS data plane image. Possible values: ubi and empty string, which defaults to rocky.
NGINX_SERVICE_TYPE ?= NodePort## The type of the bws service. Possible values: NodePort, LoadBalancer, ClusterIP
PULL_POLICY ?= Never## The pull policy of the images. Possible values: Always, IfNotPresent, Never
TAG ?= $(VERSION:v%=%)## The tag of the image. For example, 1.1.0
TARGET ?= local## The target of the build. Possible values: local and container
OUT_DIR ?= build/out## The folder where the binary will be stored
GOARCH ?= amd64## The architecture of the image and/or binary. For example: amd64 or arm64
GOOS ?= linux## The OS of the image and/or binary. For example: linux or darwin
HELM_PARAMETERS ?=## Optional extra parameters for the Helm install

override NGINX_DOCKER_BUILD_OPTIONS += --build-arg NJS_DIR=$(NJS_DIR) --build-arg NGINX_CONF_DIR=$(NGINX_CONF_DIR) --build-arg BUILD_AGENT=$(BUILD_AGENT)

.DEFAULT_GOAL := help


.PHONY: help
help: Makefile ## Display this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "; printf "Usage:\n\n	make \033[36m<target>\033[0m [VARIABLE=value...]\n\nTargets:\n\n"}; {printf "	 \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@grep -hE '^(override )?[a-zA-Z_-]+ \??\+?= .*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = " \\??\\+?= .*?## "; printf "\nVariables:\n\n"}; {gsub(/override /, "", $$1); printf "	 \033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: build-prod-images
build-prod-images: build-prod-control-plane-image build-prod-bws-image ## Build the BWS Gateway Fabric and BWS data plane docker images for production

.PHONY: build-images
build-images: build-control-plane-image build-bws-image ## Build the BWS Gateway Fabric and BWS data plane docker images

.PHONY: build-prod-control-plane-image
build-prod-control-plane-image: TELEMETRY_ENDPOINT=$(PROD_TELEMETRY_ENDPOINT)
build-prod-control-plane-image: build-control-plane-image ## Build the BWS Gateway Fabric control plane docker image for production

.PHONY: build-control-plane-image
build-control-plane-image: check-for-docker build ## Build the BWS Gateway Fabric control plane docker image
	docker build --platform linux/$(GOARCH) --build-arg BUILD_AGENT=$(BUILD_AGENT) --target $(strip $(TARGET)) -f $(SELF_DIR)build/Dockerfile.bws-gateway -t $(strip $(BWS_CONTROL_PLANE_PREFIX)):$(strip $(TAG)) $(strip $(SELF_DIR))

.PHONY: build-prod-bws-image
build-prod-bws-image: build-bws-image ## Build the BWS data plane image for production

.PHONY: build-bws-agent
build-bws-agent:
	CGO_ENABLED=0 $(MAKE) -C $(BWS_AGENT_DIR) build

.PHONY: build-bws-image
build-bws-image: check-for-docker build-bws-agent ## Build the BWS data plane image from the vendor archive and BWS Agent.
	@test -f "$(BWS_PACKAGE)" || (echo "BWS package not found: $(BWS_PACKAGE)"; exit 1)
	docker build --platform linux/amd64 $(strip $(NGINX_DOCKER_BUILD_OPTIONS)) \
		--build-context bws-package=$(dir $(BWS_PACKAGE)) \
		--build-context bws-agent=$(BWS_AGENT_BINARY_DIR) \
		--build-arg BWS_PACKAGE_FILE=$(notdir $(BWS_PACKAGE)) \
		--build-arg BWS_PACKAGE_SHA256=$(BWS_PACKAGE_SHA256) \
		--build-arg BWS_INSTALL_DEBUG_TOOLS=$(BWS_INSTALL_DEBUG_TOOLS) \
		-f $(SELF_DIR)build/Dockerfile.bws \
		-t $(strip $(BWS_PREFIX)):$(strip $(TAG)) \
		$(strip $(SELF_DIR))

.PHONY: check-for-docker
check-for-docker: ## Check if Docker is installed
	@docker -v || (code=$$?; printf "\033[0;31mError\033[0m: there was a problem with Docker\n"; exit $$code)

.PHONY: build
build: ## Build the binary
ifeq (${TARGET},local)
	@go version || (code=$$?; printf "\033[0;31mError\033[0m: unable to build locally\n"; exit $$code)
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -C $(SELF_DIR) -trimpath -a -ldflags "$(GO_LINKER_FLAGS)" $(ADDITIONAL_GO_BUILD_FLAGS) -o $(OUT_DIR)/gateway github.com/nginx/nginx-gateway-fabric/v2/cmd/gateway
endif

.PHONY: build-goreleaser
build-goreleaser: ## Build the binary using GoReleaser
	@goreleaser -v || (code=$$?; printf "\033[0;31mError\033[0m: there was a problem with GoReleaser. Follow the docs to install it https://goreleaser.com/install\n"; exit $$code)
	GOOS=linux GOPATH=$(shell go env GOPATH) GOARCH=$(GOARCH) goreleaser build --clean --snapshot --single-target

.PHONY: generate
generate: ## Run go generate
	go generate ./...

.PHONY: generate-crds
generate-crds: ## Generate CRDs and Go types using kubebuilder
	go run sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION) crd object paths=./apis/... output:crd:artifacts:config=config/crd/bases
	rm -f $(SELF_DIR)config/crd/bases/gateway.nginx.org_*.yaml $(SELF_DIR)config/crd/bases/gateway.bessystem.com_wafpolicies.yaml
	./scripts/strip-crd-excludes.sh config/crd/bases
	kubectl kustomize config/crd >deploy/crds.yaml

.PHONY: install-crds
install-crds: ## Install CRDs
	kubectl kustomize $(SELF_DIR)config/crd | kubectl apply --server-side -f -

.PHONY: install-gateway-crds
install-gateway-crds: ## Install Gateway API CRDs
	kubectl kustomize $(SELF_DIR)config/crd/gateway-api/$(if $(filter true,$(ENABLE_EXPERIMENTAL)),experimental,standard) | kubectl apply --server-side -f -

.PHONY: uninstall-gateway-crds
uninstall-gateway-crds: ## Uninstall Gateway API CRDs
	kubectl kustomize $(SELF_DIR)config/crd/gateway-api/$(if $(filter true,$(ENABLE_EXPERIMENTAL)),experimental,standard) | kubectl delete -f -

.PHONY: install-inference-crds
install-inference-crds: ## Install Gateway API Inference Extension CRDs
	kubectl kustomize $(SELF_DIR)config/crd/inference-extension | kubectl apply -f -

.PHONY: uninstall-inference-crds
uninstall-inference-crds: ## Uninstall Gateway API Inference Extension CRDs
	kubectl kustomize $(SELF_DIR)config/crd/inference-extension | kubectl delete -f -

.PHONY: generate-manifests
generate-manifests: ## Generate manifests using Helm.
	./scripts/generate-manifests.sh

generate-api-docs: ## Generate API docs
	go run github.com/ahmetb/gen-crd-api-reference-docs@$(GEN_CRD_API_REFERENCE_DOCS_VERSION) -config docs/api/config.json -template-dir docs/api -out-file docs/api/content.md -api-dir "github.com/nginx/nginx-gateway-fabric/v2/apis"

.PHONY: generate-helm-docs
generate-helm-docs: ## Generate the Helm chart documentation
	go run github.com/norwoodj/helm-docs/cmd/helm-docs@$(HELM_DOCS_VERSION) --chart-search-root=charts --template-files _templates.gotmpl --template-files README.md.gotmpl

.PHONY: generate-helm-schema
generate-helm-schema: ## Generate the Helm chart schema
	go run github.com/dadav/helm-schema/cmd/helm-schema@$(HELM_SCHEMA_VERSION) --chart-search-root=charts --add-schema-reference "--skip-auto-generation=required,additionalProperties" --append-newline

.PHONY: generate-all
generate-all: generate generate-crds generate-helm-schema generate-manifests generate-api-docs generate-helm-docs verify-operator-rbac ## Generate all the necessary files

.PHONY: verify-operator-rbac
verify-operator-rbac: ## Verify operator RBAC is in sync with Helm chart
	@./operators/scripts/verify-rbac-sync.sh

.PHONY: clean
clean: ## Clean the build
	-rm -r $(OUT_DIR)

.PHONY: clean-go-cache
clean-go-cache: ## Clean go cache
	@go clean -modcache

.PHONY: deps
deps: ## Add missing and remove unused modules, verify deps and download them to local cache
	@go mod tidy && go mod verify && go mod download

.PHONY: create-kind-cluster
create-kind-cluster: ## Create a kind cluster
	@kind version || (code=$$?; printf "\033[0;31mError\033[0m: there was a problem with kind. Follow the docs to install it https://kind.sigs.k8s.io/docs/user/quick-start/\n"; exit $$code)
	kind create cluster --image kindest/node:$(KIND_K8S_VERSION) --config $(KIND_CONFIG_FILE)

.PHONY: delete-kind-cluster
delete-kind-cluster: ## Delete kind cluster
	kind delete cluster

.PHONY: fmt
fmt: ## Run go fmt against code
	go fmt ./...

.PHONY: njs-fmt
njs-fmt: ## Run prettier against the njs httpmatches module
	docker run --rm -w /modules \
		-v $(CURDIR)/internal/nginx/modules/:/modules/ \
		node:${NODE_VERSION} \
		/bin/bash -c "npm ci && npm run format"

.PHONY: vet
vet: ## Run go vet against code
	go vet ./...

.PHONY: lint
lint: ## Run golangci-lint against code
	go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION) run --fix

.PHONY: unit-test
unit-test: ## Run unit tests for the go code
	go test ./cmd/... ./internal/... -buildvcs -race -shuffle=on -coverprofile=coverage.out -covermode=atomic
	go tool cover -html=coverage.out -o cover.html

.PHONY: njs-unit-test
njs-unit-test: ## Run unit tests for the njs httpmatches module
	docker run --rm -w /modules \
		-v $(CURDIR)/internal/controller/nginx/modules:/modules/ \
		node:${NODE_VERSION} \
		/bin/bash -c "npm ci && npm test && npm run clean"

.PHONY: lint-helm
lint-helm: ## Run the helm chart linter
	docker run --pull always --rm -v $(CURDIR):/nginx-gateway-fabric -w /nginx-gateway-fabric quay.io/helmpack/chart-testing:$(CHART_TESTING_VERSION) ct lint --config .ct.yaml

.PHONY: load-images
load-images: ## Load BWS Gateway Fabric and BWS data plane images on configured kind cluster.
	kind load docker-image $(BWS_CONTROL_PLANE_PREFIX):$(TAG) $(BWS_PREFIX):$(TAG)

.PHONY: install-bws-local-build
install-bws-local-build: build-bws-control-plane-image build-bws-image load-images helm-install-local ## Install BWS Gateway Fabric from local build on configured kind cluster.

.PHONY: helm-install-local
helm-install-local: install-gateway-crds ## Helm install BWS Gateway Fabric on configured kind cluster with local images. To build, load, and install with helm run make install-bws-local-build.
	@if [ "$(ENABLE_INFERENCE_EXTENSION)" = "true" ]; then \
		$(MAKE) install-inference-crds; \
	fi
	helm install bws-gateway $(CHART_DIR) --set bws.image.repository=$(BWS_PREFIX) --create-namespace --wait --set bwsGateway.image.pullPolicy=$(PULL_POLICY) --set bws.service.type=$(NGINX_SERVICE_TYPE) --set bwsGateway.image.repository=$(BWS_CONTROL_PLANE_PREFIX) --set bwsGateway.image.tag=$(TAG) --set bws.image.tag=$(TAG) --set bws.image.pullPolicy=$(PULL_POLICY) --set bwsGateway.gwAPIExperimentalFeatures.enable=$(ENABLE_EXPERIMENTAL) -n bws-gateway $(HELM_PARAMETERS)

.PHONY: create-image-pull-secret
create-image-pull-secret: ## Creates the bws-registry-secret image pull secret in the bws-gateway namespace using dockerconfig.jwt
	kubectl create namespace bws-gateway || true
	test -f $(REGISTRY_JWT_FILE) || { echo "Error: $(REGISTRY_JWT_FILE) not found"; exit 1; }; \
	JWT=$$(tr -d '[:space:]' < $(REGISTRY_JWT_FILE)); \
	test -n "$$JWT" || { echo "Error: $(REGISTRY_JWT_FILE) is empty"; exit 1; }; \
	kubectl create secret docker-registry $(NGINX_IMAGE_PULL_SECRET) \
		--docker-server=private-registry.nginx.com \
		--docker-username=$$JWT \
		--docker-password=none \
		-n bws-gateway \
		--dry-run=client -o yaml | kubectl apply -f -

# Debug Targets
.PHONY: debug-build
debug-build: GO_LINKER_FLAGS=$(GO_LINKER_FlAGS_VARS)
debug-build: ADDITIONAL_GO_BUILD_FLAGS=-gcflags "all=-N -l"
debug-build: build ## Build binary with debug info, symbols, and no optimizations

.PHONY: debug-build-dlv-image
debug-build-dlv-image: check-for-docker ## Build the dlv debugger image.
	docker build --platform linux/$(GOARCH) -f debug/Dockerfile -t dlv-debug:edge .

.PHONY: debug-build-images
debug-build-images: debug-build build-bws-control-plane-image build-bws-image debug-build-dlv-image ## Build all images used in debugging.

.PHONY: debug-install-local-build
debug-install-local-build: debug-build-images debug-load-images helm-install-local ## Install BWS Gateway Fabric from local build using debug binary on configured kind cluster.

.PHONY: dev-all
dev-all: deps fmt njs-fmt vet lint unit-test njs-unit-test ## Run all the development checks
