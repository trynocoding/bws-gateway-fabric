#!/usr/bin/env bash

set -euo pipefail

readonly namespace="bws-m4"
readonly control_namespace="bws-m4-system"
readonly gateway="bws-gateway"
readonly host="bws.example.com"
readonly temp_dir="$(mktemp -d)"
readonly traffic_stop_file="${temp_dir}/stop"
readonly traffic_failure_file="${temp_dir}/failures"
readonly traffic_success_file="${temp_dir}/successes"

traffic_probe_pid=""

cleanup() {
    touch "${traffic_stop_file}"
    if [[ -n "${traffic_probe_pid}" ]]; then
        wait "${traffic_probe_pid}" >/dev/null 2>&1 || true
    fi
    rm -rf "${temp_dir}"
}
trap cleanup EXIT

retry() {
    local description="$1"
    shift
    for ((attempt = 1; attempt <= 90; attempt++)); do
        if "$@"; then
            return 0
        fi
        sleep 2
    done
    echo "timed out waiting for ${description}" >&2
    return 1
}

http_request() {
    curl -fsS --noproxy '*' --connect-timeout 1 --max-time 2 \
        --resolve "${host}:80:${service_ip}" \
        "http://${host}/" | grep -q 'Server name: coffee-'
}

continuous_traffic() {
    while [[ ! -e "${traffic_stop_file}" ]]; do
        if http_request; then
            printf '.' >>"${traffic_success_file}"
        else
            date -u +%Y-%m-%dT%H:%M:%SZ >>"${traffic_failure_file}"
        fi
        sleep 0.25
    done
}

assert_no_traffic_failures() {
    if [[ -s "${traffic_failure_file}" ]]; then
        echo "traffic failed during resilience operations:" >&2
        cat "${traffic_failure_file}" >&2
        return 1
    fi
}

all_agents_reconnected() {
    local connected
    connected="$(kubectl -n "${namespace}" logs \
        -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
        -c bws --since-time="${reconnect_start}" --tail=-1 --prefix=true 2>/dev/null | \
        grep -c 'Agent connected' || true)"
    [[ "${connected}" -ge 2 ]]
}

deployment_is_stable() {
    local state
    state="$(kubectl -n "${namespace}" get deployment "${dataplane_deployment}" \
        -o jsonpath='{.spec.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}/{.status.availableReplicas}/{.status.unavailableReplicas}')"
    [[ "${state}" == "2/2/2/2/" || "${state}" == "2/2/2/2/0" ]]
}

wait_for_stable_deployment() {
    local consecutive=0
    for ((attempt = 1; attempt <= 90; attempt++)); do
        if deployment_is_stable; then
            ((consecutive += 1))
            if [[ "${consecutive}" -ge 5 ]]; then
                return 0
            fi
        else
            consecutive=0
        fi
        sleep 2
    done
    echo "data-plane Deployment did not remain stable" >&2
    return 1
}

dataplane_deployment="$(kubectl -n "${namespace}" get deployment \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
control_deployment="$(kubectl -n "${control_namespace}" get deployment \
    -l app.kubernetes.io/instance=bws-m4 \
    -o jsonpath='{.items[0].metadata.name}')"
service_ip="$(kubectl -n "${namespace}" get service \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].spec.clusterIP}')"

if [[ -z "${dataplane_deployment}" || -z "${control_deployment}" || -z "${service_ip}" ]]; then
    echo "could not resolve M4.3 deployments or ClusterIP endpoint" >&2
    exit 1
fi

wait_for_stable_deployment
retry "initial BWS traffic" http_request
continuous_traffic &
traffic_probe_pid=$!

old_pod="$(kubectl -n "${namespace}" get pod \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${namespace}" delete pod "${old_pod}" --wait=false >/dev/null
kubectl -n "${namespace}" wait --for=delete "pod/${old_pod}" --timeout=2m
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m
wait_for_stable_deployment
assert_no_traffic_failures

reconnect_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
control_pod="$(kubectl -n "${control_namespace}" get pod \
    -l app.kubernetes.io/instance=bws-m4 \
    -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${control_namespace}" delete pod "${control_pod}" --wait=false >/dev/null
kubectl -n "${control_namespace}" wait --for=delete "pod/${control_pod}" --timeout=2m
kubectl -n "${control_namespace}" rollout status "deployment/${control_deployment}" --timeout=5m
retry "both BWS Agents to reconnect" all_agents_reconnected
retry "traffic after Agent reconnection" http_request
assert_no_traffic_failures

kubectl -n "${namespace}" rollout restart "deployment/${dataplane_deployment}" >/dev/null
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m
wait_for_stable_deployment
retry "traffic after rolling restart" http_request

touch "${traffic_stop_file}"
wait "${traffic_probe_pid}"
traffic_probe_pid=""
assert_no_traffic_failures

successful_requests="$(wc -c <"${traffic_success_file}")"
echo "M4.3 resilience verification passed"
echo "validated: ${successful_requests} uninterrupted requests, Pod replacement, control-plane restart, two-Agent reconnect, and rolling restart"
