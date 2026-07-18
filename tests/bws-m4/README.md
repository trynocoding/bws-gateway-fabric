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

The deferred release gates have dedicated commands, but they are not part of the current execution queue:

```shell
./tests/bws-m4/verify-image-security.sh
BWS_M4_LONGEVITY_REPORT=/secure/results/bws-m4-24h.txt ./tests/bws-m4/verify-longevity.sh
```

Run destructive capability regression in a dedicated one-control-plane, two-worker Kind cluster. The creation script
installs the Gateway API experimental CRDs and loads the local control-plane, data-plane, and HTTP workload images:

```shell
export PATH="$(go env GOPATH)/bin:${PATH}"
go install sigs.k8s.io/kind@v0.32.0
./tests/bws-m4/create-isolated-cluster.sh
export KUBECONFIG="${PWD}/build/bws-m4-isolated.kubeconfig"
BWS_LICENSE_FILE=/secure/path/bws.lic.txt ./tests/bws-m4/deploy.sh
./tests/bws-m4/verify.sh
./tests/bws-m4/verify-stream-tlsroute.sh
./tests/bws-m4/install-metrics-server.sh
./tests/bws-m4/verify-hpa.sh
./tests/bws-m4/verify-node-recovery.sh
./tests/bws-m4/verify-conformance.sh
```

`verify-stream-tlsroute.sh` refuses to run outside `kind-bws-m4-isolated`. It adds a temporary TLS passthrough listener
and backend, verifies the TLSRoute status and generated stream configuration in both data-plane Pods, runs the real
`bws -t`, and sends a TLS request through the generated Gateway Service. It restores the baseline Gateway afterward.
Set `BWS_M4_WORKLOAD_IMAGE` for an offline or locally rebuilt HTTP workload image; the creation and deployment scripts
use the same override.

The Metrics Server installer pins `v0.8.1`, verifies the release manifest SHA-256, and enables the kubelet TLS override
required by Kind. `verify-hpa.sh` records CPU-driven scale-up, request outcomes, and scale-down. The worker recovery test
keeps continuous HTTP traffic through worker drain, replacement scheduling, and restart. After the zero-failure window
is recorded, it verifies post-recovery Pod redistribution, both BWS Agent reconnections, and a fresh end-to-end request.
Its cleanup restores both workers, the HPA maximum, and the single-replica HTTP backend baseline.

`verify-conformance.sh` builds the pinned Gateway API `v1.5.1` runner, preloads its fixture images, and temporarily
switches the controller to all-namespace watching with one BWS replica per test Gateway. It copies the BWS license into
the conformance infrastructure namespace, runs the `GATEWAY-HTTP`, `GATEWAY-GRPC`, and `GATEWAY-TLS` core and declared
extended features, writes the profile and full log under `build/`, then restores the normal namespace and HPA values.

The security verifier fails on fixed HIGH or CRITICAL findings from Trivy. The longevity verifier defaults to 24 hours
and fails on any request loss; use `BWS_M4_LONGEVITY_SECONDS` only for script smoke testing. Both gates are currently
deferred, and the short longevity smoke is not a 24-hour pass. The license replacement matrix is also deferred.
HTTP/3 is not a BWS release gate: native NGF v2.6.7 does not generate QUIC configuration or a UDP Service port, and the
BWS fork does not extend native NGF capabilities.

The completed M4.2 environment, results, retained technical paths, and zero-downtime finding are recorded in
[`docs/bws-m4-directory-migration-report.md`](../../docs/bws-m4-directory-migration-report.md).
The current M4.4 evidence and support matrix are recorded in
[`docs/bws-m4-productization-verification-report.md`](../../docs/bws-m4-productization-verification-report.md).

Cleanup is explicit:

```shell
helm uninstall bws-m4 -n bws-m4-system
kubectl delete namespace bws-m4 bws-m4-system
```
