# BWS M3 cluster PoC

This PoC uses the unchanged NGF v2.6.7 APIs and Helm value names. It installs a separate `bws-poc` GatewayClass and
control plane, mounts the BWS license as a read-only Secret, and provisions a BWS data plane with `plus=false`.

## Prerequisites

- Kubernetes 1.31 or newer with the NGF v2.6.7 CRDs installed.
- `kubectl`, Helm, OpenSSL, Docker, and a cluster image-loading mechanism.
- The local `bws-gateway-fabric/bws:m3-local` image available to every cluster node.
- A valid `bws.lic.txt`. The scripts never place it in the repository or an image layer.

Build and tag the image from the workspace root:

```shell
make build-bws-image TAG=m3-local BWS_PREFIX=bws-gateway-fabric/bws
```

For kind, run `kind load docker-image bws-gateway-fabric/bws:m3-local`. For a host-local containerd node, import the
image into the `k8s.io` namespace. For a remote or multi-node cluster, push it to a registry and override
`BWS_IMAGE_REPOSITORY`, `BWS_IMAGE_TAG`, and `BWS_IMAGE_PULL_POLICY`.

## Deploy and verify

```shell
BWS_LICENSE_FILE=/secure/path/bws.lic.txt ./tests/bws-m3/deploy.sh
./tests/bws-m3/verify.sh
./tests/bws-m3/verify-resilience.sh
```

For environments where the license should never be copied to a temporary file, create `bws-m3/bws-license` first with
the key `bws.lic.txt`, then run `deploy.sh` without `BWS_LICENSE_FILE`.

The deployment is isolated in `bws-m3-system` and `bws-m3`; it does not modify the existing `nginx` GatewayClass.
Verification covers the BWS process and version, Agent TLS material, readiness, UID 101, read-only root filesystem,
HTTP/HTTPS traffic, an incremental backend change, and preservation of the last known-good configuration after an
invalid snippet. The verifier restores the original route and removes the invalid policy on exit.

The resilience verifier expects the two replicas configured in `values.yaml`. It deletes one data-plane Pod, restarts
the control plane and waits for both Agents to reconnect, then performs a rolling restart while continuously sending
requests through the HTTP NodePort.

The Secret is mounted as a directory, not with `subPath`, so Kubernetes can project updated license bytes. The current
entrypoint copies the license only at process startup; a true online license rotation still requires a second valid
license and explicit BWS reload validation. Do not report a Pod restart as an online-rotation pass.

Cleanup is intentionally explicit:

```shell
helm uninstall bws-m3 -n bws-m3-system
kubectl delete namespace bws-m3 bws-m3-system
```
