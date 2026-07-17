# BWS M4.1 productization verification

This suite verifies the first productization batch while retaining the upstream Helm top-level `nginx` value and
NGF custom-resource APIs for compatibility. It expects the visible product identity to be BWS: control-plane binary
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
```

The verifier requires two ready BWS replicas, validates the init binary and both BWS Agent processes, checks HTTP and
HTTPS routing, and applies an incremental backend change before restoring the original route. The namespaces are
isolated from the M3 baseline.

Cleanup is explicit:

```shell
helm uninstall bws-m4 -n bws-m4-system
kubectl delete namespace bws-m4 bws-m4-system
```
