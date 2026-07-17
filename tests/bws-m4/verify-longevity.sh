#!/usr/bin/env bash

set -euo pipefail

readonly namespace="${BWS_M4_NAMESPACE:-bws-m4}"
readonly gateway="${BWS_M4_GATEWAY:-bws-gateway}"
readonly host="${BWS_M4_HOST:-bws.example.com}"
readonly duration_seconds="${BWS_M4_LONGEVITY_SECONDS:-86400}"
readonly interval_seconds="${BWS_M4_LONGEVITY_INTERVAL_SECONDS:-5}"
readonly port="${BWS_M4_LONGEVITY_PORT:-58080}"
readonly report="${BWS_M4_LONGEVITY_REPORT:-bws-m4-longevity-report.txt}"
readonly selector="gateway.networking.k8s.io/gateway-name=${gateway}"

port_forward_pid=""

cleanup() {
    if [[ -n "${port_forward_pid}" ]]; then
        kill "${port_forward_pid}" >/dev/null 2>&1 || true
        wait "${port_forward_pid}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

for command in curl kubectl; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done
if ! [[ "${duration_seconds}" =~ ^[1-9][0-9]*$ && "${interval_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    echo "longevity duration and interval must be positive integers" >&2
    exit 1
fi

service="$(kubectl -n "${namespace}" get service -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
initial_pods="$(kubectl -n "${namespace}" get pods -l "${selector}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}')"
kubectl -n "${namespace}" port-forward "service/${service}" "${port}:80" >/dev/null 2>&1 &
port_forward_pid=$!

for ((attempt = 1; attempt <= 30; attempt++)); do
    if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
        -H "Host: ${host}" "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
        break
    fi
    if [[ "${attempt}" -eq 30 ]]; then
        echo "timed out waiting for the longevity port-forward" >&2
        exit 1
    fi
    sleep 1
done

start_epoch="$(date +%s)"
end_epoch="$((start_epoch + duration_seconds))"
successes=0
failures=0

while [[ "$(date +%s)" -lt "${end_epoch}" ]]; do
    if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
        -H "Host: ${host}" "http://127.0.0.1:${port}/" >/dev/null; then
        successes="$((successes + 1))"
    else
        failures="$((failures + 1))"
    fi
    sleep "${interval_seconds}"
done

final_pods="$(kubectl -n "${namespace}" get pods -l "${selector}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}')"
agent_connections="$(kubectl -n "${namespace}" logs -l "${selector}" -c bws --since="${duration_seconds}s" --prefix=true 2>/dev/null | \
    grep -c 'Connected to Command server' || true)"

{
    echo "BWS M4.4 longevity report"
    echo "started_epoch=${start_epoch}"
    echo "duration_seconds=${duration_seconds}"
    echo "interval_seconds=${interval_seconds}"
    echo "successes=${successes}"
    echo "failures=${failures}"
    echo "agent_connection_events=${agent_connections}"
    echo "initial_pods:"
    echo "${initial_pods}"
    echo "final_pods:"
    echo "${final_pods}"
} | tee "${report}"

if [[ "${failures}" -ne 0 ]]; then
    echo "M4.4 longevity verification failed with ${failures} request failures" >&2
    exit 1
fi

echo "M4.4 longevity verification passed"
