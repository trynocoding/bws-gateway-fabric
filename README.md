# BWS Gateway Fabric

BWS Gateway Fabric is a Kubernetes Gateway API implementation that uses BES WebServer (BWS) as its data plane. The
control plane watches standard Gateway API resources, generates BWS configuration, and delivers it to BWS Agent over
the existing mTLS gRPC protocol.

This repository is derived from NGINX Gateway Fabric v2.6.7. The BWS productization branch provides its own control-plane
and data-plane images, BWS process and Agent identity, and the BWS runtime directory contract.

## Current product contract

- Controller: `gateway.bessystem.com/bws-gateway-controller`
- GatewayClass: `bws`
- Helm Chart and values: `bws-gateway-fabric`, `bwsGateway`, and `bws`
- Custom APIs: `gateway.bessystem.com`, `BwsGateway`, and `BwsProxy`
- Control-plane binary and container: `bws-gateway`
- Data-plane container: `bws`
- Agent binary: `bws-agent`
- Configuration root: `/etc/bws`
- Runtime directory: `/var/run/bws`
- Cache directory: `/var/cache/bws`

Standard Gateway API kinds remain unchanged. New installations do not require or render the transitional
`nginxGateway`/`nginx` values or `gateway.nginx.org` custom resources. NGINX Plus, NGINX One, and F5 WAF fields are not
part of the BWS Chart or generated CRD schemas.

## Build and test

```bash
make build
make unit-test
make fmt vet lint
```

Build the BWS-specific images with:

```bash
make build-bws-control-plane-image TAG=dev
make build-bws-image TAG=dev BWS_PREFIX=bws-gateway-fabric/bws
```

The BWS image contract is documented in [`docs/bws-data-plane-image.md`](docs/bws-data-plane-image.md), and the M4.3
API contract and rollback boundary are documented in [`docs/bws-m4-api-migration.md`](docs/bws-m4-api-migration.md). Repeatable M4
cluster deployment and smoke verification are under [`tests/bws-m4/`](tests/bws-m4/). The staged integration plan is
maintained in the parent workspace at `docs/2026-07-16-bws-gateway-fabric-integration-plan.md`.
