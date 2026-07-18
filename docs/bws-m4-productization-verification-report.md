# BWS M4.4 productization verification report

Status: the currently executable native-capability regression batch is complete, updated on 2026-07-18. This report
records the M4.4 isolated stream/TLSRoute, HPA, worker-recovery, and Gateway API conformance regressions. HTTP/3 is
outside the native NGF v2.6.7 capability boundary. The 24-hour, image-security, and complete license matrix gates are
deferred by the current priority decision and are not marked as passed.

## Verified build and environment

- Kubernetes `v1.31.9`, one node (`cool`), containerd `2.2.5`.
- Isolated regression cluster: Kind with Kubernetes `v1.35.1`, one control-plane and two workers. The two BWS data-plane
  replicas ran on separate workers. Gateway API `v1.5.1` experimental CRDs and Metrics Server `v0.8.1` were installed;
  `metrics.k8s.io` and `kubectl top` were available.
- Control plane: `bws-gateway-fabric:m4-local`, image ID and local digest
  `sha256:05f9abc0a61b43f00d74b7d71a9721ab0f28fee1b2f073356ff4b14a2898ce88`.
- Data plane: `bws-gateway-fabric/bws:m4-local`, image ID and local digest
  `sha256:390fbe2e45db2a741618b7d7954e9e0a68c4a54ef75142e7ee874200a10f2dd5`.
- Live container config IDs were `sha256:fa1610a...` for the control plane and `sha256:23e70b7a...` for both data-plane
  replicas after Helm revision 2 and a forced data-plane rollout.
- BWS reports `BES WebServer 3.2.0.242`. Its configure arguments include HTTP/2, HTTP/3, stream, stream TLS,
  stream TLS preread, stub_status, NJS, and the packaged BWS modules.

## Passed release checks

| Area | Result | Evidence |
|---|---|---|
| HTTP/HTTPS and incremental update | Passed | `verify.sh` |
| Invalid config rollback and TLS rotation | Passed | `verify-config-tls.sh` |
| HTTP/2, WebSocket, NJS, metrics, logs | Passed | `verify-extended.sh` |
| gRPC | Passed | `verify-grpc.sh`: Accepted GRPCRoute, generated `grpc_pass`, real `bws -t`, unary RPC |
| Stream/TLSRoute | Passed | `verify-stream-tlsroute.sh`: Accepted/ResolvedRefs, TCP 8443 Service, generated `ssl_preread` and `proxy_pass`, real `bws -t` in both replicas, backend certificate and TLS response |
| HPA | Passed | `verify-hpa.sh`: CPU load scaled the data plane from 2 to 4 replicas, completed 30,177 requests with zero failures, and returned to 2 replicas after load stopped |
| Worker recovery | Passed | `verify-node-recovery.sh`: cordon/drain, replacement on the surviving worker, worker restart, 245 requests with zero failures, post-recovery cross-worker redistribution, two-Agent reconnect, and end-to-end smoke |
| Gateway API conformance | Passed | Gateway API `v1.5.1` experimental channel: HTTP 33 core + 47 extended, gRPC 13 core + 10 extended, TLS 18 core + 11 extended; 132 passed, zero failed |
| Pod/control-plane recovery | Passed | `verify-resilience.sh`: 305 requests, zero failures, Pod replacement, control-plane restart, two-Agent reconnect, rolling restart |
| Helm/CRD/API contract | Passed | `verify-contract.sh` |
| Product identity | Passed | `audit-product-identity.sh` |
| Missing license | Passed negative case | Image exited 1 with `BWS license is missing or empty` |
| Generated/static checks | Passed | `make generate-all`, Helm lint, diff check, shell syntax/shellcheck, focused Go and CEL tests |

The identity audit found no unclassified old product identity. It classified 65 aggregate `nginx`/`ngf` line matches
across rendered and image evidence; the Helm/CRD/RBAC rendering contained 56. These are nginx directive and context
names, `nginx.org` documentation, `nginx_*` metric contracts, `nginx.conf`, internal upstream Go/source paths, and the
retained `/usr/share/nginx` static-resource path. Old API groups/kinds, product labels, image repositories, runtime
directories, user-visible NGF branding, `product-type=ngf`, `nginx-debug`, NGINX Plus OIDC/JWT, and WAF APIs are rejected.

## Support and release-gate matrix

| Capability | Current state | Release disposition |
|---|---|---|
| HTTP/1.1, HTTPS/TLS, HTTP/2 | Supported and verified | Pass |
| WebSocket | Supported and verified | Pass |
| GRPCRoute / gRPC | Supported and verified | Pass |
| Prometheus and container metrics | Supported and verified | Pass |
| Access/error log collection | Supported and verified | Pass |
| HTTP/3 | BWS binary has `--with-http_v3_module`, but native NGF v2.6.7 has no QUIC generation or UDP Service port | Not supported; out of scope because the BWS fork does not extend native NGF capabilities |
| Stream/TLSRoute | Supported and verified in a three-node isolated cluster | Pass |
| HPA | Metrics API and CPU-driven 2 -> 4 -> 2 scaling verified with zero request failures | Pass |
| Node restart | Worker cordon/drain/restart verified with zero failures during the failure window; redistribution and Agent reconnect passed | Pass |
| License states | Valid and missing cases verified | Expired, near-expiry, second valid license, and online replacement are deferred and remain unpassed |
| Gateway API conformance | HTTP, GRPC, and TLS core and declared extended profiles passed; 132 tests passed and zero failed | Pass |
| 24-hour stability | Script smoke passed for 6 seconds with zero failures | Deferred because the company machine powers off overnight; not a 24-hour pass |
| Image vulnerability scan | Trivy image pulled | Deferred; both default and GHCR DB sources were too slow and no vulnerability result was produced |

## Security scan evidence

`verify-image-security.sh` pins Trivy `0.72.0` and fails on fixed HIGH or CRITICAL findings for either release image. The first
attempt stalled against `mirror.gcr.io`; the GHCR retry transferred less than 1 MiB of the 100.39 MiB database while its
ETA increased beyond one hour. Both temporary scanner containers were stopped and removed. This is a scanner
infrastructure failure, not a clean scan. The gate is deferred by the current priority decision and remains unpassed.

## Scope decisions and deferred gates

1. Do not implement HTTP/3 in the BWS fork. Native NGF v2.6.7 does not provide the required QUIC configuration or UDP
   Service behavior, and this fork is limited to BWS differential adaptation.
2. The expired, near-expiry, second-valid-license, and online replacement matrix is deferred and remains unpassed.
3. The default 24-hour longevity run is deferred because the company machine powers off overnight. The 6-second smoke
   only validates the script path and must not be reported as a longevity pass.
4. Image vulnerability scanning is deliberately deferred and remains unpassed.
5. The active next step is to consolidate the completed isolated-regression assets, reports, and delivery checklist.
