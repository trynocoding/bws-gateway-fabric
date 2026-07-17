# BWS M3 compatibility baseline

Date: 2026-07-17

This baseline freezes the last compatibility PoC before M4 productization. It deliberately uses the unchanged NGF
v2.6.7 APIs, Helm value names, runtime directories, and official control-plane image. M4 changes must be compared
against this baseline until the BWS runtime-directory and API migrations are complete.

## Source and image inputs

| Component | Frozen value |
|---|---|
| BWS Gateway Fabric source | Git tag `bws-m3-baseline-20260717` based on NGF `v2.6.7` |
| BWS Agent source | `da7b9a952ae96ab9c851ee0f5aa7d5a09b3a57f4` based on Agent `v3.11.2` |
| BWS archive | `bws-3.2.0-LINUX-X64.tar_94b299d8d6b5c686ffbe0ee912c79cbb304b93dc.gz` |
| BWS archive SHA-256 | `885a2ea9fb91b6837971259dac118854fc5d3b6236a432819f8f1dac6e7fd95f` |
| Data-plane image | `bws-gateway-fabric/bws:m3-local` |
| Data-plane runtime image ID | `sha256:5575290fc87a4b4e727a0406e3bfa7d2feb3c462a60a00d0653dcb3219937563` |
| Control-plane image | `ghcr.io/nginx/nginx-gateway-fabric:2.6.7` |
| Control-plane runtime image ID | `sha256:1b5f8131482557bbcdcca9ad05984b4465bd6cc59db719e18bb26dad169cc30b` |

The runtime image IDs are evidence from the validation cluster, not portable image names. Rebuilt images must use the
same source commits, BWS archive digest, build arguments, and architecture; record the resulting digest separately.

## Cluster contract

- Kubernetes client/server baseline: v1.31.9.
- Helm release: `bws-m3`, chart/app version 2.6.7, namespace `bws-m3-system`, revision 2.
- GatewayClass: `bws-poc`; application namespace: `bws-m3`; data-plane replicas: 2.
- Gateway API standard CRDs: bundle v1.5.1, serving `v1` and `v1beta1` where applicable.
- NGF custom resources retain `gateway.nginx.org`; the cluster originally had the NGF v2.6.5 CRDs. Helm does not
  upgrade existing CRDs, so a clean replay must explicitly install the intended v2.6.7 CRDs first.
- PoC runtime paths remain `/etc/nginx`, `/etc/nginx-agent`, `/var/run/nginx`, and `/var/cache/nginx`.

## Replay gate

Build and load the data-plane image, then run:

```shell
BWS_LICENSE_FILE=/secure/path/bws.lic.txt ./tests/bws-m3/deploy.sh
./tests/bws-m3/verify.sh
./tests/bws-m3/verify-resilience.sh
./tests/bws-m3/verify-extended.sh
```

All four scripts must pass before comparing an M4 build. The detailed verified and open behaviors are recorded in
[`bws-m3-poc-report.md`](bws-m3-poc-report.md). The M4 comparison must preserve HTTP/HTTPS, HTTP/2, WebSocket,
configuration rollback, TLS rotation, metrics/logging, Agent reconnect, Pod replacement, and rolling restart behavior.
