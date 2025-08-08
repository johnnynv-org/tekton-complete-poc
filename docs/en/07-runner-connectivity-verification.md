# 07 - Runner Connectivity Verification

This document details how to verify network connectivity between GitHub Actions Runner and Kubernetes cluster.

## Environment Information

### Cluster Environment
- **Cluster Node IP**: `10.117.3.193`
- **EventListener ClusterIP**: `10.109.72.223` (dynamically assigned)
- **EventListener NodePort**: `10.117.3.193:30080`
- **EventListener DNS**: `el-github-listener.tekton-pipelines.svc.cluster.local:8080`

### Runner Machine Requirements
- **Runner Name**: `swqa-gh-runner-poc`
- **Network Requirements**: Access to Kubernetes cluster internal network
- **Permission Requirements**: kubectl access permissions

## Connectivity Verification Steps

### Step 1: Basic Network Connectivity

**Execute on Runner machine:**

```bash
# 1. Test network connectivity to cluster node
ping -c 3 10.117.3.193

# 2. Test kubectl connection
kubectl get nodes
kubectl cluster-info
```

**Expected results:**
```
PING 10.117.3.193: 56 data bytes
64 bytes from 10.117.3.193: icmp_seq=0 ttl=64 time=0.123 ms

NAME        STATUS   ROLES           AGE   VERSION
ipp1-1877   Ready    control-plane   22h   v1.30.14
```

### Step 2: Get EventListener Information

**Execute on Runner machine:**

```bash
# Get EventListener Service details
kubectl get svc el-github-listener -n tekton-pipelines -o wide

# Get ClusterIP
CLUSTER_IP=$(kubectl get svc el-github-listener -n tekton-pipelines -o jsonpath='{.spec.clusterIP}')
echo "EventListener ClusterIP: $CLUSTER_IP"

# Get NodePort Service details
kubectl get svc el-github-listener-nodeport -n tekton-pipelines -o wide
```

**Expected results:**
```
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
el-github-listener   ClusterIP   10.109.72.223   <none>        8080/TCP,9000/TCP   15m

EventListener ClusterIP: 10.109.72.223

NAME                          TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)          AGE
el-github-listener-nodeport   NodePort   10.96.97.5    <none>        8080:30080/TCP   5m
```

### Step 3: Test DNS Resolution

**Execute on Runner machine:**

```bash
# Test cluster internal DNS resolution
nslookup el-github-listener.tekton-pipelines.svc.cluster.local

# Test Kubernetes default DNS
nslookup kubernetes.default.svc.cluster.local
```

**Possible results:**

✅ **DNS resolution successful:**
```
Server:    10.96.0.10
Address:   10.96.0.10#53

Name:      el-github-listener.tekton-pipelines.svc.cluster.local
Address:   10.109.72.223
```

❌ **DNS resolution failed:**
```
** server can't find el-github-listener.tekton-pipelines.svc.cluster.local: NXDOMAIN
```

### Step 4: Network Connectivity Testing

#### Method A: ClusterIP Direct Access (May Fail)

**Execute on Runner machine:**

```bash
# Use ClusterIP for connectivity test
CLUSTER_IP=$(kubectl get svc el-github-listener -n tekton-pipelines -o jsonpath='{.spec.clusterIP}')

# Test TCP connection
ping -c 3 $CLUSTER_IP

# Test HTTP request
curl -v http://$CLUSTER_IP:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "connectivity test from runner"}'
```

**Expected failure (common in production):**
```
PING 10.109.72.223: 56 data bytes
--- 10.109.72.223 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss

curl: (7) Failed to connect to 10.109.72.223 port 8080: Connection timeout
```

#### Method B: NodePort Access (Recommended Solution)

**Execute on Runner machine:**

```bash
# Get cluster node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Cluster Node IP: $NODE_IP"

# Test NodePort connectivity
curl -v http://$NODE_IP:30080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "nodeport test from runner"}'
```

**Expected success result:**
```
* Connected to 10.117.3.193 (10.117.3.193) port 30080
< HTTP/1.1 202 Accepted
< Content-Type: application/json
{"eventListener":"github-listener","namespace":"tekton-pipelines","eventListenerUID":"..."}
```

## Troubleshooting

### Issue 1: DNS Resolution Failed

**Symptoms:**
```bash
curl: (6) Could not resolve host: el-github-listener.tekton-pipelines.svc.cluster.local
```

**Solutions:**
1. Use ClusterIP instead of DNS name (recommended)
2. Check kubeconfig DNS configuration
3. Verify cluster DNS service status

### Issue 2: ClusterIP Network Unreachable

**Symptoms:**
```bash
# ✅ Can ping cluster node
ping 10.117.3.193  # Success

# ❌ Cannot access ClusterIP
ping 10.109.72.223  # 100% packet loss
curl: (7) Failed to connect to 10.109.72.223 port 8080: Connection timeout
```

**Root Cause:** Runner machine cannot directly route to Kubernetes Service CIDR network segment (10.96.0.0/12)

**Solution: Use NodePort Access**

1. **Create NodePort Service**
```bash
# NodePort Service configuration
cat > eventlistener-nodeport.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: el-github-listener-nodeport
  namespace: tekton-pipelines
spec:
  type: NodePort
  selector:
    eventlistener: github-listener
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30080
      protocol: TCP
EOF

# Apply configuration
kubectl apply -f eventlistener-nodeport.yaml
```

2. **Verify NodePort Service**
```bash
kubectl get svc -n tekton-pipelines | grep nodeport
```

3. **Use NodePort for connectivity testing**
```bash
# Use Node IP + NodePort port
curl -v http://10.117.3.193:30080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "nodeport test from runner"}'
```

**Network Architecture:**
```
Runner Machine ──→ Node IP:30080 ──→ ClusterIP:8080 ──→ EventListener Pod
10.117.3.193:30080    10.109.72.223:8080
(Accessible)          (Internal routing)
```

### Issue 3: HTTP Connection Refused

**Symptoms:**
```bash
curl: (7) Failed to connect to 10.109.72.223 port 8080: Connection refused
```

**Diagnosis steps:**
```bash
# 1. Check EventListener Pod status
kubectl get pods -l eventlistener=github-listener -n tekton-pipelines

# 2. Check Service endpoints
kubectl get endpoints el-github-listener -n tekton-pipelines

# 3. Check EventListener logs
kubectl logs -l eventlistener=github-listener -n tekton-pipelines --tail=20
```

## Verification Checklist

Before conducting end-to-end testing, confirm the following items:

- [ ] Runner machine can ping cluster node (10.117.3.193)
- [ ] kubectl commands work normally
- [ ] Can get EventListener Service information
- [ ] NodePort connectivity test successful (HTTP 202)
- [ ] EventListener response contains correct eventListener and namespace information

## Network Architecture Overview

```
┌─────────────────┐    Network Connection    ┌──────────────────────┐
│  GitHub Runner  │─────────────────────────→│  Kubernetes Cluster │
│ swqa-gh-runner  │    Internal Network      │    10.117.3.193     │
│      POC        │      Access              │                      │
└─────────────────┘                          └──────────────────────┘
                                                      │
                                                      ▼
                                  ┌──────────────────────────────────┐
                                  │        NodePort Service          │
                                  │    10.117.3.193:30080           │
                                  │           │                      │
                                  │           ▼                      │
                                  │    EventListener Service         │
                                  │      10.109.72.223:8080          │
                                  └──────────────────────────────────┘
```

## Next Steps

After successful connectivity verification, continue with:
- [05 - End-to-End Testing](./05-end-to-end-testing.md)
