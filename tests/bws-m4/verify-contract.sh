#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${script_dir}/../.." && pwd)"
readonly namespace="bws-m4"
readonly control_namespace="bws-m4-system"
readonly gateway="bws-gateway"
readonly chart_dir="${repo_dir}/charts/bws-gateway-fabric"
readonly crd_dir="${repo_dir}/config/crd/bases"
readonly rendered_file="$(mktemp)"
readonly old_path_pattern="/etc/nginx-agent|/etc/nginx(/|[[:space:]\"'])|/etc/bws/nginx\\.conf|/var/run/nginx|/var/cache/nginx|/var/lib/nginx-agent|/var/log/nginx-agent"
readonly legacy_api_pattern="gateway\\.nginx\\.org|kind: Nginx(Gateway|Proxy)|nginx(gateways|proxies)|wafpolicies"

cleanup() {
    rm -f "${rendered_file}"
}
trap cleanup EXIT

source_targets=(
    build/Dockerfile.bws
    build/bws-entrypoint.sh
    internal/controller/nginx/agent/deployment.go
    internal/controller/nginx/conf
    internal/controller/nginx/config
    internal/controller/provisioner
)

if rg -n "${old_path_pattern}" "${source_targets[@]}"; then
    echo "BWS runtime source still contains an old directory contract" >&2
    exit 1
fi

helm template bws-m4 "${repo_dir}/charts/bws-gateway-fabric" \
    --namespace "${control_namespace}" \
    --kube-version 1.31.0 \
    --skip-crds \
    --values "${script_dir}/values.yaml" >"${rendered_file}"
if rg -n "${old_path_pattern}" "${rendered_file}"; then
    echo "M4 Helm rendering contains an old directory contract" >&2
    exit 1
fi

if [[ "$(yq '.name' "${chart_dir}/Chart.yaml")" != "bws-gateway-fabric" ]]; then
    echo "unexpected Helm Chart name" >&2
    exit 1
fi

legacy_values="$(jq -r '.properties | keys[] | select(. == "nginxGateway" or . == "nginx")' \
    "${chart_dir}/values.schema.json")"
if [[ -n "${legacy_values}" ]]; then
    echo "legacy Helm top-level values remain in the generated schema: ${legacy_values}" >&2
    exit 1
fi

if ! jq -e '.properties.bwsGateway and .properties.bws' "${chart_dir}/values.schema.json" >/dev/null; then
    echo "generated Helm schema is missing bwsGateway or bws" >&2
    exit 1
fi

if rg -n "${legacy_api_pattern}" "${crd_dir}" "${rendered_file}"; then
    echo "M4 artifacts contain a legacy or unsupported custom-resource contract" >&2
    exit 1
fi

for crd in \
    gateway.bessystem.com_bwsgateways.yaml \
    gateway.bessystem.com_bwsproxies.yaml; do
    if [[ ! -s "${crd_dir}/${crd}" ]]; then
        echo "missing generated BWS CRD: ${crd}" >&2
        exit 1
    fi
done

if rg -n 'nginxPlus:|waf:|wafContainers:' "${crd_dir}/gateway.bessystem.com_bwsproxies.yaml"; then
    echo "BwsProxy exposes unsupported NGINX Plus or F5 WAF fields" >&2
    exit 1
fi

gateway_class_ref="$(kubectl get gatewayclass bws \
    -o jsonpath='{.spec.parametersRef.group}/{.spec.parametersRef.kind}')"
if [[ "${gateway_class_ref}" != "gateway.bessystem.com/BwsProxy" ]]; then
    echo "unexpected GatewayClass parametersRef: ${gateway_class_ref}" >&2
    exit 1
fi

kubectl -n "${control_namespace}" get bwsgateway.gateway.bessystem.com bws-gateway-fabric-config >/dev/null
kubectl -n "${control_namespace}" get bwsproxy.gateway.bessystem.com bws-gateway-fabric-proxy-config >/dev/null

agent_config_keys="$(kubectl -n "${namespace}" get configmap bws-gateway-bws-agent-config -o json | \
    jq -r '.data | keys[]')"
if [[ "${agent_config_keys}" != "bws-agent.conf" ]]; then
    echo "unexpected BWS Agent ConfigMap keys: ${agent_config_keys}" >&2
    exit 1
fi

volume_names="$(kubectl -n "${namespace}" get deployment \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{range .items[0].spec.template.spec.volumes[*]}{.name}{"\n"}{end}')"
if grep -q 'nginx' <<<"${volume_names}"; then
    echo "data-plane volume names expose the old product identity" >&2
    exit 1
fi

mapfile -t pods < <(kubectl -n "${namespace}" get pods \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}')
if [[ "${#pods[@]}" -ne 2 ]]; then
    echo "expected two active BWS data-plane Pods, got ${#pods[@]}" >&2
    exit 1
fi

for pod in "${pods[@]}"; do
    kubectl -n "${namespace}" exec "${pod}" -c bws -- sh -c '
        test -s /etc/bws/bws.conf
        test ! -e /etc/bws/nginx.conf
        test -s /etc/bws-agent/bws-agent.conf
        test -s /var/run/bws/bws.pid
        test -d /var/cache/bws
        test -d /var/lib/bws-agent
        test -d /var/log/bws-agent
        test ! -e /etc/nginx
        test ! -e /etc/nginx-agent
        test ! -e /var/run/nginx
        test ! -e /var/cache/nginx
        test ! -e /var/lib/nginx-agent
        test ! -e /var/log/nginx-agent
    '
done

recent_logs="$(
    kubectl -n "${control_namespace}" logs deployment/bws-m4-bws-gateway-fabric --since=10m 2>/dev/null || true
    kubectl -n "${namespace}" logs \
        -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
        -c bws --since=10m --tail=-1 --prefix=true 2>/dev/null || true
)"
if rg -n 'NGINX Agent|NGINX Gateway Fabric|Creating/Updating nginx resources|nginx pod|NGINX configuration' \
    <<<"${recent_logs}"; then
    echo "recent M4 logs expose an old product identity" >&2
    exit 1
fi

echo "M4.3 product and API contract verification passed"
echo "validated: BWS Chart/schema/CRDs, live API references, runtime paths, ConfigMap key, volume names, filesystems, and logs"
