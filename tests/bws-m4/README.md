# BWS M4.4 productization verification

This suite verifies the product identity, runtime directory migration, and BWS-only Helm/CRD API contract. It uses
the `bwsGateway` and `bws` top-level values, `gateway.bessystem.com`, `BwsGateway`, and `BwsProxy`. It expects the visible product identity to be BWS: control-plane binary
and container `bws-gateway`, GatewayClass `bws`, controller name under `gateway.bessystem.com`, data-plane container
`bws`, and Agent binary `bws-agent`.

Build the two local images from this repository:

```shell
make build-bws-control-plane-image TAG=m4-local
make build-bws-image TAG=m4-local BWS_PREFIX=bws-gateway-fabric/bws BWS_INSTALL_DEBUG_TOOLS=false
```

Load both images into every cluster node, then deploy and verify:

```shell
BWS_LICENSE_FILE=/secure/path/bws.lic.txt ./tests/bws-m4/deploy.sh
./tests/bws-m4/verify.sh
./tests/bws-m4/verify-config-tls.sh
./tests/bws-m4/verify-resilience.sh
./tests/bws-m4/verify-extended.sh
./tests/bws-m4/verify-grpc.sh
./tests/bws-m4/verify-contract.sh
./tests/bws-m4/audit-product-identity.sh
```

The verifier requires two ready BWS replicas, validates the init binary and both BWS Agent processes, confirms the
`/etc/bws`, `/etc/bws-agent`, `/var/run/bws`, and `/var/cache/bws` contracts, and rejects old nginx directory or volume
dependencies. It also checks HTTP and HTTPS routing and applies an incremental backend change before restoring the
original route. The namespaces are isolated from the M3 baseline.

`verify-config-tls.sh` proves that both Agents reject and roll back an invalid generated configuration, then rotates the
Gateway TLS Secret to a temporary certificate and restores the original certificate without restarting data-plane Pods.
`verify-resilience.sh` continuously sends traffic through the ClusterIP while replacing one data-plane Pod, restarting
the control plane, waiting for both Agents to reconnect, and rolling both data-plane replicas. The M4 values include a
five-second BWS `preStop` drain window so terminating Pods leave Service endpoints before the BWS process exits.
`verify-contract.sh` rejects old runtime directories and legacy Helm/CRD contracts in source, generated CRDs, Helm
rendering, and live objects. It also verifies the Agent ConfigMap key, volume names, and recent user-visible product logs.
`verify-extended.sh` migrates the M3 HTTP/2, WebSocket, metrics, NJS, and log checks to the BWS-only API and directory
contract. `verify-grpc.sh` adds a GRPCRoute backend and performs a real unary RPC through BWS. The identity audit scans
both image configurations and histories, Helm rendering, CRDs, RBAC, live logs, Agent labels, and the container
filesystem; only nginx configuration terms, module/source paths, metric contracts, documentation URLs, and the retained
`/usr/share/nginx` static-resource directory are allowed.

The remaining release gates have dedicated commands:

```shell
./tests/bws-m4/verify-image-security.sh
BWS_M4_LONGEVITY_REPORT=/secure/results/bws-m4-24h.txt ./tests/bws-m4/verify-longevity.sh
```

The security verifier fails on fixed HIGH or CRITICAL findings from Trivy. The longevity verifier defaults to 24 hours
and fails on any request loss; use `BWS_M4_LONGEVITY_SECONDS` only for script smoke testing. HTTP/3, stream, HPA, node
restart, the complete Gateway API conformance profile, and license replacement scenarios remain separate release gates.

The completed M4.2 environment, results, retained technical paths, and zero-downtime finding are recorded in
[`docs/bws-m4-directory-migration-report.md`](../../docs/bws-m4-directory-migration-report.md).
The current M4.4 evidence and support matrix are recorded in
[`docs/bws-m4-productization-verification-report.md`](../../docs/bws-m4-productization-verification-report.md).

Cleanup is explicit:

```shell
helm uninstall bws-m4 -n bws-m4-system
kubectl delete namespace bws-m4 bws-m4-system
```
