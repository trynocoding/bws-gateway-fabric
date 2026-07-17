#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly namespace="bws-m3"
readonly control_namespace="bws-m3-system"
readonly gateway="bws-gateway"
readonly route="cafe"
readonly host="bws.example.com"
readonly http_port="${BWS_M3_HTTP_PORT:-18080}"
readonly https_port="${BWS_M3_HTTPS_PORT:-18443}"

port_forward_pid=""

restore() {
    kubectl -n "${namespace}" delete -f "${script_dir}/invalid-snippet.yaml" --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "${namespace}" patch httproute "${route}" --type=json \
        -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/name","value":"coffee"}]' \
        >/dev/null 2>&1 || true
    if [[ -n "${port_forward_pid}" ]]; then
        kill "${port_forward_pid}" >/dev/null 2>&1 || true
        wait "${port_forward_pid}" >/dev/null 2>&1 || true
    fi
}
trap restore EXIT

retry() {
    local description="$1"
    shift
    for ((attempt = 1; attempt <= 60; attempt++)); do
        if "$@"; then
            return 0
        fi
        sleep 2
    done
    echo "timed out waiting for ${description}" >&2
    return 1
}

response_contains() {
    local protocol="$1"
    local port="$2"
    local expected="$3"
    local curl_args=(-fsS --noproxy '*' --connect-timeout 2 --max-time 5 --resolve "${host}:${port}:127.0.0.1")
    if [[ "${protocol}" == "https" ]]; then
        curl_args+=(-k)
    fi
    curl "${curl_args[@]}" "${protocol}://${host}:${port}/" | grep -q "Server name: ${expected}-"
}

rollback_logged() {
    kubectl -n "${namespace}" logs "${pod}" -c nginx --since-time="${invalid_start}" 2>/dev/null | \
        grep -q "Config apply failed, rollback successful"
}

control_deployment="$(kubectl -n "${control_namespace}" get deployment \
    -l app.kubernetes.io/instance=bws-m3 \
    -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${control_deployment}" ]]; then
    echo "M3 control-plane Deployment was not found" >&2
    exit 1
fi
kubectl -n "${control_namespace}" rollout status "deployment/${control_deployment}" --timeout=3m
kubectl wait --for=condition=Accepted gatewayclass/bws-poc --timeout=2m
kubectl -n "${namespace}" wait --for=condition=Programmed "gateway/${gateway}" --timeout=3m

dataplane_deployment="$(kubectl -n "${namespace}" get deployment \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${dataplane_deployment}" ]]; then
    echo "BWS data-plane Deployment was not created" >&2
    exit 1
fi
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m

pod="$(kubectl -n "${namespace}" get pod \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
service="$(kubectl -n "${namespace}" get service \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"

run_as_user="$(kubectl -n "${namespace}" get pod "${pod}" -o jsonpath='{.spec.containers[0].securityContext.runAsUser}')"
read_only_root="$(kubectl -n "${namespace}" get pod "${pod}" -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}')"
license_read_only="$(kubectl -n "${namespace}" get pod "${pod}" \
    -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="bws-license")].readOnly}')"
if [[ "${run_as_user}" != "101" || "${read_only_root}" != "true" || "${license_read_only}" != "true" ]]; then
    echo "unexpected data-plane security context or license mount" >&2
    exit 1
fi

kubectl -n "${namespace}" exec "${pod}" -- bash -c '
    test -s /var/run/secrets/ngf/tls.crt
    test -s /var/run/secrets/bws/bws.lic.txt
    test -s /etc/nginx-agent/nginx-agent.conf
    test -s /var/run/nginx/nginx.pid
    /opt/bws/bin/bws.sh -V 2>&1 | grep -q "BES WebServer 3.2.0.242"
'

kubectl -n "${namespace}" port-forward "service/${service}" \
    "${http_port}:80" "${https_port}:443" >/dev/null 2>&1 &
port_forward_pid=$!
retry "HTTP route to coffee" response_contains http "${http_port}" coffee
retry "HTTPS route to coffee" response_contains https "${https_port}" coffee

kubectl -n "${namespace}" patch httproute "${route}" --type=json \
    -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/name","value":"tea"}]' >/dev/null
retry "incremental route update to tea" response_contains http "${http_port}" tea

invalid_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
kubectl -n "${namespace}" apply -f "${script_dir}/invalid-snippet.yaml" >/dev/null
retry "Agent rejection and rollback of invalid BWS configuration" rollback_logged
if ! response_contains http "${http_port}" tea; then
    echo "last known-good configuration was not preserved after an invalid update" >&2
    exit 1
fi

kubectl -n "${namespace}" delete -f "${script_dir}/invalid-snippet.yaml" --ignore-not-found >/dev/null
kubectl -n "${namespace}" patch httproute "${route}" --type=json \
    -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/name","value":"coffee"}]' >/dev/null
retry "route restoration to coffee" response_contains http "${http_port}" coffee

echo "M3 smoke verification passed"
echo "control plane: deployment/${control_deployment}"
echo "data plane: deployment/${dataplane_deployment}, pod/${pod}"
echo "validated: Agent TLS files, BWS version, readiness, non-root/read-only settings, HTTP, HTTPS, incremental update, invalid-config rollback"
