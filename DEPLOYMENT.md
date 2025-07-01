# OpenShift Deployment Guide

This guide explains how to deploy the LLM Benchmark Arena application to an OpenShift cluster with GPU support.

## Prerequisites

### 1. OpenShift Cluster Requirements
- OpenShift 4.12+ cluster with GPU-enabled nodes
- NVIDIA GPU Operator installed and configured
- Cluster administrator access or sufficient permissions to:
  - Create namespaces/projects
  - Deploy applications with GPU resources
  - Create routes and services

### 2. Local Environment
- OpenShift CLI (`oc`) installed and configured
- Git access to your repository
- Bash shell (Linux/macOS/WSL)

### 3. GPU Node Configuration
Your cluster nodes should have:
- NVIDIA GPUs with proper drivers
- GPU Operator deployed
- Nodes labeled with `nvidia.com/gpu=true`

## Quick Deployment

### 1. Clone and Prepare
```bash
git clone <your-repo-url>
cd benchmark-arena
chmod +x deploy.sh
```

### 2. Login to OpenShift
```bash
oc login <your-cluster-api-url>
```

### 3. Deploy Application
```bash
./deploy.sh deploy
```

The script will:
- ✅ Check prerequisites
- ✅ Create namespace and resources
- ✅ Build container images
- ✅ Deploy all components
- ✅ Configure networking
- ✅ Provide access URLs

## Manual Deployment Steps

If you prefer manual deployment or need to customize the process:

### 1. Create Namespace
```bash
oc apply -f openshift/namespace.yaml
```

### 2. Configure Secrets (if needed)
```bash
# If you need HuggingFace token for model access
oc create secret generic huggingface-token \
  --from-literal=token=your_token_here \
  -n llm-benchmark
```

### 3. Deploy Build Configurations
```bash
oc apply -f openshift/buildconfig.yaml
```

### 4. Start Builds
```bash
oc start-build llm-benchmark-frontend-build -n llm-benchmark
oc start-build llm-benchmark-gpu-monitor-build -n llm-benchmark
```

### 5. Deploy Applications
```bash
# Deploy configuration
oc apply -f openshift/configmap.yaml

# Deploy frontend
oc apply -f openshift/frontend-deployment.yaml

# Deploy GPU monitor
oc apply -f openshift/gpu-monitor-deployment.yaml

# Deploy vLLM services
oc apply -f openshift/vllm-deployment.yaml
```

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │  GPU Monitor    │    │   vLLM Models   │
│   (Nginx)       │    │   (Python)      │    │   (Baseline +   │
│                 │    │                 │    │   Quantized)    │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ Pod: 2 replicas │    │ Pod: 1 replica  │    │ Pod: 1 each     │
│ CPU: 50m-100m   │    │ CPU: 100m-500m  │    │ GPU: 1 each     │
│ RAM: 64Mi-128Mi │    │ RAM: 128Mi-512Mi│    │ RAM: 6-16Gi     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │  OpenShift      │
                    │  Routes         │
                    │  (External      │
                    │   Access)       │
                    └─────────────────┘
```

## Configuration

### Environment Variables

The application uses these configuration sources:

1. **ConfigMap** (`llm-benchmark-config`):
   - Model URLs
   - GPU monitoring settings
   - Cost calculation parameters

2. **Secret** (`huggingface-token`):
   - HuggingFace API token (if required)

### Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | GPU |
|-----------|-------------|-----------|----------------|--------------|-----|
| Frontend | 50m | 100m | 64Mi | 128Mi | 0 |
| GPU Monitor | 100m | 500m | 128Mi | 512Mi | 0* |
| vLLM Baseline | 2 | 4 | 8Gi | 16Gi | 1 |
| vLLM Quantized | 2 | 4 | 6Gi | 12Gi | 1 |

*GPU Monitor needs access to GPU devices but doesn't consume GPU resources

## GPU Access Configuration

The GPU monitor requires special configuration to access NVIDIA GPUs:

```yaml
# Host path mounts for GPU device access
volumeMounts:
- name: nvidia-dev
  mountPath: /dev/nvidia0
- name: nvidia-ml
  mountPath: /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1

