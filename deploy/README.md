# Deployment manifests

This directory contains the Kubernetes manifests for deploying BWS Gateway Fabric in a Kubernetes cluster. They are generated from the Helm Chart [examples](../examples/helm/).

They are a single file deployment manifest that can be applied to a Kubernetes cluster using `kubectl apply -f <file>`. You should have the Gateway API CRDs and the BWS Gateway Fabric CRDs deployed before applying these manifests.
The BWS Gateway Fabric CRDs can be found in this directory as a single file deployment manifest [crds.yaml](./crds.yaml).

To deploy the manifests using a different registry or tag, you can modify the `kustomization.yaml` file with the desired values and
use the following command to apply the manifests:

```shell
kubectl kustomize | kubectl apply -f -
```

Use the BWS Gateway Fabric installation guide for product deployment instructions and the Gateway API documentation for the standard CRDs.
