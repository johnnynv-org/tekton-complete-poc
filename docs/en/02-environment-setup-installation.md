# 02 - Environment Setup and Installation

This document provides detailed instructions for setting up the complete CI/CD environment from scratch, including Kubernetes cluster, Tekton components, and GitHub Runner configuration.

## Environment Requirements

### Infrastructure
- **Kubernetes Cluster**: Single-node or multi-node, version >=1.24
- **Network Environment**: Cluster nodes can access GitHub.com
- **Storage**: Support for dynamic PV provisioning
- **Self-hosted Machine**: Machine that can access Kubernetes cluster internal network for GitHub Runner

### Tools Required
- kubectl (version matching Kubernetes)
- curl
- git

## Step 1: Kubernetes Cluster Preparation

### 1.1 Verify Cluster Status

Execute in k8s environment:

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes
kubectl version
```

Expected output example:
```
Kubernetes control plane is running at https://10.117.3.193:6443
NAME        STATUS   ROLES           AGE     VERSION
ipp1-1877   Ready    control-plane   3h25m   v1.30.14
```

### 1.2 Check Required Components

```bash
# Check storage class
kubectl get storageclass

# Check ingress controller
kubectl get pods -n ingress-nginx
```

If ingress-nginx is not present, install it first.

## Step 2: Install Tekton Components

### 2.1 Install Tekton Pipelines

```bash
# Install core Pipeline components
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for components to start
kubectl get pods -n tekton-pipelines
```

### 2.2 Install Tekton Triggers

```bash
# Install Triggers components
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

# Install Core Interceptors (Important! EventListener needs these components)
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

# Verify installation
kubectl get pods -n tekton-pipelines | grep trigger
kubectl get pods -n tekton-pipelines | grep interceptor
kubectl get clusterinterceptor
```

**Expected output:**
```
tekton-triggers-controller-xxx                 1/1     Running
tekton-triggers-webhook-xxx                    1/1     Running  
tekton-triggers-core-interceptors-xxx          1/1     Running

NAME        AGE
bitbucket   1m
cel         1m  
github      1m
gitlab      1m
slack       1m
```

### 2.3 Install Tekton Dashboard

```bash
# Install Dashboard
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Check Dashboard pod
kubectl get pods -n tekton-pipelines | grep dashboard
```

### 2.4 Configure Dashboard Access

Get current IP address:
```bash
hostname -I | awk '{print $1}'
```

Create Ingress configuration file `tekton-dashboard-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tekton-dashboard
  namespace: tekton-pipelines
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: tekton.<your-IP>.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tekton-dashboard
            port:
              number: 9097
```

Apply configuration:
```bash
kubectl apply -f tekton-dashboard-ingress.yaml
```

### 2.5 Verify Tekton Installation

```bash
# Check all component status
kubectl get pods -n tekton-pipelines
kubectl get pods -n tekton-pipelines-resolvers

# Test Dashboard access
curl -s -o /dev/null -w "%{http_code}\n" http://tekton.<your-IP>.nip.io
```

Expected: All pods in Running state, Dashboard returns HTTP 200.

## Step 3: Configure GitHub Runner

### 3.1 Runner Machine Requirements

**Important:** Runner machine must be able to access Kubernetes cluster internal network services.

### 3.2 Install kubectl

Execute on Runner machine:

```bash
# Download kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Set permissions and install
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify installation
kubectl version --client
```

### 3.3 Configure kubectl Access

Get configuration in k8s environment:
```bash
kubectl config view --raw --flatten > /tmp/kubeconfig-for-runner
```

Copy configuration to Runner machine:
```bash
# Execute on Runner machine
mkdir -p ~/.kube

# Copy kubeconfig (using scp or manual copy)
scp root@<k8s-ip>:/tmp/kubeconfig-for-runner ~/.kube/config
chmod 600 ~/.kube/config

# Test connection
kubectl get nodes
kubectl get pods -n tekton-pipelines
```

### 3.4 Register GitHub Runner

1. In GitHub repository: `Settings` → `Actions` → `Runners` → `New self-hosted runner`
2. Select Linux x64 platform
3. Follow the page instructions to execute installation commands on Runner machine
4. Configure Runner name as: `swqa-gh-runner-poc`
5. Start Runner service

Verify Runner status:
```bash
# Check Runner service
sudo systemctl status actions.runner.*

# Or check GitHub page to confirm Runner is online
```

## Step 4: Test Environment Connectivity

### 4.1 Network Connectivity Test

Test on Runner machine:

```bash
# Test DNS resolution
nslookup el-github-listener.tekton-pipelines.svc.cluster.local

# Test basic network connectivity (test after configuring EventListener)
# curl -v http://el-github-listener.tekton-pipelines.svc.cluster.local:8080
```

### 4.2 Permissions Test

Test on Runner machine:

```bash
# Test k8s access permissions
kubectl get namespaces
kubectl get pods -n tekton-pipelines

