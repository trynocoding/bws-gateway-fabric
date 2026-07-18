#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${script_dir}/../.." && pwd)"
readonly cluster_name="${BWS_M4_KIND_CLUSTER:-bws-m4-isolated}"
readonly node_image="${BWS_M4_KIND_NODE_IMAGE:-kindest/node:v1.35.1}"
readonly kubeconfig="${BWS_M4_KIND_KUBECONFIG:-${repo_dir}/build/bws-m4-isolated.kubeconfig}"
readonly control_image="${BWS_CONTROL_IMAGE_REPOSITORY:-bws-gateway-fabric}:${BWS_CONTROL_IMAGE_TAG:-m4-local}"
readonly data_image="${BWS_DATA_IMAGE_REPOSITORY:-bws-gateway-fabric/bws}:${BWS_DATA_IMAGE_TAG:-m4-local}"
readonly workload_image="${BWS_M4_WORKLOAD_IMAGE:-nginxdemos/nginx-hello:plain-text}"

for command in docker kind kubectl; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

for image in "${control_image}" "${data_image}" "${workload_image}"; do
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
        echo "required local image not found: ${image}" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "${kubeconfig}")"
if ! kind get clusters | grep -Fxq "${cluster_name}"; then
    kind create cluster \
        --name "${cluster_name}" \
        --image "${node_image}" \
        --config "${script_dir}/kind-isolated.yaml" \
        --kubeconfig "${kubeconfig}"
else
    kind get kubeconfig --name "${cluster_name}" >"${kubeconfig}"
fi
chmod 600 "${kubeconfig}"

if [[ "$(kubectl --kubeconfig "${kubeconfig}" get nodes --no-headers | wc -l)" -ne 3 ]]; then
    echo "isolated cluster must contain one control-plane and two worker nodes" >&2
    exit 1
fi

kubectl --kubeconfig "${kubeconfig}" kustomize \
    "${repo_dir}/config/crd/gateway-api/experimental" |
    kubectl --kubeconfig "${kubeconfig}" apply --server-side -f -

for image in "${control_image}" "${data_image}" "${workload_image}"; do
    kind load docker-image "${image}" --name "${cluster_name}"
done

kubectl --kubeconfig "${kubeconfig}" wait --for=condition=Ready nodes --all --timeout=3m

echo "isolated cluster is ready"
echo "cluster: ${cluster_name}"
echo "kubeconfig: ${kubeconfig}"
echo "nodes: one control-plane and two workers"
echo "loaded images: ${control_image}, ${data_image}, ${workload_image}"
