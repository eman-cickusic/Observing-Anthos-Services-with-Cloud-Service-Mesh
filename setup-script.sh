#!/bin/bash
# Setup script for Cloud Service Mesh on GKE

# Exit on error
set -e

# Check if required tools are installed
command -v gcloud >/dev/null 2>&1 || { echo "gcloud is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting."; exit 1; }

# Input parameters
read -p "Enter your GCP Project ID: " PROJECT_ID
read -p "Enter your GKE cluster name [gke]: " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-gke}
read -p "Enter your GKE cluster zone: " CLUSTER_ZONE
read -p "Enter your GKE cluster region: " CLUSTER_REGION

# Set environment variables
echo "Setting up environment variables..."
export CLUSTER_NAME=$CLUSTER_NAME
export CLUSTER_ZONE=$CLUSTER_ZONE
export CLUSTER_REGION=$CLUSTER_REGION
export PROJECT_ID=$PROJECT_ID
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
export FLEET_PROJECT_ID="${PROJECT_ID}"
export IDNS="${PROJECT_ID}.svc.id.goog"
export DIR_PATH=.

# Verify variables
echo -e "\nVerifying environment variables:"
echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "CLUSTER_ZONE: $CLUSTER_ZONE"
echo "CLUSTER_REGION: $CLUSTER_REGION"
echo "PROJECT_ID: $PROJECT_ID"
echo "PROJECT_NUMBER: $PROJECT_NUMBER"
echo "FLEET PROJECT_ID: $FLEET_PROJECT_ID"
echo "IDNS: $IDNS"
echo -e "DIR_PATH: $DIR_PATH\n"

# Configure kubectl
echo "Configuring kubectl to manage your GKE cluster..."
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone $CLUSTER_ZONE --project $PROJECT_ID

# Check cluster status
echo "Checking cluster status..."
gcloud container clusters list

# Enable GKE Enterprise API
echo "Enabling GKE Enterprise API..."
gcloud services enable --project="${PROJECT_ID}" anthos.googleapis.com

# Register GKE cluster to the Fleet
echo "Registering GKE cluster to the Fleet..."
gcloud container clusters update $CLUSTER_NAME --enable-fleet --region "${CLUSTER_ZONE}"

# Verify registration
echo "Verifying registration..."
gcloud container fleet memberships list --project "${PROJECT_ID}"

# Enable Cloud Service Mesh
echo "Enabling Cloud Service Mesh on the fleet project..."
gcloud container fleet mesh enable --project "${PROJECT_ID}"

# Enable automatic management of the control plane
echo "Enabling automatic management of the control plane..."
gcloud container fleet mesh update \
  --management automatic \
  --memberships $CLUSTER_NAME \
  --project "${PROJECT_ID}" \
  --location "$CLUSTER_REGION"

# Wait for control plane to be ready
echo "Waiting for control plane to be ready (this might take several minutes)..."
while true; do
  STATUS=$(gcloud container fleet mesh describe --project "${PROJECT_ID}" --format="value(membershipStates.*.servicemesh.controlPlaneManagement.state)")
  if [[ "$STATUS" == "ACTIVE" ]]; then
    echo "Control plane is ready!"
    break
  fi
  echo "Control plane status: $STATUS. Checking again in 30 seconds..."
  sleep 30
done

# Enable Cloud Service Mesh to send telemetry to Cloud Trace
echo "Enabling Cloud Service Mesh to send telemetry to Cloud Trace..."
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

# Configure mesh data plane
echo "Configuring mesh data plane..."
kubectl label namespace default istio.io/rev- istio-injection=enabled --overwrite
kubectl annotate --overwrite namespace default mesh.cloud.google.com/proxy='{"managed":"true"}'

# Deploy Online Boutique application
echo "Deploying Online Boutique application..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/kubernetes-manifests.yaml
kubectl patch deployments/productcatalogservice -p '{"spec":{"template":{"metadata":{"labels":{"version":"v1"}}}}}'

# Install ingress Gateway
echo "Installing ingress Gateway..."
git clone https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages
kubectl apply -f anthos-service-mesh-packages/samples/gateways/istio-ingressgateway

# Install required custom resource definitions
echo "Installing required custom resource definitions..."
kubectl apply -k "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v0.6.0"
kubectl kustomize "https://github.com/GoogleCloudPlatform/gke-networking-recipes.git/gateway-api/config/mesh/crd" | kubectl apply -f -

# Configure Gateway
echo "Configuring Gateway..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/master/release/istio-manifests.yaml

# Get the external IP address
echo "Waiting for external IP address to be assigned..."
while true; do
  EXTERNAL_IP=$(kubectl get service frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  if [[ -n "$EXTERNAL_IP" ]]; then
    echo "External IP assigned: $EXTERNAL_IP"
    break
  fi
  echo "Waiting for external IP to be assigned... Checking again in 10 seconds."
  sleep 10
done

echo -e "\nSetup completed successfully!"
echo "Access the Online Boutique application at: http://$EXTERNAL_IP"
echo "To deploy a canary release with high latency for testing, run: ./deploy-canary.sh"