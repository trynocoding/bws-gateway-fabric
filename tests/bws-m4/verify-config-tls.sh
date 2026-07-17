#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly namespace="bws-m4"
readonly gateway="bws-gateway"
readonly route="cafe"
readonly host="bws.example.com"
readonly tls_secret="bws-m4-tls"
readonly temp_dir="$(mktemp -d)"

secret_rotated=false

restore_secret() {
    if [[ "${secret_rotated}" == "true" ]]; then
        kubectl -n "${namespace}" create secret tls "${tls_secret}" \
            --cert="${temp_dir}/original.crt" \
            --key="${temp_dir}/original.key" \
            --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true
    fi
}

restore() {
    kubectl -n "${namespace}" delete -f "${script_dir}/invalid-snippet.yaml" \
        --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "${namespace}" patch httproute "${route}" --type=json \
        -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/name","value":"coffee"}]' \
        >/dev/null 2>&1 || true
    restore_secret
    rm -rf "${temp_dir}"
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

http_routes_to_coffee() {
    curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 \
        --resolve "${host}:80:${service_ip}" \
        "http://${host}/" | grep -q 'Server name: coffee-'
}

https_routes_to_coffee() {
    curl -kfsS --noproxy '*' --connect-timeout 2 --max-time 5 \
        --resolve "${host}:443:${service_ip}" \
        "https://${host}/" | grep -q 'Server name: coffee-'
}

served_certificate_fingerprint() {
    openssl s_client -connect "${service_ip}:443" -servername "${host}" </dev/null 2>/dev/null | \
        openssl x509 -noout -fingerprint -sha256 | cut -d= -f2
}

new_certificate_is_served() {
    [[ "$(served_certificate_fingerprint)" == "${rotated_fingerprint}" ]]
}

original_certificate_is_served() {
    [[ "$(served_certificate_fingerprint)" == "${original_fingerprint}" ]]
}

rollback_logged_by_both_agents() {
    local count
    count="$(kubectl -n "${namespace}" logs \
        -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
        -c bws --since-time="${invalid_start}" --tail=-1 --prefix=true 2>/dev/null | \
        grep -c 'Config apply failed, rollback successful' || true)"
    [[ "${count}" -ge 2 ]]
}

dataplane_pod_uids() {
    kubectl -n "${namespace}" get pods \
        -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
        -o jsonpath='{range .items[*]}{.metadata.uid}{"\n"}{end}' | sort
}

service_ip="$(kubectl -n "${namespace}" get service \
    -l "gateway.networking.k8s.io/gateway-name=${gateway}" \
    -o jsonpath='{.items[0].spec.clusterIP}')"
if [[ -z "${service_ip}" ]]; then
    echo "BWS data-plane ClusterIP was not found" >&2
    exit 1
fi
initial_pod_uids="$(dataplane_pod_uids)"

kubectl -n "${namespace}" get secret "${tls_secret}" -o jsonpath='{.data.tls\.crt}' | \
    base64 -d >"${temp_dir}/original.crt"
kubectl -n "${namespace}" get secret "${tls_secret}" -o jsonpath='{.data.tls\.key}' | \
    base64 -d >"${temp_dir}/original.key"

retry "initial HTTP route" http_routes_to_coffee
retry "initial HTTPS route" https_routes_to_coffee
original_fingerprint="$(served_certificate_fingerprint)"

invalid_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
kubectl -n "${namespace}" apply -f "${script_dir}/invalid-snippet.yaml" >/dev/null
retry "both BWS Agents to reject and roll back invalid configuration" rollback_logged_by_both_agents
retry "last known-good route after invalid configuration" http_routes_to_coffee
kubectl -n "${namespace}" delete -f "${script_dir}/invalid-snippet.yaml" --ignore-not-found >/dev/null

openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
    -keyout "${temp_dir}/rotated.key" \
    -out "${temp_dir}/rotated.crt" \
    -days 1 \
    -subj "/CN=${host}" \
    -addext "subjectAltName=DNS:${host}" >/dev/null 2>&1
rotated_fingerprint="$(openssl x509 -in "${temp_dir}/rotated.crt" -noout -fingerprint -sha256 | cut -d= -f2)"

kubectl -n "${namespace}" create secret tls "${tls_secret}" \
    --cert="${temp_dir}/rotated.crt" \
    --key="${temp_dir}/rotated.key" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
secret_rotated=true
retry "rotated TLS certificate to be served without a Pod restart" new_certificate_is_served
retry "HTTPS route after certificate rotation" https_routes_to_coffee

restore_secret
secret_rotated=false
retry "original TLS certificate restoration" original_certificate_is_served
retry "HTTPS route after certificate restoration" https_routes_to_coffee
if [[ "$(dataplane_pod_uids)" != "${initial_pod_uids}" ]]; then
    echo "data-plane Pods changed during online TLS rotation" >&2
    exit 1
fi

echo "M4.3 configuration and TLS regression verification passed"
echo "validated: two-Agent invalid-config rollback, last-known-good traffic, online TLS rotation, and certificate restoration"
