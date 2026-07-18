#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${script_dir}/../.." && pwd)"
readonly cluster_name="${BWS_M4_KIND_CLUSTER:-bws-m4-isolated}"
readonly expected_context="kind-${cluster_name}"
readonly namespace="bws-m4-system"
readonly release="bws-m4"
readonly runner_image="bws-m4/conformance-runner:v1.5.1"
readonly echo_image="gcr.io/k8s-staging-gateway-api/echo-basic:v20260204-monthly-2026.01-60-g28382302"
readonly coredns_image="registry.k8s.io/coredns/coredns:v1.12.2"
readonly report="${repo_dir}/build/bws-m4-conformance-profile.yaml"
readonly test_log="${repo_dir}/build/bws-m4-conformance.log"
readonly pod="bws-m4-conformance"

temporary_container=""
baseline_changed=false

cleanup() {
    local exit_code=$?

    if [[ -n "${temporary_container}" ]]; then
        docker rm "${temporary_container}" >/dev/null 2>&1 || true
    fi
    kubectl delete pod "${pod}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete -f "${repo_dir}/tests/conformance/conformance-rbac.yaml" \
        --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete namespace \
        gateway-conformance-infra \
        gateway-conformance-app-backend \
        gateway-conformance-web-backend \
        --ignore-not-found --wait=false >/dev/null 2>&1 || true
    if [[ "${baseline_changed}" == true ]]; then
        helm upgrade "${release}" "${repo_dir}/charts/bws-gateway-fabric" \
            --namespace "${namespace}" \
            --values "${script_dir}/values.yaml" \
            --wait --timeout 10m >/dev/null || true
    fi
    return "${exit_code}"
}
trap cleanup EXIT

for command in docker go helm jq kind kubectl yq; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

if [[ "$(kubectl config current-context)" != "${expected_context}" ]]; then
    echo "refusing to run outside isolated context ${expected_context}" >&2
    exit 1
fi

mkdir -p "${repo_dir}/build"
rm -f "${report}" "${test_log}"

load_fixture_image() {
    local image=$1
    local suffix=$2

    if ! docker image inspect "${image}" >/dev/null 2>&1; then
        docker pull --platform linux/amd64 "${image}"
    fi
    if kind load docker-image "${image}" --name "${cluster_name}"; then
        return
    fi

    echo "kind image import failed for ${image}; flattening the local image" >&2
    temporary_container="${cluster_name}-${suffix}-flatten-$$"
    docker create --name "${temporary_container}" "${image}" >/dev/null
    docker commit "${temporary_container}" "${image}" >/dev/null
    docker rm "${temporary_container}" >/dev/null
    temporary_container=""
    kind load docker-image "${image}" --name "${cluster_name}"
}

(
    cd "${repo_dir}/tests"
    go test -c -tags conformance,experimental \
        -o "${repo_dir}/build/conformance.test" ./conformance
)
docker build --platform linux/amd64 -t "${runner_image}" \
    -f "${script_dir}/Dockerfile.conformance" "${repo_dir}"
kind load docker-image "${runner_image}" --name "${cluster_name}"
load_fixture_image "${echo_image}" echo
load_fixture_image "${coredns_image}" coredns

baseline_changed=true
helm upgrade "${release}" "${repo_dir}/charts/bws-gateway-fabric" \
    --namespace "${namespace}" \
    --values "${script_dir}/values.yaml" \
    --set-json 'bwsGateway.watchNamespaces=[]' \
    --set bws.autoscaling.enable=false \
    --set bws.replicas=1 \
    --set-string bws.container.resources.requests.memory=128Mi \
    --wait --timeout 10m >/dev/null

# Every provisioned BWS data-plane Pod needs the product license in its own
# namespace. The upstream suite applies this Namespace idempotently.
kubectl create namespace gateway-conformance-infra \
    --dry-run=client -o json | kubectl apply -f - >/dev/null
kubectl -n bws-m4 get secret bws-license -o json |
    jq '.metadata = {"name":"bws-license","namespace":"gateway-conformance-infra"}' |
    kubectl apply -f - >/dev/null

kubectl apply -f "${repo_dir}/tests/conformance/conformance-rbac.yaml" >/dev/null
kubectl delete pod "${pod}" --ignore-not-found --wait=true >/dev/null
kubectl run "${pod}" \
    --image="${runner_image}" \
    --image-pull-policy=Never \
    --overrides='{ "spec": { "serviceAccountName": "conformance" } }' \
    --restart=Never \
    --command -- /bin/bash -c '
        set -o pipefail
        /usr/local/bin/conformance.test \
            -test.v \
            -test.timeout=15m \
            -test.run=TestConformance \
            -gateway-class=bws \
            -version=m4-local \
            -conformance-profiles=GATEWAY-HTTP,GATEWAY-GRPC,GATEWAY-TLS \
            -report-output=/tmp/conformance-profile.yaml \
            2>&1 | tee /tmp/conformance.log
        code=${PIPESTATUS[0]}
        echo "${code}" >/tmp/exit-code
        exec sleep infinity
    ' >/dev/null
kubectl wait --for=condition=Ready "pod/${pod}" --timeout=3m

for ((attempt = 1; attempt <= 180; attempt++)); do
    if kubectl exec "${pod}" -- test -s /tmp/exit-code >/dev/null 2>&1; then
        break
    fi
    if ((attempt % 6 == 0)); then
        echo "conformance still running: $((attempt * 5)) seconds elapsed"
        kubectl logs "${pod}" --tail=3 || true
    fi
    if [[ "${attempt}" -eq 180 ]]; then
        echo "conformance test did not finish within 15 minutes" >&2
        exit 1
    fi
    sleep 5
done

kubectl cp "default/${pod}:/tmp/conformance-profile.yaml" "${report}"
kubectl cp "default/${pod}:/tmp/conformance.log" "${test_log}"
sed -i '1{/^CONFORMANCE PROFILE$/d;}' "${report}"
test_exit_code="$(kubectl exec "${pod}" -- cat /tmp/exit-code)"
if [[ "${test_exit_code}" -ne 0 ]]; then
    echo "Gateway API conformance test failed; see ${test_log}" >&2
    tail -80 "${test_log}" >&2
    exit 1
fi

for profile in GATEWAY-HTTP GATEWAY-GRPC GATEWAY-TLS; do
    core_result="$(yq -r ".profiles[] | select(.name == \"${profile}\") | .core.result" "${report}")"
    if [[ "${core_result}" != success ]]; then
        echo "${profile} core result is ${core_result}" >&2
        exit 1
    fi
done

http_extended_result="$(yq -r '.profiles[] | select(.name == "GATEWAY-HTTP") | .extended.result' "${report}")"
if [[ "${http_extended_result}" == failure ]]; then
    echo "GATEWAY-HTTP extended result is failure" >&2
    exit 1
fi

echo "M4.4 Gateway API conformance verification passed"
echo "profiles: GATEWAY-HTTP, GATEWAY-GRPC, GATEWAY-TLS"
echo "report: ${report}"
