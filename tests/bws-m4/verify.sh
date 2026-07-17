#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly namespace="bws-m4"
readonly control_namespace="bws-m4-system"
readonly gateway="bws-gateway"
readonly route="cafe"
readonly host="bws.example.com"
readonly http_port="${BWS_M4_HTTP_PORT:-28080}"
readonly https_port="${BWS_M4_HTTPS_PORT:-28443}"

port_forward_pid=""
restore() {
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

control_deployment="$(kubectl -n "${control_namespace}" get deployment \
    -l app.kubernetes.io/instance=bws-m4 \
    -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${control_namespace}" rollout status "deployment/${control_deployment}" --timeout=3m
kubectl wait --for=condition=Accepted gatewayclass/bws --timeout=2m
kubectl -n "${namespace}" wait --for=condition=Programmed "gateway/${gateway}" --timeout=3m

dataplane_deployment="$(kubectl -n "${namespace}" get deployment \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m

container_name="$(kubectl -n "${namespace}" get deployment "${dataplane_deployment}" \
    -o jsonpath='{.spec.template.spec.containers[0].name}')"
init_command="$(kubectl -n "${namespace}" get deployment "${dataplane_deployment}" \
    -o jsonpath='{.spec.template.spec.initContainers[0].command[0]}')"
replicas="$(kubectl -n "${namespace}" get deployment "${dataplane_deployment}" \
    -o jsonpath='{.status.readyReplicas}')"
if [[ "${container_name}" != "bws" || "${init_command}" != "/usr/bin/bws-gateway" || "${replicas}" != "2" ]]; then
    echo "unexpected M4.1 data-plane identity or replica state" >&2
    exit 1
fi

while IFS= read -r pod; do
    kubectl -n "${namespace}" exec "${pod}" -c bws -- sh -c '
        test -s /var/run/secrets/ngf/tls.crt
        test -s /var/run/secrets/bws/bws.lic.txt
        /usr/bin/bws-agent -v | grep -q "bws-agent version"
        /opt/bws/bin/bws.sh -V 2>&1 | grep -q "BES WebServer 3.2.0.242"
    '
done < <(kubectl -n "${namespace}" get pods \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o name)

service="$(kubectl -n "${namespace}" get service \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${namespace}" port-forward "service/${service}" \
    "${http_port}:80" "${https_port}:443" >/dev/null 2>&1 &
port_forward_pid=$!
retry "HTTP route to coffee" response_contains http "${http_port}" coffee
retry "HTTPS route to coffee" response_contains https "${https_port}" coffee

kubectl -n "${namespace}" patch httproute "${route}" --type=json \
    -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/name","value":"tea"}]' >/dev/null
retry "incremental route update to tea" response_contains http "${http_port}" tea

echo "M4.1 smoke verification passed"
echo "control plane: deployment/${control_deployment}"
echo "data plane: deployment/${dataplane_deployment}"
echo "validated: BWS identities, two Agents, readiness, HTTP, HTTPS, and incremental route update"
