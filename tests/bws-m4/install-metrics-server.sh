#!/usr/bin/env bash

set -euo pipefail

readonly cluster_name="${BWS_M4_KIND_CLUSTER:-bws-m4-isolated}"
readonly expected_context="kind-${cluster_name}"
readonly version="v0.8.1"
readonly manifest_sha256="4a672c4891902573a3ff753cece5de1bf1f55dd053403dfec39df9d1636b7ff1"
readonly manifest_url="https://github.com/kubernetes-sigs/metrics-server/releases/download/${version}/components.yaml"
readonly image="registry.k8s.io/metrics-server/metrics-server:${version}"
readonly fallback_image="${BWS_M4_METRICS_IMAGE:-bws-m4/metrics-server:${version}}"

temporary_container=""

cleanup() {
    rm -f "${manifest}"
    if [[ -n "${temporary_container}" ]]; then
        docker rm "${temporary_container}" >/dev/null 2>&1 || true
    fi
}

for command in curl docker kind kubectl sha256sum; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

if [[ "$(kubectl config current-context)" != "${expected_context}" ]]; then
    echo "refusing to run outside isolated context ${expected_context}" >&2
    exit 1
fi

manifest="$(mktemp)"
trap cleanup EXIT
curl -fsSL "${manifest_url}" -o "${manifest}"
echo "${manifest_sha256}  ${manifest}" | sha256sum --check --status

if ! docker image inspect "${image}" >/dev/null 2>&1; then
    docker pull "${image}"
fi
runtime_image="${image}"
if ! kind load docker-image "${image}" --name "${cluster_name}"; then
    echo "kind image import failed; creating a local single-platform image" >&2
    if ! docker image inspect "${fallback_image}" >/dev/null 2>&1; then
        temporary_container="${cluster_name}-metrics-server-flatten-$$"
        docker create --name "${temporary_container}" "${image}" >/dev/null
        docker commit "${temporary_container}" "${fallback_image}" >/dev/null
        docker rm "${temporary_container}" >/dev/null
        temporary_container=""
    fi
    kind load docker-image "${fallback_image}" --name "${cluster_name}"
    runtime_image="${fallback_image}"
fi

kubectl apply -f "${manifest}"
kubectl -n kube-system set image deployment/metrics-server "metrics-server=${runtime_image}" >/dev/null
if ! kubectl -n kube-system get deployment metrics-server \
    -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--kubelet-insecure-tls'; then
    kubectl -n kube-system patch deployment metrics-server --type=json -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/containers/0/args/-",
        "value": "--kubelet-insecure-tls"
      }
    ]' >/dev/null
fi

kubectl -n kube-system rollout status deployment/metrics-server --timeout=5m
kubectl wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=3m

for ((attempt = 1; attempt <= 30; attempt++)); do
    if kubectl top nodes >/dev/null 2>&1; then
        echo "Metrics API is ready"
        echo "metrics-server: ${version}"
        exit 0
    fi
    sleep 2
done

echo "Metrics API became Available but kubectl top nodes did not return metrics" >&2
exit 1
