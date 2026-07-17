#!/usr/bin/env bash

set -euo pipefail

readonly scanner_image="${TRIVY_IMAGE:-aquasec/trivy:0.72.0}"
readonly db_repository="${TRIVY_DB_REPOSITORY:-ghcr.io/aquasecurity/trivy-db:2}"
readonly control_image="${BWS_CONTROL_IMAGE:-bws-gateway-fabric:m4-local}"
readonly data_image="${BWS_DATA_IMAGE:-bws-gateway-fabric/bws:m4-local}"
readonly cache_dir="$(mktemp -d)"

cleanup() {
    rm -rf "${cache_dir}"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
    echo "required command not found: docker" >&2
    exit 1
fi

for image in "${control_image}" "${data_image}"; do
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "${cache_dir}:/root/.cache/trivy" \
        "${scanner_image}" image \
        --db-repository "${db_repository}" \
        --scanners vuln \
        --severity HIGH,CRITICAL \
        --ignore-unfixed \
        --exit-code 1 \
        "${image}"
done

echo "M4.4 image security verification passed"
echo "validated: no fixed HIGH or CRITICAL OS/library vulnerabilities reported for either release image"
