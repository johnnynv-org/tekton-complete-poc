# 06 - Troubleshooting Guide

This document records common issue diagnosis and resolution methods, based on problems encountered during actual deployment.

## Network Connectivity Issues

### Issue: DNS Resolution Failed

**Symptoms:**
```bash
curl: (6) Could not resolve host: el-github-listener.tekton-pipelines.svc.cluster.local
```

**Diagnosis Steps:**

1. **Verify EventListener Service Status**
```bash
kubectl get svc el-github-listener -n tekton-pipelines
kubectl get endpoints el-github-listener -n tekton-pipelines
```

2. **Test DNS Resolution**
```bash
# Test on Runner machine
nslookup el-github-listener.tekton-pipelines.svc.cluster.local
```

**Solution:**
Use ClusterIP instead of DNS name:
```bash
CLUSTER_IP=$(kubectl get svc el-github-listener -n tekton-pipelines -o jsonpath='{.spec.clusterIP}')
curl -v http://$CLUSTER_IP:8080
```

### Issue: ClusterIP Network Unreachable (Production Environment Common)

**Symptoms:**
```bash
# ✅ Can ping cluster node
ping 10.117.3.193  # Success

# ❌ Cannot access ClusterIP (100% packet loss)
ping 10.109.72.223  # Failed
curl: (7) Failed to connect to 10.109.72.223 port 8080: Connection timeout
```

**Root Cause:** 
Runner machine cannot directly route to Kubernetes Service CIDR network segment (10.96.0.0/12).

**Complete Solution: Use NodePort Service**

1. **Create NodePort Service**
```bash
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

kubectl apply -f .tekton/infrastructure/eventlistener-nodeport.yaml
```

2. **Verify and Test**
```bash
# Verify NodePort Service
kubectl get svc -n tekton-pipelines | grep nodeport

# Test connectivity
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -v http://$NODE_IP:30080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "nodeport test"}'
```

**Network Architecture:**
```
Runner Machine ──→ Node IP:30080 ──→ ClusterIP:8080 ──→ EventListener Pod
(Accessible)        (NodePort Proxy)    (Internal Routing)
```

## Security Best Practices

### Why Use Strict Pod Security Policies?

This POC adopts **Principle of Least Privilege** and **Defense in Depth** strategies:

#### 🔐 Task Security Configuration Details

**stepTemplate Security Context:**
```yaml
stepTemplate:
  securityContext:
    allowPrivilegeEscalation: false  # Prevent privilege escalation
    capabilities:
      drop: ["ALL"]                  # Remove all Linux capabilities
    runAsNonRoot: true              # Force non-root execution
    runAsUser: 65532               # Use nobody user (minimal privileges)
    seccompProfile:
      type: RuntimeDefault         # Enable seccomp security profile
```

#### 🎯 Purpose of Each Setting

1. **runAsUser: 65532 (nobody)**
   - Standard non-privileged user ID
   - Cannot access system-sensitive files
   - Complies with enterprise K8s security standards

2. **allowPrivilegeEscalation: false**
   - Prevents containers from gaining more privileges than parent process
   - Blocks potential privilege escalation attacks

3. **capabilities.drop: ["ALL"]**
   - Removes all Linux capabilities
   - Minimizes system call permissions

4. **seccompProfile: RuntimeDefault**
   - Restricts available system calls for containers
   - Reduces attack surface

#### 💡 Permission Issues Encountered and Solutions

**Git Configuration Permission Issues:**
```bash
# Problem: Cannot write to global Git config
# Solution: Use inline config git -c safe.directory='*'
```

**Pip Installation Permission Issues:**
```bash
# Problem: Cannot write to system package directory
# Solution: Use user-level install pip install --user --break-system-packages
```

#### 🏢 Enterprise Environment Compatibility

- ✅ **Complies with PCI-DSS requirements**
- ✅ **Passes SOC2 audit standards**
- ✅ **Meets financial industry security standards**
- ✅ **Compatible with CIS Kubernetes Benchmark**

#### 🔄 Security and Usability Balance

This POC demonstrates how to achieve **complete functionality** under **strict security policies**:
- Maintain security boundaries without compromise
- Solve permission conflicts through technical means
- Provide reproducible solutions for production environments

## Alpine Image Issues with Strict Security Context

### Issue: Task using Alpine image encounters permission errors

**Symptoms:**
```bash
ERROR: Unable to lock database: Permission denied
ERROR: Failed to open apk database: Permission denied
```

**Root Cause:** 
Strict Pod Security Policy (`runAsUser: 65532`) prevents Alpine's package manager from accessing system databases.

**Diagnostic Steps:**
```bash
# 1. Check Task step logs
kubectl logs <taskrun-pod> -n tekton-pipelines -c step-<step-name>

# 2. Check security context settings
kubectl get task <task-name> -n tekton-pipelines -o yaml | grep -A5 stepTemplate

# 3. Verify Pod's running user
kubectl exec <pod-name> -n tekton-pipelines -- id
```

**Solutions:**

