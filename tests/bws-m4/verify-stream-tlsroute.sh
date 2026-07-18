#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly namespace="bws-m4"
readonly gateway="bws-gateway"
readonly route="bws-m4-tls-passthrough"
readonly host="passthrough.bws.example.com"
readonly port="${BWS_M4_TLS_PASSTHROUGH_PORT:-28444}"
readonly expected_context="kind-${BWS_M4_KIND_CLUSTER:-bws-m4-isolated}"
readonly selector="gateway.networking.k8s.io/gateway-name=${gateway}"

port_forward_pid=""

cleanup() {
    kubectl -n "${namespace}" delete -f "${script_dir}/stream-tlsroute.yaml" \
        --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "${namespace}" delete secret bws-m4-tls-backend \
        --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "${namespace}" apply -f "${script_dir}/gateway.yaml" >/dev/null 2>&1 || true
    if [[ -n "${port_forward_pid}" ]]; then
        kill "${port_forward_pid}" >/dev/null 2>&1 || true
        wait "${port_forward_pid}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

for command in curl kubectl openssl; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done

if [[ "$(kubectl config current-context)" != "${expected_context}" ]]; then
    echo "refusing to run outside isolated context ${expected_context}" >&2
    exit 1
fi

tls_dir="$(mktemp -d)"
trap 'rm -rf "${tls_dir}"; cleanup' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj "/CN=${host}" \
    -addext "subjectAltName=DNS:${host}" \
    -keyout "${tls_dir}/tls.key" \
    -out "${tls_dir}/tls.crt" >/dev/null 2>&1

kubectl -n "${namespace}" create secret tls bws-m4-tls-backend \
    --cert="${tls_dir}/tls.crt" \
    --key="${tls_dir}/tls.key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "${namespace}" apply -f "${script_dir}/stream-tlsroute.yaml" >/dev/null
kubectl -n "${namespace}" rollout status deployment/bws-m4-tls-backend --timeout=3m

kubectl -n "${namespace}" patch gateway "${gateway}" --type=json -p='[
  {
    "op": "add",
    "path": "/spec/listeners/-",
    "value": {
      "name": "tls-passthrough",
      "port": 8443,
      "protocol": "TLS",
      "hostname": "passthrough.bws.example.com",
      "tls": {"mode": "Passthrough"},
      "allowedRoutes": {
        "kinds": [{"group": "gateway.networking.k8s.io", "kind": "TLSRoute"}]
      }
    }
  }
]' >/dev/null

for ((attempt = 1; attempt <= 60; attempt++)); do
    route_status="$(kubectl -n "${namespace}" get tlsroute "${route}" \
        -o jsonpath='{range .status.parents[*].conditions[?(@.type=="Accepted")]}{.status}{end}')"
    resolved_refs="$(kubectl -n "${namespace}" get tlsroute "${route}" \
        -o jsonpath='{range .status.parents[*].conditions[?(@.type=="ResolvedRefs")]}{.status}{end}')"
    if [[ "${route_status}" == *True* && "${resolved_refs}" == *True* ]]; then
        break
    fi
    if [[ "${attempt}" -eq 60 ]]; then
        echo "timed out waiting for TLSRoute Accepted and ResolvedRefs conditions" >&2
        kubectl -n "${namespace}" get tlsroute "${route}" -o yaml >&2
        exit 1
    fi
    sleep 2
done

dataplane_deployment="$(kubectl -n "${namespace}" get deployment \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
service="$(kubectl -n "${namespace}" get service \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m

service_protocol="$(kubectl -n "${namespace}" get service "${service}" \
    -o jsonpath='{.spec.ports[?(@.port==8443)].protocol}')"
if [[ "${service_protocol}" != "TCP" ]]; then
    echo "Gateway Service does not expose TCP port 8443" >&2
    exit 1
fi

mapfile -t pods < <(kubectl -n "${namespace}" get pods -l "${selector}" \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}')
if [[ "${#pods[@]}" -ne 2 ]]; then
    echo "expected two BWS data-plane pods" >&2
    exit 1
fi
for pod in "${pods[@]}"; do
    kubectl -n "${namespace}" exec "${pod}" -c bws -- sh -c '
        grep -q "ssl_preread on;" /etc/bws/stream-conf.d/stream.conf
        grep -q "listen 8443;" /etc/bws/stream-conf.d/stream.conf
        grep -q "proxy_pass" /etc/bws/stream-conf.d/stream.conf
        /opt/bws/bin/bws.sh -p /opt/bws -c /etc/bws/nginx.conf -t
    ' >/dev/null
done

kubectl -n "${namespace}" port-forward "service/${service}" "${port}:8443" >/dev/null 2>&1 &
port_forward_pid=$!

for ((attempt = 1; attempt <= 30; attempt++)); do
    response=""
    if response="$(curl -ksS --noproxy '*' --connect-timeout 2 --max-time 5 \
        --resolve "${host}:${port}:127.0.0.1" "https://${host}:${port}/")" && \
        grep -q "s_server" <<<"${response}"; then
        certificate_subject="$(openssl s_client \
            -connect "127.0.0.1:${port}" -servername "${host}" </dev/null 2>/dev/null |
            openssl x509 -noout -subject)"
        if [[ "${certificate_subject}" != *"CN = ${host}"* && \
            "${certificate_subject}" != *"CN=${host}"* ]]; then
            echo "TLS passthrough returned an unexpected backend certificate" >&2
            exit 1
        fi
        echo "M4.4 stream/TLSRoute verification passed"
        echo "validated: isolated context, TLSRoute status, TCP Service port, generated stream config, real bws -t, and end-to-end TLS passthrough"
        exit 0
    fi
    sleep 2
done

echo "timed out waiting for end-to-end TLS passthrough" >&2
exit 1
