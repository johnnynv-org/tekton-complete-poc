# 02 - Tekton环境安装

本文档记录了在Kubernetes集群中安装和配置Tekton组件的完整过程。

## 前置条件

- 运行中的Kubernetes集群 (v1.30.14)
- kubectl已配置并能访问集群
- 集群已安装ingress-nginx controller

## 环境检查

### 1. 检查集群状态

```bash
# 检查集群信息
kubectl cluster-info

# 检查节点状态
kubectl get nodes

# 检查当前context
kubectl config current-context
```

**实际输出：**
```
Kubernetes control plane is running at https://10.117.3.193:6443
NAME        STATUS   ROLES           AGE    VERSION
ipp1-1877   Ready    control-plane   170m   v1.30.14
```

### 2. 检查现有namespace

```bash
kubectl get namespaces
```

**结果：** 初始时没有tekton相关的namespace。

## Tekton组件安装

### 步骤1: 安装Tekton Pipelines核心组件

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

**安装的组件：**
- namespace/tekton-pipelines
- namespace/tekton-pipelines-resolvers
- 核心控制器和webhook
- CRD定义（Pipeline, Task, PipelineRun, TaskRun等）

**验证安装：**
```bash
kubectl get pods -n tekton-pipelines
kubectl get pods -n tekton-pipelines-resolvers
```

**预期结果：**
```
NAME                                           READY   STATUS    RESTARTS   AGE
tekton-events-controller-xxx                   1/1     Running   0          45s
tekton-pipelines-controller-xxx                1/1     Running   0          45s
tekton-pipelines-webhook-xxx                   1/1     Running   0          45s
```

### 步骤2: 安装Tekton Dashboard

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
```

**验证Dashboard：**
```bash
kubectl get pods -n tekton-pipelines | grep dashboard
kubectl get svc -n tekton-pipelines tekton-dashboard
```

**预期结果：**
```
NAME                           TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
tekton-dashboard               ClusterIP   10.96.48.87   <none>        9097/TCP   88s
```

### 步骤3: 安装Tekton Triggers

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
```

**验证Triggers：**
```bash
kubectl get pods -n tekton-pipelines | grep trigger
```

## 配置Dashboard访问

### 1. 创建Ingress配置

创建文件 `k8s-configs/tekton-dashboard-ingress.yaml`：

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
  - host: tekton.10.117.3.193.nip.io
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

### 2. 应用Ingress配置

```bash
kubectl apply -f k8s-configs/tekton-dashboard-ingress.yaml
```

### 3. 验证访问

```bash
# 检查ingress状态
kubectl get ingress -n tekton-pipelines

# 测试HTTP访问
curl -s -o /dev/null -w "%{http_code}" http://tekton.10.117.3.193.nip.io
```

**预期结果：** HTTP 200

## 访问信息

### Tekton Dashboard
- **URL**: http://tekton.10.117.3.193.nip.io
- **用户名**: admin
- **密码**: admin123

## 最终验证

### 检查所有组件状态

```bash
# 检查tekton-pipelines namespace
kubectl get pods -n tekton-pipelines

# 检查tekton-pipelines-resolvers namespace
kubectl get pods -n tekton-pipelines-resolvers

# 检查ingress
kubectl get ingress -n tekton-pipelines
```

**预期最终状态：**
```
tekton-pipelines namespace:
- tekton-dashboard (1/1 Running)
- tekton-events-controller (1/1 Running)
- tekton-pipelines-controller (1/1 Running)
- tekton-pipelines-webhook (1/1 Running)
- tekton-triggers-controller (1/1 Running)
- tekton-triggers-webhook (1/1 Running)

tekton-pipelines-resolvers namespace:
- tekton-pipelines-remote-resolvers (1/1 Running)
```

## 故障排除

### 常见问题

1. **Pod处于ContainerCreating状态**
   - 等待镜像拉取完成（通常需要1-2分钟）

2. **Ingress无法访问**
   - 检查ingress-nginx controller是否运行
   - 验证DNS解析（nip.io需要internet访问）

3. **Dashboard无法登录**
   - 确认使用正确的用户名密码：admin/admin123
   - 检查浏览器网络控制台是否有错误

### 诊断命令

```bash
# 查看Pod详细状态
kubectl describe pod <pod-name> -n tekton-pipelines

# 查看Pod日志
kubectl logs <pod-name> -n tekton-pipelines

# 查看ingress详情
kubectl describe ingress tekton-dashboard -n tekton-pipelines
```

## 下一步

Tekton环境安装完成后，请继续阅读：
- [03 - 项目代码结构](./03-项目代码结构.md)
