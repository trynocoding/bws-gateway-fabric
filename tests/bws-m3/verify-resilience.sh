#!/usr/bin/env bash

set -euo pipefail

readonly namespace="bws-m3"
readonly control_namespace="bws-m3-system"
readonly gateway="bws-gateway"
readonly host="bws.example.com"

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

http_request() {
    curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
        --resolve "${host}:${node_port}:${node_ip}" \
        "http://${host}:${node_port}/" | grep -q 'Server name: coffee-'
}

all_agents_reconnected() {
    local connected
    connected="$(kubectl -n "${namespace}" logs \
        -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
        -c nginx --since-time="${reconnect_start}" --prefix=true 2>/dev/null | \
        grep -c 'Agent connected' || true)"
    [[ "${connected}" -ge 2 ]]
}

dataplane_deployment="$(kubectl -n "${namespace}" get deployment \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
control_deployment="$(kubectl -n "${control_namespace}" get deployment \
    -l app.kubernetes.io/instance=bws-m3 \
    -o jsonpath='{.items[0].metadata.name}')"
service="$(kubectl -n "${namespace}" get service \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
node_port="$(kubectl -n "${namespace}" get service "${service}" \
    -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"
node_ip="$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"

if [[ -z "${dataplane_deployment}" || -z "${control_deployment}" || -z "${node_port}" || -z "${node_ip}" ]]; then
    echo "could not resolve M3 deployments or NodePort endpoint" >&2
    exit 1
fi

ready_replicas="$(kubectl -n "${namespace}" get deployment "${dataplane_deployment}" \
    -o jsonpath='{.status.readyReplicas}')"
if [[ "${ready_replicas}" != "2" ]]; then
    echo "expected two ready BWS replicas, got ${ready_replicas:-0}" >&2
    exit 1
fi
retry "initial NodePort traffic" http_request

old_pod="$(kubectl -n "${namespace}" get pod \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${namespace}" delete pod "${old_pod}" --wait=false >/dev/null
retry "traffic while one BWS Pod is replaced" http_request
kubectl -n "${namespace}" wait --for=delete "pod/${old_pod}" --timeout=2m
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m
retry "traffic after BWS Pod replacement" http_request

reconnect_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
control_pod="$(kubectl -n "${control_namespace}" get pod \
    -l app.kubernetes.io/instance=bws-m3 \
    -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${control_namespace}" delete pod "${control_pod}" --wait=false >/dev/null
retry "traffic during control-plane restart" http_request
kubectl -n "${control_namespace}" wait --for=delete "pod/${control_pod}" --timeout=2m
kubectl -n "${control_namespace}" rollout status "deployment/${control_deployment}" --timeout=5m
retry "both Agents to reconnect" all_agents_reconnected
retry "traffic after Agent reconnection" http_request

kubectl -n "${namespace}" rollout restart "deployment/${dataplane_deployment}" >/dev/null
(
    for ((attempt = 1; attempt <= 40; attempt++)); do
        http_request
        sleep 0.25
    done
) &
traffic_probe_pid=$!
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m
if ! wait "${traffic_probe_pid}"; then
    echo "traffic failed during the two-replica rolling restart" >&2
    exit 1
fi

echo "M3 resilience verification passed"
echo "validated: two replicas, Pod replacement, control-plane restart, Agent reconnect, rolling restart without request failure"
