# BWS M4.2 directory migration report

Date: 2026-07-17
Result: Passed
Follow-up: on 2026-07-20 the main configuration was migrated from `/etc/bws/nginx.conf` to `/etc/bws/bws.conf` and
revalidated in the three-node isolated Kind cluster.

## Scope

This report covers the BWS runtime directory migration and its extended cluster regression. It validates product-visible
M4.1 naming, `/etc/bws` and `/var/run/bws` runtime contracts, migration from an existing `nginx-agent.conf` ConfigMap,
configuration rollback, online TLS rotation, Pod replacement, control-plane restart, Agent reconnect, and a two-replica
rolling restart.

The transitional `bwsGateway`/`nginx` Helm fields and NGF custom-resource APIs are intentionally outside M4.2 and
remain scheduled for M4.3.

## Environment

- Kubernetes client/server: v1.31.9/v1.31.9
- BWS: 3.2.0.242
- Control-plane image: `bws-gateway-fabric@sha256:16851f00d598dfd9159f01ec6894f57228a8765694e2af3b7bca7b523be0dc98`
- Data-plane image: `bws-gateway-fabric/bws@sha256:85dac7dcd34a8fd9b5c1b90120cddf529dc903263cf7aa2bcd4013ad12a6145f`
- Namespaces: `bws-m4-system`, `bws-m4`
- Gateway conditions: `Accepted=True`, `Programmed=True`

## Results

| Gate | Result | Evidence |
|---|---|---|
| M4.2 smoke | Passed | Two Ready BWS replicas, real `bws -t`, HTTP/HTTPS, incremental route update |
| Invalid configuration | Passed | Both Agents rejected the invalid gzip directive and reported rollback success |
| Last-known-good traffic | Passed | HTTP traffic remained on the valid coffee route after rejection |
| TLS rotation | Passed | Temporary certificate became active and the original certificate was restored |
| Online certificate update | Passed | Data-plane Pod UIDs did not change during rotation or restoration |
| Single Pod replacement | Passed | Replica replacement completed under continuous traffic |
| Control-plane restart | Passed | Traffic continued and both Agents recorded a new connection |
| Rolling restart | Passed | 312 continuous requests completed with zero failures |
| Directory contract | Passed | Source, Helm rendering, ConfigMap, volume names, and live filesystems passed static checks |
| Main configuration identity | Passed | Both active replicas use `/etc/bws/bws.conf`; `/etc/bws/nginx.conf` is absent |
| Product log identity | Passed | Recent control/data-plane logs contained no old user-visible product identity |

## Runtime contract

The running data plane uses:

- `/etc/bws` for generated BWS configuration and certificates, with `/etc/bws/bws.conf` as the main configuration;
- `/var/run/bws` for PID and sockets;
- `/var/cache/bws` for cache, temporary files, logs, and the writable license copy;
- `/etc/bws-agent`, `/var/lib/bws-agent`, and `/var/log/bws-agent` for Agent configuration and state;
- `/var/run/secrets/bws` and `/var/run/secrets/bws-gateway` for license and Agent mTLS material.

The verifier confirmed that `/etc/nginx`, `/etc/nginx-agent`, `/var/run/nginx`, `/var/cache/nginx`,
`/var/lib/nginx-agent`, and `/var/log/nginx-agent` do not exist in the BWS containers. `/usr/share/nginx` remains an
explicit technical dependency for static files shipped by the base package; it is not a BWS configuration or runtime
state directory.

## Finding and fix

The first zero-downtime rolling test recorded one ClusterIP connection refusal at `2026-07-17T08:10:48Z`. Deployment
events showed that Kubernetes waited for a new replica to become Ready before terminating an old replica, but BWS
exited before EndpointSlice and node datapath removal had fully propagated.

The M4 product values now add a five-second `/usr/bin/sleep` `preStop` drain window. The smoke test verifies that this
hook is present. Repeating the full Pod replacement, control-plane restart, Agent reconnect, and rolling restart then
completed 312 requests without a failure.

## Repeatable commands

```bash
./tests/bws-m4/verify.sh
./tests/bws-m4/verify-config-tls.sh
./tests/bws-m4/verify-resilience.sh
./tests/bws-m4/verify-contract.sh
```

All scripts restore temporary route, invalid policy, and certificate changes before exit.
