#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${script_dir}/../.." && pwd)"
readonly namespace="bws-m4"
readonly control_namespace="bws-m4-system"
readonly release="bws-m4"
readonly license_file="${BWS_LICENSE_FILE:-}"
readonly control_image_repository="${BWS_CONTROL_IMAGE_REPOSITORY:-bws-gateway-fabric}"
readonly control_image_tag="${BWS_CONTROL_IMAGE_TAG:-m4-local}"
readonly data_image_repository="${BWS_DATA_IMAGE_REPOSITORY:-bws-gateway-fabric/bws}"
readonly data_image_tag="${BWS_DATA_IMAGE_TAG:-m4-local}"
readonly image_pull_policy="${BWS_IMAGE_PULL_POLICY:-Never}"

for command in helm kubectl openssl; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

if kubectl get gatewayclass bws >/dev/null 2>&1; then
    owner_release="$(kubectl get gatewayclass bws -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}')"
    if [[ "${owner_release}" != "${release}" ]]; then
        echo "GatewayClass bws already exists and is not owned by Helm release ${release}" >&2
        exit 1
    fi
fi

kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${license_file}" ]]; then
    if [[ ! -s "${license_file}" ]]; then
        echo "BWS_LICENSE_FILE does not point to a non-empty file: ${license_file}" >&2
        exit 1
    fi
    kubectl -n "${namespace}" create secret generic bws-license \
        --from-file="bws.lic.txt=${license_file}" \
        --dry-run=client -o yaml | kubectl apply -f -
elif ! kubectl -n "${namespace}" get secret bws-license >/dev/null 2>&1; then
    echo "set BWS_LICENSE_FILE or create Secret ${namespace}/bws-license with key bws.lic.txt" >&2
    exit 1
fi

tls_dir="$(mktemp -d)"
trap 'rm -rf "${tls_dir}"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
    -subj "/CN=bws.example.com" \
    -addext "subjectAltName=DNS:bws.example.com" \
    -keyout "${tls_dir}/tls.key" \
    -out "${tls_dir}/tls.crt" >/dev/null 2>&1
kubectl -n "${namespace}" create secret tls bws-m4-tls \
    --cert="${tls_dir}/tls.crt" \
    --key="${tls_dir}/tls.key" \
    --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "${release}" "${repo_dir}/charts/bws-gateway-fabric" \
    --namespace "${control_namespace}" \
    --create-namespace \
    --values "${script_dir}/values.yaml" \
    --set-string "bwsGateway.image.repository=${control_image_repository}" \
    --set-string "bwsGateway.image.tag=${control_image_tag}" \
    --set-string "bwsGateway.image.pullPolicy=${image_pull_policy}" \
    --set-string "bws.image.repository=${data_image_repository}" \
    --set-string "bws.image.tag=${data_image_tag}" \
    --set-string "bws.image.pullPolicy=${image_pull_policy}" \
    --wait \
    --timeout 5m

kubectl -n "${namespace}" apply -f "${script_dir}/../bws-m3/workloads.yaml"
kubectl -n "${namespace}" apply -f "${script_dir}/gateway.yaml"
kubectl -n "${namespace}" rollout status deployment/coffee --timeout=2m
kubectl -n "${namespace}" rollout status deployment/tea --timeout=2m

echo "M4.3 resources deployed. Run ${script_dir}/verify.sh"
