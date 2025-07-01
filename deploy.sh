#!/bin/bash

# LLM Benchmark Arena - OpenShift Deployment Script
# This script deploys the complete LLM benchmark application to OpenShift

set -e

# Configuration
NAMESPACE="llm-benchmark"
REGISTRY="image-registry.openshift-image-registry.svc:5000"
CLUSTER_DOMAIN=""  # Will be detected automatically

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if OpenShift CLI is available
check_oc_cli() {
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) is not installed or not in PATH"
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster"
        print_status "Please run: oc login <your-cluster-url>"
        exit 1
    fi
    
    print_status "OpenShift CLI is available and logged in as: $(oc whoami)"
}

# Function to detect cluster domain
detect_cluster_domain() {
    CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
    if [ -z "$CLUSTER_DOMAIN" ]; then
        print_error "Could not detect cluster domain"
        exit 1
    fi
    print_status "Detected cluster domain: $CLUSTER_DOMAIN"
}

# Function to check if cluster has GPU nodes
check_gpu_nodes() {
    GPU_NODES=$(oc get nodes -l nvidia.com/gpu=true --no-headers 2>/dev/null | wc -l)
    if [ "$GPU_NODES" -eq 0 ]; then
        print_warning "No GPU-enabled nodes found in cluster"
        print_warning "GPU monitoring and vLLM deployments may not work properly"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_status "Found $GPU_NODES GPU-enabled nodes"
    fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
    if oc get namespace $NAMESPACE &> /dev/null; then
        print_status "Namespace $NAMESPACE already exists"
    else
        print_status "Creating namespace $NAMESPACE"
        oc apply -f openshift/namespace.yaml
    fi
}

# Function to update URLs in configuration
update_config() {
    print_status "Updating configuration with cluster domain: $CLUSTER_DOMAIN"
    
    # Update ConfigMap with actual cluster domain
    sed -i.bak "s/your-cluster\.com/$CLUSTER_DOMAIN/g" openshift/configmap.yaml
    
    # Update JavaScript with service URLs for internal communication
    BASELINE_SERVICE_URL="http://llm-benchmark-vllm-baseline-service.${NAMESPACE}.svc.cluster.local:9000/v1"
    QUANTIZED_SERVICE_URL="http://llm-benchmark-vllm-quantized-service.${NAMESPACE}.svc.cluster.local:9001/v1"
    GPU_MONITOR_SERVICE_URL="http://llm-benchmark-gpu-monitor-service.${NAMESPACE}.svc.cluster.local:8080"
    
    # Create a configmap for frontend configuration
    cat > openshift/frontend-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
  namespace: ${NAMESPACE}
data:
  config.js: |
    window.CONFIG = {
      BASELINE_URL: "${BASELINE_SERVICE_URL}",
      QUANTIZED_URL: "${QUANTIZED_SERVICE_URL}",
      GPU_MONITOR_URL: "${GPU_MONITOR_SERVICE_URL}"
    };
EOF
}

# Function to deploy all components
deploy_components() {
    print_status "Deploying configuration and secrets..."
    oc apply -f openshift/configmap.yaml
    oc apply -f openshift/frontend-config.yaml
    
    print_status "Setting up build configurations..."
    oc apply -f openshift/buildconfig.yaml
    
    print_status "Starting builds..."
    # Trigger builds if they don't exist
    if ! oc get build -l buildconfig=llm-benchmark-frontend-build -n $NAMESPACE &> /dev/null; then
        oc start-build llm-benchmark-frontend-build -n $NAMESPACE
    fi
    
    if ! oc get build -l buildconfig=llm-benchmark-gpu-monitor-build -n $NAMESPACE &> /dev/null; then
        oc start-build llm-benchmark-gpu-monitor-build -n $NAMESPACE
    fi
    
    print_status "Waiting for builds to complete..."
    oc wait --for=condition=Complete build -l buildconfig=llm-benchmark-frontend-build -n $NAMESPACE --timeout=600s
    oc wait --for=condition=Complete build -l buildconfig=llm-benchmark-gpu-monitor-build -n $NAMESPACE --timeout=600s
    
    print_status "Deploying frontend..."
    oc apply -f openshift/frontend-deployment.yaml
    
    print_status "Deploying GPU monitor..."
    oc apply -f openshift/gpu-monitor-deployment.yaml
    
    print_status "Deploying vLLM services..."
    oc apply -f openshift/vllm-deployment.yaml
}

# Function to wait for deployments to be ready
wait_for_deployments() {
    print_status "Waiting for deployments to be ready..."
    
    oc wait --for=condition=Available deployment/llm-benchmark-frontend -n $NAMESPACE --timeout=300s
    oc wait --for=condition=Available deployment/llm-benchmark-gpu-monitor -n $NAMESPACE --timeout=300s
    
    print_status "Waiting for vLLM services (this may take several minutes)..."
    oc wait --for=condition=Available deployment/llm-benchmark-vllm-baseline -n $NAMESPACE --timeout=1200s
    oc wait --for=condition=Available deployment/llm-benchmark-vllm-quantized -n $NAMESPACE --timeout=1200s
}

# Function to display access information
display_access_info() {
    print_status "Deployment completed successfully!"
    echo
    echo "Access URLs:"
    echo "============"
    
    FRONTEND_URL=$(oc get route llm-benchmark-frontend-route -n $NAMESPACE -o jsonpath='{.spec.host}')
    GPU_MONITOR_URL=$(oc get route llm-benchmark-gpu-monitor-route -n $NAMESPACE -o jsonpath='{.spec.host}')
    BASELINE_URL=$(oc get route llm-benchmark-vllm-baseline-route -n $NAMESPACE -o jsonpath='{.spec.host}')
    QUANTIZED_URL=$(oc get route llm-benchmark-vllm-quantized-route -n $NAMESPACE -o jsonpath='{.spec.host}')
    
    echo "Frontend:       https://$FRONTEND_URL"
    echo "GPU Monitor:    https://$GPU_MONITOR_URL"
    echo "Baseline vLLM:  https://$BASELINE_URL"
    echo "Quantized vLLM: https://$QUANTIZED_URL"
    echo
    echo "Configuration:"
    echo "============="
    echo "In the web UI, use these URLs:"
    echo "Baseline URL:  https://$BASELINE_URL/v1"
    echo "Quantized URL: https://$QUANTIZED_URL/v1"
}

# Function to show deployment status
show_status() {
    echo
    print_status "Deployment Status:"
    echo "=================="
    oc get pods -n $NAMESPACE
    echo
    oc get routes -n $NAMESPACE
}

# Function to clean up deployment
cleanup() {
    print_warning "This will delete the entire $NAMESPACE namespace and all resources"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleaning up deployment..."
        oc delete namespace $NAMESPACE
        print_status "Cleanup completed"
    fi
}

# Main execution
main() {
    case "${1:-deploy}" in
        "deploy")
            print_status "Starting LLM Benchmark Arena deployment to OpenShift..."
            check_oc_cli
            detect_cluster_domain
            check_gpu_nodes
            create_namespace
            update_config
            deploy_components
            wait_for_deployments
            display_access_info
            show_status
            ;;
        "status")
            show_status
            ;;
        "cleanup")
            cleanup
            ;;
        "help")
            echo "Usage: $0 [deploy|status|cleanup|help]"
            echo "  deploy  - Deploy the application (default)"
            echo "  status  - Show deployment status"
            echo "  cleanup - Remove the deployment"
            echo "  help    - Show this help message"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 