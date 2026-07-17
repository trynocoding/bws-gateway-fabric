#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${script_dir}/../.." && pwd)"
readonly namespace="${BWS_M4_NAMESPACE:-bws-m4}"
readonly control_namespace="${BWS_M4_CONTROL_NAMESPACE:-bws-m4-system}"
readonly gateway="${BWS_M4_GATEWAY:-bws-gateway}"
readonly control_image="${BWS_CONTROL_IMAGE:-bws-gateway-fabric:m4-local}"
readonly data_image="${BWS_DATA_IMAGE:-bws-gateway-fabric/bws:m4-local}"
readonly live_scan="${BWS_M4_LIVE_SCAN:-true}"
readonly product_pattern='gateway\.nginx\.org|NGINX Gateway Fabric|nginxGateway|kind:[[:space:]]+Nginx(Gateway|Proxy)|product-type[^[:alnum:]]+ngf|ngf-product-telemetry|ghcr\.io/nginx/nginx-gateway-fabric|app\.kubernetes\.io/(name|part-of):[[:space:]]+nginx-gateway-fabric|nginx-debug|Successfully configured nginx'
readonly technical_pattern='nginx\.org/|github\.com/nginx/nginx-gateway-fabric|NGINX .*directive|NGINX (configuration|config|worker|error log|default|snippets|context)|nginx worker|nginx_gateway_fabric_nginx_process_requests_total|nginx_http_|nginx\.conf|/usr/share/nginx|internal/controller/nginx|NGINX stub status|NGINX Plus API'

readonly work_dir="$(mktemp -d)"
readonly rendered_file="${work_dir}/rendered.yaml"
readonly metadata_file="${work_dir}/image-metadata.txt"
readonly history_file="${work_dir}/image-history.txt"
readonly residual_file="${work_dir}/residuals.txt"
readonly unclassified_file="${work_dir}/unclassified.txt"
readonly logs_file="${work_dir}/logs.txt"

cleanup() {
    rm -rf "${work_dir}"
}
trap cleanup EXIT

for command in docker helm jq kubectl rg; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

assert_no_product_residue() {
    local label="$1"
    local file="$2"
    local matches
    matches="$(rg -ni "${product_pattern}" "${file}" || true)"
    if [[ -n "${matches}" ]]; then
        echo "${label} contains an old product identity:" >&2
        echo "${matches}" >&2
        return 1
    fi
}

helm template bws-m4 "${repo_dir}/charts/bws-gateway-fabric" \
    --namespace "${control_namespace}" \
    --kube-version 1.31.0 \
    --include-crds \
    --values "${script_dir}/values.yaml" >"${rendered_file}"

assert_no_product_residue "Helm/CRD/RBAC rendering" "${rendered_file}"

if rg -ni 'NGINX Plus|nginx-debug|app_protect|kind:[[:space:]]+WAFPolicy|wafpolicies' "${rendered_file}"; then
    echo "Helm/CRD/RBAC rendering exposes an unsupported upstream capability" >&2
    exit 1
fi

for image in "${control_image}" "${data_image}"; do
    docker image inspect "${image}" --format '{{json .Config}}' >>"${metadata_file}"
    docker history --no-trunc --format '{{.CreatedBy}}' "${image}" >>"${history_file}"
done
assert_no_product_residue "image metadata" "${metadata_file}"
assert_no_product_residue "image history" "${history_file}"

rg -ni 'nginx|ngf' "${rendered_file}" "${metadata_file}" "${history_file}" >"${residual_file}" || true
rg -vi "${technical_pattern}" "${residual_file}" >"${unclassified_file}" || true
if [[ -s "${unclassified_file}" ]]; then
    echo "unclassified nginx/ngf residuals remain:" >&2
    cat "${unclassified_file}" >&2
    exit 1
fi

if [[ "${live_scan}" == "true" ]]; then
    dataplane_pod="$(kubectl -n "${namespace}" get pod \
        -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
        -o jsonpath='{.items[0].metadata.name}')"
    if [[ -z "${dataplane_pod}" ]]; then
        echo "could not resolve a live BWS data-plane Pod" >&2
        exit 1
    fi

    {
        kubectl -n "${control_namespace}" logs deployment/bws-m4-bws-gateway-fabric --tail=-1
        kubectl -n "${namespace}" logs "${dataplane_pod}" -c bws --tail=-1
    } >"${logs_file}"
    assert_no_product_residue "live logs" "${logs_file}"

    mapfile -t old_paths < <(kubectl -n "${namespace}" exec "${dataplane_pod}" -c bws -- sh -c \
        'find / \( -iname "*nginx*" -o -iname "*ngf*" \) 2>/dev/null | sort')
    for path in "${old_paths[@]}"; do
        case "${path}" in
            /etc/bws/nginx.conf|/usr/share/nginx)
                ;;
            *)
                echo "unclassified nginx/ngf filesystem path: ${path}" >&2
                exit 1
                ;;
        esac
    done

    live_labels="$(kubectl -n "${namespace}" get configmap bws-gateway-bws-agent-config \
        -o jsonpath='{.data.bws-agent\.conf}')"
    if ! grep -q 'product-type: bws' <<<"${live_labels}"; then
        echo "live BWS Agent configuration does not report product-type: bws" >&2
        exit 1
    fi
fi

technical_count="$(wc -l <"${residual_file}" | tr -d ' ')"
echo "M4.4 product identity audit passed"
if [[ "${live_scan}" == "true" ]]; then
    echo "validated: image metadata/history, Helm rendering, CRDs, RBAC, logs, Agent labels, and container filesystem"
else
    echo "validated: image metadata/history, Helm rendering, CRDs, and RBAC (live scan disabled)"
fi
echo "classified technical nginx/ngf residual lines: ${technical_count}"
echo "allowed examples: nginx directives/docs, nginx_* metric contracts, nginx.conf, internal source paths, and /usr/share/nginx"
