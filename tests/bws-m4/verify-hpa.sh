#!/usr/bin/env bash

set -euo pipefail

readonly namespace="bws-m4"
readonly gateway="bws-gateway"
readonly host="bws.example.com"
readonly port="${BWS_M4_HPA_HTTP_PORT:-38080}"
readonly expected_context="kind-${BWS_M4_KIND_CLUSTER:-bws-m4-isolated}"
readonly selector="gateway.networking.k8s.io/gateway-name=${gateway}"
readonly min_replicas=2
readonly scale_up_replicas=3

port_forward_pid=""
load_marker=""
result_dir=""
load_pids=()

stop_load() {
    if [[ -n "${load_marker}" ]]; then
        rm -f "${load_marker}"
    fi
    local pid
    for pid in "${load_pids[@]}"; do
        wait "${pid}" >/dev/null 2>&1 || true
    done
    load_pids=()
}

cleanup() {
    stop_load
    if [[ -n "${port_forward_pid}" ]]; then
        kill "${port_forward_pid}" >/dev/null 2>&1 || true
        wait "${port_forward_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${result_dir}" ]]; then
        rm -rf "${result_dir}"
    fi
}
trap cleanup EXIT

for command in curl kubectl; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

if [[ "$(kubectl config current-context)" != "${expected_context}" ]]; then
    echo "refusing to run outside isolated context ${expected_context}" >&2
    exit 1
fi

if ! kubectl get apiservice v1beta1.metrics.k8s.io \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -q True; then
    echo "Metrics API is not Available; run install-metrics-server.sh first" >&2
    exit 1
fi

deployment="$(kubectl -n "${namespace}" get deployment -l "${selector}" \
    -o jsonpath='{.items[0].metadata.name}')"
service="$(kubectl -n "${namespace}" get service -l "${selector}" \
    -o jsonpath='{.items[0].metadata.name}')"
hpa="$(kubectl -n "${namespace}" get hpa -l "${selector}" \
    -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${hpa}" ]]; then
    echo "BWS data-plane HPA was not provisioned" >&2
    exit 1
fi

kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=5m
kubectl -n "${namespace}" port-forward "service/${service}" "${port}:80" >/dev/null 2>&1 &
port_forward_pid=$!

for ((attempt = 1; attempt <= 30; attempt++)); do
    if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
        --resolve "${host}:${port}:127.0.0.1" "http://${host}:${port}/" |
        grep -q 'Server name: coffee-'; then
        break
    fi
    if [[ "${attempt}" -eq 30 ]]; then
        echo "timed out waiting for the baseline HTTP route" >&2
        exit 1
    fi
    sleep 2
done

for ((attempt = 1; attempt <= 60; attempt++)); do
    current_replicas="$(kubectl -n "${namespace}" get hpa "${hpa}" -o jsonpath='{.status.currentReplicas}')"
    current_cpu="$(kubectl -n "${namespace}" get hpa "${hpa}" \
        -o jsonpath='{.status.currentMetrics[?(@.resource.name=="cpu")].resource.current.averageUtilization}')"
    if [[ "${current_replicas}" == "${min_replicas}" && -n "${current_cpu}" ]]; then
        break
    fi
    if [[ "${attempt}" -eq 60 ]]; then
        echo "HPA did not settle at ${min_replicas} replicas with CPU metrics" >&2
        kubectl -n "${namespace}" describe hpa "${hpa}" >&2
        exit 1
    fi
    sleep 5
done

result_dir="$(mktemp -d)"
load_marker="${result_dir}/run"
touch "${load_marker}"

load_worker() {
    local worker_id="$1"
    local successes=0
    local failures=0
    while [[ -e "${load_marker}" ]]; do
        if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
            --resolve "${host}:${port}:127.0.0.1" "http://${host}:${port}/" >/dev/null; then
            ((successes += 1))
        else
            ((failures += 1))
        fi
    done
    echo "${successes} ${failures}" >"${result_dir}/${worker_id}"
}

for worker_id in $(seq 1 32); do
    load_worker "${worker_id}" &
    load_pids+=("$!")
done

scaled_replicas=0
for ((attempt = 1; attempt <= 60; attempt++)); do
    scaled_replicas="$(kubectl -n "${namespace}" get hpa "${hpa}" -o jsonpath='{.status.currentReplicas}')"
    if [[ "${scaled_replicas}" -ge "${scale_up_replicas}" ]]; then
        break
    fi
    if [[ "${attempt}" -eq 60 ]]; then
        stop_load
        echo "HPA did not scale the BWS data plane above ${min_replicas} replicas" >&2
        kubectl -n "${namespace}" describe hpa "${hpa}" >&2
        exit 1
    fi
    sleep 5
done

kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=5m
stop_load

read -r successes failures < <(awk '{successes += $1; failures += $2} END {print successes + 0, failures + 0}' \
    "${result_dir}"/[0-9]*)
if [[ "${successes}" -eq 0 || "${failures}" -ne 0 ]]; then
    echo "HPA load traffic had ${successes} successes and ${failures} failures" >&2
    exit 1
fi

for ((attempt = 1; attempt <= 90; attempt++)); do
    current_replicas="$(kubectl -n "${namespace}" get hpa "${hpa}" -o jsonpath='{.status.currentReplicas}')"
    ready_replicas="$(kubectl -n "${namespace}" get deployment "${deployment}" \
        -o jsonpath='{.status.readyReplicas}')"
    if [[ "${current_replicas}" == "${min_replicas}" && "${ready_replicas}" == "${min_replicas}" ]]; then
        echo "M4.4 HPA verification passed"
        echo "validated: Metrics API, CPU-driven scale-up to ${scaled_replicas}, ${successes} successful requests with zero failures, and scale-down to ${min_replicas}"
        exit 0
    fi
    sleep 5
done

echo "HPA did not scale down to ${min_replicas} replicas" >&2
kubectl -n "${namespace}" describe hpa "${hpa}" >&2
exit 1
