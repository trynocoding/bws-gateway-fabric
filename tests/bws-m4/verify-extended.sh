#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly namespace="bws-m4"
readonly gateway="bws-gateway"
readonly host="bws.example.com"
readonly http_port="${BWS_M4_EXTENDED_HTTP_PORT:-38080}"
readonly https_port="${BWS_M4_EXTENDED_HTTPS_PORT:-38443}"
readonly metrics_port="${BWS_M4_EXTENDED_METRICS_PORT:-39113}"
readonly selector="gateway.networking.k8s.io/gateway-name=${gateway}"

service_port_forward_pid=""
metrics_port_forward_pid=""

cleanup() {
    kubectl -n "${namespace}" delete -f "${script_dir}/observability-snippet.yaml" \
        --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "${namespace}" delete -f "${script_dir}/websocket.yaml" \
        --ignore-not-found >/dev/null 2>&1 || true
    for pid in "${service_port_forward_pid}" "${metrics_port_forward_pid}"; do
        if [[ -n "${pid}" ]]; then
            kill "${pid}" >/dev/null 2>&1 || true
            wait "${pid}" >/dev/null 2>&1 || true
        fi
    done
}
trap cleanup EXIT

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

http2_works() {
    local version
    version="$(curl -ksS --noproxy '*' --http2 --connect-timeout 2 --max-time 5 \
        --resolve "${host}:${https_port}:127.0.0.1" \
        -o /dev/null -w '%{http_version}' "https://${host}:${https_port}/" 2>/dev/null)"
    [[ "${version}" == "2" ]]
}

metrics_available() {
    local output
    output="$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
        "http://127.0.0.1:${metrics_port}/metrics")"
    grep -q '^nginx_http_requests_total{' <<<"${output}"
}

access_log_contains_probe() {
    local output
    output="$(kubectl -n "${namespace}" logs -l "${selector}" -c bws \
        --since-time="${probe_start}" --prefix=true 2>/dev/null)"
    grep -q "${probe_path}" <<<"${output}"
}

access_log_configured() {
    kubectl -n "${namespace}" exec -c bws "${pod}" -- \
        grep -q 'log_format bws_m4' \
        /etc/bws/includes/SnippetsPolicy_http_bws-m4-bws-m4-access-log.conf
}

websocket_works() {
    python3 - "${http_port}" "${host}" 2>/dev/null <<'PY'
import base64
import os
import socket
import sys

port = int(sys.argv[1])
host = sys.argv[2]
key = base64.b64encode(os.urandom(16)).decode()
sock = socket.create_connection(("127.0.0.1", port), timeout=5)
sock.sendall(
    (
        "GET /ws HTTP/1.1\r\n"
        f"Host: {host}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    ).encode()
)
response = b""
while b"\r\n\r\n" not in response:
    response += sock.recv(4096)
if not response.startswith(b"HTTP/1.1 101"):
    raise RuntimeError(response.decode(errors="replace"))

payload = b"bws-m4-websocket"
mask = os.urandom(4)
masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
sock.sendall(bytes((0x81, 0x80 | len(payload))) + mask + masked)
header = sock.recv(2)
if len(header) != 2 or header[0] != 0x81:
    raise RuntimeError("invalid WebSocket response frame")
length = header[1] & 0x7F
echo = b""
while len(echo) < length:
    echo += sock.recv(length - len(echo))
if echo != payload:
    raise RuntimeError(f"unexpected echo: {echo!r}")
sock.close()
PY
}

for command in curl kubectl python3; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "required command not found: ${command}" >&2
        exit 1
    fi
done
if ! curl --version | grep -q 'Features:.*HTTP2'; then
    echo "curl was built without HTTP/2 support" >&2
    exit 1
fi

dataplane_deployment="$(kubectl -n "${namespace}" get deployment \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
service="$(kubectl -n "${namespace}" get service \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
pod="$(kubectl -n "${namespace}" get pod \
    -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${dataplane_deployment}" || -z "${service}" || -z "${pod}" ]]; then
    echo "could not resolve the M4.4 data-plane resources" >&2
    exit 1
fi

kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m

# Validate the generated NJS and WebSocket proxy configuration with the real BWS binary.
kubectl -n "${namespace}" exec -c bws "${pod}" -- bash -c '
	grep -q "js_import modules/njs/httpmatches.js" /etc/bws/bws.conf
    grep -q "map \$http_upgrade \$connection_upgrade" /etc/bws/conf.d/http.conf
    grep -q "proxy_set_header Upgrade" /etc/bws/conf.d/http.conf
	/opt/bws/bin/bws.sh -p /opt/bws -c /etc/bws/bws.conf -t
' >/dev/null

kubectl -n "${namespace}" apply -f "${script_dir}/observability-snippet.yaml" >/dev/null
kubectl -n "${namespace}" apply -f "${script_dir}/websocket.yaml" >/dev/null
kubectl -n "${namespace}" rollout status deployment/bws-m4-websocket --timeout=3m
kubectl -n "${namespace}" rollout status "deployment/${dataplane_deployment}" --timeout=5m
retry "access-log configuration on the BWS data plane" \
    access_log_configured

kubectl -n "${namespace}" port-forward "service/${service}" \
    "${http_port}:80" "${https_port}:443" >/dev/null 2>&1 &
service_port_forward_pid=$!

kubectl -n "${namespace}" port-forward "pod/${pod}" \
    "${metrics_port}:9113" >/dev/null 2>&1 &
metrics_port_forward_pid=$!

retry "HTTP/2 negotiation over the TLS listener" http2_works
retry "live WebSocket upgrade and bidirectional echo" websocket_works
retry "BWS metrics derived from stub_status" metrics_available

metrics="$(curl -fsS --noproxy '*' "http://127.0.0.1:${metrics_port}/metrics")"
for metric in nginx_http_connections_total nginx_http_requests_total system_cpu_utilization_ratio system_memory_usage_bytes; do
    if ! grep -q "^${metric}{" <<<"${metrics}"; then
        echo "expected Prometheus metric was not exposed: ${metric}" >&2
        exit 1
    fi
done

probe_path="/bws-m4-log-probe-$(date +%s)"
probe_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
    --resolve "${host}:${http_port}:127.0.0.1" \
    "http://${host}:${http_port}${probe_path}" >/dev/null
retry "BWS access log collection through kubectl logs" access_log_contains_probe

error_logs="$(kubectl -n "${namespace}" logs "${pod}" -c bws)"
if ! grep -q '\[notice\].*start worker process' <<<"${error_logs}"; then
    echo "BWS error-log notices were not present in the container log stream" >&2
    exit 1
fi

echo "M4.4 extended verification passed"
echo "validated: BWS config test, NJS load, WebSocket exchange, HTTP/2, stub_status-derived Prometheus metrics, access/error log collection"
echo "not validated by this script: gRPC, HTTP/3, stream, HPA, license scenarios, node restart, conformance, or longevity"
