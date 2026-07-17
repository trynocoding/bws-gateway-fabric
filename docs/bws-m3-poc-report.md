# BWS M3 Kubernetes PoC report

Date: 2026-07-17

## Result

The first M3 cluster pass succeeded with the unchanged NGF v2.6.7 APIs and Helm top-level fields. The PoC used a
dedicated `bws-poc` GatewayClass, `bws-m3-system` control-plane namespace, and `bws-m3` workload namespace. It did not
modify the pre-existing `nginx` GatewayClass or `nginx-gateway` workloads.

The final data plane had two ready replicas of `bws-gateway-fabric/bws:m3-local`. Both ran as UID 101 with a read-only
root filesystem and a read-only license Secret mounted at `/var/run/secrets/bws`. The BWS wrapper reported
`BES WebServer 3.2.0.242`, and the configured `/readyz` endpoint passed.

## Verified behavior

| Area | Result | Evidence |
|---|---|---|
| Agent connection | Pass | Both Agents established mTLS connections to the NGF v2.6.7 control plane. |
| Initial configuration | Pass | Agent ran the real BWS configuration test, filtered only the known license alert, and reloaded BWS. |
| HTTP and HTTPS | Pass | `HTTPRoute` traffic reached the coffee backend on ports 80 and 443 with hostname/SNI matching. |
| HTTP/2 | Pass | curl negotiated HTTP/2 over TLS and received the routed backend response. |
| Incremental update | Pass | The route changed from coffee to tea and back without replacing the data-plane Deployment. |
| Invalid configuration | Pass | BWS rejected an invalid `gzip` value; Agent rolled back and reported `rollback successful`; traffic stayed available. |
| Certificate update | Pass | The TLS Secret was regenerated during Helm revision 2 and HTTPS passed afterward. |
| Replicas and restart | Pass | Two replicas were ready; one Pod was deleted and replaced while NodePort traffic remained available. |
| Control-plane restart | Pass | The control Pod was replaced, both Agents reconnected, and traffic remained available. |
| Rolling restart | Pass | Forty consecutive requests passed during a two-replica data-plane rolling restart. |
| NJS and WebSocket | Pass | The real `bws -t` accepted the loaded NGF NJS modules and generated upgrade headers; a live upgrade and bidirectional text-frame echo passed through BWS. |
| Prometheus metrics | Pass | Agent port 9113 exposed stub_status-derived NGINX connection/request metrics and container CPU/memory metrics. |
| Container logs | Pass | A temporary `SnippetsPolicy` sent access logs to stdout; the unique request marker and BWS error-log notices were visible through `kubectl logs`. |

The repeatable assets are in `tests/bws-m3/`. Run `deploy.sh`, `verify.sh`, `verify-resilience.sh`, and
`verify-extended.sh` in that order. The extended verifier removes its temporary access-log policy on exit.
The exact pre-M4 source, image, archive, CRD, and cluster inputs are frozen in [`bws-m3-baseline.md`](bws-m3-baseline.md).

Static validation passed with `bash -n`, `helm lint`, Helm rendering for Kubernetes 1.31.9, and `git diff --check`.
The BWS-focused Agent tests and the process, watcher, and NGINX packages passed without cache. The upstream
`TestResolveConfig` test remains environment-sensitive in this container: both the unmodified reference tree and the
BWS tree add `container_metrics` when `/run/.containerenv` is present, while the fixture expects host-only receivers.

## Open gates

- The cluster has no Metrics API (`kubectl top nodes` returns `Metrics API not available`), so HPA behavior is blocked.
- The cluster started with NGF v2.6.5 CRDs. Helm does not upgrade existing CRDs; the PoC values therefore use fields
  shared by v2.6.5 and v2.6.7. A production v2.6.7 rollout must upgrade CRDs explicitly.
- A Secret directory mount can receive updated bytes, but the current entrypoint copies the license only at startup.
  True online license rotation needs a second valid license, runtime copy/derived-file handling, BWS reload, and
  uninterrupted traffic evidence.
- Node restart, multi-node placement, license failure states, HTTP/3, gRPC, stream, cluster-level metrics/log scraping,
  Gateway API conformance, and the 24-hour stability gate remain unverified.
