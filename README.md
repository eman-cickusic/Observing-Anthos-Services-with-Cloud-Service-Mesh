# Observing Anthos Services with Cloud Service Mesh

This repository documents my implementation of the "AHYBRID041 - Observing Anthos Services" lab where I learned to install and configure Cloud Service Mesh on Google Kubernetes Engine and use its observability features.

## Overview

Cloud Service Mesh is a managed service based on Istio that provides a framework for connecting, securing, and managing microservices. It creates a networking layer on top of Kubernetes with features like:

- Advanced load balancing
- Service-to-service authentication
- Comprehensive monitoring capabilities
- No code changes required for service integration

In this project, I explored the following features:

- Automatic ingestion of service metrics and logs for HTTP(S) traffic
- Preconfigured service dashboards
- In-depth telemetry with filtering and slicing capabilities
- Service-to-service relationship visualization
- Service-level objectives (SLOs) for monitoring service health

## Prerequisites

- Google Cloud account with billing enabled
- `gcloud` CLI installed
- `kubectl` installed
- Basic understanding of Kubernetes and microservices

## Environment Setup

```bash
# Set environment variables
CLUSTER_NAME=gke
CLUSTER_ZONE="your-zone"
CLUSTER_REGION="your-region"
PROJECT_ID="your-project-id"
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
FLEET_PROJECT_ID="${PROJECT_ID}"
IDNS="${PROJECT_ID}.svc.id.goog"
DIR_PATH=.

# Configure kubectl to manage your GKE cluster
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone $CLUSTER_ZONE --project $PROJECT_ID

# Verify cluster is running
gcloud container clusters list
```

## Implementation Steps

### 1. Enable GKE Enterprise and Register Cluster

```bash
# Enable GKE Enterprise API
gcloud services enable --project="${PROJECT_ID}" anthos.googleapis.com

# Register GKE cluster to the Fleet
gcloud container clusters update gke --enable-fleet --region "${CLUSTER_ZONE}"

# Verify registration
gcloud container fleet memberships list --project "${PROJECT_ID}"
```

### 2. Install Cloud Service Mesh

```bash
# Enable Cloud Service Mesh on the fleet project
gcloud container fleet mesh enable --project "${PROJECT_ID}"

# Enable automatic management of the control plane
gcloud container fleet mesh update \
  --management automatic \
  --memberships gke \
  --project "${PROJECT_ID}" \
  --location "$CLUSTER_REGION"

# Verify control plane status (wait until REVISION_READY)
gcloud container fleet mesh describe --project "${PROJECT_ID}"

# Enable Cloud Service Mesh to send telemetry to Cloud Trace
cat <<EOF | kubectl apply -n istio-system -f -
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: enable-cloud-trace
  namespace: istio-system
spec:
  tracing:
  - providers:
    - name: stackdriver
EOF

# Verify the config map has been enabled
kubectl get configmap
```

### 3. Configure Mesh Data Plane

```bash
# Enable Istio sidecar injection
kubectl label namespace default istio.io/rev- istio-injection=enabled --overwrite

# Enable Google to manage the data plane
kubectl annotate --overwrite namespace default \
  mesh.cloud.google.com/proxy='{"managed":"true"}'
```

### 4. Deploy the Online Boutique Application

```bash
# Deploy the application
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml
kubectl patch deployments/productcatalogservice -p '{"spec":{"template":{"metadata":{"labels":{"version":"v1"}}}}}'

# Install the ingress Gateway
git clone https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages
kubectl apply -f anthos-service-mesh-packages/samples/gateways/istio-ingressgateway

# Install required custom resource definitions
kubectl apply -k "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v0.6.0"
kubectl kustomize "https://github.com/GoogleCloudPlatform/gke-networking-recipes.git/gateway-api/config/mesh/crd" | kubectl apply -f -

# Configure the Gateway
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/istio-manifests.yaml
```

### 5. Deploy a Canary Release with High Latency

```bash
# Clone the repository with configuration files
git clone https://github.com/GoogleCloudPlatform/istio-samples.git ~/istio-samples

# Create the new destination rule
kubectl apply -f ~/istio-samples/istio-canary-gke/canary/destinationrule.yaml

# Deploy the problematic product catalog service (v2)
kubectl apply -f ~/istio-samples/istio-canary-gke/canary/productcatalog-v2.yaml

# Create a traffic split (75% v1, 25% v2)
kubectl apply -f ~/istio-samples/istio-canary-gke/canary/vs-split-traffic.yaml
```

### 6. Roll Back the Problematic Release

```bash
# Remove the destination rule
kubectl delete -f ~/istio-samples/istio-canary-gke/canary/destinationrule.yaml

# Remove the problematic product catalog service
kubectl delete -f ~/istio-samples/istio-canary-gke/canary/productcatalog-v2.yaml

# Remove the traffic split
kubectl delete -f ~/istio-samples/istio-canary-gke/canary/vs-split-traffic.yaml
```

## Observability Features Used

### Cloud Trace

Cloud Trace provides distributed tracing information that helps understand:
- How long requests take
- When requests occur
- Which services are called
- Inter-service dependencies
- Performance bottlenecks

To view traces:
1. Go to Google Cloud Console > Trace
2. Click on data points to see detailed trace information

### Service Level Objectives (SLOs)

Steps to create an SLO for the product catalog service:
1. Go to Kubernetes Engine > Features > Service Mesh
2. Click on the desired service (productcatalogservice)
3. Go to Health tab and click "+Create SLO"
4. Configure:
   - Metric: Latency
   - Evaluation method: Request-based
   - Latency threshold: 1000ms
   - Period type: Calendar
   - Period length: Calendar day
   - Performance goal: 99.5%

### Cloud Service Mesh Dashboard

The Service Mesh dashboard provides:
- Service topology visualization
- Service-to-service relationships
- Performance metrics
- SLO compliance monitoring
- Traffic flow visualization

## Key Learnings

- Cloud Service Mesh automatically collects information about network calls within the mesh
- Trace data documents time spent on calls without requiring extra developer effort
- SLOs help define performance expectations and monitor compliance
- The topology view helps understand service dependencies
- Canary deployments can be easily implemented and rolled back when issues are detected

## Additional Resources

- [Cloud Service Mesh Documentation](https://cloud.google.com/service-mesh/docs)
- [Online Boutique Demo Application](https://github.com/GoogleCloudPlatform/microservices-demo)
- [Cloud Trace Documentation](https://cloud.google.com/trace/docs)
- [Istio Documentation](https://istio.io/docs)