1. **Use BusyBox instead of Alpine (Recommended):**
```yaml
- name: prepare-reports
  image: busybox:latest  # Replace alpine:latest
  script: |
    #!/bin/sh
    # Avoid using apk add or similar package managers
```

2. **Or use statically compiled tool images:**
```yaml
- name: prepare-reports
  image: gcr.io/distroless/static:latest
```

3. **Remove package manager dependencies:**
```bash
# ❌ Avoid using in scripts
apk add --no-cache curl
apt-get update && apt-get install -y curl

# ✅ Use pre-built images or built-in commands
```

**Best Practices:**
- 🚫 **Avoid installing packages in Task steps** - Violates container least privilege principle
- ✅ **Use pre-built images** - Choose images with required tools already included
- ✅ **BusyBox compatibility** - More stable in restricted environments than Alpine
- ✅ **Static binaries** - Distroless images provide minimal attack surface

**Impact:**
- prepare-test-reports step failure causes subsequent upload-to-web-server step to be skipped
- Entire Pipeline marked as failed, but Git clone and Python test steps may have executed successfully

## PVC Permission Conflicts (Init Container Best Practice)

### Issue: Shared storage permission conflicts

**Symptoms:**
```bash
can't create /shared-reports/index.html: Permission denied
```

**Root Cause:** 
- Tekton Tasks run as `runAsUser: 65532`
- Web server Pod may run as different user
- Inconsistent write permissions on same PVC

**Best Practice Solution: Init Container + fsGroup**

1. **Add Init Container to Web Server:**
```yaml
spec:
  securityContext:
    fsGroup: 65532  # Match Tekton Task user
    fsGroupChangePolicy: "OnRootMismatch"
  
  initContainers:
  - name: setup-permissions
    image: busybox:latest
    securityContext:
      runAsUser: 0  # Run as root to set permissions
      runAsNonRoot: false
    command: ["/bin/sh", "-c"]
    args:
    - |
      chown -R 65532:65532 /shared-reports
      chmod -R 775 /shared-reports
    volumeMounts:
    - name: reports-volume
      mountPath: /shared-reports
```

2. **Main Container Uses Consistent User:**
```yaml
containers:
- name: nginx
  securityContext:
    runAsUser: 65532
    runAsGroup: 65532
    runAsNonRoot: true
```

**Why This is Best Practice:**
- ✅ **Kubernetes Pattern** - Init containers handle initialization work
- ✅ **Separation of Concerns** - Permission setup decoupled from application runtime
- ✅ **One-time Setup** - No need for repeated permission debugging
- ✅ **Security Controlled** - Main container maintains least privilege principle

**Technical Details:**
- `fsGroup: 65532`: Ensures all containers have consistent volume permissions
- `fsGroupChangePolicy: "OnRootMismatch"`: Only changes permissions when necessary
- Init container runs as root to set ownership, main container runs as nobody for security

## EventListener Deployment Issues

### Issue 1: EventListener Pod CrashLoopBackOff

**Symptoms:**
```bash
kubectl get pods -l eventlistener=github-listener -n tekton-pipelines
NAME                                  READY   STATUS             RESTARTS      AGE
el-github-listener-799ddc84dd-2l5q5   0/1     CrashLoopBackOff   7 (41s ago)   8m12s
```

**Diagnosis Steps:**

1. **Check Pod Status**
```bash
kubectl get eventlistener --all-namespaces
kubectl get pods -l eventlistener=github-listener -n tekton-pipelines
```

2. **Check Pod Logs**
```bash
kubectl logs el-github-listener-xxx-xxx -n tekton-pipelines
```

**Common Error Log:**
```
clusterinterceptors.triggers.tekton.dev is forbidden: 
User "system:serviceaccount:tekton-pipelines:tekton-triggers-sa" cannot list resource "clusterinterceptors"
```

**Root Cause:** ServiceAccount lacks permissions to access Tekton Triggers resources.

**Solution:**

1. **Check Existing ClusterRole**
```bash
kubectl get clusterrole | grep tekton
kubectl describe clusterrole tekton-triggers-eventlistener-clusterroles
```

2. **Update RBAC Configuration** Use Tekton's predefined ClusterRole:
```yaml
# Use predefined ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-eventlistener-binding
subjects:
- kind: ServiceAccount
  name: tekton-triggers-sa
  namespace: tekton-pipelines
roleRef:
  kind: ClusterRole
  name: tekton-triggers-eventlistener-clusterroles
  apiGroup: rbac.authorization.k8s.io
```

### Issue 2: Missing Core Interceptors

**Symptoms:**
```bash
kubectl logs el-github-listener-xxx-xxx -n tekton-pipelines
# Error: Timed out waiting on CaBundle to available for clusterInterceptor: empty caBundle in clusterInterceptor spec
```

**Diagnosis:**
```bash
kubectl get clusterinterceptor
# Should show: bitbucket, cel, github, gitlab, slack
```

