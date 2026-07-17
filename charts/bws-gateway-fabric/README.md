
# BWS Gateway Fabric Helm Chart

![Version: 2.6.7](https://img.shields.io/badge/Version-2.6.7-informational?style=flat-square) ![AppVersion: 2.6.7](https://img.shields.io/badge/AppVersion-2.6.7-informational?style=flat-square)

- [BWS Gateway Fabric Helm Chart](#bws-gateway-fabric-helm-chart)
  - [Introduction](#introduction)
  - [Prerequisites](#prerequisites)
    - [Installing the Gateway API resources](#installing-the-gateway-api-resources)
  - [Requirements](#requirements)
  - [Installing the Chart](#installing-the-chart)
    - [Installing the Chart from the OCI Registry](#installing-the-chart-from-the-oci-registry)
    - [Installing the Chart via Sources](#installing-the-chart-via-sources)
      - [Pulling the Chart](#pulling-the-chart)
      - [Installing the Chart](#installing-the-chart-1)
    - [Custom installation options](#custom-installation-options)
      - [Service type](#service-type)
  - [Upgrading the Chart](#upgrading-the-chart)
    - [Upgrading the Gateway Resources](#upgrading-the-gateway-resources)
    - [Upgrading the CRDs](#upgrading-the-crds)
    - [Upgrading the Chart from the OCI Registry](#upgrading-the-chart-from-the-oci-registry)
    - [Upgrading the Chart from the Sources](#upgrading-the-chart-from-the-sources)
  - [Uninstalling the Chart](#uninstalling-the-chart)
    - [Uninstalling the Gateway Resources](#uninstalling-the-gateway-resources)
  - [Configuration](#configuration)

## Introduction

This chart deploys the BWS Gateway Fabric in your Kubernetes cluster.

## Prerequisites

- [Helm 3.0+](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### Installing the Gateway API resources

> [!NOTE]
>
> The [Gateway API resources](https://github.com/kubernetes-sigs/gateway-api) from the standard channel must be
> installed before deploying BWS Gateway Fabric. If they are already installed in your cluster, please ensure
> they are the correct version as supported by the BWS Gateway Fabric -
> [see the Technical Specifications](https://github.com/trynocoding/nginx-gateway-fabric/blob/bws/m4-productization/README.md#technical-specifications).

```shell
kubectl kustomize https://github.com/kubernetes-sigs/gateway-api/config/crd?timeout=120\&ref=v1.5.1 | kubectl apply -f -
```

## Requirements

Kubernetes: `>= 1.31.0-0`

## Installing the Chart

### Installing the Chart from the OCI Registry

To install the latest stable release of BWS Gateway Fabric in the `bws-gateway` namespace, run the following command:

```shell
helm install ngf oci://ghcr.io/trynocoding/charts/bws-gateway-fabric --create-namespace -n bws-gateway
```

`ngf` is the name of the release, and can be changed to any name you want. This name is added as a prefix to the Deployment name.

If the namespace already exists, you can omit the optional `--create-namespace` flag. If you want the latest version from the `main` branch, add `--version 0.0.0-edge` to your install command.

To wait for the Deployment to be ready, you can either add the `--wait` flag to the `helm install` command, or run
the following after installing:

```shell
kubectl wait --timeout=5m -n bws-gateway deployment/ngf-bws-gateway-fabric --for=condition=Available
```

### Installing the Chart via Sources

#### Pulling the Chart

```shell
helm pull oci://ghcr.io/trynocoding/charts/bws-gateway-fabric --untar
cd bws-gateway-fabric
```

This will pull the latest stable release. To pull the latest version from the `main` branch, specify the
`--version 0.0.0-edge` flag when pulling.

#### Installing the Chart

To install the chart into the `bws-gateway` namespace, run the following command.

```shell
helm install ngf . --create-namespace -n bws-gateway
```

`ngf` is the name of the release, and can be changed to any name you want. This name is added as a prefix to the Deployment name.

If the namespace already exists, you can omit the optional `--create-namespace` flag.

To wait for the Deployment to be ready, you can either add the `--wait` flag to the `helm install` command, or run
the following after installing:

```shell
kubectl wait --timeout=5m -n bws-gateway deployment/ngf-bws-gateway-fabric --for=condition=Available
```

### Custom installation options

#### Service type

By default, the BWS Gateway Fabric helm chart deploys a LoadBalancer Service.

To use a NodePort Service instead:

```shell
helm install ngf oci://ghcr.io/trynocoding/charts/bws-gateway-fabric --create-namespace -n bws-gateway --set bws.service.type=NodePort
```

## Upgrading the Chart

### Upgrading the Gateway Resources

Before you upgrade a release, ensure the Gateway API resources are the version supported by BWS Gateway Fabric.

To upgrade the Gateway CRDs from [the Gateway API repo](https://github.com/kubernetes-sigs/gateway-api), run:

```shell
kubectl kustomize https://github.com/kubernetes-sigs/gateway-api/config/crd?timeout=120\&ref=v1.5.1 | kubectl apply -f -
```

### Upgrading the CRDs

Helm does not upgrade the BWS Gateway Fabric CRDs during a release upgrade. Before you upgrade a release, you
must [pull the chart](#pulling-the-chart) from GitHub and run the following command to upgrade the CRDs:

```shell
kubectl apply --server-side -f crds/
```

The following warning is expected and can be ignored:

```text
Warning: kubectl apply should be used on resource created by either kubectl create --save-config or kubectl apply.
```

### Upgrading the Chart from the OCI Registry

To upgrade the release `ngf`, run:

```shell
helm upgrade ngf oci://ghcr.io/trynocoding/charts/bws-gateway-fabric -n bws-gateway
```

This will upgrade to the latest stable release. To upgrade to the latest version from the `main` branch, specify
the `--version 0.0.0-edge` flag when upgrading.

### Upgrading the Chart from the Sources

Pull the chart sources as described in [Pulling the Chart](#pulling-the-chart), if not already present. Then, to upgrade
the release `ngf`, run:

```shell
helm upgrade ngf . -n bws-gateway
```

## Uninstalling the Chart

To uninstall/delete the release `ngf`:

```shell
helm uninstall ngf -n bws-gateway
kubectl delete ns bws-gateway
kubectl delete -f https://raw.githubusercontent.com/trynocoding/nginx-gateway-fabric/bws/m4-productization/deploy/crds.yaml
```

These commands remove all the Kubernetes components associated with the release and deletes the release.

### Uninstalling the Gateway Resources

> **Warning: This command will delete all the corresponding custom resources in your cluster across all namespaces!
> Please ensure there are no custom resources that you want to keep and there are no other Gateway API implementations
> running in the cluster!**

To delete the Gateway API CRDs from [the Gateway API repo](https://github.com/kubernetes-sigs/gateway-api), run:

```shell
kubectl kustomize https://github.com/kubernetes-sigs/gateway-api/config/crd?timeout=120\&ref=v1.5.1 | kubectl delete -f -
```

## Configuration

The following table lists the configurable parameters of the BWS Gateway Fabric chart and their default values.

> More granular configuration options may not show up in this table.
> Viewing the `values.yaml` file directly can show all available options.

| Key | Description | Type | Default |
|-----|-------------|------|---------|
| `bws` | The bws section configures BWS data plane deployments. | object | `{"autoscaling":{"annotations":{},"behavior":{},"enable":false,"maxReplicas":10,"metrics":[],"minReplicas":1,"targetCPUUtilizationPercentage":50,"targetMemoryUtilizationPercentage":50},"config":{},"container":{"hostPorts":[],"lifecycle":{},"readinessProbe":{},"resources":{},"volumeMounts":[]},"image":{"pullPolicy":"IfNotPresent","repository":"bws-gateway-fabric/bws","tag":"2.6.7"},"imagePullSecret":"","imagePullSecrets":[],"kind":"deployment","patches":[],"pod":{},"replicas":1,"service":{"externalTrafficPolicy":"Local","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"nodePorts":[],"patches":[],"type":"LoadBalancer"}}` |
| `bws.autoscaling` | Autoscaling configuration for the BWS data plane. | object | `{"annotations":{},"behavior":{},"enable":false,"maxReplicas":10,"metrics":[],"minReplicas":1,"targetCPUUtilizationPercentage":50,"targetMemoryUtilizationPercentage":50}` |
| `bws.autoscaling.annotations` | Set of custom annotations for the HPA object. | object | `{}` |
| `bws.autoscaling.behavior` | The full HPA `spec.behavior` object, passed as-is to the HPA resource. Accepts any valid Kubernetes HPA behavior spec. See the [Kubernetes docs](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior) for all available fields. | object | `{}` |
| `bws.autoscaling.enable` | Enable or disable Horizontal Pod Autoscaler for the BWS data plane. | bool | `false` |
| `bws.autoscaling.maxReplicas` | Maximum number of replicas for the BWS data plane HPA. | int | `10` |
| `bws.autoscaling.metrics` | Custom or additional autoscaling metrics. https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#scaling-on-custom-metrics | list | `[]` |
| `bws.autoscaling.minReplicas` | Minimum number of replicas for the BWS data plane HPA. | int | `1` |
| `bws.autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization percentage for the BWS data plane HPA. Requires `bws.container.resources` to be set. | int | `50` |
| `bws.autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization percentage for the BWS data plane HPA. Requires `bws.container.resources` to be set. | | int | `50` |
| `bws.config` | The configuration for the data plane that is contained in the BwsProxy resource. This is applied globally to all Gateways managed by this instance of BWS Gateway Fabric. | object | `{}` |
| `bws.container` | The container configuration for the BWS container. This is applied globally to all Gateways managed by this instance of BWS Gateway Fabric. | object | `{"hostPorts":[],"lifecycle":{},"readinessProbe":{},"resources":{},"volumeMounts":[]}` |
| `bws.container.hostPorts` | A list of HostPorts to expose on the host. This configuration allows containers to bind to a specific port on the host node, enabling external network traffic to reach the container directly through the host's IP address and port. Use this option when you need to expose container ports on the host for direct access, such as for debugging, legacy integrations, or when NodePort/LoadBalancer services are not suitable. Note: Using hostPort may have security and scheduling implications, as it ties pods to specific nodes and ports. | list | `[]` |
| `bws.container.lifecycle` | The lifecycle of the BWS container. | object | `{}` |
| `bws.container.resources` | The resource requirements of the BWS container. You should set this value if you want to use dataplane Autoscaling(HPA). | object | `{}` |
| `bws.container.volumeMounts` | volumeMounts are the additional volume mounts for the BWS container. | list | `[]` |
| `bws.image.repository` | The BWS data plane image to use. | string | `"bws-gateway-fabric/bws"` |
| `bws.imagePullSecret` | The name of the secret containing docker registry credentials. Secret must exist in the same namespace as the helm release. The control plane will copy this secret into any namespace where BWS is deployed. | string | `""` |
| `bws.imagePullSecrets` | A list of secret names containing docker registry credentials. Secrets must exist in the same namespace as the helm release. The control plane will copy these secrets into any namespace where BWS is deployed. | list | `[]` |
| `bws.kind` | The kind of BWS deployment. | string | `"deployment"` |
| `bws.patches` | Custom patches to apply to the BWS Deployment/DaemonSet. | list | `[]` |
| `bws.pod` | The pod configuration for the BWS data plane pod. This is applied globally to all Gateways managed by this instance of BWS Gateway Fabric. | object | `{}` |
| `bws.replicas` | The number of replicas of the BWS Deployment. This value is ignored if autoscaling.enable is true. | int | `1` |
| `bws.service` | The service configuration for the BWS data plane. This is applied globally to all Gateways managed by this instance of BWS Gateway Fabric. | object | `{"externalTrafficPolicy":"Local","loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"nodePorts":[],"patches":[],"type":"LoadBalancer"}` |
| `bws.service.externalTrafficPolicy` | The externalTrafficPolicy of the service. The value Local preserves the client source IP. | string | `"Local"` |
| `bws.service.loadBalancerClass` | LoadBalancerClass is the class of the load balancer implementation this Service belongs to. Requires bws.service.type set to LoadBalancer. | string | `""` |
| `bws.service.loadBalancerIP` | The static IP address for the load balancer. Requires bws.service.type set to LoadBalancer. | string | `""` |
| `bws.service.loadBalancerSourceRanges` | The IP ranges (CIDR) that are allowed to access the load balancer. Requires bws.service.type set to LoadBalancer. | list | `[]` |
| `bws.service.nodePorts` | A list of NodePorts to expose on the BWS data plane service. Each NodePort MUST map to a Gateway listener port, otherwise it will be ignored. The default NodePort range enforced by Kubernetes is 30000-32767. | list | `[]` |
| `bws.service.patches` | Custom patches to apply to the BWS Service. | list | `[]` |
| `bws.service.type` | The type of service to create for the BWS data plane. | string | `"LoadBalancer"` |
| `bwsGateway` | The bwsGateway section contains configuration for the BWS Gateway Fabric control plane deployment. | object | `{"affinity":{},"autoscaling":{"annotations":{},"behavior":{},"enable":false,"maxReplicas":10,"metrics":[],"minReplicas":1,"targetCPUUtilizationPercentage":50,"targetMemoryUtilizationPercentage":50},"config":{"logging":{"level":"info"}},"configAnnotations":{},"extraVolumeMounts":[],"extraVolumes":[],"gatewayClassAnnotations":{},"gatewayClassName":"bws","gatewayControllerName":"gateway.bessystem.com/bws-gateway-controller","gwAPIExperimentalFeatures":{"enable":false},"gwAPIInferenceExtension":{"enable":false,"endpointPicker":{"disableTLS":false,"skipVerify":true}},"image":{"pullPolicy":"IfNotPresent","repository":"bws-gateway-fabric","tag":"2.6.7"},"kind":"deployment","labels":{},"leaderElection":{"enable":true,"lockName":""},"lifecycle":{},"metrics":{"enable":true,"port":9113,"secure":false},"name":"bws-gateway-fabric","nodeSelector":{},"podAnnotations":{},"priorityClassName":"","productTelemetry":{"enable":false},"readinessProbe":{"enable":true,"failureThreshold":3,"initialDelaySeconds":3,"periodSeconds":10,"port":8081,"successThreshold":1,"timeoutSeconds":1},"replicas":1,"resources":{},"service":{"annotations":{},"labels":{}},"serviceAccount":{"annotations":{},"imagePullSecret":"","imagePullSecrets":[],"name":""},"snippets":{"enable":false},"snippetsFilters":{"enable":false},"terminationGracePeriodSeconds":30,"tolerations":[],"topologySpreadConstraints":[],"watchNamespaces":[]}` |
| `bwsGateway.affinity` | The affinity of the BWS Gateway Fabric control plane pod. | object | `{}` |
| `bwsGateway.autoscaling` | Autoscaling configuration for the BWS Gateway Fabric control plane. | object | `{"annotations":{},"behavior":{},"enable":false,"maxReplicas":10,"metrics":[],"minReplicas":1,"targetCPUUtilizationPercentage":50,"targetMemoryUtilizationPercentage":50}` |
| `bwsGateway.autoscaling.annotations` | Set of custom annotations for the HPA object. | object | `{}` |
| `bwsGateway.autoscaling.behavior` | The full HPA `spec.behavior` object, passed as-is to the HPA resource. Accepts any valid Kubernetes HPA behavior spec. See the [Kubernetes docs](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior) for all available fields. | object | `{}` |
| `bwsGateway.autoscaling.enable` | Enable or disable Horizontal Pod Autoscaler for the control plane. | bool | `false` |
| `bwsGateway.autoscaling.maxReplicas` | Maximum number of replicas for the BWS data plane HPA. | int | `10` |
| `bwsGateway.autoscaling.metrics` | Custom or additional autoscaling metrics. https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#scaling-on-custom-metrics | list | `[]` |
| `bwsGateway.autoscaling.minReplicas` | Minimum number of replicas for the BWS data plane HPA. | int | `1` |
| `bwsGateway.autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization percentage for the BWS data plane HPA. Requires `bws.container.resources` to be set. | int | `50` |
| `bwsGateway.autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization percentage for the BWS data plane HPA. Requires `bws.container.resources` to be set. | | int | `50` |
| `bwsGateway.config.logging.level` | Log level. | string | `"info"` |
| `bwsGateway.configAnnotations` | Set of custom annotations for BwsGateway objects. | object | `{}` |
| `bwsGateway.extraVolumeMounts` | extraVolumeMounts are the additional volume mounts for the bws-gateway container. | list | `[]` |
| `bwsGateway.extraVolumes` | extraVolumes for the BWS Gateway Fabric control plane pod. Use in conjunction with bwsGateway.extraVolumeMounts mount additional volumes to the container. | list | `[]` |
| `bwsGateway.gatewayClassAnnotations` | Set of custom annotations for GatewayClass objects. | object | `{}` |
| `bwsGateway.gatewayClassName` | The name of the GatewayClass that will be created as part of this release. Every BWS Gateway Fabric must have a unique corresponding GatewayClass resource. BWS Gateway Fabric only processes resources that belong to its class - i.e. have the "gatewayClassName" field resource equal to the class. | string | `"bws"` |
| `bwsGateway.gatewayControllerName` | The name of the Gateway controller. The controller name must be of the form: DOMAIN/PATH. The controller's domain is gateway.bessystem.com. | string | `"gateway.bessystem.com/bws-gateway-controller"` |
| `bwsGateway.gwAPIExperimentalFeatures.enable` | Enable the experimental features of Gateway API which are supported by BWS Gateway Fabric. Requires the Gateway APIs installed from the experimental channel. | bool | `false` |
| `bwsGateway.gwAPIInferenceExtension.enable` | Enable Gateway API Inference Extension support. Allows for configuring InferencePools to route traffic to AI workloads. | bool | `false` |
| `bwsGateway.gwAPIInferenceExtension.endpointPicker` | EndpointPicker TLS configuration. | object | `{"disableTLS":false,"skipVerify":true}` |
| `bwsGateway.gwAPIInferenceExtension.endpointPicker.disableTLS` | Disable TLS for EndpointPicker communication. By default, TLS is enabled. Set to true only for development/testing or when using a service mesh for encryption. | bool | `false` |
| `bwsGateway.gwAPIInferenceExtension.endpointPicker.skipVerify` | Disables TLS certificate verification when connecting to the EndpointPicker. By default, certificate verification is disabled. REQUIRED: Must be true until Gateway API Inference Extension EndpointPicker supports mounting certificates. See: https://github.com/kubernetes-sigs/gateway-api-inference-extension/issues/1556 | bool | `true` |
| `bwsGateway.image` | The image configuration for the BWS Gateway Fabric control plane. | object | `{"pullPolicy":"IfNotPresent","repository":"bws-gateway-fabric","tag":"2.6.7"}` |
| `bwsGateway.image.repository` | The BWS Gateway Fabric image to use. | string | `"bws-gateway-fabric"` |
| `bwsGateway.kind` | The kind of the BWS Gateway Fabric installation - currently, only deployment is supported. | string | `"deployment"` |
| `bwsGateway.labels` | Set of labels to be added for BWS Gateway Fabric deployment. | object | `{}` |
| `bwsGateway.leaderElection.enable` | Enable leader election. Leader election is used to avoid multiple replicas of the BWS Gateway Fabric reporting the status of the Gateway API resources. If not enabled, all replicas of BWS Gateway Fabric will update the statuses of the Gateway API resources. | bool | `true` |
| `bwsGateway.leaderElection.lockName` | The name of the leader election lock. A Lease object with this name will be created in the same Namespace as the controller. | string | Autogenerated if not set or set to "". |
| `bwsGateway.lifecycle` | The lifecycle of the bws-gateway container. | object | `{}` |
| `bwsGateway.metrics.enable` | Enable exposing metrics in the Prometheus format. | bool | `true` |
| `bwsGateway.metrics.port` | Set the port where the Prometheus metrics are exposed. | int | `9113` |
| `bwsGateway.metrics.secure` | Enable serving metrics via https. By default metrics are served via http. Please note that this endpoint will be secured with a self-signed certificate. | bool | `false` |
| `bwsGateway.name` | The name of the BWS Gateway Fabric deployment - if not present, then by default uses release name given during installation. | string | `"bws-gateway-fabric"` |
| `bwsGateway.nodeSelector` | The nodeSelector of the BWS Gateway Fabric control plane pod. | object | `{}` |
| `bwsGateway.podAnnotations` | Set of custom annotations for the BWS Gateway Fabric pods. | object | `{}` |
| `bwsGateway.priorityClassName` | The priority class name for the BWS Gateway Fabric control plane pod. | string | `""` |
| `bwsGateway.productTelemetry.enable` | Enable the collection of product telemetry. | bool | `false` |
| `bwsGateway.readinessProbe.enable` | Enable the /readyz endpoint on the control plane. | bool | `true` |
| `bwsGateway.readinessProbe.failureThreshold` | The number of retries after a failed probe before marking the container as Unready. | int | `3` |
| `bwsGateway.readinessProbe.initialDelaySeconds` | The number of seconds after the Pod has started before the readiness probes are initiated. | int | `3` |
| `bwsGateway.readinessProbe.periodSeconds` | How often (in seconds) to perform the readiness probe. | int | `10` |
| `bwsGateway.readinessProbe.port` | Port in which the readiness endpoint is exposed. | int | `8081` |
| `bwsGateway.readinessProbe.successThreshold` | Minimum consecutive successes for the probe to be considered successful after having failed. | int | `1` |
| `bwsGateway.readinessProbe.timeoutSeconds` | Number of seconds after which the probe times out. | int | `1` |
| `bwsGateway.replicas` | The number of replicas of the BWS Gateway Fabric Deployment. This value is ignored if autoscaling.enable is true. | int | `1` |
| `bwsGateway.resources` | The resource requests and/or limits of the bws-gateway container. | object | `{}` |
| `bwsGateway.service` | The service configuration for the BWS Gateway Fabric control plane. | object | `{"annotations":{},"labels":{}}` |
| `bwsGateway.service.annotations` | The annotations of the BWS Gateway Fabric control plane service. | object | `{}` |
| `bwsGateway.service.labels` | The labels of the BWS Gateway Fabric control plane service. | object | `{}` |
| `bwsGateway.serviceAccount` | The serviceaccount configuration for the BWS Gateway Fabric control plane. | object | `{"annotations":{},"imagePullSecret":"","imagePullSecrets":[],"name":""}` |
| `bwsGateway.serviceAccount.annotations` | Set of custom annotations for the BWS Gateway Fabric control plane service account. | object | `{}` |
| `bwsGateway.serviceAccount.imagePullSecret` | The name of the secret containing docker registry credentials for the control plane. Secret must exist in the same namespace as the helm release. | string | `""` |
| `bwsGateway.serviceAccount.imagePullSecrets` | A list of secret names containing docker registry credentials for the control plane. Secrets must exist in the same namespace as the helm release. | list | `[]` |
| `bwsGateway.serviceAccount.name` | The name of the service account of the BWS Gateway Fabric control plane pods. Used for RBAC. | string | Autogenerated if not set or set to "" |
| `bwsGateway.snippets.enable` | Enable Snippets feature through SnippetsFilter and SnippetsPolicy APIs. SnippetsFilters allow inserting NGINX configuration into the generated NGINX config for HTTPRoute and GRPCRoute resources. SnippetsPolicies allow inserting NGINX configuration into the generated NGINX config for Gateway resources. | bool | `false` |
| `bwsGateway.snippetsFilters.enable` | This flag is deprecated in favor of the snippets.enable flag. The latter will enable snippets for both SnippetsFilters and SnippetsPolicies. Enable SnippetsFilters feature. SnippetsFilters allow inserting NGINX configuration into the generated NGINX config for HTTPRoute and GRPCRoute resources. | bool | `false` |
| `bwsGateway.terminationGracePeriodSeconds` | The termination grace period of the BWS Gateway Fabric control plane pod. | int | `30` |
| `bwsGateway.tolerations` | Tolerations for the BWS Gateway Fabric control plane pod. | list | `[]` |
| `bwsGateway.topologySpreadConstraints` | The topology spread constraints for the BWS Gateway Fabric control plane pod. | list | `[]` |
| `bwsGateway.watchNamespaces` | List of namespaces to watch for resources. If not set, all namespaces are watched. The controller's own namespace is always included. | list | `[]` |
| `certGenerator` | The certGenerator section contains the configuration for the cert-generator Job. | object | `{"affinity":{},"agentTLSSecretName":"agent-tls","annotations":{},"enable":true,"nodeSelector":{},"overwrite":false,"serverTLSSecretName":"server-tls","tolerations":[],"topologySpreadConstraints":[],"ttlSecondsAfterFinished":30}` |
| `certGenerator.affinity` | The affinity of the cert-generator pod. | object | `{}` |
| `certGenerator.agentTLSSecretName` | The name of the base Secret containing TLS CA, certificate, and key for the BWS Agent to securely communicate with the BWS Gateway Fabric control plane. Must exist in the same namespace that the BWS Gateway Fabric control plane is running in (default namespace: bws-gateway). | string | `"agent-tls"` |
| `certGenerator.annotations` | The annotations of the cert-generator Job. | object | `{}` |
| `certGenerator.enable` | Enable the cert-generator Job. If this is disabled, then cert-manager or some other method must be used to create the required Secrets. | bool | `true` |
| `certGenerator.nodeSelector` | The nodeSelector of the cert-generator pod. | object | `{}` |
| `certGenerator.overwrite` | Overwrite existing TLS Secrets on startup. | bool | `false` |
| `certGenerator.serverTLSSecretName` | The name of the Secret containing TLS CA, certificate, and key for the BWS Gateway Fabric control plane to securely communicate with the BWS Agent. Must exist in the same namespace that the BWS Gateway Fabric control plane is running in (default namespace: bws-gateway). | string | `"server-tls"` |
| `certGenerator.tolerations` | Tolerations for the cert-generator pod. | list | `[]` |
| `certGenerator.topologySpreadConstraints` | The topology spread constraints for the cert-generator pod. | list | `[]` |
| `certGenerator.ttlSecondsAfterFinished` | How long to wait after the cert generator job has finished before it is removed by the job controller. | int | `30` |
| `clusterDomain` | The DNS cluster domain of your Kubernetes cluster. | string | `"cluster.local"` |
| `extraObjects` | A list of extra Kubernetes manifests to deploy. Each item is a raw YAML string representing a complete Kubernetes resource. Useful for deploying additional resources (e.g. ConfigMaps, Secrets, NetworkPolicies) alongside the chart without creating a separate chart. | list | `[]` |
| `gateways` | A list of Gateway objects. View https://gateway-api.sigs.k8s.io/reference/spec/#gateway for full Gateway reference. | list | `[]` |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs](https://github.com/norwoodj/helm-docs)
