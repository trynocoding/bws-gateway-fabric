#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly namespace="bws-m4"
readonly control_namespace="bws-m4-system"
readonly gateway="bws-gateway"
readonly expected_context="kind-${BWS_M4_KIND_CLUSTER:-bws-m4-isolated}"
readonly selector="gateway.networking.k8s.io/gateway-name=${gateway}"
readonly traffic_pod="bws-m4-node-traffic"

target_worker=""
hpa=""
proxy_name=""
proxy_namespace=""
surviving_worker=""

cleanup() {
    if [[ -n "${target_worker}" ]]; then
        kubectl uncordon "${target_worker}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${surviving_worker}" ]]; then
        kubectl uncordon "${surviving_worker}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${proxy_name}" && -n "${proxy_namespace}" ]]; then
        kubectl -n "${proxy_namespace}" patch bwsproxy "${proxy_name}" --type=merge \
            -p='{"spec":{"kubernetes":{"deployment":{"autoscaling":{"maxReplicas":4}}}}}' \
            >/dev/null 2>&1 || true
    fi
    kubectl -n "${namespace}" delete -f "${script_dir}/node-recovery-traffic.yaml" \
        --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "${namespace}" delete -f "${script_dir}/node-recovery-backend.yaml" \
        --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

for command in docker kubectl; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

if [[ "$(kubectl config current-context)" != "${expected_context}" ]]; then
    echo "refusing to run outside isolated context ${expected_context}" >&2
    exit 1
fi

deployment="$(kubectl -n "${namespace}" get deployment -l "${selector}" \
    -o jsonpath='{.items[0].metadata.name}')"
hpa="$(kubectl -n "${namespace}" get hpa -l "${selector}" \
    -o jsonpath='{.items[0].metadata.name}')"
proxy_namespace="$(kubectl get bwsproxy -A -l app.kubernetes.io/instance=bws-m4 \
    -o jsonpath='{.items[0].metadata.namespace}')"
proxy_name="$(kubectl get bwsproxy -A -l app.kubernetes.io/instance=bws-m4 \
    -o jsonpath='{.items[0].metadata.name}')"
workload_image="$(kubectl -n "${namespace}" get deployment coffee \
    -o jsonpath='{.spec.template.spec.containers[0].image}')"
control_deployment="$(kubectl -n "${control_namespace}" get deployment \
    -l app.kubernetes.io/instance=bws-m4 -o jsonpath='{.items[0].metadata.name}')"

kubectl -n "${proxy_namespace}" patch bwsproxy "${proxy_name}" --type=merge \
    -p='{"spec":{"kubernetes":{"deployment":{"autoscaling":{"maxReplicas":2}}}}}' >/dev/null
for ((attempt = 1; attempt <= 90; attempt++)); do
    current_replicas="$(kubectl -n "${namespace}" get deployment "${deployment}" \
        -o jsonpath='{.status.readyReplicas}')"
    desired_replicas="$(kubectl -n "${namespace}" get deployment "${deployment}" \
        -o jsonpath='{.spec.replicas}')"
    hpa_max_replicas="$(kubectl -n "${namespace}" get hpa "${hpa}" -o jsonpath='{.spec.maxReplicas}')"
    if [[ "${current_replicas}" == "2" && "${desired_replicas}" == "2" && \
        "${hpa_max_replicas}" == "2" ]]; then
        break
    fi
    if [[ "${attempt}" -eq 90 ]]; then
        echo "BWS data plane did not settle at two replicas before node recovery" >&2
        exit 1
    fi
    sleep 5
done

kubectl -n "${namespace}" rollout status deployment/coffee --timeout=3m
kubectl -n "${namespace}" apply -f "${script_dir}/node-recovery-backend.yaml" >/dev/null
kubectl -n "${namespace}" set image deployment/coffee-recovery "coffee=${workload_image}" >/dev/null
kubectl -n "${namespace}" rollout status deployment/coffee-recovery --timeout=3m
kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=8m

coffee_worker_count="$(kubectl -n "${namespace}" get pods -l app=coffee \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.spec.nodeName}}{{"\n"}}{{end}}{{end}}' |
    sort -u | wc -l)"
if [[ "${coffee_worker_count}" -ne 2 ]]; then
    echo "coffee backends must be distributed across both workers" >&2
    exit 1
fi

mapfile -t initial_workers < <(kubectl -n "${namespace}" get pods -l "${selector}" \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.spec.nodeName}}{{"\n"}}{{end}}{{end}}' |
    sort -u)
if [[ "${#initial_workers[@]}" -eq 1 ]]; then
    occupied_worker="${initial_workers[0]}"
    mapfile -t worker_nodes < <(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
        -o go-template='{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | sort)
    empty_worker=""
    for worker_node in "${worker_nodes[@]}"; do
        if [[ "${worker_node}" != "${occupied_worker}" ]]; then
            empty_worker="${worker_node}"
            break
        fi
    done
    if [[ -z "${empty_worker}" ]]; then
        echo "could not find an empty worker for BWS baseline redistribution" >&2
        exit 1
    fi
    surviving_worker="${occupied_worker}"
    kubectl cordon "${occupied_worker}" >/dev/null
    mapfile -t occupied_pods < <(kubectl -n "${namespace}" get pods -l "${selector}" \
        --field-selector "spec.nodeName=${occupied_worker}" \
        -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}')
    kubectl -n "${namespace}" delete pod "${occupied_pods[0]}" --wait=false >/dev/null
    kubectl -n "${namespace}" wait --for=delete "pod/${occupied_pods[0]}" --timeout=2m
    kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=8m
    kubectl uncordon "${occupied_worker}" >/dev/null
    surviving_worker=""
    mapfile -t initial_workers < <(kubectl -n "${namespace}" get pods -l "${selector}" \
        -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.spec.nodeName}}{{"\n"}}{{end}}{{end}}' |
        sort -u)