**Solution:**
```bash
# Install Core Interceptors
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

# Verify installation
kubectl get pods -n tekton-pipelines | grep interceptor
kubectl get clusterinterceptor
```

## GitHub Actions Issues

### Issue 3: Workflow Execution Fails

**Symptoms:**
- GitHub Actions shows workflow as running but no progress
- EventListener receives no requests

**Diagnosis Steps:**

1. **Check GitHub Actions Logs**
   View detailed logs in GitHub Actions interface

2. **Verify Runner Status**
```bash
# On Runner machine
sudo systemctl status actions.runner.*
```

3. **Test Manual Trigger**
```bash
# On Runner machine
curl -v http://10.117.3.193:30080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{"ref": "refs/heads/main", "repository": {"name": "test"}}'
```

**Common Solutions:**
- Ensure Runner is online and connected
- Verify network connectivity to Kubernetes cluster
- Check kubectl configuration on Runner machine

## Pipeline Execution Issues

### Issue 4: Pipeline Not Found

**Symptoms:**
```bash
kubectl get pipelinerun -n default
# Error: couldn't find resource for "tekton.dev/v1beta1, Resource=pipelineruns"
```

**Solution:**
```bash
# Apply Pipeline definitions first
kubectl apply -f .tekton/pipelines/task-pytest.yaml
kubectl apply -f .tekton/pipelines/pipeline.yaml

# Verify resources exist
kubectl get task pytest-task -n default
kubectl get pipeline pytest-pipeline -n default
```

### Issue 5: Permission Denied in Pipeline

**Symptoms:**
Pipeline logs show permission errors when accessing git repository or running commands.

**Solution:**
Update ServiceAccount permissions in task definition or verify git credentials.

## Quick Diagnosis Checklist

When encountering issues, troubleshoot in this order:

1. **EventListener Pod Status**
   ```bash
   kubectl get pods -l eventlistener=github-listener -n tekton-pipelines
   ```

2. **Permission Check**
   ```bash
   kubectl auth can-i list clusterinterceptors --as=system:serviceaccount:tekton-pipelines:tekton-triggers-sa
   ```

3. **Core Interceptors Status**
   ```bash
   kubectl get clusterinterceptor
   kubectl get pods -n tekton-pipelines | grep interceptor
   ```

4. **Network Connectivity (using NodePort)**
   ```bash
   # Preferred method: Use NodePort
   NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
   curl -v http://$NODE_IP:30080 \
     -H "Content-Type: application/json" \
     -H "X-GitHub-Event: ping" \
     -d '{"zen": "test"}'
   ```

5. **GitHub Actions Logs**
   Check GitHub Actions workflow execution logs

6. **Tekton Dashboard**
   Visit http://tekton.<IP>.nip.io to view Pipeline execution status

## Common Debug Commands

### Resource Status Check
```bash
# Complete system status check
kubectl get eventlistener,triggerbinding,triggertemplate -n tekton-pipelines
kubectl get task,pipeline,pipelinerun -n default
kubectl get pods --all-namespaces | grep -E "(tekton|github)"
```

### Log Collection
```bash
# EventListener logs
kubectl logs -l eventlistener=github-listener -n tekton-pipelines --tail=100

# Tekton Controller logs
kubectl logs -l app=tekton-pipelines-controller -n tekton-pipelines --tail=50

# Triggers Controller logs
kubectl logs -l app=tekton-triggers-controller -n tekton-pipelines --tail=50
```

### Event Viewing
```bash
# View related events
kubectl get events -n default --sort-by='.lastTimestamp'
kubectl get events -n tekton-pipelines --sort-by='.lastTimestamp'
```

## Prevention Measures

1. **Pre-deployment Checks**
   - Ensure all Tekton components are running normally
   - Verify RBAC permission configuration
   - Test network connectivity

2. **Monitoring Setup**
   - Set up EventListener Pod status monitoring
   - Configure PipelineRun failure alerts
   - Monitor Runner connection status

3. **Version Compatibility**
   - Ensure Tekton component version compatibility
   - Verify kubectl client version
   - Check Kubernetes cluster version support

## Quick Recovery Checklist

Quick recovery steps when encountering issues:

1. **Delete Problematic Resources**
```bash
kubectl delete eventlistener github-listener -n tekton-pipelines
kubectl delete clusterrolebinding tekton-triggers-eventlistener-binding
```

2. **Redeploy Infrastructure**
```bash
kubectl apply -f .tekton/infrastructure/rbac.yaml
kubectl apply -f .tekton/infrastructure/triggerbinding.yaml
kubectl apply -f .tekton/infrastructure/triggertemplate.yaml
kubectl apply -f .tekton/infrastructure/eventlistener.yaml
kubectl apply -f .tekton/infrastructure/eventlistener-nodeport.yaml
```

3. **Verify Deployment Status**
```bash
kubectl wait --for=condition=Ready pod -l eventlistener=github-listener -n tekton-pipelines --timeout=60s
```

4. **Test Connectivity**
```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -X POST http://$NODE_IP:30080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "recovery test"}'
```
