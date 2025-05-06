#!/bin/bash
# Script to deploy and manage a canary release with high latency for testing

set -e

# Function to show usage
show_usage() {
  echo "Usage: $0 [deploy|rollback]"
  echo "  deploy   - Deploy the canary release with high latency"
  echo "  rollback - Roll back the canary release"
  exit 1
}

# Check if istio-samples is already cloned
if [ ! -d ~/istio-samples ]; then
  echo "Cloning istio-samples repository..."
  git clone https://github.com/GoogleCloudPlatform/istio-samples.git ~/istio-samples
fi

# Process command-line arguments
if [ $# -ne 1 ]; then
  show_usage
fi

case "$1" in
  deploy)
    echo "Deploying canary release with high latency..."
    
    # Create the new destination rule
    echo "Creating destination rule..."
    kubectl apply -f ~/istio-samples/istio-canary-gke/canary/destinationrule.yaml
    
    # Deploy the problematic product catalog service (v2)
    echo "Deploying product catalog service v2 with high latency..."
    kubectl apply -f ~/istio-samples/istio-canary-gke/canary/productcatalog-v2.yaml
    
    # Create a traffic split (75% v1, 25% v2)
    echo "Creating traffic split (75% v1, 25% v2)..."
    kubectl apply -f ~/istio-samples/istio-canary-gke/canary/vs-split-traffic.yaml
    
    echo "Canary deployment completed!"
    echo "Wait for a few minutes, then check SLOs in the Cloud Service Mesh dashboard"
    echo "To roll back the canary release, run: $0 rollback"
    ;;
    
  rollback)
    echo "Rolling back canary release..."
    
    # Remove the traffic split
    echo "Removing traffic split..."
    kubectl delete -f ~/istio-samples/istio-canary-gke/canary/vs-split-traffic.yaml
    
    # Remove the problematic product catalog service
    echo "Removing product catalog service v2..."
    kubectl delete -f ~/istio-samples/istio-canary-gke/canary/productcatalog-v2.yaml
    
    # Remove the destination rule
    echo "Removing destination rule..."
    kubectl delete -f ~/istio-samples/istio-canary-gke/canary/destinationrule.yaml
    
    echo "Rollback completed!"
    echo "Wait for a few minutes, then check SLOs in the Cloud Service Mesh dashboard to see the improvement"
    ;;
    
  *)
    show_usage
    ;;
esac