fi
if [[ "${#initial_workers[@]}" -ne 2 ]]; then
    echo "BWS replicas must start on two separate workers" >&2
    exit 1
fi
target_worker="${initial_workers[0]}"
surviving_worker="${initial_workers[1]}"
log_since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

kubectl -n "${namespace}" apply -f "${script_dir}/node-recovery-traffic.yaml" >/dev/null
kubectl -n "${namespace}" wait --for=condition=Ready "pod/${traffic_pod}" --timeout=2m

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) starting worker-failure traffic phase"
kubectl cordon "${target_worker}" >/dev/null
kubectl drain "${target_worker}" --ignore-daemonsets --delete-emptydir-data --force \
    --grace-period=30 --timeout=5m >/dev/null
kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=8m

if kubectl -n "${namespace}" get pods -l "${selector}" \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.spec.nodeName}}{{"\n"}}{{end}}{{end}}' |
    grep -Fxq "${target_worker}"; then
    echo "a BWS replica remained on the drained worker" >&2
    exit 1
fi

docker restart "${target_worker}" >/dev/null
kubectl wait --for=condition=Ready "node/${target_worker}" --timeout=5m

# End the continuity measurement before the deliberate post-recovery Pod
# redistribution. This keeps planned maintenance separate from the worker
# failure window while still exercising drain, replacement, and node restart.
kubectl -n "${namespace}" exec "${traffic_pod}" -- rm -f /tmp/run
for ((attempt = 1; attempt <= 30; attempt++)); do
    if kubectl -n "${namespace}" exec "${traffic_pod}" -- test -s /tmp/result; then
        break
    fi
    if [[ "${attempt}" -eq 30 ]]; then
        echo "traffic probe did not write its result" >&2
        exit 1
    fi
    sleep 1
done
read -r successes failures < <(kubectl -n "${namespace}" exec "${traffic_pod}" -- cat /tmp/result)
if [[ "${successes}" -eq 0 || "${failures}" -ne 0 ]]; then
    echo "worker-failure traffic had ${successes} successes and ${failures} failures" >&2
    kubectl -n "${namespace}" exec "${traffic_pod}" -- sh -c \
        'test ! -s /tmp/failures || cat /tmp/failures' >&2
    exit 1
fi
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) worker-failure traffic phase passed: ${successes} requests, zero failures"

# Redistribute one replica only after the failed worker is Ready again. The
# continuity requirement above has already been measured; this phase validates
# scheduling recovery, Agent reconnection, and a fresh end-to-end request.
kubectl uncordon "${target_worker}" >/dev/null
kubectl cordon "${surviving_worker}" >/dev/null
mapfile -t surviving_pods < <(kubectl -n "${namespace}" get pods -l "${selector}" \
    --field-selector "spec.nodeName=${surviving_worker}" \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}')
replacement_pod="${surviving_pods[0]:-}"
if [[ -z "${replacement_pod}" ]]; then
    echo "could not find a BWS Pod to relocate from the surviving worker" >&2
    exit 1
fi
kubectl -n "${namespace}" delete pod "${replacement_pod}" --wait=false >/dev/null
kubectl -n "${namespace}" wait --for=delete "pod/${replacement_pod}" --timeout=2m
kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=8m
kubectl uncordon "${surviving_worker}" >/dev/null

mapfile -t recovered_workers < <(kubectl -n "${namespace}" get pods -l "${selector}" \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.spec.nodeName}}{{"\n"}}{{end}}{{end}}' |
    sort -u)
if [[ "${#recovered_workers[@]}" -ne 2 ]] || \
    [[ ! " ${recovered_workers[*]} " =~ ${target_worker} ]] || \
    [[ ! " ${recovered_workers[*]} " =~ ${surviving_worker} ]]; then
    echo "BWS replicas were not redistributed across both workers" >&2
    exit 1
fi

for ((attempt = 1; attempt <= 30; attempt++)); do
    connection_count="$(kubectl -n "${control_namespace}" logs "deployment/${control_deployment}" \
        --since-time="${log_since}" | grep -c 'Successfully connected to BWS Agent' || true)"
    if [[ "${connection_count}" -ge 2 ]]; then
        break
    fi
    if [[ "${attempt}" -eq 30 ]]; then
        echo "did not observe both BWS Agents reconnecting after worker recovery" >&2
        exit 1
    fi
    sleep 2
done

if ! kubectl -n "${namespace}" exec "${traffic_pod}" -- sh -c \
    "curl -fsS --connect-timeout 1 --max-time 5 -H 'Host: bws.example.com' http://bws-gateway-bws.bws-m4.svc/ | grep -q 'Server name: coffee-'"; then
    echo "post-recovery end-to-end request failed" >&2
    exit 1
fi

echo "M4.4 isolated worker recovery verification passed"
echo "validated: cordon, drain, worker restart, ${successes} requests with zero failures, BWS Pod relocation, two-Agent reconnect, cross-worker redistribution, and post-recovery traffic"