# Test resource creation permissions (for EventListener deployment)
kubectl auth can-i create eventlisteners --namespace=tekton-pipelines
kubectl auth can-i create triggerbindings --namespace=tekton-pipelines
```

## Step 5: Deploy Project Infrastructure

### 5.1 Directory Structure Overview

This project uses layered configuration management:

```
.tekton/
├── infrastructure/           # Infrastructure layer (one-time deployment)
│   ├── rbac.yaml            # Permission configuration
│   ├── eventlistener.yaml   # Event listener
│   ├── triggerbinding.yaml  # Parameter binding
│   ├── triggertemplate.yaml # Trigger template
│   └── eventlistener-nodeport.yaml # NodePort service
└── pipelines/               # Business logic layer (versioned deployment)
    ├── task-pytest.yaml    # Task definition
    ├── pipeline.yaml       # Pipeline definition
    └── pipelinerun.yaml    # Example run (for manual testing)
```

**Design Philosophy:**
- **Infrastructure Layer**: One-time deployment by Ops team, shared across projects
- **Business Logic Layer**: Automatically deployed by GitHub Actions, evolves with code versions

### 5.2 Deploy Infrastructure

Execute in k8s environment:

```bash
# 1. First configure Namespace security policy (Important!)
kubectl apply -f .tekton/infrastructure/namespace-security-policy.yaml

# 2. Apply RBAC configuration
kubectl apply -f .tekton/infrastructure/rbac.yaml

# 3. Apply TriggerBinding
kubectl apply -f .tekton/infrastructure/triggerbinding.yaml

# 4. Apply TriggerTemplate  
kubectl apply -f .tekton/infrastructure/triggertemplate.yaml

# 5. Apply EventListener
kubectl apply -f .tekton/infrastructure/eventlistener.yaml

# 6. Apply NodePort Service (resolve network connectivity)
kubectl apply -f .tekton/infrastructure/eventlistener-nodeport.yaml
```

**Important Security Notes:**
- Tekton Pipelines requires privileged Pod Security Policy to function properly
- This is due to architectural requirements of Tekton internal containers (prepare, place-scripts, etc.)
- User-defined Pipeline steps still use restricted security contexts

### 5.3 Verify Infrastructure Deployment

```bash
# Check EventListener deployment status
kubectl get eventlistener -n tekton-pipelines

# Check EventListener Pod
kubectl get pods -l eventlistener=github-listener -n tekton-pipelines

# Check Service creation
kubectl get svc -l eventlistener=github-listener -n tekton-pipelines

# Wait for Pod Ready
kubectl wait --for=condition=Ready pod -l eventlistener=github-listener -n tekton-pipelines --timeout=60s
```

### 5.4 Resolve Network Connectivity Issues

**Background:** Runner machines typically cannot directly access Kubernetes Service CIDR network, requiring NodePort Service to solve network routing issues.

**Create NodePort Service:**

```bash
# Create NodePort Service configuration
cat > .tekton/infrastructure/eventlistener-nodeport.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: el-github-listener-nodeport
  namespace: tekton-pipelines
  labels:
    app: eventlistener-nodeport
spec:
  type: NodePort
  selector:
    eventlistener: github-listener
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30080
      protocol: TCP
      name: http-listener
EOF

# Apply NodePort Service
kubectl apply -f .tekton/infrastructure/eventlistener-nodeport.yaml

# Verify NodePort Service
kubectl get svc -n tekton-pipelines | grep nodeport
```

**Expected output:**
```
el-github-listener-nodeport         NodePort    10.96.97.5       <none>        8080:30080/TCP
```

### 5.5 Test EventListener Connectivity

Test in k8s environment (using ClusterIP):

```bash
# Get EventListener Service ClusterIP
SERVICE_IP=$(kubectl get svc el-github-listener -n tekton-pipelines -o jsonpath='{.spec.clusterIP}')
echo "EventListener Service IP: $SERVICE_IP"

# Send test request
curl -v -X POST http://$SERVICE_IP:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "test connectivity"}'
```

Test on Runner machine (using NodePort):

```bash
# Get cluster node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Test Runner to EventListener connectivity (using NodePort)
curl -v http://$NODE_IP:30080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "nodeport test from runner"}'
```

**Expected success output:**
```
< HTTP/1.1 202 Accepted
< Content-Type: application/json
{"eventListener":"github-listener","namespace":"tekton-pipelines",...}
```

## Environment Verification Checklist

After installation completion, confirm the following items:

- [ ] Kubernetes cluster running normally
- [ ] All Tekton Pipelines components Running
- [ ] All Tekton Triggers components Running  
- [ ] Tekton Dashboard accessible
- [ ] GitHub Runner online and connected
- [ ] Runner can access k8s cluster
- [ ] kubectl works normally on Runner
- [ ] NodePort connectivity test successful

## Troubleshooting

### Tekton Component Startup Failure

```bash
# View specific errors
kubectl describe pod <pod-name> -n tekton-pipelines
kubectl logs <pod-name> -n tekton-pipelines
```

### Runner Connection Issues

```bash
# Check Runner logs
sudo journalctl -u actions.runner.* -f

# Check network connection
ping <k8s-cluster-ip>
telnet <k8s-cluster-ip> 6443
```

### Dashboard Access Issues

```bash
# Check ingress status
kubectl get ingress -n tekton-pipelines
kubectl describe ingress tekton-dashboard -n tekton-pipelines

# Check Service
kubectl get svc tekton-dashboard -n tekton-pipelines
```

## Next Steps

After environment preparation is complete, continue with:
- [03 - Tekton Triggers Configuration](./03-tekton-triggers-configuration.md)
