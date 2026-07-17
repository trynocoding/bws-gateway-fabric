# BWS M4.4 productization verification report

Status: in progress on 2026-07-17. This report records the first M4.4 release-verification batch; it does not mark the
24-hour, conformance, HPA, node-restart, HTTP/3, stream, or complete license matrix gates as passed.

## Verified build and environment

- Kubernetes `v1.31.9`, one node (`cool`), containerd `2.2.5`.
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
| HTTP/3 | BWS binary has `--with-http_v3_module`; controller has no QUIC generation or UDP Service port | Not supported by current product contract; implementation and E2E required |
| Stream/TLSRoute | BWS binary and TLSRoute CRD are present | E2E not yet run |
| HPA | `autoscaling/v2` exists, but `metrics.k8s.io` is absent and `kubectl top` fails | Blocked on Metrics API |
| Node restart | Single shared node hosts unrelated workloads | Run only in an isolated test cluster |
| License states | Valid and missing cases verified | Expired, near-expiry, second valid license, and online replacement require supplied fixtures |
| Gateway API conformance | GRPCRoute smoke passed | Full HTTP/GRPC/TLS profiles not yet run |
| 24-hour stability | Script smoke passed for 6 seconds with zero failures | Run the default 86,400-second gate and archive its report |
| Image vulnerability scan | Trivy image pulled | Blocked: both default and GHCR DB sources were too slow; no vulnerability result was produced |

## Security scan evidence

`verify-image-security.sh` pins Trivy `0.72.0` and fails on fixed HIGH or CRITICAL findings for either release image. The first
attempt stalled against `mirror.gcr.io`; the GHCR retry transferred less than 1 MiB of the 100.39 MiB database while its
ETA increased beyond one hour. Both temporary scanner containers were stopped and removed. This is a scanner
infrastructure failure, not a clean scan, and remains a release blocker.

## Next gates

1. Run Trivy where its vulnerability database can be mirrored or preloaded, then archive both image results.
2. Add isolated-cluster stream/TLSRoute and node-restart tests; implement control-plane QUIC/UDP support before claiming
   HTTP/3.
3. Install Metrics API and execute HPA scaling; run the complete Gateway API conformance profiles.
4. Supply expired, near-expiry, and replacement licenses and verify online rotation semantics.
5. Run `verify-longevity.sh` for its default 24-hour duration and archive the generated report.
