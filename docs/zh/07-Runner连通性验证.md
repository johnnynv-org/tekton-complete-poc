# 07 - Runner连通性验证

本文档详细说明如何验证GitHub Actions Runner与Kubernetes集群的网络连通性。

## 验证环境信息

### 集群环境信息
- **集群节点IP**: `10.117.3.193`
- **EventListener ClusterIP**: `10.109.72.223` (动态分配)
- **EventListener DNS**: `el-github-listener.tekton-pipelines.svc.cluster.local:8080`

### Runner机器要求
- **Runner名称**: `swqa-gh-runner-poc`
- **网络要求**: 能够访问Kubernetes集群内网
- **权限要求**: kubectl访问权限

## 连通性验证步骤

### 步骤1：基础网络连通性

**在Runner机器上执行：**

```bash
# 1. 测试到集群节点的网络连通性
ping -c 3 10.117.3.193

# 2. 测试kubectl连接
kubectl get nodes
kubectl cluster-info
```

**预期结果：**
```
PING 10.117.3.193: 56 data bytes
64 bytes from 10.117.3.193: icmp_seq=0 ttl=64 time=0.123 ms

NAME        STATUS   ROLES           AGE   VERSION
ipp1-1877   Ready    control-plane   22h   v1.30.14
```

### 步骤2：获取EventListener信息

**在Runner机器上执行：**

```bash
# 获取EventListener Service详情
kubectl get svc el-github-listener -n tekton-pipelines -o wide

# 获取ClusterIP
CLUSTER_IP=$(kubectl get svc el-github-listener -n tekton-pipelines -o jsonpath='{.spec.clusterIP}')
echo "EventListener ClusterIP: $CLUSTER_IP"
```

**预期结果：**
```
NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
el-github-listener   ClusterIP   10.109.72.223   <none>        8080/TCP,9000/TCP   15m

EventListener ClusterIP: 10.109.72.223
```

### 步骤3：测试DNS解析

**在Runner机器上执行：**

```bash
# 测试集群内DNS解析
nslookup el-github-listener.tekton-pipelines.svc.cluster.local

# 测试Kubernetes默认DNS
nslookup kubernetes.default.svc.cluster.local
```

**可能的结果：**

✅ **DNS解析成功:**
```
Server:    10.96.0.10
Address:   10.96.0.10#53

Name:      el-github-listener.tekton-pipelines.svc.cluster.local
Address:   10.109.72.223
```

❌ **DNS解析失败:**
```
** server can't find el-github-listener.tekton-pipelines.svc.cluster.local: NXDOMAIN
```

### 步骤4：网络连通性测试

#### 方案A：ClusterIP直接访问（推荐）

**在Runner机器上执行：**

```bash
# 使用ClusterIP进行连通性测试
CLUSTER_IP=$(kubectl get svc el-github-listener -n tekton-pipelines -o jsonpath='{.spec.clusterIP}')

# 测试TCP连接
telnet $CLUSTER_IP 8080

# 测试HTTP请求
curl -v http://$CLUSTER_IP:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "connectivity test from runner"}'
```

**预期成功结果：**
```
* Connected to 10.109.72.223 (10.109.72.223) port 8080
< HTTP/1.1 202 Accepted
< Content-Type: application/json
{"eventListener":"github-listener","namespace":"tekton-pipelines",...}
```

#### 方案B：DNS名称访问（如果DNS解析成功）

**在Runner机器上执行：**

```bash
# 使用完整DNS名称测试
curl -v http://el-github-listener.tekton-pipelines.svc.cluster.local:8080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "dns test from runner"}'
```

## 故障排除

### 问题1：DNS解析失败

**现象:**
```bash
curl: (6) Could not resolve host: el-github-listener.tekton-pipelines.svc.cluster.local
```

**解决方案:**
1. 使用ClusterIP替代DNS名称（推荐）
2. 检查kubeconfig DNS配置
3. 验证集群DNS服务状态

### 问题2：ClusterIP网络不可达

**现象:**
```bash
# 能ping通集群节点
ping 10.117.3.193  # ✅ 成功

# 但无法访问ClusterIP
ping 10.109.72.223  # ❌ 100% packet loss
curl: (7) Failed to connect to 10.109.72.223 port 8080: Connection timeout
```

**根本原因:** Runner机器无法直接路由到Kubernetes Service CIDR网段(10.96.0.0/12)

**解决方案：使用NodePort访问**

1. **创建NodePort Service**
```bash
# 创建NodePort Service配置文件
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

# 应用配置
kubectl apply -f eventlistener-nodeport.yaml
```

2. **验证NodePort Service**
```bash
kubectl get svc -n tekton-pipelines | grep nodeport
```

3. **使用NodePort进行连通性测试**
```bash
# 使用节点IP + NodePort端口
curl -v http://10.117.3.193:30080 \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen": "nodeport test from runner"}'
```

**网络架构说明:**
```
Runner Machine ──→ Node IP:30080 ──→ ClusterIP:8080 ──→ EventListener Pod
10.117.3.193:30080    10.109.72.223:8080
(可访问)                (内网路由)
```

### 问题3：HTTP连接被拒绝

**现象:**
```bash
curl: (7) Failed to connect to 10.109.72.223 port 8080: Connection refused
```

**排查步骤:**
```bash
# 1. 检查EventListener Pod状态
kubectl get pods -l eventlistener=github-listener -n tekton-pipelines

# 2. 检查Service端点
kubectl get endpoints el-github-listener -n tekton-pipelines

# 3. 检查EventListener日志
kubectl logs -l eventlistener=github-listener -n tekton-pipelines --tail=20
```

## 验证清单

在进行端到端测试前，确认以下项目：

- [ ] Runner机器能ping通集群节点 (10.117.3.193)
- [ ] kubectl命令正常工作
- [ ] 能获取EventListener Service信息
- [ ] ClusterIP连通性测试成功（HTTP 202）
- [ ] EventListener响应包含正确的eventListener和namespace信息

## 网络架构说明

```
┌─────────────────┐    网络连接    ┌──────────────────────┐
│  GitHub Runner  │──────────────→│  Kubernetes Cluster │
│ swqa-gh-runner  │    内网访问    │    10.117.3.193     │
│      POC        │               │                      │
└─────────────────┘               └──────────────────────┘
                                           │
                                           ▼
                                  ┌──────────────────┐
                                  │  EventListener   │
                                  │   Service        │
                                  │ 10.109.72.223    │
                                  │    :8080         │
                                  └──────────────────┘
```

## 下一步

连通性验证成功后，请继续：
- [05 - 端到端测试](./05-端到端测试.md)