# Security context for GPU access
securityContext:
  capabilities:
    add:
    - SYS_ADMIN
```

## Networking

### Internal Communication
- Frontend ↔ GPU Monitor: `http://llm-benchmark-gpu-monitor-service:8080`
- Frontend ↔ vLLM Services: `http://llm-benchmark-vllm-*-service:900[0,1]`

### External Access
- Frontend: `https://frontend-route.apps.cluster.domain`
- GPU Monitor API: `https://gpu-monitor-route.apps.cluster.domain`
- vLLM APIs: `https://vllm-*-route.apps.cluster.domain`

## Troubleshooting

### Common Issues

#### 1. GPU Nodes Not Found
```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu=true

# If empty, ensure GPU Operator is installed
oc get pods -n nvidia-gpu-operator
```

#### 2. Build Failures
```bash
# Check build logs
oc logs -f bc/llm-benchmark-frontend-build -n llm-benchmark

# Restart build if needed
oc start-build llm-benchmark-frontend-build -n llm-benchmark
```

#### 3. Pod Scheduling Issues
```bash
# Check pod events
oc describe pod <pod-name> -n llm-benchmark

# Check resource availability
oc describe nodes
```

#### 4. GPU Access Problems
```bash
# Check GPU operator status
oc get pods -n nvidia-gpu-operator

# Verify GPU resources
oc describe node <gpu-node-name>
```

### Logs and Monitoring

```bash
# View application logs
oc logs -f deployment/llm-benchmark-frontend -n llm-benchmark
oc logs -f deployment/llm-benchmark-gpu-monitor -n llm-benchmark
oc logs -f deployment/llm-benchmark-vllm-baseline -n llm-benchmark

# Check resource usage
oc top pods -n llm-benchmark
oc top nodes

# Monitor GPU usage
oc exec -it deployment/llm-benchmark-gpu-monitor -n llm-benchmark -- nvidia-smi
```

## Scaling and Performance

### Horizontal Scaling
```bash
# Scale frontend replicas
oc scale deployment/llm-benchmark-frontend --replicas=3 -n llm-benchmark

# Scale is limited for GPU components due to GPU resource constraints
```

### Resource Optimization
```bash
# Update resource limits
oc patch deployment/llm-benchmark-frontend -n llm-benchmark -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "frontend",
          "resources": {
            "requests": {"cpu": "100m", "memory": "128Mi"},
            "limits": {"cpu": "200m", "memory": "256Mi"}
          }
        }]
      }
    }
  }
}'
```

## Security Considerations

### 1. Network Policies
Consider implementing network policies to restrict traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: llm-benchmark-network-policy
  namespace: llm-benchmark
spec:
  podSelector:
    matchLabels:
      app: llm-benchmark
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: openshift-ingress
```

### 2. Security Context Constraints
The GPU monitor requires elevated privileges. Ensure proper SCCs:

```bash
# Create custom SCC if needed
oc adm policy add-scc-to-user privileged -z default -n llm-benchmark
```

### 3. Secrets Management
- Store sensitive data in OpenShift secrets
- Use service accounts with minimal required permissions
- Regularly rotate API tokens

## Backup and Disaster Recovery

### Configuration Backup
```bash
# Export all resources
oc get all,configmap,secret,route -n llm-benchmark -o yaml > backup.yaml

# Backup specific configurations
oc get configmap llm-benchmark-config -n llm-benchmark -o yaml > config-backup.yaml
```

### Restore Process
```bash
# Apply backed up resources
oc apply -f backup.yaml
```

## Maintenance

### Updates
```bash
# Update application
./deploy.sh deploy  # Re-run deployment script

# Or update specific components
oc rollout restart deployment/llm-benchmark-frontend -n llm-benchmark
```

### Cleanup
```bash
# Remove entire deployment
./deploy.sh cleanup

# Or manually
oc delete namespace llm-benchmark
```

## Support and Monitoring

### Health Checks
- Frontend: `GET /`
- GPU Monitor: `GET /health`
- vLLM Services: `GET /health`

### Metrics Collection
Consider integrating with OpenShift monitoring:
- Prometheus metrics
- Grafana dashboards
- Alert manager rules

For additional support, check the application logs and OpenShift cluster events. 