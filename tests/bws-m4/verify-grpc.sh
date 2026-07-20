#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly tests_dir="$(cd "${script_dir}/.." && pwd)"
readonly namespace="bws-m4"
readonly gateway="bws-gateway"
readonly port="${BWS_M4_GRPC_PORT:-48080}"
readonly selector="gateway.networking.k8s.io/gateway-name=${gateway}"

port_forward_pid=""

cleanup() {
    kubectl -n "${namespace}" delete -f "${script_dir}/grpc.yaml" --ignore-not-found >/dev/null 2>&1 || true
    if [[ -n "${port_forward_pid}" ]]; then
        kill "${port_forward_pid}" >/dev/null 2>&1 || true
        wait "${port_forward_pid}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

for command in go kubectl; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

kubectl -n "${namespace}" apply -f "${script_dir}/grpc.yaml" >/dev/null
kubectl -n "${namespace}" rollout status deployment/bws-m4-grpc --timeout=3m
for ((attempt = 1; attempt <= 60; attempt++)); do
    route_status="$(kubectl -n "${namespace}" get grpcroute bws-m4-grpc \
        -o jsonpath='{range .status.parents[*].conditions[?(@.type=="Accepted")]}{.status}{end}')"
    if [[ "${route_status}" == *True* ]]; then
        break
    fi
    if [[ "${attempt}" -eq 60 ]]; then
        echo "timed out waiting for the GRPCRoute Accepted parent condition" >&2
        exit 1
    fi
    sleep 2
done

dataplane_deployment="$(kubectl -n "${namespace}" get deployment \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
service="$(kubectl -n "${namespace}" get service \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
pod="$(kubectl -n "${namespace}" get pod \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m

kubectl -n "${namespace}" exec "${pod}" -c bws -- sh -c '
    grep -Rqs "grpc_pass grpc://" /etc/bws/conf.d
    /opt/bws/bin/bws.sh -p /opt/bws -c /etc/bws/bws.conf -t
' >/dev/null

kubectl -n "${namespace}" port-forward "service/${service}" "${port}:80" >/dev/null 2>&1 &
port_forward_pid=$!

for ((attempt = 1; attempt <= 30; attempt++)); do
    if (cd "${tests_dir}" && go run ./bws-m4/grpc-client "127.0.0.1:${port}" bws.example.com); then
        echo "M4.4 gRPC verification passed"
        echo "validated: GRPCRoute acceptance, generated grpc_pass configuration, real BWS config test, and unary gRPC request"
        exit 0
    fi
    sleep 2
done

echo "timed out waiting for a successful gRPC request" >&2
exit 1
