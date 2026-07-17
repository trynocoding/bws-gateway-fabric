# Helm Chart Examples

This directory contains values examples for deploying BWS Gateway Fabric in a Kubernetes cluster.

## Prerequisites

- Helm 3.x

## Examples

- [Default](./default) - deploys BWS Gateway Fabric with the default configuration.
- [Experimental](./experimental) - enables Gateway API experimental features.
- [Inference](./inference) - enables the Gateway API Inference Extension.
- [Snippets](./snippets) - enables BWS configuration snippets.
- [Azure](./azure) - uses a node selector suitable for Azure Kubernetes Service.
- [NodePort](./nodeport) - exposes the BWS data plane with a NodePort Service.

## Manifests generation

These examples generate the BWS Gateway Fabric manifests in the [deploy directory](../../deploy).

If you want to generate manifests for a specific example, or need to customize one of the examples, run the following
command from the root of the project:

```shell
helm template bws-gateway --namespace bws-gateway --values examples/helm/<example>/values.yaml charts/bws-gateway-fabric
```
