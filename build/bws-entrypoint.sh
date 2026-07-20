#!/usr/bin/env bash

set -euo pipefail

readonly bws_launcher="${BWS_LAUNCHER:-/opt/bws/bin/bws.sh}"
readonly bws_prefix="${BWS_PREFIX:-/opt/bws}"
readonly bws_config="${BWS_CONFIG:-/etc/bws/bws.conf}"
readonly bws_license="${BWS_LICENSE_FILE:-/var/run/secrets/bws/bws.lic.txt}"
readonly bws_runtime_license="${BWS_RUNTIME_LICENSE_FILE:-${bws_prefix}/license/bws.lic.txt}"
readonly bws_pid_file="${BWS_PID_FILE:-/var/run/bws/bws.pid}"

bws_pid=""
agent_pid=""

stop_process() {
    local signal="$1"
    local pid="$2"
    local name="$3"

    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        echo "stopping ${name} with ${signal} ..."
        kill "-${signal}" "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
    fi
}

handle_signal() {
    local signal="$1"

    trap - TERM QUIT INT
    stop_process "${signal}" "${agent_pid}" "bws-agent"
    stop_process "${signal}" "${bws_pid}" "BWS"
    exit 0
}

trap 'handle_signal TERM' TERM
trap 'handle_signal QUIT' QUIT
trap 'handle_signal INT' INT

if [[ ! -s "${bws_license}" ]]; then
    echo "BWS license is missing or empty: ${bws_license}" >&2
    exit 1
fi

mkdir -p \
    /var/cache/bws/ajp_temp \
    /var/cache/bws/license \
    /var/cache/bws/logs \
    /var/cache/bws/temp/client_body_temp \
    /var/cache/bws/temp/fastcgi_temp \
    /var/cache/bws/temp/proxy_temp \
    /var/cache/bws/temp/scgi_temp \
    /var/cache/bws/temp/uwsgi_temp
touch /var/cache/bws/logs/access.log /var/cache/bws/logs/error.log
cp "${bws_license}" "${bws_runtime_license}"
chmod 0600 "${bws_runtime_license}"

for socket in /var/run/bws/*.sock; do
    if [[ -S "${socket}" ]]; then
        unlink "${socket}"
    fi
done

echo "starting BWS ..."
"${bws_launcher}" \
    -p "${bws_prefix}" \
    -c "${bws_config}" \
    -g "daemon off;" &
bws_pid=$!

for ((attempt = 1; attempt <= 30; attempt++)); do
    if [[ -s "${bws_pid_file}" ]]; then
        break
    fi
    if ! kill -0 "${bws_pid}" 2>/dev/null; then
        wait "${bws_pid}"
        exit $?
    fi
    sleep 1
done

if [[ ! -s "${bws_pid_file}" ]]; then
    echo "BWS master PID file was not created: ${bws_pid_file}" >&2
    stop_process QUIT "${bws_pid}" "BWS"
    exit 1
fi

if [[ "${BWS_AGENT_DISABLED:-false}" == "true" ]]; then
    echo "BWS Agent is disabled"
    wait "${bws_pid}"
    exit $?
fi

echo "starting BWS Agent ..."
bws-agent "$@" &
agent_pid=$!

set +e
wait -n "${bws_pid}" "${agent_pid}"
exit_status=$?
set -e

trap - TERM QUIT INT
stop_process QUIT "${agent_pid}" "bws-agent"
stop_process QUIT "${bws_pid}" "BWS"

exit "${exit_status}"
