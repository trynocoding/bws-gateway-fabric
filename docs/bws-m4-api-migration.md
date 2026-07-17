# BWS M4.3 Helm and API contract

M4.3 establishes the first public BWS Gateway Fabric API. The transitional NGINX Gateway Fabric names used by the
M3 proof of concept and the M4.1/M4.2 implementation branches were never published as a BWS product API, so this
release uses the BWS contract directly and does not install conversion webhooks or legacy CRDs.

## Contract mapping

| Transitional contract | M4.3 contract |
|---|---|
| Chart `nginx-gateway-fabric` | Chart `bws-gateway-fabric` |
| `nginxGateway` | `bwsGateway` |
| `nginx` | `bws` |
| `gateway.nginx.org` | `gateway.bessystem.com` |
| `NginxGateway` | `BwsGateway` |
| `NginxProxy` | `BwsProxy` |
| `nginxgateways` | `bwsgateways` |
| `nginxproxies` | `bwsproxies` |

Standard Gateway API resources and fields are unchanged. GatewayClass `bws` continues to use controller name
`gateway.bessystem.com/bws-gateway-controller`, and its `parametersRef` now points to
`gateway.bessystem.com/BwsProxy`.

## Unsupported upstream fields

The BWS Chart and generated `BwsProxy` schema do not expose NGINX Plus, NGINX One, `nginxPlus`, F5 `WAFPolicy`,
`waf`, or WAF sidecar fields. Those capabilities cannot be made valid BWS APIs by renaming them. A future BWS
security API must be based on verified BWS module behavior and its own lifecycle and policy semantics.

## Upgrade and rollback

M4.3 is installed as a fresh BWS release. Do not overwrite an M3 release in place: export standard Gateway API
resources, install the BWS Chart and CRDs, then recreate any required configuration using `BwsGateway` and
`BwsProxy`. Kubernetes does not convert objects between the old and new API groups automatically.

Rollback consists of uninstalling the M4.3 Helm release and reinstalling the frozen M3 chart and CRDs from tag
`bws-m3-baseline-20260717`. Standard Gateway API manifests can be reused after restoring the M3 GatewayClass and
its parameters reference; product-specific objects must be restored from the corresponding exported manifests.

Regenerate all API, CRD, schema, RBAC, deployment, and Chart documentation artifacts after source changes with:

```shell
make generate-all
```
